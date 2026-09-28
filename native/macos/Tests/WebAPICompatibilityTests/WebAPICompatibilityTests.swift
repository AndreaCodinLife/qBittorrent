import Testing
@testable import WebAPICompatibility

struct WebAPICompatibilityTests {
    @Test(arguments: ["2.16.2", "2.16.3", "2.17", "2.16.10", "2.16.2.1", " 2.16.2\n"])
    func supportedVersionsHaveNoWarning(_ version: String) {
        #expect(WebAPICompatibility.message(serverAPIVersion: version, isConnected: true) == nil)
    }

    @Test(arguments: ["2.15.1", "2.16.1", "2.16", "2.15.99"])
    func olderVersionsShowCompatibilityWarning(_ version: String) {
        let message = WebAPICompatibility.message(serverAPIVersion: version, isConnected: true)
        #expect(message?.contains(version.trimmingCharacters(in: .whitespacesAndNewlines)) == true)
        #expect(message?.contains("2.16.2") == true)
    }

    @Test(arguments: ["", "unknown", "2..16.2", ".2.16.2", "2.16.2.", "2.16.x", "-1.16.2", "v2.16.2"])
    func malformedOrUnavailableVersionsShowUnconfirmedWarning(_ version: String) {
        let message = WebAPICompatibility.message(serverAPIVersion: version, isConnected: true)
        #expect(message?.contains("cannot be confirmed") == true)
        #expect(message?.contains("requires 2.16.2") == false)
    }

    @Test func disconnectedServerHasNoCompatibilityWarning() {
        #expect(WebAPICompatibility.message(serverAPIVersion: "unknown", isConnected: false) == nil)
    }
}
