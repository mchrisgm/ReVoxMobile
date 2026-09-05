import Foundation
import Observation
import ReVoxCore

/// The first-run tutorial (M10): which page is showing, whether it should be showing at all, and the state of
/// the demos the reader taps on the way through. Completion is one integer in `UserDefaults` — the version of
/// the tutorial that was finished or skipped — so bumping `version` after a revision shows it once more, and
/// "Show the tutorial" in Settings clears it.
@MainActor
@Observable
final class OnboardingViewModel {
    /// Bump when the tutorial changes enough that someone who finished the old one should see the new one.
    /// 2: M11 §6, the pages host the real Live controls.
    static let version = 2
    /// `UserDefaults.standard`, required-reason CA92.1, already declared in `PrivacyInfo.xcprivacy`.
    static let storageKey = "onboarding_completed_version"

    let pages = OnboardingPage.ordered
    private(set) var currentIndex = 0
    /// Bound to the `fullScreenCover` on the root: true at launch until this version has been completed, true
    /// again after `reset()`, false once finished or skipped.
    var shouldShowNow: Bool

    // The demos. The strip's model is `controls` (M11 §6); the rest are bound to one page each, and `reset()`
    // puts them all back.
    let controls: OnboardingLiveControls
    /// The strip's per-launch states, which `LiveView` keeps in `@State`: here so `reset()` folds them and a
    /// test can render both.
    var demoShowsDetails = false
    var demoShowsVolumeSlider = false
    var demoRomanize = false
    var demoModel: WhisperModelID = OnboardingDemo.recommendedModel
    var demoKeepModelWhenHot = false
    private(set) var demoRows: [LiveTranscriptRow] = []
    private(set) var isDemoPlaying = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var demoTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.controls = OnboardingLiveControls()
        self.shouldShowNow = Self.shouldShow(defaults: defaults)
    }

    /// True until `version` (or a newer one) has been recorded as completed.
    static func shouldShow(defaults: UserDefaults) -> Bool {
        defaults.integer(forKey: storageKey) < version
    }

    // MARK: Pages

    var page: OnboardingPage { pages[currentIndex] }
    var isFirstPage: Bool { currentIndex == 0 }
    var isLastPage: Bool { currentIndex == pages.count - 1 }
    /// 1/7 on the first page, 1 on the last: the bar is never empty, and full means done.
    var progress: Double { Double(currentIndex + 1) / Double(pages.count) }

    func advance() {
        guard !isLastPage else { return }
        currentIndex += 1
    }

    func back() {
        guard !isFirstPage else { return }
        currentIndex -= 1
    }

    func show(_ page: OnboardingPage) {
        currentIndex = pages.firstIndex(of: page) ?? 0
    }

    func skip() { complete() }
    func finish() { complete() }

    private func complete() {
        defaults.set(Self.version, forKey: Self.storageKey)
        stopDemo()
        controls.stop()
        shouldShowNow = false
    }

    /// "Show the tutorial" in Settings: forget the completion, start from the first page with the demos fresh.
    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
        currentIndex = 0
        stopDemo()
        controls.reset()
        demoShowsDetails = false
        demoShowsVolumeSlider = false
        demoRomanize = false
        demoModel = OnboardingDemo.recommendedModel
        demoKeepModelWhenHot = false
        shouldShowNow = true
    }

    // MARK: The transcript demo

    /// Rows arrive one at a time, `OnboardingDemo.rowInterval` apart, until the script is spent; the demo stays
    /// "running" after that so the ages keep counting up, exactly as the Live screen does, until Stop.
    func startDemo() {
        demoTask?.cancel()
        demoRows = []
        isDemoPlaying = true
        demoTask = Task { [weak self] in
            var more = true
            while more, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(OnboardingDemo.rowInterval))
                guard !Task.isCancelled, let self else { return }
                more = self.appendNextDemoRow()
            }
        }
    }

    func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
        isDemoPlaying = false
    }

    var isDemoComplete: Bool { demoRows.count >= OnboardingDemo.transcriptScript.count }
    /// The last row on screen is the script's guess: the caption under the rows explains the greying.
    var lastDemoRowIsGuess: Bool { demoRows.last?.isGuess ?? false }

    /// The next scripted row, stamped `now`; false when the script is spent. Public so a test — or a
    /// screenshot — can play the demo through without waiting.
    @discardableResult
    func appendNextDemoRow(now: Date = Date()) -> Bool {
        guard demoRows.count < OnboardingDemo.transcriptScript.count else { return false }
        let line = OnboardingDemo.transcriptScript[demoRows.count]
        demoRows.append(LiveTranscriptRow(time: now, kind: .entry(language: line.language, original: line.original, english: line.english),
                                          isGuess: line.isGuess))
        return true
    }
}
