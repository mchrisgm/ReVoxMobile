import Foundation

/// The two identifiers the app must read from its own Info.plist (requirement E3, spec §6.11).
/// Bundle identifiers are never written literally in Swift: `project.yml` derives both keys
/// from `REVOX_BUNDLE_PREFIX`.
struct AppConfiguration: Sendable, Equatable {
    static let appGroupKey = "REVOXAppGroup"
    static let broadcastExtensionBundleIDKey = "REVOXBroadcastExtensionBundleID"

    enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case missingKey(String)

        var description: String {
            switch self {
            case .missingKey(let key):
                return "Info.plist is missing the key \(key); check project.yml and ReVoxMobile/Info.plist"
            }
        }
    }

    let appGroup: String
    let broadcastExtensionBundleID: String

    init(appGroup: String, broadcastExtensionBundleID: String) {
        self.appGroup = appGroup
        self.broadcastExtensionBundleID = broadcastExtensionBundleID
    }

    init(infoDictionary: [String: Any]) throws {
        guard let appGroup = infoDictionary[Self.appGroupKey] as? String, !appGroup.isEmpty else {
            throw Error.missingKey(Self.appGroupKey)
        }
        guard let extensionID = infoDictionary[Self.broadcastExtensionBundleIDKey] as? String, !extensionID.isEmpty else {
            throw Error.missingKey(Self.broadcastExtensionBundleIDKey)
        }
        self.init(appGroup: appGroup, broadcastExtensionBundleID: extensionID)
    }

    /// Fails loudly at launch: a missing key is a build configuration error, never a runtime condition.
    static func load(bundle: Bundle = .main) -> AppConfiguration {
        do {
            return try AppConfiguration(infoDictionary: bundle.infoDictionary ?? [:])
        } catch {
            fatalError(String(describing: error))
        }
    }
}
