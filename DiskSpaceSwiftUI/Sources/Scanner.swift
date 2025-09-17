import Foundation

public enum FileCategory: String, CaseIterable, Codable, Hashable {
    case documents, media, archives, other

    public var title: String {
        switch self { case .documents: return "Documents"; case .media: return "Media"; case .archives: return "Archives"; case .other: return "Other" }
    }
}

public struct ScanFilters {
    public var minSizeBytes: Int64
    public var include: Set<FileCategory>
    public var ignorePatterns: [String] // lowercased substrings

    public init(minSizeBytes: Int64, include: Set<FileCategory>, ignorePatterns: [String]) {
        self.minSizeBytes = minSizeBytes
        self.include = include
        self.ignorePatterns = ignorePatterns
    }
}

public struct ScanOutput {
    public var totals: [FileCategory: Int64]
    public var top: [(url: URL, size: Int64)]
}

private struct CacheEntry: Codable { let size: Int64; let mtime: TimeInterval; let category: FileCategory }

public struct Scanner {
    public init() {}

    public static func run(paths: [URL], filters: ScanFilters, topLimit: Int = 200, useCache: Bool = true, onProgress: @escaping (Double, String) -> Void, isCancelled: @escaping () -> Bool) -> ScanOutput {
        var totals = [FileCategory: Int64]()
        var top: [(URL, Int64)] = [] // min-ordered by size
        var cache: [String: CacheEntry] = useCache ? Self.loadCache() : [:]

        func considerTop(_ url: URL, _ size: Int64) {
            if top.count < topLimit {
                top.append((url, size))
                top.sort { $0.1 < $1.1 } // keep ascending
            } else if let smallest = top.first, size > smallest.1 {
                top.removeFirst()
                // insert in ascending order
                var i = 0
                while i < top.count && top[i].1 < size { i += 1 }
                top.insert((url, size), at: i)
            }
        }

        let roots = paths
        let rootCount = max(1, roots.count)
        let fileKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        let keySet = Set(fileKeys)

        let lock = NSLock()
        let start = Date()

        func handle(url: URL, values: URLResourceValues) {
            guard values.isRegularFile == true else { return }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= filters.minSizeBytes else { return }
            let path = url.path
            let lower = path.lowercased()
            if filters.ignorePatterns.contains(where: { lower.contains($0) }) { return }

            let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let cat: FileCategory
            if let ce = cache[path], ce.size == size, ce.mtime == mtime {
                cat = ce.category
            } else {
                cat = Self.category(for: url)
                cache[path] = CacheEntry(size: size, mtime: mtime, category: cat)
            }
            guard filters.include.contains(cat) else { return }

            lock.lock()
            totals[cat, default: 0] += size
            considerTop(url, size)
            lock.unlock()
        }

        #if compiler(>=5.9)
        let group = DispatchGroup()
        for (idx, root) in roots.enumerated() {
            if isCancelled() { break }
            onProgress(Double(idx) / Double(rootCount), root.path)
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let fm = FileManager.default
                if let en = fm.enumerator(at: root, includingPropertiesForKeys: fileKeys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let url as URL in en {
                        if isCancelled() { break }
                        onProgress(Double(idx) / Double(rootCount), url.path)
                        do {
                            let vals = try url.resourceValues(forKeys: keySet)
                            handle(url: url, values: vals)
                        } catch { /* ignore */ }
                    }
                }
            }
        }
        group.wait()
        #else
        for (idx, root) in roots.enumerated() {
            if isCancelled() { break }
            onProgress(Double(idx) / Double(rootCount), root.path)
            let fm = FileManager.default
            if let en = fm.enumerator(at: root, includingPropertiesForKeys: fileKeys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let url as URL in en {
                    if isCancelled() { break }
                    onProgress(Double(idx) / Double(rootCount), url.path)
                    do { let vals = try url.resourceValues(forKeys: keySet); handle(url: url, values: vals) } catch {}
                }
            }
        }
        #endif

        if useCache { Self.saveCache(cache) }
        // flip top to descending order (largest first)
        let sortedDesc = top.sorted { $0.1 > $1.1 }
        let took = String(format: "%.1f", Date().timeIntervalSince(start))
        onProgress(1.0, "Done in \(took)s")
        return ScanOutput(totals: totals, top: sortedDesc)
    }

    private static func category(for url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if ["pdf","doc","docx","txt","rtf","md","pages","numbers","key","ppt","pptx","xls","xlsx"].contains(ext) { return .documents }
        if ["png","jpg","jpeg","heic","gif","webp","mov","mp4","m4v","avi","mkv","mp3","aac","wav","aiff","flac"].contains(ext) { return .media }
        if ["zip","rar","7z","tar","gz","tgz","bz2"].contains(ext) { return .archives }
        return .other
    }

    private static func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DiskSpaceDashboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scanCache.json")
    }
    private static func loadCache() -> [String: CacheEntry] {
        let url = cacheURL()
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: CacheEntry].self, from: data)) ?? [:]
    }
    private static func saveCache(_ cache: [String: CacheEntry]) {
        let url = cacheURL()
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: url, options: .atomic) }
    }
}
