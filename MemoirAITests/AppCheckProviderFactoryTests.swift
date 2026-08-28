import XCTest
import FirebaseAppCheck
import FirebaseCore
@testable import MemoirAI

final class AppCheckProviderFactoryTests: XCTestCase {
    func testFactoryCreatesProviderForConfiguredFirebaseApp() throws {
        let app = try XCTUnwrap(FirebaseApp.app())

        let provider = MemoirAppAttestProviderFactory().createProvider(with: app)

        XCTAssertNotNil(provider)
    }
}
