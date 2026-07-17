import Foundation
import Testing
@testable import SkillsManager

struct KeychainServiceTests {
    private let account = "keychain-service-tests-\(UUID().uuidString)"

    @Test
    func roundTripsAString() {
        defer { KeychainService.remove(forKey: account) }

        #expect(KeychainService.string(forKey: account) == nil)

        KeychainService.setString("sk-test-secret", forKey: account)
        #expect(KeychainService.string(forKey: account) == "sk-test-secret")

        KeychainService.setString("sk-test-updated", forKey: account)
        #expect(KeychainService.string(forKey: account) == "sk-test-updated")

        KeychainService.remove(forKey: account)
        #expect(KeychainService.string(forKey: account) == nil)
    }

    @Test
    func emptyValueRemovesTheItem() {
        defer { KeychainService.remove(forKey: account) }

        KeychainService.setString("sk-test-secret", forKey: account)
        KeychainService.setString("", forKey: account)
        #expect(KeychainService.string(forKey: account) == nil)
    }
}
