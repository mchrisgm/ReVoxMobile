import Foundation
import ReVoxCore

/// What the About screen shows (§8.7, C5): version, the privacy paragraph, the five catalog licences, the app licence,
/// the pocket-tts and voice attribution and the two project links.
struct AboutInfo: Equatable, Sendable {
    static let appName = "ReVox"
    static let privacyText = "ReVox translates speech to English entirely on this iPhone. After the one-time model download it never uses the network: no audio, text or usage data leaves the phone, and there are no analytics."
    static let appLicenceText = "ReVox Mobile is open source under the MIT licence."
    static let windowsProjectURL = URL(string: "https://github.com/mchrisgm/ReVox")!
    static let platformLimitationsURL = URL(string: "https://github.com/mchrisgm/ReVoxMobile#platform-limitations")!
    static let pocketTTSLicenceID = "pocket-tts"

    let marketingVersion: String
    let buildNumber: String

    init(marketingVersion: String, buildNumber: String) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    init(infoDictionary: [String: Any]) {
        self.init(marketingVersion: infoDictionary["CFBundleShortVersionString"] as? String ?? "0",
                  buildNumber: infoDictionary["CFBundleVersion"] as? String ?? "0")
    }

    static func current(bundle: Bundle = .main) -> AboutInfo {
        AboutInfo(infoDictionary: bundle.infoDictionary ?? [:])
    }

    var versionText: String { "\(marketingVersion) (\(buildNumber))" }

    var licences: [LicenceNotice] { ModelCatalog.licences }

    /// The CC-BY-4.0 attribution line, taken from the catalog entry so the About screen and the catalog never drift.
    var pocketTTSAttributionText: String? {
        guard let notice = ModelCatalog.licences.first(where: { $0.id == Self.pocketTTSLicenceID }), let attribution = notice.attribution else {
            return nil
        }
        return "\(attribution) Core ML weights under \(notice.licence)."
    }
}
