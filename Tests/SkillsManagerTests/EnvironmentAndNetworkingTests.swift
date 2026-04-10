import Foundation
import Testing
@testable import SkillsManager

struct EnvironmentAndNetworkingTests {
    @Test
    func locateFindsExecutableInFallbackDirectoriesWhenPATHIsMinimal() {
        let path = ExecutableLocator.resolve(
            command: "npx",
            environment: ["PATH": "/usr/bin:/bin"],
            homePath: "/Users/tester",
            isExecutable: { candidate in
                candidate == "/opt/homebrew/bin/npx"
            }
        )

        #expect(path == "/opt/homebrew/bin/npx")
    }

    @Test
    func buildEnvironmentPrependsResolvedExecutableDirectoryToPath() {
        let environment = ExecutableLocator.buildEnvironment(
            base: ["PATH": "/usr/bin:/bin"],
            homePath: "/Users/tester",
            resolvedExecutable: "/opt/homebrew/bin/npx"
        )

        #expect(environment["HOME"] == "/Users/tester")
        #expect(environment["XDG_CONFIG_HOME"] == "/Users/tester/.config")
        #expect(environment["PATH"]?.hasPrefix("/opt/homebrew/bin:/usr/bin:/bin") == true)
        #expect(environment["PATH"]?.contains("/Users/tester/.local/bin") == true)
    }

    @Test
    func networkSessionDisablesURLCacheBackedStorage() {
        let session = NetworkSessionFactory.makeEphemeralSession()

        #expect(session.configuration.urlCache == nil)
        #expect(session.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @MainActor
    @Test
    func discoverInstallTracksConcurrentActivitiesAndPreservesLogs() async throws {
        let firstStarted = AsyncStream.makeStream(of: Void.self)
        let secondStarted = AsyncStream.makeStream(of: Void.self)
        let agents = Locked<[String]>([])

        let store = SkillStore(
            directoryService: SkillsDirectoryService(),
            discoverInstaller: { skill, agentIDs, appendLog in
                agents.withLock { $0.append(contentsOf: agentIDs) }
                appendLog("Starting \(skill.skillId)")
                if skill.skillId == "first" {
                    firstStarted.continuation.yield()
                    try await Task.sleep(for: .milliseconds(50))
                    appendLog("Finished first")
                } else {
                    secondStarted.continuation.yield()
                    try await Task.sleep(for: .milliseconds(10))
                    appendLog("Finished second")
                }
            }
        )

        let first = DiscoverSkill(
            id: "repo:first",
            source: "repo",
            skillId: "first",
            name: "First",
            installs: 1,
            repoURL: URL(string: "https://github.com/example/repo")!,
            installCommand: "npx skills add https://github.com/example/repo --skill first",
            summary: nil,
            readmeExcerpt: nil
        )
        let second = DiscoverSkill(
            id: "repo:second",
            source: "repo",
            skillId: "second",
            name: "Second",
            installs: 1,
            repoURL: URL(string: "https://github.com/example/repo")!,
            installCommand: "npx skills add https://github.com/example/repo --skill second",
            summary: nil,
            readmeExcerpt: nil
        )

        async let installFirst: Void = store.installDiscoverSkill(first, agentIDs: ["claude-code", "cursor"])
        var firstIterator = firstStarted.stream.makeAsyncIterator()
        _ = await firstIterator.next()
        async let installSecond: Void = store.installDiscoverSkill(second, agentIDs: ["codex"])
        var secondIterator = secondStarted.stream.makeAsyncIterator()
        _ = await secondIterator.next()

        #expect(store.discoverInstallActivities.count == 2)
        #expect(store.isInstallingDiscoverSkill(first))
        #expect(store.isInstallingDiscoverSkill(second))

        _ = await (installFirst, installSecond)

        let firstActivity = try #require(store.discoverInstallActivity(for: first.id))
        let secondActivity = try #require(store.discoverInstallActivity(for: second.id))
        #expect(firstActivity.status == DiscoverInstallStatus.succeeded)
        #expect(secondActivity.status == DiscoverInstallStatus.succeeded)
        #expect(firstActivity.targetAgents == ["claude-code", "cursor"])
        #expect(secondActivity.targetAgents == ["codex"])
        #expect(firstActivity.log.contains(where: { $0.contains("Finished first") }))
        #expect(secondActivity.log.contains(where: { $0.contains("Finished second") }))
        #expect(agents.withLock { $0 } == ["claude-code", "cursor", "codex"])
    }

    @Test
    func agentRegistryIncludesClaudeCodeAsInstallTarget() {
        #expect(AgentRegistry.agent(id: "claude-code")?.displayName == "Claude Code")
        #expect(AgentRegistry.agent(id: "claude-code")?.cliCommands == ["claude"])
    }

    @Test
    func importedAgentFolderOverridesDetectionPath() {
        let imported = ["cursor": "/tmp/custom-cursor"]
        let installed = AgentRegistry.installedInstallTargets(importedPaths: imported) { path in
            path == "/tmp/custom-cursor" || path.hasSuffix("/.claude")
        }

        #expect(installed.contains(where: { $0.id == "cursor" }))
        #expect(installed.contains(where: { $0.id == "claude-code" }))
    }

    @Test
    func discoverDirectoryCategoryURLsMatchSkillsShSections() {
        #expect(DiscoverDirectoryCategory.allTime.url.absoluteString == "https://skills.sh/")
        #expect(DiscoverDirectoryCategory.trending.url.absoluteString == "https://skills.sh/trending")
        #expect(DiscoverDirectoryCategory.allCases.count == 2)
    }

    @Test
    func openAICompatibleProviderEndpointsAreNormalized() throws {
        let ollamaURL = try LLMService.debugResolvedChatCompletionsURL(for: LLMConfig(
            provider: .ollama,
            apiKey: "",
            model: "llama3",
            baseURL: "http://localhost:11434"
        ))
        #expect(ollamaURL.absoluteString == "http://localhost:11434/v1/chat/completions")

        let lmStudioURL = try LLMService.debugResolvedChatCompletionsURL(for: LLMConfig(
            provider: .lmStudio,
            apiKey: "",
            model: "local-model",
            baseURL: "http://localhost:1234/v1"
        ))
        #expect(lmStudioURL.absoluteString == "http://localhost:1234/v1/chat/completions")

        let openAIURL = try LLMService.debugResolvedChatCompletionsURL(for: LLMConfig(
            provider: .openAI,
            apiKey: "sk-test",
            model: "gpt-4o-mini",
            baseURL: "https://api.openai.com"
        ))
        #expect(openAIURL.absoluteString == "https://api.openai.com/v1/chat/completions")

        let customCompatibleURL = try LLMService.debugResolvedChatCompletionsURL(for: LLMConfig(
            provider: .openAI,
            apiKey: "sk-test",
            model: "gpt-4o-mini",
            baseURL: "https://example.com/v1/chat/completions"
        ))
        #expect(customCompatibleURL.absoluteString == "https://example.com/v1/chat/completions")
    }
}

private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
