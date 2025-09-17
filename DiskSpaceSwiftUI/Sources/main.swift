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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Usage: \(model.usage)%  •  Free: \(model.free)")
                        .font(.system(.body, design: .rounded))
                    HStack {
                        Button("Check Now") { model.check() }
                        Button("Auto Clean") { model.autoClean() }
                    }
                    Divider()
                    // Preferences popover
                    DisclosureGroup("Preferences") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Threshold")
                                Slider(value: Binding(get: {
                                    Double(model.threshold)
                                }, set: { model.threshold = Int($0) }), in: 50...95)
                                Text("\(model.threshold)%").frame(width: 44, alignment: .trailing)
                            }
                            Toggle("Notifications", isOn: $model.notificationsEnabled)
                            HStack {
                                let schedText = model.scheduledDate.map { DateFormatter.hm.string(from: $0) } ?? "Not scheduled"
                                Text("Scheduled: \(schedText)")
                                Spacer()
                            }
                        }
                    }
                    Divider()
                    Button("Open App") { NSApp.activate(ignoringOtherApps: true) }
                    Button("Quit") { NSApp.terminate(nil) }
                }
                .padding(10)
                .frame(width: 300)
            }
        }
    }
}

final class DiskModel: ObservableObject {
    @Published var usage: Int = 0
    @Published var free: String = ""
    @Published var problems: [Problem] = []
    @Published var error: String?

    // Preferences
    @AppStorage("threshold") var threshold: Int = 80
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @AppStorage("scheduleTime") var scheduleTime: Double = Date().timeIntervalSince1970 // last chosen time
    @Published var scheduledDate: Date? = nil // nil = not scheduled

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
                // also update schedule status
                self.fetchScheduleStatus()
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
        var args = ["schedule", String(format: "%02d:%02d", h, m)]
        if notificationsEnabled == false { args.append("--no-notify") }
        _ = try? self.run(args)
        scheduleTime = date.timeIntervalSince1970
        scheduledDate = date
    }

    func unschedule() {
        _ = try? self.run(["unschedule"])
        scheduledDate = nil
    }

    func fetchScheduleStatus() {
        let out = try? self.run(["status"]) // e.g., "status: scheduled at 10:00" or "status: not scheduled"
        guard let out else { return }
        if let range = out.range(of: #"status: scheduled at ([0-9]{2}):([0-9]{2})"#, options: .regularExpression) {
            let str = String(out[range])
            let comps = str.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if comps.count >= 2 {
                let cal = Calendar.current
                var d = Date()
                d = cal.date(bySettingHour: comps[0], minute: comps[1], second: 0, of: d) ?? d
                DispatchQueue.main.async { self.scheduledDate = d }
            }
        } else {
            DispatchQueue.main.async { self.scheduledDate = nil }
        }
    }

    func applyThreshold() {
        _ = try? self.run(["config", "set", "threshold", String(threshold)])
    }
}

struct ContentView: View {
    @EnvironmentObject var model: DiskModel
    @State private var scheduleDate = Date()
    @State private var prefExpanded = false
    @State private var enableSchedule = false
    @State private var showSchedulePopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "internaldrive")
                    .imageScale(.large)
                    .foregroundStyle(gradient)
                Text("DiskSpace")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Spacer()
            }

            // Usage
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage").font(.subheadline).foregroundColor(.secondary)
                if #available(macOS 13.0, *) {
                    Gauge(value: Double(model.usage), in: 0...100) { EmptyView() } currentValueLabel: {
                        Text("\(model.usage)%").bold()
                    }
                    .tint(usageColor)
                    .gaugeStyle(.accessoryLinearCapacity)
                    .animation(.easeInOut(duration: 0.35), value: model.usage)
                } else {
                    ProgressView(value: Double(model.usage), total: 100)
                        .tint(usageColor)
                }
            }

            // Stats
            HStack {
                Label("Free: \(model.free)", systemImage: "externaldrive.badge.minus")
                    .font(.headline)
                Spacer()
                if !model.problems.isEmpty {
                    Label("\(model.problems.count) suggestions", systemImage: "lightbulb")
                        .foregroundStyle(.orange)
                }
            }

            // Opportunities
            GroupBox("Cleanup Opportunities") {
                if model.problems.isEmpty {
                    Text("No significant opportunities right now.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    List(model.problems) { p in
                        HStack {
                            Text(p.description)
                            Spacer()
                            if #available(macOS 13.3, *) { Text(p.humanSize).monospaced().foregroundStyle(.orange) } else { Text(p.humanSize).foregroundColor(.orange) }
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 160, maxHeight: 240)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            // Action bar
            HStack(spacing: 12) {
                Button { model.check() } label: { Label("Check Now", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent)
                Button { model.autoClean() } label: { Label("Auto Clean", systemImage: "wand.and.stars") }
                    .buttonStyle(.bordered)
                Button { model.interactiveClean() } label: { Label("Interactive", systemImage: "terminal") }
                    .buttonStyle(.bordered)
                Spacer()
                // Schedule summary + popover
                HStack(spacing: 8) {
                    let schedText = model.scheduledDate.map { DateFormatter.hm.string(from: $0) } ?? "Not scheduled"
                    Label("Schedule: \(schedText)", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                    Button("Change…") { showSchedulePopover.toggle() }
                        .buttonStyle(.link)
                        .popover(isPresented: $showSchedulePopover, arrowEdge: .bottom) {
                            SchedulePopover(model: model, scheduleDate: $scheduleDate, enableSchedule: $enableSchedule)
                                .padding()
                                .frame(width: 380)
                        }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420)
        .controlSize(.regular)
        .onAppear {
            scheduleDate = Date(timeIntervalSince1970: model.scheduleTime)
            enableSchedule = model.scheduledDate != nil
            model.applyThreshold()
            model.fetchScheduleStatus()
            model.check()
        }
        .onChange(of: model.threshold) { _ in model.applyThreshold() }
        .onChange(of: scheduleDate) { _ in if enableSchedule { model.scheduleAt(scheduleDate) } }
    }

    var gradient: LinearGradient { .linearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing) }

    var usageColor: Color {
        if model.usage < 60 { return .green }
        if model.usage < 80 { return .yellow }
        return .red
    }
}

// MARK: - Schedule popover
struct SchedulePopover: View {
    @ObservedObject var model: DiskModel
    @Binding var scheduleDate: Date
    @Binding var enableSchedule: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable schedule", isOn: $enableSchedule)
                .onChange(of: enableSchedule) { on in
                    if on { model.scheduleAt(scheduleDate) } else { model.unschedule() }
                }
            HStack {
                Text("Time")
                Spacer()
                DatePicker("Time", selection: $scheduleDate, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .frame(width: 140)
                    .disabled(!enableSchedule)
            }
            Toggle("Notifications", isOn: $model.notificationsEnabled)
            HStack {
                Spacer()
                Button("Apply") { model.scheduleAt(scheduleDate) }.disabled(!enableSchedule)
            }
        }
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
