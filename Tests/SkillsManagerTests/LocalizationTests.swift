import Foundation
import Testing
@testable import SkillsManager

struct LocalizationTests {
    @Test
    func appDefaultsToEnglishAndBundlesSimplifiedChinese() throws {
        let appBundle = Bundle(for: SkillStore.self)
        #expect(appBundle.developmentLocalization == "en")

        let english = try #require(localizationBundle("en", in: appBundle))
        let simplifiedChinese = try #require(localizationBundle("zh-Hans", in: appBundle))

        #expect(english.localizedString(forKey: "Control Center", value: nil, table: nil) == "Control Center")
        #expect(simplifiedChinese.localizedString(forKey: "Control Center", value: nil, table: nil) == "控制台")
        #expect(simplifiedChinese.localizedString(forKey: "Create Collection", value: nil, table: nil) == "新建分组")
        #expect(simplifiedChinese.localizedString(forKey: "Reapply", value: nil, table: nil) == "重新应用")
    }

    private func localizationBundle(_ language: String, in appBundle: Bundle) -> Bundle? {
        guard let path = appBundle.path(forResource: language, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}
