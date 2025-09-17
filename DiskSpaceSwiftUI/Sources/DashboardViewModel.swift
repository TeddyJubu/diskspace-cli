import Foundation
import SwiftUI
import AppKit

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

    // Settings
    @AppStorage("ds.includeSystem") var includeSystem: Bool = false
    @AppStorage("ds.includeExternal") var includeExternal: Bool = false
    @AppStorage("ds.extraRootsJSON") private var extraRootsJSON: String = "[]" // [String]
    // Filters
    @AppStorage("ds.minSizeMB") var minSizeMB: Int = 50
    @AppStorage("ds.includeDocuments") var includeDocuments: Bool = true
    @AppStorage("ds.includeMedia") var includeMedia: Bool = true
    @AppStorage("ds.includeArchives") var includeArchives: Bool = true
    @AppStorage("ds.includeOther") var includeOther: Bool = true
    @AppStorage("ds.ignorePatterns") var ignorePatternsRaw: String = "" // comma or newline separated substrings

    var extraRoots: [URL] {
        get {
            (try? JSONDecoder().decode([String].self, from: Data(extraRootsJSON.utf8)))?.map { URL(fileURLWithPath: $0) } ?? []
        }
        set {
            let strings = newValue.map { $0.path }
            if let data = try? JSONEncoder().encode(strings) {
                extraRootsJSON = String(data: data, encoding: .utf8) ?? "[]"
            }
        }
    }

    var ignorePatterns: [String] {
        ignorePatternsRaw
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

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

    // MARK: Scan based on settings
    func scanFullDisk() {
        // capture settings on main actor to avoid cross-actor awaits
        let includeSystem = self.includeSystem
        let includeExternal = self.includeExternal
        let extra = self.extraRoots
        isScanning = true
        Task.detached { [weak self, includeSystem, includeExternal, extra] in
            guard let self else { return }
            let start = Date()
            let roots = Self.buildScanPaths(includeSystem: includeSystem, includeExternal: includeExternal, extra: extra)
            let result = Self.scan(paths: roots)
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

    // MARK: File actions
    func reveal(_ item: DSFileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func revealInTerminal(_ item: DSFileItem) {
        let dir = item.url.deletingLastPathComponent()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal", dir.path]
        try? proc.run()
    }

    func copyPath(_ item: DSFileItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
    }

    func trash(_ item: DSFileItem) -> Bool {
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: item.url, resultingItemURL: &resulting)
            // update lists & usage estimate
            self.topFiles.removeAll { $0.id == item.id }
            refreshDeviceUsage()
            return true
        } catch {
            print("Trash failed: \(error)")
            return false
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // Extra roots management
    func addExtraRootViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            var set = Set(extraRoots.map { $0.path })
            if set.insert(url.path).inserted {
                var arr = extraRoots
                arr.append(url)
                extraRoots = arr
            }
        }
    }

    func removeExtraRoot(_ url: URL) {
        extraRoots = extraRoots.filter { $0.path != url.path }
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

    private struct CacheEntry: Codable { let size: Int64; let mtime: TimeInterval; let category: String }

    nonisolated private static func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DiskSpaceDashboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scanCache.json")
    }

    nonisolated private static func loadCache() -> [String: CacheEntry] {
        let url = cacheURL()
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: CacheEntry].self, from: data)) ?? [:]
    }

    nonisolated private static func saveCache(_ cache: [String: CacheEntry]) {
        let url = cacheURL()
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: url, options: .atomic) }
    }

    nonisolated private static func defaultUserPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let subdirs = ["Downloads","Documents","Desktop","Movies","Music","Pictures"]
        var urls = subdirs.map { home.appendingPathComponent($0, isDirectory: true) }
        // Include large common roots if readable
        urls.append(home)
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated private static func systemPaths() -> [URL] {
        var roots: [URL] = []
        let candidates = ["/Applications", "/Library", "/System/Volumes/Data/Applications", "/System/Volumes/Data/Library"]
        for p in candidates {
            let u = URL(fileURLWithPath: p, isDirectory: true)
            if FileManager.default.fileExists(atPath: u.path) { roots.append(u) }
        }
        return roots
    }

    nonisolated private static func externalVolumePaths() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .isVolumeKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.filter { url in
            do {
                let vals = try url.resourceValues(forKeys: Set(keys))
                let isInternal = vals.volumeIsInternal ?? false
                return !isInternal
            } catch { return false }
        }
    }

    nonisolated private static func buildScanPaths(includeSystem: Bool, includeExternal: Bool, extra: [URL]) -> [URL] {
        var roots = defaultUserPaths()
        if includeSystem { roots.append(contentsOf: systemPaths()) }
        if includeExternal { roots.append(contentsOf: externalVolumePaths()) }
        roots.append(contentsOf: extra)
        // de-duplicate
        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }



    nonisolated private static func scan(paths: [URL]) -> (top: [DSFileItem], usage: [DSFileTypeUsage], recommendation: String, files: [DSFileItem]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        var acc = Accum()
        let fm = FileManager.default
        var cache = loadCache()
        let minSizeBytes = Int64((UserDefaults.standard.integer(forKey: "ds.minSizeMB")) * 1024 * 1024)
        let allowDocs = UserDefaults.standard.bool(forKey: "ds.includeDocuments")
        let allowMedia = UserDefaults.standard.bool(forKey: "ds.includeMedia")
        let allowArchives = UserDefaults.standard.bool(forKey: "ds.includeArchives")
        let allowOther = UserDefaults.standard.bool(forKey: "ds.includeOther")
        let ignore = (UserDefaults.standard.string(forKey: "ds.ignorePatterns") ?? "")
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        func allowedCategory(_ cat: String) -> Bool {
            switch cat { case "Documents": return allowDocs; case "Media": return allowMedia; case "Archives": return allowArchives; default: return allowOther }
        }

        for root in paths {
            if let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let url as URL in en {
                    autoreleasepool {
                        do {
                            let values = try url.resourceValues(forKeys: Set(keys))
                            guard values.isRegularFile == true else { return }
                            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                            guard size >= minSizeBytes else { return }
                            let pathLower = url.path.lowercased()
                            if ignore.contains(where: { pathLower.contains($0) }) { return }

                            // cache by path + mtime + size
                            let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
                            let key = url.path
                            let cat: String
                            if let ce = cache[key], ce.size == size, ce.mtime == mtime {
                                cat = ce.category
                            } else {
                                cat = category(for: url)
                                cache[key] = CacheEntry(size: size, mtime: mtime, category: cat)
                            }
                            guard allowedCategory(cat) else { return }

                            let item = DSFileItem(url: url, size: size)
                            acc.files.append(item)
                            acc.totals[cat, default: 0] += size
                        } catch {
                            // skip unreadable
                        }
                    }
                }
            }
        }
        saveCache(cache)

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
