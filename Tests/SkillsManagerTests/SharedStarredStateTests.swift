import Foundation
import Testing
@testable import SkillsManager

struct SharedStarredStateTests {
    private func makeTempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-starred-tests-\(UUID().uuidString)")
            .appendingPathComponent("tui-state.json")
        return url
    }

    @Test
    func missingFileReadsAsEmpty() throws {
        let file = try makeTempFile()
        #expect(SharedStarredState.starredNames(fileURL: file).isEmpty)
    }

    @Test
    func starAndUnstarRoundTrip() throws {
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        SharedStarredState.setStarred(true, skillName: "bazi", fileURL: file)
        SharedStarredState.setStarred(true, skillName: "humanizer", fileURL: file)
        #expect(SharedStarredState.starredNames(fileURL: file) == ["bazi", "humanizer"])

        // Starring twice does not duplicate.
        SharedStarredState.setStarred(true, skillName: "bazi", fileURL: file)
        #expect(SharedStarredState.starredNames(fileURL: file) == ["bazi", "humanizer"])

        SharedStarredState.setStarred(false, skillName: "bazi", fileURL: file)
        #expect(SharedStarredState.starredNames(fileURL: file) == ["humanizer"])
    }

    @Test
    func writePreservesUnknownKeys() throws {
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"starred": ["a"], "futureKey": {"nested": true}}"#.write(to: file, atomically: true, encoding: .utf8)

        SharedStarredState.setStarred(true, skillName: "b", fileURL: file)

        let data = try Data(contentsOf: file)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["starred"] as? [String])?.sorted() == ["a", "b"])
        #expect(object["futureKey"] != nil)
    }
}
