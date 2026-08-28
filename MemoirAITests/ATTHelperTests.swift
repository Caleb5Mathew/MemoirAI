import AppTrackingTransparency
import Testing
@testable import MemoirAI

struct ATTHelperTests {
    @Test func advertiserTrackingRequiresExplicitAuthorization() {
        #expect(ATTHelper.advertiserTrackingEnabled(for: .authorized))
        #expect(!ATTHelper.advertiserTrackingEnabled(for: .notDetermined))
        #expect(!ATTHelper.advertiserTrackingEnabled(for: .denied))
        #expect(!ATTHelper.advertiserTrackingEnabled(for: .restricted))
    }
}
