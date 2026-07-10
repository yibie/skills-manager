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
