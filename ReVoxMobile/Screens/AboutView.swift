import SwiftUI
import ReVoxCore

/// The About screen (§8.7). Every external link is a `Link` (opens Safari) with a VoiceOver label that says so.
struct AboutView: View {
    let info: AboutInfo

    var body: some View {
        List {
            Section {
                HStack {
                    Text(AboutInfo.appName).font(.headline)
                    Spacer()
                    Text(info.versionText).foregroundStyle(.secondary).font(.subheadline.monospacedDigit())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(AboutInfo.appName), version \(info.versionText)")
                Text(AboutInfo.privacyText).font(.body)
                Link(destination: AboutInfo.privacyPolicyURL) {
                    Label("Read the privacy policy", systemImage: "hand.raised").frame(minHeight: 44)
                }
                .accessibilityHint("Opens the privacy policy in Safari")
            } header: {
                Text("On-device translation")
            }

            Section {
                ForEach(info.licences) { notice in
                    Link(destination: notice.url) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(notice.name).foregroundStyle(.primary)
                                Spacer()
                                Text(notice.licence).foregroundStyle(.secondary)
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary).accessibilityHidden(true)
                            }
                            if let attribution = notice.attribution {
                                Text(attribution).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel("\(notice.name), \(notice.licence) licence\(notice.attribution.map { ", \($0)" } ?? "")")
                    .accessibilityHint("Opens in Safari")
                }
            } header: {
                Text("Licences")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AboutInfo.appLicenceText)
                    if let attribution = info.pocketTTSAttributionText {
                        Text(attribution)
                    }
                }
            }

            Section("Links") {
                Link(destination: AboutInfo.privacyPolicyURL) {
                    Label("Privacy policy", systemImage: "hand.raised").frame(minHeight: 44)
                }
                .accessibilityHint("Opens the privacy policy in Safari")
                Link(destination: AboutInfo.supportURL) {
                    Label("Support", systemImage: "questionmark.circle").frame(minHeight: 44)
                }
                .accessibilityHint("Opens the issue tracker in Safari")
                Link(destination: AboutInfo.windowsProjectURL) {
                    Label("ReVox for Windows", systemImage: "desktopcomputer").frame(minHeight: 44)
                }
                .accessibilityHint("Opens the Windows project in Safari")
                Link(destination: AboutInfo.platformLimitationsURL) {
                    Label("Platform limitations on iPhone", systemImage: "info.circle").frame(minHeight: 44)
                }
                .accessibilityHint("Opens the README section in Safari")
            }
        }
        .navigationTitle("About")
    }
}
