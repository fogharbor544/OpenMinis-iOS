import XCTest
@testable import Minis

final class BrowserCredentialOriginTests: XCTestCase {
    @MainActor
    func testOriginMatchingDoesNotTrustSimilarDomainsOrInsecurePages() {
        XCTAssertEqual(BrowserCredentialStore.origin(for: "https://Example.com:443/login?q=1"), "https://example.com")
        XCTAssertNotEqual(BrowserCredentialStore.origin(for: "https://example.com:8443"), "https://example.com")
        XCTAssertNotEqual(BrowserCredentialStore.origin(for: "https://example.com.attacker.test"), "https://example.com")
        XCTAssertNotEqual(BrowserCredentialStore.origin(for: "https://accounts.example.com"), "https://example.com")
        XCTAssertNil(BrowserCredentialStore.origin(for: "http://example.com"))
        XCTAssertNil(BrowserCredentialStore.origin(for: "file:///tmp/login.html"))
        XCTAssertNil(BrowserCredentialStore.origin(for: "about:blank"))
    }
}
