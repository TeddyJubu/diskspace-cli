import SwiftUI

@main
struct DiskSpaceApp: App {
    @StateObject private var model = DiskModel()
    @State private var showWindow = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.automatic)

        if #available(macOS 13.0, *) {
            MenuBarExtra("DiskSpace", systemImage: model.menuBarSystemImage) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage: \(model.usage)%  •  Free: \(model.free)")
                    .font(.system(.body, design: .rounded))
                HStack {
                    Button("Check Now") { model.check() }
                    Button("Auto Clean") { model.autoClean() }
                }
                Divider()
                Button("Open App") { NSApp.activate(ignoringOtherApps: true) }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(8)
            .frame(width: 240)
        }
        }
    }
}

final class DiskModel: ObservableObject {
    @Published var usage: Int = 0
    @Published var free: String = ""
    @Published var problems: [Problem] = []
    @Published var error: String?
    @AppStorage("scheduleTime") var scheduleTime: Double = Date().timeIntervalSince1970

    var menuBarSystemImage: String {
        if usage < 60 { return "internaldrive" }
        if usage < 80 { return "internaldrive.badge.icloud" }
        return "internaldrive.fill" 
    }

    func run(_ args: [String]) throws -> String {
        let paths = ["/usr/local/bin/diskspace", NSString(string: "~").expandingTildeInPath + "/diskspace"]
        guard let bin = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "DiskSpace", code: 1, userInfo: [NSLocalizedDescriptionKey: "diskspace binary not found"])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    func check() {
        DispatchQueue.global().async {
            do {
                let out = try self.run(["check", "--json"])
                guard let data = out.data(using: .utf8) else { throw NSError(domain: "", code: 0) }
                let resp = try JSONDecoder().decode(CheckResponse.self, from: data)
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        self.usage = resp.disk_usage_percent
                        self.free = resp.free_space
                        self.problems = resp.cleanup_opportunities.problems
                    }
                }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    func autoClean() {
        DispatchQueue.global().async {
            _ = try? self.run(["auto-clean"])
            self.check()
        }
    }

    func interactiveClean() {
        let script = "tell app \"Terminal\" to do script \"diskspace clean\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }

    func scheduleAt(_ date: Date) {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        _ = try? self.run(["schedule", String(format: "%02d:%02d", h, m)])
        scheduleTime = date.timeIntervalSince1970
    }

    func unschedule() { _ = try? self.run(["unschedule"]) }
}

struct ContentView: View {
    @EnvironmentObject var model: DiskModel
    @State private var scheduleDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Image(systemName: "internaldrive")
                    .imageScale(.large)
                    .foregroundStyle(gradient)
                Text("DiskSpace")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
            }

            if #available(macOS 13.0, *) {
                Gauge(value: Double(model.usage), in: 0...100) {
                Text("Usage")
            } currentValueLabel: {
                Text("\(model.usage)%")
                    .bold()
            }
            .tint(usageColor)
                .gaugeStyle(.accessoryLinearCapacity)
                .animation(.easeInOut(duration: 0.35), value: model.usage)
            } else {
                ProgressView(value: Double(model.usage), total: 100)
                    .tint(usageColor)
            }

            HStack {
                Label("Free: \(model.free)", systemImage: "arrow.down.to.line")
                Spacer()
                if !model.problems.isEmpty {
                    Label("\(model.problems.count) suggestions", systemImage: "lightbulb")
                        .foregroundStyle(.orange)
                }
            }
            .font(.headline)

            GroupBox("Cleanup Opportunities") {
                if model.problems.isEmpty {
                    Text("No significant opportunities right now.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List(model.problems) { p in
                        HStack {
                            Text(p.description)
                            Spacer()
if #available(macOS 13.3, *) { Text(p.humanSize).monospaced().foregroundStyle(.orange) } else { Text(p.humanSize).foregroundColor(.orange) }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 160, maxHeight: 240)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            HStack(spacing: 12) {
                Button { model.check() } label: { Label("Check Now", systemImage: "arrow.clockwise") }
                Button { model.autoClean() } label: { Label("Auto Clean", systemImage: "wand.and.stars") }
                Button { model.interactiveClean() } label: { Label("Interactive", systemImage: "terminal") }
                Spacer()
                DatePicker("Schedule", selection: $scheduleDate, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                Button { model.scheduleAt(scheduleDate) } label: { Label("Set", systemImage: "calendar.badge.clock") }
                Button { model.unschedule() } label: { Label("Unschedule", systemImage: "calendar.badge.exclamationmark") }
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
        .background(.thinMaterial)
        .onAppear {
            scheduleDate = Date(timeIntervalSince1970: model.scheduleTime)
            model.check()
        }
    }

    var gradient: LinearGradient { .linearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing) }

    var usageColor: Color {
        if model.usage < 60 { return .green }
        if model.usage < 80 { return .yellow }
        return .red
    }
}

struct CheckResponse: Codable {
    let disk_usage_percent: Int
    let free_space: String
    let threshold: Int
    let status: String
    let cleanup_opportunities: Cleanup
}

struct Cleanup: Codable {
    let total_reclaimable: Int
    let problems: [Problem]
}

struct Problem: Codable, Identifiable {
    let id: String
    let size: Int
    let description: String
    let command: String

    var humanSize: String {
        let kb = Double(size)
        if kb >= 1048576 { return String(format: "%.1f GB", kb/1048576) }
        if kb >= 1024 { return String(format: "%.1f MB", kb/1024) }
        return String(format: "%.0f KB", kb)
    }
}
