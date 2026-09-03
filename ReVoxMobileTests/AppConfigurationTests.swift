import XCTest
@testable import ReVoxMobile

final class AppConfigurationTests: XCTestCase {
    func testReadsBothKeys() throws {
        let configuration = try AppConfiguration(infoDictionary: [
            "REVOXAppGroup": "group.com.example.revox",
            "REVOXBroadcastExtensionBundleID": "com.example.revox.broadcast",
        ])
        XCTAssertEqual(configuration.appGroup, "group.com.example.revox")
        XCTAssertEqual(configuration.broadcastExtensionBundleID, "com.example.revox.broadcast")
    }

    func testMissingKeyThrowsNamingTheKey() {
        XCTAssertThrowsError(try AppConfiguration(infoDictionary: ["REVOXAppGroup": "group.x"])) { error in
            XCTAssertEqual(error as? AppConfiguration.Error, .missingKey("REVOXBroadcastExtensionBundleID"))
        }
        XCTAssertThrowsError(try AppConfiguration(infoDictionary: ["REVOXBroadcastExtensionBundleID": "x"])) { error in
            XCTAssertEqual(error as? AppConfiguration.Error, .missingKey("REVOXAppGroup"))
        }
    }

    func testHostBundleCarriesBothKeys() throws {
        // The test bundle is hosted by the app, so Bundle.main is ReVoxMobile's Info.plist.
        let configuration = try AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
        XCTAssertTrue(configuration.appGroup.hasPrefix("group."))
        XCTAssertTrue(configuration.appGroup.hasSuffix(".revox"))
        XCTAssertTrue(configuration.broadcastExtensionBundleID.hasSuffix(".revox.broadcast"))
    }
}
