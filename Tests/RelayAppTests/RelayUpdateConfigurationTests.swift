import Foundation
import Testing
@testable import RelayApp

struct RelayUpdateConfigurationTests {
    @Test
    @MainActor
    func onlyIdleUpdatePresentationIsHidden() {
        #expect(!RelayUpdatePresentation.idle.isVisible)
        #expect(RelayUpdatePresentation.checking.isVisible)
        #expect(
            RelayUpdatePresentation.available(version: "1.1.0").isVisible
        )
        #expect(RelayUpdatePresentation.upToDate.isVisible)
        #expect(
            RelayUpdatePresentation.failed(message: "Offline").isVisible
        )
    }

    @Test
    func releaseInfoPlistUsesSignedHTTPSUpdateFeed() throws {
        let data = try Data(contentsOf: projectURL("Resources/Info.plist"))
        let value = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        )
        let plist = try #require(value as? [String: Any])

        #expect(
            plist["SUFeedURL"] as? String
                == "https://raw.githubusercontent.com/ayushrungta8/relay/main/appcast.xml"
        )
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(plist["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(plist["SURequireSignedFeed"] as? Bool == true)
        #expect(
            plist["SUPublicEDKey"] as? String
                == "QvIeR1oi7pfKEqm4eLaYSFdlsxVRX9S5wI2KKTZEvgk="
        )
    }

    private func projectURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
