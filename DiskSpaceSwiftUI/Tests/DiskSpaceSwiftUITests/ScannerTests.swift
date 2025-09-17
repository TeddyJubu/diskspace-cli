import XCTest
@testable import DiskSpaceSwiftUI

final class ScannerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testRespectsMinimumSizeThreshold() throws {
        try writeFile(named: "video.mov", sizeInBytes: 3 * 1024 * 1024)
        try writeFile(named: "notes.txt", sizeInBytes: 512 * 1024)

        let filters = ScanFilters(
            minSizeBytes: 2 * 1024 * 1024,
            include: Set(FileCategory.allCases),
            ignorePatterns: []
        )

        let output = Scanner.run(
            paths: [tempDirectory],
            filters: filters,
            topLimit: 5,
            useCache: false,
            onProgress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertEqual(output.top.map { $0.url.lastPathComponent }, ["video.mov"])
        XCTAssertEqual(output.totals[.media], 3 * 1024 * 1024)
        XCTAssertNil(output.totals[.documents])
    }

    func testIgnorePatternsSkipsMatchingFiles() throws {
        try writeFile(named: "cache_bundle.zip", sizeInBytes: 3 * 1024 * 1024)

        let filters = ScanFilters(
            minSizeBytes: 0,
            include: Set(FileCategory.allCases),
            ignorePatterns: ["cache"]
        )

        let output = Scanner.run(
            paths: [tempDirectory],
            filters: filters,
            topLimit: 5,
            useCache: false,
            onProgress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertTrue(output.top.isEmpty)
        XCTAssertTrue(output.totals.isEmpty)
    }

    func testTopLimitKeepsLargestFiles() throws {
        try writeFile(named: "alpha.mov", sizeInBytes: 2 * 1024 * 1024)
        try writeFile(named: "beta.mov", sizeInBytes: 4 * 1024 * 1024)
        try writeFile(named: "gamma.mov", sizeInBytes: 3 * 1024 * 1024)

        let filters = ScanFilters(
            minSizeBytes: 0,
            include: [.media],
            ignorePatterns: []
        )

        let output = Scanner.run(
            paths: [tempDirectory],
            filters: filters,
            topLimit: 2,
            useCache: false,
            onProgress: { _, _ in },
            isCancelled: { false }
        )

        XCTAssertEqual(output.top.count, 2)
        XCTAssertEqual(output.top.map { $0.url.lastPathComponent }, ["beta.mov", "gamma.mov"])
    }

    // MARK: - Helpers

    private func writeFile(named name: String, sizeInBytes: Int) throws {
        let url = tempDirectory.appendingPathComponent(name)
        let data = Data(count: sizeInBytes)
        try data.write(to: url, options: .atomic)
    }
}
