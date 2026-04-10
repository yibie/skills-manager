import Foundation

enum ExecutableLocator {
    static func resolve(
        command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String? {
        resolve(command: command, environment: environment, homePath: homePath) { candidate in
            FileManager.default.isExecutableFile(atPath: candidate)
        }
    }

    static func resolve(
        command: String,
        environment: [String: String],
        homePath: String,
        isExecutable: (String) -> Bool
    ) -> String? {
        if command.hasPrefix("/") {
            return isExecutable(command) ? command : nil
        }

        for directory in searchDirectories(environment: environment, homePath: homePath) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(command).path
            if isExecutable(candidate) {
                return candidate
            }
        }

        return nil
    }

    static func buildEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        resolvedExecutable: String? = nil
    ) -> [String: String] {
        var environment = base
        environment["HOME"] = homePath
        environment["XDG_CONFIG_HOME"] = URL(fileURLWithPath: homePath).appendingPathComponent(".config").path

        var pathEntries: [String] = []
        if let resolvedExecutable {
            pathEntries.append(URL(fileURLWithPath: resolvedExecutable).deletingLastPathComponent().path)
        }
        pathEntries.append(contentsOf: searchDirectories(environment: base, homePath: homePath))
        environment["PATH"] = unique(pathEntries).joined(separator: ":")

        return environment
    }

    private static func searchDirectories(environment: [String: String], homePath: String) -> [String] {
        let envPathEntries = environment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)

        let fallbackEntries = [
            "\(homePath)/.local/bin",
            "\(homePath)/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/opt/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        return unique(envPathEntries + fallbackEntries)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }

        return result
    }
}
