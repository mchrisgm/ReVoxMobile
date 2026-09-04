import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class ModelFallbackTests: XCTestCase {
    func testLargestSmallerInstalledModelFollowsCatalogOrder() {
        XCTAssertEqual(ModelFallback.smallerInstalledModel(than: .largeV3, installed: [.tiny, .small]), .small)
        XCTAssertEqual(ModelFallback.smallerInstalledModel(than: .small, installed: [.tiny, .base, .medium]), .base)
        XCTAssertEqual(ModelFallback.smallerInstalledModel(than: .base, installed: [.tiny]), .tiny)
        XCTAssertNil(ModelFallback.smallerInstalledModel(than: .tiny, installed: [.tiny, .small]), "nothing is smaller than tiny")
        XCTAssertNil(ModelFallback.smallerInstalledModel(than: .small, installed: [.small, .medium]), "only larger models are installed")
        XCTAssertNil(ModelFallback.smallerInstalledModel(than: .small, installed: []))
    }
}
