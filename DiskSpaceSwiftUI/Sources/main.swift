import SwiftUI

@main
struct DiskSpaceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
    }
}

struct ContentView: View {
    @State private var usage: Int = 0
    @State private var free: String = ""
    @State private var problems: [Problem] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DiskSpace").font(.title).bold()
            ProgressView(value: Double(usage), total: 100)
                .tint(usageColor)
            HStack {
                Text("Usage: \(usage)%")
                Spacer()
                Text("Free: \(free)").bold()
            }
            if let error { Text(error).foregroundColor(.red) }

            if problems.isEmpty {
                Text("No significant cleanup opportunities.")
                    .foregroundColor(.secondary)
            } else {
                Text("Cleanup Opportunities").font(.headline)
                List(problems) { p in
                    HStack {
                        Text(p.description)
                        Spacer()
                        Text(p.humanSize)
                            .foregroundColor(.orange)
                    }
                }
                .frame(minHeight: 160, maxHeight: 240)
            }

            HStack {
                Button("Check Now", action: check)
                Button("Auto Clean", action: autoClean)
                Button("Interactive Clean", action: interactiveClean)
                Spacer()
                Button("Schedule", action: schedule)
                Button("Unschedule", action: unschedule)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 380)
        .task(check)
    }

    var usageColor: Color {
        if usage < 60 { return .green }
        if usage < 80 { return .yellow }
        return .red
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
        loading = true
        error = nil
        DispatchQueue.global().async {
            do {
                let out = try run(["check", "--json"])
                guard let data = out.data(using: .utf8) else { throw NSError(domain: "", code: 0) }
                let resp = try JSONDecoder().decode(CheckResponse.self, from: data)
                DispatchQueue.main.async {
                    usage = resp.disk_usage_percent
                    free = resp.free_space
                    problems = resp.cleanup_opportunities.problems
                    loading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.loading = false
                }
            }
        }
    }

    func autoClean() {
        DispatchQueue.global().async {
            _ = try? run(["auto-clean"])
            check()
        }
    }

    func interactiveClean() {
        let script = "tell app \"Terminal\" to do script \"diskspace clean\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }

    func schedule() { _ = try? run(["schedule"]) }
    func unschedule() { _ = try? run(["unschedule"]) }
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
