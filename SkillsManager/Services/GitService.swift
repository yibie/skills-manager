import Foundation

actor GitService {

    /// Initialize a git repo at the given path if not already initialized
    func initRepo(at path: URL) async throws {
        let gitDir = path.appending(path: ".git")
        guard !FileManager.default.fileExists(atPath: gitDir.path()) else { return }
        try await run("git", args: ["init"], at: path)
        try await run("git", args: ["add", "."], at: path)
        try await run("git", args: ["commit", "-m", "Initial version"], at: path)
    }

    /// Stage and commit all changes
    func commitChanges(at path: URL, message: String) async throws {
        try await run("git", args: ["add", "."], at: path)
        // Check if there are staged changes
        let status = try await run("git", args: ["status", "--porcelain"], at: path)
        guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try await run("git", args: ["commit", "-m", message], at: path)
    }

    /// Get commit log
    func log(at path: URL, maxCount: Int = 20) async throws -> [GitCommit] {
        let output = try await run("git", args: [
            "log", "--format=%H%n%s%n%ai%n---", "-\(maxCount)"
        ], at: path)
        return parseLog(output)
    }

    /// Get diff of working directory
    func diff(at path: URL) async throws -> String {
        try await run("git", args: ["diff"], at: path)
    }

    /// Get diff between two commits
    func diff(at path: URL, from: String, to: String = "HEAD") async throws -> String {
        try await run("git", args: ["diff", from, to], at: path)
    }

    /// Checkout a specific commit (for rollback)
    func checkout(at path: URL, ref: String) async throws {
        try await run("git", args: ["checkout", ref, "--", "."], at: path)
    }

    /// Check if path is a git repo
    func isGitRepo(at path: URL) -> Bool {
        FileManager.default.fileExists(atPath: path.appending(path: ".git").path())
    }

    // MARK: - Private

    @discardableResult
    private func run(_ command: String, args: [String], at directory: URL) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            throw GitError.commandFailed(command: "\(command) \(args.joined(separator: " "))", stderr: errOutput)
        }

        return output
    }

    private func parseLog(_ output: String) -> [GitCommit] {
        output.components(separatedBy: "---\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap { entry in
                let lines = entry.components(separatedBy: "\n").filter { !$0.isEmpty }
                guard lines.count >= 3 else { return nil }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate, .withTime, .withSpaceBetweenDateAndTime, .withTimeZone]
                return GitCommit(
                    hash: lines[0],
                    message: lines[1],
                    date: formatter.date(from: lines[2]) ?? Date()
                )
            }
    }
}

struct GitCommit: Identifiable, Sendable {
    let id: String  // same as hash
    let hash: String
    let message: String
    let date: Date

    init(hash: String, message: String, date: Date) {
        self.id = hash
        self.hash = hash
        self.message = message
        self.date = date
    }
}

enum GitError: LocalizedError {
    case commandFailed(command: String, stderr: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let stderr):
            "Git command failed: \(cmd)\n\(stderr)"
        }
    }
}
