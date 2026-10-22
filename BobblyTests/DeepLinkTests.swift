import XCTest
@testable import Bobbly

final class DeepLinkTests: XCTestCase {
    func testParsesGateWithApp() {
        XCTAssertEqual(DeepLink(url: URL(string: "bobbly://gate?app=Instagram")!), .gate(appName: "Instagram", source: .shortcuts))
        XCTAssertEqual(DeepLink(url: URL(string: "BOBBLY://GATE?app=Insta%20gram")!), .gate(appName: "Insta gram", source: .shortcuts))
    }

    func testParsesGateWithoutApp() {
        XCTAssertEqual(DeepLink(url: URL(string: "bobbly://gate")!), .gate(appName: nil, source: .shortcuts))
        XCTAssertEqual(DeepLink(url: URL(string: "bobbly://gate?app=")!), .gate(appName: nil, source: .shortcuts))
    }

    func testParsesEmergencyChatTutorial() {
        XCTAssertEqual(DeepLink(url: URL(string: "bobbly://emergency")!), .emergency)
        XCTAssertEqual(DeepLink(url: URL(string: "bobbly://tutorial")!), .tutorial)
        XCTAssertEqual(DeepLink(url: URL(string: "bobbly://chat?source=shield")!), .chat(appName: nil, source: .shield))
    }

    func testRejectsForeignURLs() {
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/gate")!))
        XCTAssertNil(DeepLink(url: URL(string: "bobbly://unknown")!))
    }

    func testLinkBuildersRoundTrip() {
        XCTAssertEqual(DeepLink(url: BobblyLink.gate(appName: "TikTok")), .gate(appName: "TikTok", source: .shortcuts))
        XCTAssertEqual(DeepLink(url: BobblyLink.chat(appName: "X", source: .shield)), .chat(appName: "X", source: .shield))
        XCTAssertEqual(DeepLink(url: BobblyLink.emergency), .emergency)
    }
}
