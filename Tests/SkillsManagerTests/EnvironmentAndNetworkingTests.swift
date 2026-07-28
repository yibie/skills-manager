import Foundation
import Testing
@testable import SkillsManager

private final class SearchURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

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
            discoverCache: makeIsolatedDiscoverCache(),
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
            baseDescription: nil,
            baseDescriptionLocale: "en",
            localizedDescription: nil,
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
            baseDescription: nil,
            baseDescriptionLocale: "en",
            localizedDescription: nil,
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
        let installed = AgentRegistry.installedInstallTargets(
            importedPaths: imported,
            fileExists: { path in
                path == "/tmp/custom-cursor" || path.hasSuffix("/.claude")
            },
            executableExists: { _ in false }
        )

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
    func discoverSearchUsesThePublicApiSearchEndpoint() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = SkillsDirectoryService(session: session)

        SearchURLProtocol.requestHandler = { request in
            guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw URLError(.badURL)
            }
            #expect(components.host == "skills.sh")
            #expect(components.path == "/api/search")

            let queryItems = components.queryItems ?? []
            #expect(queryItems.first(where: { $0.name == "q" })?.value == "translate")
            #expect(queryItems.first(where: { $0.name == "limit" })?.value == "1000")

            let body = """
            {
              "query": "translate",
              "searchType": "global",
              "skills": [
                {
                  "id": "demo/repo/demo-skill",
                  "skillId": "demo-skill",
                  "name": "demo-skill",
                  "installs": 42,
                  "source": "demo/repo"
                }
              ],
              "count": 1,
              "duration_ms": 12
            }
            """
            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }
        defer { SearchURLProtocol.requestHandler = nil }

        let result = try await service.searchSkills(query: "translate")
        #expect(result.count == 1)
        #expect(result.skills.count == 1)
        #expect(result.skills.first?.id == "demo/repo:demo-skill")
        #expect(result.skills.first?.installCommand == "npx skills add https://github.com/demo/repo --skill demo-skill")
    }

    @Test
    func discoverDirectoryCachePersistsSearchAndDetailSnapshots() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("discover-cache-\(UUID().uuidString).json")
        let cache = DiscoverDirectoryCache(fileURL: cacheURL)
        let skill = DiscoverSkill(
            id: "demo/repo:demo-skill",
            source: "demo/repo",
            skillId: "demo-skill",
            name: "demo-skill",
            installs: 42,
            repoURL: URL(string: "https://github.com/demo/repo")!,
            installCommand: "npx skills add https://github.com/demo/repo --skill demo-skill",
            baseDescription: nil,
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            readmeExcerpt: nil
        )
        let detailed = DiscoverSkill(
            id: skill.id,
            source: skill.source,
            skillId: skill.skillId,
            name: skill.name,
            installs: skill.installs,
            repoURL: skill.repoURL,
            installCommand: skill.installCommand,
            baseDescription: "Short skill summary.",
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            readmeExcerpt: "Longer SKILL.md excerpt."
        )

        await cache.storeDirectory(skills: [skill], total: 91_000, category: .allTime)
        await cache.storeSearch(query: "Demo", skills: [skill], count: 1)
        await cache.storeDetail(detailed)

        let reloaded = DiscoverDirectoryCache(fileURL: cacheURL)
        let directorySnapshot = try #require(await reloaded.directorySnapshot(category: .allTime))
        let searchSnapshot = try #require(await reloaded.searchSnapshot(query: " demo "))
        let cachedDetail = try #require(await reloaded.detail(for: skill.id))

        #expect(directorySnapshot.total == 91_000)
        #expect(directorySnapshot.skills.first?.baseDescription == "Short skill summary.")
        #expect(searchSnapshot.total == 1)
        #expect(searchSnapshot.skills.first?.readmeExcerpt == "Longer SKILL.md excerpt.")
        #expect(cachedDetail.summary == "Short skill summary.")
        #expect(await reloaded.isDetailStale(for: skill.id, olderThan: 60 * 60) == false)
    }

    @Test
    func openAICompatibleProviderEndpointsAreNormalized() throws {
        let ollamaURL = try LLMService.debugResolvedChatCompletionsURL(for: LLMConfig(
            provider: .ollama,
            apiKey: "",
            model: "llama3",
            baseURL: "http://localhost:11434"
        ))
        #expect(ollamaURL.absoluteString == "http://127.0.0.1:11434/v1/chat/completions")

        let lmStudioURL = try LLMService.debugResolvedChatCompletionsURL(for: LLMConfig(
            provider: .lmStudio,
            apiKey: "",
            model: "local-model",
            baseURL: "http://localhost:1234/v1"
        ))
        #expect(lmStudioURL.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")

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

    @Test
    func localProviderChatCompletionTimeoutAllowsColdModelStarts() {
        let ollamaTimeout = LLMService.debugChatCompletionsTimeout(for: LLMConfig(
            provider: .ollama,
            apiKey: "",
            model: "qwen3.5:9b",
            baseURL: "http://127.0.0.1:11434"
        ))
        let openAITimeout = LLMService.debugChatCompletionsTimeout(for: LLMConfig(
            provider: .openAI,
            apiKey: "sk-test",
            model: "gpt-4o-mini",
            baseURL: "https://api.openai.com"
        ))

        #expect(ollamaTimeout == 180)
        #expect(openAITimeout == nil)
    }

    @Test
    func skillParserSeparatesFrontmatterFromMarkdownBody() {
        let content = """
        ---
        name: seo-monitoring
        description: Monitor SEO data and benchmarks.
        metadata:
          version: 1.0.0
        ---

        # SEO Monitoring

        Track rankings and indexing over time.
        """

        let parsed = SkillParser.parse(content: content)

        #expect(parsed.frontmatter["name"] == "seo-monitoring")
        #expect(parsed.frontmatter["description"] == "Monitor SEO data and benchmarks.")
        #expect(parsed.body.contains("# SEO Monitoring"))
        #expect(parsed.body.contains("Track rankings and indexing over time."))
        #expect(parsed.body.contains("name: seo-monitoring") == false)
        #expect(parsed.body.contains("metadata:") == false)
    }

    @Test
    func descriptionLanguageSettingsRespectSystemAndManualModes() {
        let suiteName = "DescriptionLanguageSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppSettings.currentDescriptionLocale(defaults: defaults, locale: Locale(identifier: "zh_Hans_CN")) == "zh-Hans-CN")

        defaults.set(DescriptionLanguageMode.manual.rawValue, forKey: AppSettings.descriptionLanguageModeKey)
        defaults.set("ja", forKey: AppSettings.manualDescriptionLocaleKey)

        #expect(AppSettings.currentDescriptionLocale(defaults: defaults, locale: Locale(identifier: "zh_Hans_CN")) == "ja")
    }

    @Test
    func descriptionLocaleDetectionHonorsFrontmatterAndChineseScripts() {
        #expect(DescriptionLocale.descriptionLocale(
            frontmatter: ["description_locale": "ja"],
            description: "Use this skill for code review."
        ) == "ja")
        #expect(DescriptionLocale.descriptionLocale(description: "用于分析和优化技能简介翻译。") == "zh-Hans")
        #expect(DescriptionLocale.descriptionLocale(description: "用於分析和優化技能簡介翻譯。") == "zh-Hant")
    }

    @Test
    func descriptionLocaleComparisonHandlesSimplifiedAndTraditionalChinese() {
        #expect(DescriptionLocale.shouldTranslate(sourceLocale: "zh-Hans", targetLocale: "zh-Hant"))
        #expect(DescriptionLocale.shouldTranslate(sourceLocale: "zh-Hant", targetLocale: "zh-Hans-CN"))
        #expect(!DescriptionLocale.shouldTranslate(sourceLocale: "zh-Hans", targetLocale: "zh-Hans-CN"))
        #expect(!DescriptionLocale.shouldTranslate(sourceLocale: "en-US", targetLocale: "en-GB"))
    }

    @Test
    func descriptionTranslationCacheUsesSourceHashAndLocalesForInvalidation() async {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("description-cache-\(UUID().uuidString).json")
        let cache = DescriptionTranslationCache(fileURL: cacheURL)

        await cache.store(
            skillID: "local:test",
            sourceText: "Translate this description.",
            sourceLocale: "en",
            targetLocale: "zh-Hans",
            translatedText: "翻译这段简介。"
        )

        let hit = await cache.translation(
            skillID: "local:test",
            sourceText: "Translate this description.",
            sourceLocale: "en",
            targetLocale: "zh-Hans"
        )
        let sharedHitForDifferentSkillID = await cache.translation(
            skillID: "universal:test",
            sourceText: "Translate this description.",
            sourceLocale: "en",
            targetLocale: "zh-Hans"
        )
        let missForTargetLocale = await cache.translation(
            skillID: "local:test",
            sourceText: "Translate this description.",
            sourceLocale: "en",
            targetLocale: "ja"
        )
        let missForSourceLocale = await cache.translation(
            skillID: "local:test",
            sourceText: "Translate this description.",
            sourceLocale: "ja",
            targetLocale: "zh-Hans"
        )
        let missForSource = await cache.translation(
            skillID: "local:test",
            sourceText: "Translate this description differently.",
            sourceLocale: "en",
            targetLocale: "zh-Hans"
        )

        #expect(hit == "翻译这段简介。")
        #expect(sharedHitForDifferentSkillID == "翻译这段简介。")
        #expect(missForTargetLocale == nil)
        #expect(missForSourceLocale == nil)
        #expect(missForSource == nil)
    }

    @Test
    func descriptionTranslationCacheReadsPrebuiltCatalogBeforeUserCache() async {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("description-cache-\(UUID().uuidString).json")
        let catalog = DescriptionTranslationCache.Catalog(entries: [
            DescriptionTranslationCache.cacheKey(
                skillID: "local:test",
                sourceText: "Translate this description.",
                sourceLocale: "en",
                targetLocale: "zh-Hans"
            ): "预装翻译"
        ])
        let cache = DescriptionTranslationCache(fileURL: cacheURL, catalog: catalog)

        let hit = await cache.translation(
            skillID: "local:test",
            sourceText: "Translate this description.",
            sourceLocale: "en",
            targetLocale: "zh-Hans"
        )
        let miss = await cache.translation(
            skillID: "local:test",
            sourceText: "Translate this description.",
            sourceLocale: "en",
            targetLocale: "ja"
        )

        #expect(hit == "预装翻译")
        #expect(miss == nil)
    }

    @Test
    func descriptionTranslationCatalogLoadsGeneratedResourceShape() async throws {
        let sourceText = "Translate this description."
        let key = DescriptionTranslationCache.cacheKey(
            skillID: "local:test",
            sourceText: sourceText,
            sourceLocale: "en",
            targetLocale: "zh-Hans"
        )
        let catalogURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("description-catalog-\(UUID().uuidString).json")
        let payload = """
        {
          "version": "\(DescriptionTranslationCache.translatorVersion)",
          "generatedAt": "2026-04-25T00:00:00Z",
          "locales": ["en", "zh-Hans"],
          "entries": {
            "\(key)": "生成的预装翻译"
          }
        }
        """
        try payload.data(using: .utf8)?.write(to: catalogURL)

        let catalog = DescriptionTranslationCache.Catalog.load(from: catalogURL)
        let cache = DescriptionTranslationCache(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("description-cache-\(UUID().uuidString).json"),
            catalog: catalog
        )

        let hit = await cache.translation(
            skillID: "local:any-id",
            sourceText: sourceText,
            sourceLocale: "en",
            targetLocale: "zh-Hans"
        )

        #expect(hit == "生成的预装翻译")
    }

    @MainActor
    @Test
    func refreshingLocalizedDescriptionsUsesCacheWithoutTriggeringTranslation() async {
        let localizer = MockDescriptionLocalizer()
        await localizer.setCachedTranslation("缓存翻译")

        let store = makeIsolatedSkillStore(descriptionLocalizer: localizer)
        store.skills = [
            Skill(
                id: "local:test",
                name: "test",
                displayName: "Test",
                baseDescription: "Base description",
                baseDescriptionLocale: "en",
                localizedDescription: nil,
                source: .local,
                version: nil,
                filePath: URL(fileURLWithPath: "/tmp/SKILL.md"),
                directoryPath: URL(fileURLWithPath: "/tmp"),
                compatibleAgents: [],
                tags: [],
                markdownContent: "",
                frontmatter: [:]
            )
        ]

        await store.refreshLocalizedDescriptions(using: Locale(identifier: "zh_Hans_CN"))

        #expect(store.skills.first?.localizedDescription == "缓存翻译")
        #expect(await localizer.cachedCallCount == 1)
        #expect(await localizer.translateCallCount == 0)
    }

    @MainActor
    @Test
    func manualTranslationButtonFlowTriggersTranslationRequests() async {
        let localizer = MockDescriptionLocalizer()
        await localizer.setAttempt(.translated("手动翻译"))

        let store = makeIsolatedSkillStore(descriptionLocalizer: localizer)
        store.skills = [
            Skill(
                id: "local:test",
                name: "test",
                displayName: "Test",
                baseDescription: "Base description",
                baseDescriptionLocale: "en",
                localizedDescription: nil,
                source: .local,
                version: nil,
                filePath: URL(fileURLWithPath: "/tmp/SKILL.md"),
                directoryPath: URL(fileURLWithPath: "/tmp"),
                compatibleAgents: [],
                tags: [],
                markdownContent: "",
                frontmatter: [:]
            )
        ]

        await store.translateDescriptions(using: Locale(identifier: "zh_Hans_CN"))

        #expect(store.skills.first?.localizedDescription == "手动翻译")
        #expect(await localizer.translateCallCount == 1)
        #expect(store.lastTranslationSummary == DescriptionTranslationSummary(translated: 1, skipped: 0, failed: 0))
    }

    @MainActor
    @Test
    func loadedDiscoverDetailAutoTranslatesAfterManualTranslationWasRequested() async {
        let localizer = MockDescriptionLocalizer()
        await localizer.setAttempt(.translated("详情翻译"))

        let store = makeIsolatedSkillStore(descriptionLocalizer: localizer)

        await store.translateDescriptions(using: Locale(identifier: "zh_Hans_CN"))

        let detail = DiscoverSkill(
            id: "repo:test",
            source: "repo",
            skillId: "test",
            name: "Test",
            installs: 1,
            repoURL: URL(string: "https://github.com/example/repo")!,
            installCommand: "npx skills add https://github.com/example/repo --skill test",
            baseDescription: "Base detail",
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            readmeExcerpt: nil
        )

        await store.storeLoadedDiscoverDetail(detail, locale: Locale(identifier: "zh_Hans_CN"))

        #expect(store.discoverableSkillDetails[detail.id]?.localizedDescription == "详情翻译")
        #expect(await localizer.translateCallCount == 1)
    }

    @MainActor
    @Test
    func translationSummaryShowsDeferredDiscoverSummaries() async throws {
        let localizer = MockDescriptionLocalizer()

        let store = makeIsolatedSkillStore(descriptionLocalizer: localizer)
        store.discoverableSkills = [
            DiscoverSkill(
                id: "repo:test",
                source: "repo",
                skillId: "test",
                name: "Test",
                installs: 1,
                repoURL: URL(string: "https://github.com/example/repo")!,
                installCommand: "npx skills add https://github.com/example/repo --skill test",
                baseDescription: nil,
                baseDescriptionLocale: "en",
                localizedDescription: nil,
                readmeExcerpt: nil
            )
        ]

        await store.translateDescriptions(using: Locale(identifier: "zh_Hans_CN"))

        let summary = try #require(store.lastTranslationSummary)
        #expect(summary.failed == 0)
        #expect(summary.deferredReasons[.summaryNotLoaded] == 1)
        #expect(summary.skippedReasons[.missingBaseDescription] == nil)
        #expect(summary.breakdownText?.contains("summary not loaded 1") == true)
    }

    @MainActor
    @Test
    func translationDebugLoggingPrintsSummaryAndFailures() async throws {
        let localizer = MockDescriptionLocalizer()
        await localizer.setAttempt(.failed(.requestTimedOut))
        let logs = Locked<[String]>([])

        let store = makeIsolatedSkillStore(
            descriptionLocalizer: localizer,
            translationDebugLogger: { line in
                logs.withLock { $0.append(line) }
            }
        )
        store.skills = [
            Skill(
                id: "local:test",
                name: "test",
                displayName: "Test",
                baseDescription: "Base description",
                baseDescriptionLocale: "en",
                localizedDescription: nil,
                source: .local,
                version: nil,
                filePath: URL(fileURLWithPath: "/tmp/SKILL.md"),
                directoryPath: URL(fileURLWithPath: "/tmp"),
                compatibleAgents: [],
                tags: [],
                markdownContent: "",
                frontmatter: [:]
            )
        ]
        store.discoverableSkills = [
            DiscoverSkill(
                id: "repo:test",
                source: "repo",
                skillId: "test",
                name: "Test",
                installs: 1,
                repoURL: URL(string: "https://github.com/example/repo")!,
                installCommand: "npx skills add https://github.com/example/repo --skill test",
                baseDescription: nil,
                baseDescriptionLocale: "en",
                localizedDescription: nil,
                readmeExcerpt: nil
            )
        ]

        await store.translateDescriptions(using: Locale(identifier: "zh_Hans_CN"))

        let output = logs.withLock { $0 }
        #expect(output.contains(where: { $0.contains("local:test") && $0.contains("timeout") }))
        #expect(output.contains(where: { $0.contains("Translated 0") && $0.contains("Skipped 0") && $0.contains("Failed 1") }))
    }

    @MainActor
    @Test
    func translationStopsAfterFirstProviderFailureWithoutCooldownCascade() async throws {
        let localizer = MockDescriptionLocalizer()
        await localizer.setAttempts([
            .failed(.requestTimedOut),
            .failed(.providerCooldown)
        ])
        let logs = Locked<[String]>([])

        let store = makeIsolatedSkillStore(
            descriptionLocalizer: localizer,
            translationDebugLogger: { line in
                logs.withLock { $0.append(line) }
            }
        )
        store.skills = [
            makeLocalSkill(id: "local:first", baseDescription: "First description"),
            makeLocalSkill(id: "local:second", baseDescription: "Second description")
        ]

        await store.translateDescriptions(using: Locale(identifier: "zh_Hans_CN"))

        let summary = try #require(store.lastTranslationSummary)
        let output = logs.withLock { $0 }
        #expect(await localizer.translateCallCount == 1)
        #expect(summary.failedReasons[.requestTimedOut] == 1)
        #expect(summary.failedReasons[.providerCooldown] == nil)
        #expect(output.filter { $0.contains("[DescriptionTranslation] failed") }.count == 1)
        #expect(output.contains(where: { $0.contains("local:first") && $0.contains("timeout") }))
        #expect(output.contains(where: { $0.contains("local:second") }) == false)
    }

    @MainActor
    @Test
    func selectedSkillTranslationDoesNotBatchTranslateOtherLocalSkills() async throws {
        let localizer = MockDescriptionLocalizer()
        await localizer.setAttempt(.translated("Second translated"))

        let store = makeIsolatedSkillStore(descriptionLocalizer: localizer)
        store.skills = [
            makeLocalSkill(id: "local:first", baseDescription: "First description"),
            makeLocalSkill(id: "local:second", baseDescription: "Second description")
        ]

        await store.translateDescriptions(
            using: Locale(identifier: "zh_Hans_CN"),
            scope: .skill(id: "local:second")
        )

        #expect(await localizer.translateCallCount == 1)
        #expect(store.skills.first { $0.id == "local:first" }?.localizedDescription == nil)
        #expect(store.skills.first { $0.id == "local:second" }?.localizedDescription == "Second translated")
        #expect(store.lastTranslationSummary == DescriptionTranslationSummary(translated: 1, skipped: 0, failed: 0))
    }

    @MainActor
    @Test
    func loadedDiscoverTranslationDoesNotRequestUnloadedSummaries() async throws {
        let localizer = MockDescriptionLocalizer()
        await localizer.setAttempt(.translated("Loaded translated"))

        let store = makeIsolatedSkillStore(descriptionLocalizer: localizer)
        store.discoverableSkills = [
            makeDiscoverSkill(id: "repo:loaded", baseDescription: nil),
            makeDiscoverSkill(id: "repo:unloaded", baseDescription: nil)
        ]
        store.discoverableSkillDetails = [
            "repo:loaded": makeDiscoverSkill(id: "repo:loaded", baseDescription: "Loaded summary")
        ]

        await store.translateDescriptions(
            using: Locale(identifier: "zh_Hans_CN"),
            scope: .loadedDiscoverDetails
        )

        #expect(await localizer.translateCallCount == 1)
        #expect(store.discoverableSkillDetails["repo:loaded"]?.localizedDescription == "Loaded translated")
        #expect(store.discoverableSkillDetails["repo:unloaded"] == nil)
        #expect(store.lastTranslationSummary == DescriptionTranslationSummary(translated: 1, skipped: 0, failed: 0))
    }

    @MainActor
    @Test
    func homepageDiscoverTranslationTranslatesCachedDetails() async throws {
        let localizer = MockDescriptionLocalizer()
        await localizer.setAttempt(.translated("首页翻译"))

        let store = makeIsolatedSkillStore(descriptionLocalizer: localizer)
        let homeSkill = makeDiscoverSkill(id: "repo:home", baseDescription: nil)
        store.discoverableSkills = [homeSkill]
        store.discoverableSkillDetails = [
            homeSkill.id: makeDiscoverSkill(id: homeSkill.id, baseDescription: "Home summary")
        ]

        let summary = await store.translateDiscoverHomeSkills(using: Locale(identifier: "zh_Hans_CN"))

        #expect(await localizer.translateCallCount == 1)
        #expect(summary == DescriptionTranslationSummary(translated: 1, skipped: 0, failed: 0))
        #expect(store.discoverableSkillDetails[homeSkill.id]?.localizedDescription == "首页翻译")
    }

    @Test
    func lifecycleDetectsSkillsCLIProvenanceFromItsLockfile() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("skills-cli-provenance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let lockFile = home.appendingPathComponent(".agents/.skill-lock.json")
        try FileManager.default.createDirectory(
            at: lockFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "version": 3,
          "skills": {
            "external-skill": {
              "source": "example/repo",
              "sourceType": "github",
              "sourceUrl": "https://github.com/example/repo",
              "ref": "release/1",
              "skillPath": "skills/external-skill",
              "skillFolderHash": "abc123",
              "installedAt": "2026-01-01T00:00:00Z",
              "updatedAt": "2026-01-02T00:00:00Z"
            }
          }
        }
        """.write(to: lockFile, atomically: true, encoding: .utf8)

        var skill = makeLocalSkill(id: "universal:external-skill", baseDescription: "")
        skill.name = "external-skill"
        skill.directoryPath = home.appendingPathComponent(".agents/skills/external-skill")
        skill.filePath = skill.directoryPath.appendingPathComponent("SKILL.md")

        let annotated = SkillLifecycleService(home: home, environment: [:]).annotate([skill])
        let provenance = try #require(annotated.first?.provenance)

        #expect(provenance.provider == .skillsCLI)
        #expect(provenance.sourceURL == URL(string: "https://github.com/example/repo"))
        #expect(provenance.skillID == "external-skill")
        #expect(provenance.sourceRef == "release/1")
        #expect(annotated.first?.canUpdate == true)
    }

    @Test
    func skillsCLILockDoesNotClaimSameNamedManualSkill() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("skills-cli-manual-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let lockFile = home.appendingPathComponent(".agents/.skill-lock.json")
        try FileManager.default.createDirectory(
            at: lockFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "version": 3,
          "skills": {
            "external-skill": {
              "sourceUrl": "https://github.com/example/repo"
            }
          }
        }
        """.write(to: lockFile, atomically: true, encoding: .utf8)

        var skill = makeLocalSkill(id: "local:external-skill", baseDescription: "")
        skill.name = "external-skill"
        skill.directoryPath = home.appendingPathComponent(".claude/skills/external-skill")
        skill.filePath = skill.directoryPath.appendingPathComponent("SKILL.md")

        let annotated = SkillLifecycleService(home: home, environment: [:]).annotate([skill])

        #expect(annotated.first?.provenance.provider == .manual)
        #expect(annotated.first?.canUpdate == false)
    }

    @Test
    func discoverInstallUsesNativeLifecycleInsteadOfSkillsCLI() async throws {
        let nativeInstalls = Locked<[String]>([])
        let providerCommands = Locked<[[String]]>([])
        let service = SkillLifecycleService(
            installNative: { skill, agentIDs, _ in
                nativeInstalls.withLock { $0.append("\(skill.skillId):\(agentIDs.joined(separator: ","))") }
            },
            runProviderCommand: { args, _ in
                providerCommands.withLock { $0.append(args) }
            },
            isSkillsCLIAvailable: { true }
        )

        try await service.installDiscover(
            makeDiscoverSkill(id: "repo:native", baseDescription: nil),
            agentIDs: ["codex", "claude-code"],
            appendLog: { _ in }
        )

        #expect(nativeInstalls.withLock { $0 } == ["repo:native:codex,claude-code"])
        #expect(providerCommands.withLock { $0 }.isEmpty)
    }

    @Test
    func nativeInstallerAcceptsSkillsCLIGitSuffixedRepositoryURL() throws {
        let archive = try NativeSkillPackageInstaller.archiveURL(
            for: URL(string: "https://github.com/example/repo.git")!,
            ref: "release/1"
        )

        #expect(
            archive.absoluteString
                == "https://api.github.com/repos/example/repo/zipball/release%2F1"
        )
    }

    @Test
    func skillsCLIManagedSkillUsesProviderForUpdateAndRemoval() async throws {
        let providerCommands = Locked<[[String]]>([])
        let nativeInstalls = Locked<[String]>([])
        let nativeUninstalls = Locked<[String]>([])
        let service = SkillLifecycleService(
            installNative: { skill, _, _ in
                nativeInstalls.withLock { $0.append(skill.skillId) }
            },
            removeNative: { skill in
                nativeUninstalls.withLock { $0.append(skill.name) }
            },
            runProviderCommand: { args, _ in
                providerCommands.withLock { $0.append(args) }
            },
            isSkillsCLIAvailable: { true }
        )
        var skill = makeLifecycleSkill()
        skill.provenance = SkillProvenance(
            provider: .skillsCLI,
            sourceURL: URL(string: "https://github.com/example/repo"),
            skillID: "managed-skill"
        )

        try await service.install(skill, agentIDs: ["codex", "claude-code"], appendLog: { _ in })
        try await service.update(skill, agentIDs: ["codex"], appendLog: { _ in })
        try await service.removeFromLibrary(skill, appendLog: { _ in })

        let pinned = "skills@\(SkillLifecycleService.skillsCLIVersion)"
        #expect(providerCommands.withLock { $0 } == [
            [
                "-y", pinned, "add", "https://github.com/example/repo",
                "--skill", "managed-skill", "--agent", "codex", "claude-code",
                "--global", "--yes",
            ],
            ["-y", pinned, "update", "managed-skill", "--global", "--yes"],
            ["-y", pinned, "remove", "managed-skill", "--global", "--yes"],
        ])
        #expect(nativeInstalls.withLock { $0 }.isEmpty)
        #expect(nativeUninstalls.withLock { $0 }.isEmpty)
    }

    @Test
    func unavailableSkillsCLIFallsBackToNativeLifecycle() async throws {
        let nativeInstalls = Locked<[String]>([])
        let nativeUninstalls = Locked<[String]>([])
        let service = SkillLifecycleService(
            installNative: { skill, agentIDs, _ in
                nativeInstalls.withLock {
                    $0.append("\(skill.skillId)@\(skill.repositoryRef ?? "default"):\(agentIDs.joined(separator: ","))")
                }
            },
            removeNative: { skill in
                nativeUninstalls.withLock { $0.append(skill.name) }
            },
            runProviderCommand: { _, _ in
                Issue.record("Provider command should not run when the CLI is unavailable")
            },
            isSkillsCLIAvailable: { false }
        )
        var skill = makeLifecycleSkill()
        skill.provenance = SkillProvenance(
            provider: .skillsCLI,
            sourceURL: URL(string: "https://github.com/example/repo"),
            skillID: "managed-skill",
            sourceRef: "release/1"
        )

        try await service.update(skill, agentIDs: ["codex"], appendLog: { _ in })
        try await service.removeFromLibrary(skill, appendLog: { _ in })

        #expect(nativeInstalls.withLock { $0 } == ["managed-skill@release/1:codex"])
        #expect(nativeUninstalls.withLock { $0 } == ["managed-skill"])
    }

    @Test
    func skillsCLITakeoverRepairsProviderDirectoryWithTrustedCanonical() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try createLifecycleSkill(at: fixture.providerSkill)
        try createManagedLifecycleSkill(at: fixture.canonicalSkill)
        try writeSkillsCLILock(at: fixture.lockFile)

        try await runSkillsCLITakeoverUpdate(fixture)
        try await runSkillsCLITakeoverUpdate(fixture)

        try expectProviderLink(fixture.providerSkill, pointsTo: fixture.canonicalSkill)
        #expect(FileManager.default.fileExists(atPath: fixture.backup.path) == false)
        try expectSkillsCLILockCleared(fixture.lockFile)
    }

    @Test
    func skillsCLITakeoverRecoversFromDeterministicBackupWithTrustedCanonical() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try createLifecycleSkill(at: fixture.backup)
        try createManagedLifecycleSkill(at: fixture.canonicalSkill)
        try writeSkillsCLILock(at: fixture.lockFile)

        try await runSkillsCLITakeoverUpdate(fixture)
        try await runSkillsCLITakeoverUpdate(fixture)

        try expectProviderLink(fixture.providerSkill, pointsTo: fixture.canonicalSkill)
        #expect(FileManager.default.fileExists(atPath: fixture.backup.path) == false)
        try expectSkillsCLILockCleared(fixture.lockFile)
    }

    @Test
    func skillsCLITakeoverWithCorrectProviderLinkOnlyClearsLock() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try createManagedLifecycleSkill(at: fixture.canonicalSkill)
        try FileManager.default.createDirectory(
            at: fixture.providerSkill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: fixture.providerSkill.path,
            withDestinationPath: fixture.canonicalSkill.path
        )
        try writeSkillsCLILock(at: fixture.lockFile)

        try await runSkillsCLITakeoverUpdate(fixture)
        try await runSkillsCLITakeoverUpdate(fixture)

        try expectProviderLink(fixture.providerSkill, pointsTo: fixture.canonicalSkill)
        try expectSkillsCLILockCleared(fixture.lockFile)
    }

    @Test
    func skillsCLITakeoverRecreatesMissingProviderLinkForTrustedCanonical() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try createManagedLifecycleSkill(at: fixture.canonicalSkill)
        try writeSkillsCLILock(at: fixture.lockFile)

        try await runSkillsCLITakeoverUpdate(fixture)
        try await runSkillsCLITakeoverUpdate(fixture)

        try expectProviderLink(fixture.providerSkill, pointsTo: fixture.canonicalSkill)
        #expect(FileManager.default.fileExists(atPath: fixture.backup.path) == false)
        try expectSkillsCLILockCleared(fixture.lockFile)
    }

    @Test
    func skillsCLITakeoverInstallsCanonicalWhenNoRecoveryStateExists() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try createLifecycleSkill(at: fixture.providerSkill)
        try writeSkillsCLILock(at: fixture.lockFile)
        let installCount = Locked(0)
        let service = SkillLifecycleService(
            home: fixture.home,
            canonicalSkillsDirectory: fixture.canonicalRoot,
            environment: [:],
            installNative: { _, _, _ in
                installCount.withLock { $0 += 1 }
                try createManagedLifecycleSkill(at: fixture.canonicalSkill)
            },
            trashItem: { try FileManager.default.removeItem(at: $0) },
            isSkillsCLIAvailable: { false }
        )

        try await service.update(makeSkillsCLITakeoverSkill(fixture), agentIDs: ["codex"], appendLog: { _ in })

        #expect(installCount.withLock { $0 } == 1)
        try expectProviderLink(fixture.providerSkill, pointsTo: fixture.canonicalSkill)
        #expect(FileManager.default.fileExists(atPath: fixture.backup.path) == false)
        try expectSkillsCLILockCleared(fixture.lockFile)
    }

    @Test
    func skillsCLITakeoverInstallRepairsProviderDirectoryWithTrustedCanonical() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try createLifecycleSkill(at: fixture.providerSkill)
        try createManagedLifecycleSkill(at: fixture.canonicalSkill)
        try writeSkillsCLILock(at: fixture.lockFile)
        let service = SkillLifecycleService(
            home: fixture.home,
            canonicalSkillsDirectory: fixture.canonicalRoot,
            environment: [:],
            installNative: { _, _, _ in
                Issue.record("Trusted takeover recovery should not reinstall the canonical skill")
            },
            trashItem: { try FileManager.default.removeItem(at: $0) },
            isSkillsCLIAvailable: { false }
        )

        try await service.install(makeSkillsCLITakeoverSkill(fixture), agentIDs: ["codex"], appendLog: { _ in })

        try expectProviderLink(fixture.providerSkill, pointsTo: fixture.canonicalSkill)
        #expect(FileManager.default.fileExists(atPath: fixture.backup.path) == false)
        try expectSkillsCLILockCleared(fixture.lockFile)
    }

    @Test
    func skillsCLITakeoverDiagnosesCanonicalConflictAndPreservesCopies() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try createLifecycleSkill(at: fixture.providerSkill)
        try createLifecycleSkill(at: fixture.canonicalSkill)
        try writeSkillsCLILock(at: fixture.lockFile)

        await #expect(throws: SymlinkInstallerError.self) {
            try await runSkillsCLITakeoverUpdate(fixture)
        }

        #expect(FileManager.default.fileExists(atPath: fixture.providerSkill.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: fixture.canonicalSkill.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: fixture.backup.path) == false)
        let lock = try String(contentsOf: fixture.lockFile, encoding: .utf8)
        #expect(lock.contains("managed-skill"))
    }

    @Test
    func skillsCLITakeoverDiagnosesForgedNonGitHubCanonicalAndPreservesState() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let forgedSource = URL(string: "https://example.com/example/repo")!
        try createLifecycleSkill(at: fixture.providerSkill)
        try createManagedLifecycleSkill(at: fixture.canonicalSkill, sourceURL: forgedSource.absoluteString)
        try writeSkillsCLILock(at: fixture.lockFile, sourceURL: forgedSource.absoluteString)

        await #expect(throws: SymlinkInstallerError.self) {
            try await runSkillsCLITakeoverUpdate(fixture, sourceURL: forgedSource)
        }

        #expect(FileManager.default.fileExists(atPath: fixture.providerSkill.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: fixture.canonicalSkill.appendingPathComponent("SKILL.md").path))
        let lock = try String(contentsOf: fixture.lockFile, encoding: .utf8)
        #expect(lock.contains("managed-skill"))
    }

    @Test
    func skillsCLITakeoverDiagnosesDanglingCanonicalSymlinkAndPreservesState() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let missingTarget = fixture.home.appendingPathComponent("missing-canonical-target")
        try createLifecycleSkill(at: fixture.providerSkill)
        try FileManager.default.createDirectory(
            at: fixture.canonicalSkill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: fixture.canonicalSkill.path,
            withDestinationPath: missingTarget.path
        )
        try writeSkillsCLILock(at: fixture.lockFile)

        await #expect(throws: SymlinkInstallerError.self) {
            try await runSkillsCLITakeoverUpdate(fixture)
        }

        #expect(FileManager.default.fileExists(atPath: fixture.providerSkill.appendingPathComponent("SKILL.md").path))
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: fixture.canonicalSkill.path)
        #expect(URL(fileURLWithPath: destination).standardizedFileURL == missingTarget.standardizedFileURL)
        let lock = try String(contentsOf: fixture.lockFile, encoding: .utf8)
        #expect(lock.contains("managed-skill"))
    }

    @Test
    func skillsCLITakeoverDiagnosesBackupOnlyAndPreservesBackup() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try createLifecycleSkill(at: fixture.backup)
        try writeSkillsCLILock(at: fixture.lockFile)

        await #expect(throws: SymlinkInstallerError.self) {
            try await runSkillsCLITakeoverUpdate(fixture)
        }

        #expect(FileManager.default.fileExists(atPath: fixture.providerSkill.path) == false)
        #expect(FileManager.default.fileExists(atPath: fixture.canonicalSkill.path) == false)
        #expect(FileManager.default.fileExists(atPath: fixture.backup.appendingPathComponent("SKILL.md").path))
        let lock = try String(contentsOf: fixture.lockFile, encoding: .utf8)
        #expect(lock.contains("managed-skill"))
    }

    @Test
    func skillsCLITakeoverDiagnosesWrongProviderSymlinkAndPreservesState() async throws {
        let fixture = try makeSkillsCLITakeoverFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let wrongTarget = fixture.home.appendingPathComponent("wrong-target")
        try createLifecycleSkill(at: wrongTarget)
        try createManagedLifecycleSkill(at: fixture.canonicalSkill)
        try FileManager.default.createDirectory(
            at: fixture.providerSkill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: fixture.providerSkill.path,
            withDestinationPath: wrongTarget.path
        )
        try writeSkillsCLILock(at: fixture.lockFile)

        await #expect(throws: SymlinkInstallerError.self) {
            try await runSkillsCLITakeoverUpdate(fixture)
        }

        try expectProviderLink(fixture.providerSkill, pointsTo: wrongTarget)
        #expect(FileManager.default.fileExists(atPath: fixture.canonicalSkill.appendingPathComponent("SKILL.md").path))
        let lock = try String(contentsOf: fixture.lockFile, encoding: .utf8)
        #expect(lock.contains("managed-skill"))
    }

    @Test
    func openClawRemovalUsesTrashInsteadOfPermanentDelete() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclaw-trash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".openclaw/workspace-main/skills/example")
        try createLifecycleSkill(at: directory)
        let trashed = Locked<[URL]>([])
        let service = SkillLifecycleService(
            home: home,
            trashItem: { url in
                trashed.withLock { $0.append(url) }
            }
        )
        var skill = makeLifecycleSkill()
        skill.directoryPath = directory
        skill.filePath = directory.appendingPathComponent("SKILL.md")
        skill.source = .openClaw(root: "workspace-main")
        skill.provenance = SkillProvenance(provider: .openClaw, sourceURL: nil, skillID: "example")

        try await service.removeFromLibrary(skill, appendLog: { _ in })

        #expect(
            trashed.withLock { $0.first?.standardizedFileURL.path }
                == directory.standardizedFileURL.path
        )
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }
}

private func makeIsolatedDiscoverCache() -> DiscoverDirectoryCache {
    DiscoverDirectoryCache(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("discover-cache-\(UUID().uuidString).json")
    )
}

@MainActor
private func makeIsolatedSkillStore(
    descriptionLocalizer: any DescriptionLocalizing,
    translationDebugLogger: @escaping @Sendable (String) -> Void = { _ in }
) -> SkillStore {
    SkillStore(
        discoverCache: makeIsolatedDiscoverCache(),
        descriptionLocalizer: descriptionLocalizer,
        translationDebugLogger: translationDebugLogger
    )
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

actor MockDescriptionLocalizer: DescriptionLocalizing {
    private(set) var cachedCallCount = 0
    private(set) var translateCallCount = 0
    private var cachedTranslation: String?
    private var attempt: DescriptionTranslationAttempt = .failed(.requestFailed)
    private var attempts: [DescriptionTranslationAttempt] = []

    func setCachedTranslation(_ value: String?) {
        cachedTranslation = value
    }

    func setAttempt(_ value: DescriptionTranslationAttempt) {
        attempt = value
        attempts = []
    }

    func setAttempts(_ values: [DescriptionTranslationAttempt]) {
        attempts = values
    }

    func cachedTranslation(
        skillID: String,
        baseDescription: String,
        baseDescriptionLocale: String,
        locale: Locale
    ) async -> String? {
        cachedCallCount += 1
        return cachedTranslation
    }

    func translationAttempt(
        skillID: String,
        baseDescription: String,
        baseDescriptionLocale: String,
        locale: Locale,
        config: LLMConfig
    ) async -> DescriptionTranslationAttempt {
        translateCallCount += 1
        if !attempts.isEmpty {
            return attempts.removeFirst()
        }
        return attempt
    }
}

private func makeLocalSkill(id: String, baseDescription: String) -> Skill {
    Skill(
        id: id,
        name: id,
        displayName: id,
        baseDescription: baseDescription,
        baseDescriptionLocale: "en",
        localizedDescription: nil,
        source: .local,
        version: nil,
        filePath: URL(fileURLWithPath: "/tmp/SKILL.md"),
        directoryPath: URL(fileURLWithPath: "/tmp"),
        compatibleAgents: [],
        tags: [],
        markdownContent: "",
        frontmatter: [:]
    )
}

private func makeDiscoverSkill(id: String, baseDescription: String?) -> DiscoverSkill {
    DiscoverSkill(
        id: id,
        source: "repo",
        skillId: id,
        name: id,
        installs: 1,
        repoURL: URL(string: "https://github.com/example/repo")!,
        installCommand: "npx skills add https://github.com/example/repo --skill \(id)",
        baseDescription: baseDescription,
        baseDescriptionLocale: "en",
        localizedDescription: nil,
        readmeExcerpt: nil
    )
}

private func makeLifecycleSkill() -> Skill {
    Skill(
        id: "universal:managed-skill",
        name: "managed-skill",
        displayName: "Managed Skill",
        baseDescription: "",
        baseDescriptionLocale: "en",
        localizedDescription: nil,
        source: .local,
        version: nil,
        filePath: URL(fileURLWithPath: "/tmp/managed-skill/SKILL.md"),
        directoryPath: URL(fileURLWithPath: "/tmp/managed-skill"),
        compatibleAgents: ["Codex"],
        tags: [],
        markdownContent: "",
        frontmatter: [:]
    )
}

private func createLifecycleSkill(at directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "---\nname: managed-skill\n---\n".write(
        to: directory.appendingPathComponent("SKILL.md"),
        atomically: true,
        encoding: .utf8
    )
}

private struct SkillsCLITakeoverFixture {
    var home: URL
    var providerSkill: URL
    var canonicalRoot: URL
    var canonicalSkill: URL
    var backup: URL
    var lockFile: URL
}

private func makeSkillsCLITakeoverFixture() throws -> SkillsCLITakeoverFixture {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("skills-cli-takeover-\(UUID().uuidString)")
    let providerSkill = home.appendingPathComponent(".agents/skills/managed-skill")
    let canonicalRoot = home.appendingPathComponent(".config/agents/skills")
    return SkillsCLITakeoverFixture(
        home: home,
        providerSkill: providerSkill,
        canonicalRoot: canonicalRoot,
        canonicalSkill: canonicalRoot.appendingPathComponent("managed-skill"),
        backup: providerSkill.deletingLastPathComponent()
            .appendingPathComponent(".managed-skill-skills-cli-backup"),
        lockFile: home.appendingPathComponent(".agents/.skill-lock.json")
    )
}

private func createManagedLifecycleSkill(
    at directory: URL,
    sourceURL: String = "https://github.com/example/repo"
) throws {
    try createLifecycleSkill(at: directory)
    try "1\n".write(
        to: directory.appendingPathComponent(SymlinkInstaller.managedMarkerName),
        atomically: true,
        encoding: .utf8
    )
    try """
    {
      "sourceURL": "\(sourceURL)",
      "skillID": "managed-skill",
      "installedAt": 0
    }
    """.write(
        to: directory.appendingPathComponent(SymlinkInstaller.managedManifestName),
        atomically: true,
        encoding: .utf8
    )
}

private func writeSkillsCLILock(
    at lockFile: URL,
    sourceURL: String = "https://github.com/example/repo"
) throws {
    try FileManager.default.createDirectory(
        at: lockFile.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try """
    {
      "version": 3,
      "skills": {
        "managed-skill": {
          "sourceUrl": "\(sourceURL)",
          "skillPath": "skills/managed-skill"
        }
      }
    }
    """.write(to: lockFile, atomically: true, encoding: .utf8)
}

private func runSkillsCLITakeoverUpdate(
    _ fixture: SkillsCLITakeoverFixture,
    sourceURL: URL = URL(string: "https://github.com/example/repo")!
) async throws {
    let service = SkillLifecycleService(
        home: fixture.home,
        canonicalSkillsDirectory: fixture.canonicalRoot,
        environment: [:],
        installNative: { _, _, _ in
            Issue.record("Trusted takeover recovery should not reinstall the canonical skill")
        },
        trashItem: { try FileManager.default.removeItem(at: $0) },
        isSkillsCLIAvailable: { false }
    )
    try await service.update(
        makeSkillsCLITakeoverSkill(fixture, sourceURL: sourceURL),
        agentIDs: ["codex"],
        appendLog: { _ in }
    )
}

private func makeSkillsCLITakeoverSkill(
    _ fixture: SkillsCLITakeoverFixture,
    sourceURL: URL = URL(string: "https://github.com/example/repo")!
) -> Skill {
    var skill = makeLifecycleSkill()
    skill.directoryPath = fixture.providerSkill
    skill.filePath = fixture.providerSkill.appendingPathComponent("SKILL.md")
    skill.provenance = SkillProvenance(
        provider: .skillsCLI,
        sourceURL: sourceURL,
        skillID: "managed-skill"
    )
    return skill
}

private func expectProviderLink(_ link: URL, pointsTo target: URL) throws {
    let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    #expect(URL(fileURLWithPath: destination).standardizedFileURL == target.standardizedFileURL)
    #expect(link.resolvingSymlinksInPath().standardizedFileURL == target.standardizedFileURL)
}

private func expectSkillsCLILockCleared(_ lockFile: URL) throws {
    let lock = try String(contentsOf: lockFile, encoding: .utf8)
    #expect(lock.contains("managed-skill") == false)
}
