import Foundation
import SwiftUI

// Utility for human-readable bytes
extension Int64 {
    var dsHumanBinary: String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.countStyle = .binary
        return f.string(fromByteCount: self)
    }
}

struct DSFileItem: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64

    var name: String { url.lastPathComponent }
    var path: String { url.deletingLastPathComponent().path }
    var sizeText: String { size.dsHumanBinary }
}

struct DSUsagePoint: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let usedPercent: Double
}

struct DSFileTypeUsage: Identifiable {
    let id = UUID()
    let type: String
    let percent: Double
    let color: Color
}

@MainActor
final class DashboardViewModel: ObservableObject {
    // Summary
    @Published var usedPercent: Double = 0
    @Published var freeText: String = "–"

    // Charts & lists
    @Published var fileTypeUsage: [DSFileTypeUsage] = []
    @Published var topFiles: [DSFileItem] = []
    @Published var history: [DSUsagePoint] = []

    // Cleanup
    @Published var cleanupMessage: String = "No significant opportunities found right now."
    @Published var isScanning: Bool = false

    // MARK: Lifecycle
    func onAppear() {
        refreshDeviceUsage()
        loadHistory()
        appendTodayHistory()
    }

    func refreshDeviceUsage() {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let used = max(0, total - free)
            usedPercent = total > 0 ? Double(used) / Double(total) : 0
            freeText = "Free: \(free.dsHumanBinary)"
        } catch {
            usedPercent = 0
            freeText = "Free: –"
        }
    }

    // MARK: Scan entire user home (excluding system dirs) for demo
    func scanFullDisk() {
        isScanning = true
        Task.detached { [weak self] in
            guard let self else { return }
            let start = Date()
            let result = Self.scan(paths: Self.defaultScanPaths())
            let duration = Date().timeIntervalSince(start)
            print("Scan finished in \(String(format: "%.1f", duration))s, files: \(result.files.count)")
            await MainActor.run {
                self.topFiles = result.top
                self.fileTypeUsage = result.usage
                self.cleanupMessage = result.recommendation
                self.isScanning = false
            }
        }
    }

    // MARK: History
    private func appendTodayHistory() {
        guard let last = history.last else {
            history.append(.init(date: Date(), usedPercent: usedPercent * 100))
            saveHistory()
            return
        }
        if !Calendar.current.isDate(last.date, inSameDayAs: Date()) {
            history.append(.init(date: Date(), usedPercent: usedPercent * 100))
            if history.count > 365 { history.removeFirst(history.count - 365) }
            saveHistory()
        }
    }

    private func historyURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DiskSpaceDashboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private func loadHistory() {
        do {
            let data = try Data(contentsOf: historyURL())
            let decoded = try JSONDecoder().decode([DSUsagePoint].self, from: data)
            history = decoded
        } catch { history = [] }
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL(), options: .atomic)
        } catch { print("save history error", error) }
    }

    // MARK: Scanner Implementation
    private struct Accum {
        var totals: [String: Int64] = [:]
        var files: [DSFileItem] = []
    }

    nonisolated private static func defaultScanPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let subdirs = ["Downloads","Documents","Desktop","Movies","Music","Pictures"]
        var urls = subdirs.map { home.appendingPathComponent($0, isDirectory: true) }
        // Include large common roots if readable
        urls.append(home)
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated private static func scan(paths: [URL]) -> (top: [DSFileItem], usage: [DSFileTypeUsage], recommendation: String, files: [DSFileItem]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        var acc = Accum()
        let fm = FileManager.default

        for root in paths {
            if let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let url as URL in en {
                    do {
                        let values = try url.resourceValues(forKeys: Set(keys))
                        guard values.isRegularFile == true else { continue }
                        let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                        guard size > 0 else { continue }
                        let item = DSFileItem(url: url, size: size)
                        acc.files.append(item)
                        acc.totals[category(for: url), default: 0] += size
                    } catch {
                        // skip unreadable
                    }
                }
            }
        }

        // Top 20
        let top = Array(acc.files.sorted { $0.size > $1.size }.prefix(20))

        // Usage breakdown
        let totalBytes = acc.totals.values.reduce(0, +)
        let order = ["Documents","Media","Archives","Other"]
        let usage: [DSFileTypeUsage] = order.map { key in
            let pct = totalBytes > 0 ? Double(acc.totals[key, default: 0]) / Double(totalBytes) * 100 : 0
            let color: Color = {
                switch key { case "Documents": return .blue; case "Media": return .red; case "Archives": return .yellow; default: return .green }
            }()
            return DSFileTypeUsage(type: key, percent: pct, color: color)
        }

        let recommendation: String
        if let biggest = top.first {
            recommendation = "Consider reviewing \(biggest.name) (\(biggest.sizeText))."
        } else {
            recommendation = "No significant opportunities found right now."
        }

        return (top, usage, recommendation, acc.files)
    }

    nonisolated private static func category(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["pdf","doc","docx","txt","rtf","md","pages","numbers","key","ppt","pptx","xls","xlsx"].contains(ext) { return "Documents" }
        if ["png","jpg","jpeg","heic","gif","webp","mov","mp4","m4v","avi","mkv","mp3","aac","wav","aiff","flac"].contains(ext) { return "Media" }
        if ["zip","rar","7z","tar","gz","tgz","bz2"].contains(ext) { return "Archives" }
        return "Other"
    }
}
