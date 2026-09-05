import SwiftUI
import ReVoxCore

/// The first-run tutorial (M10, refreshed in M11 §6): seven pages, each with a demo the reader taps rather than a
/// paragraph they read — the Live controls themselves, over a demo model. Presented as a full-screen cover from
/// the root, so it cannot be swiped away half-read; Skip is always in the corner. Pages slide in from the side
/// they come from and fade; under Reduce Motion they crossfade and nothing bounces. Every control is at least
/// 44 pt tall; every colour is a semantic one, so dark mode needs no work.
struct OnboardingView: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var direction: Direction = .forward

    enum Direction { case forward, back }

    static let skipTitle = "Skip"
    static let backTitle = "Back"
    static let nextTitle = "Next"
    static let finishTitle = "Start translating"

    static func primaryTitle(isLastPage: Bool) -> String { isLastPage ? finishTitle : nextTitle }

    /// The swipe distance that turns a page: a deliberate flick, not a wobble while tapping a toggle.
    static let swipeThreshold: CGFloat = 80

    var body: some View {
        VStack(spacing: 0) {
            header
            hero
            pager
            footer
        }
        .background(Color(.systemBackground))
        .onAppear { model.controls.refreshVoiceNote() }
        .onDisappear { model.stopDemo() }
    }

    // MARK: Header: the progress bar and Skip

    private var header: some View {
        HStack(spacing: 12) {
            OnboardingProgressBar(progress: model.progress, step: model.currentIndex + 1, count: model.pages.count,
                                  animation: pageAnimation)
            Button(Self.skipTitle) { model.skip() }
                .font(.body.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
                .opacity(model.isLastPage ? 0 : 1)
                .disabled(model.isLastPage)
                .accessibilityHidden(model.isLastPage)
                .accessibilityLabel("Skip the tutorial")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Hero: one symbol that morphs from page to page

    /// Outside the pager on purpose: the symbol stays in place and turns into the next page's symbol, which reads
    /// as one thing changing rather than seven things sliding past. It bounces once as each page lands.
    private var hero: some View {
        Image(systemName: model.page.symbol)
            .font(.system(size: 44, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 88, height: 88)
            .background(Color.accentColor.opacity(0.12), in: Circle())
            .contentTransition(symbolTransition)
            .symbolEffect(.bounce, value: reduceMotion ? 0 : model.currentIndex)
            .animation(pageAnimation, value: model.currentIndex)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    // MARK: The pages

    private var pager: some View {
        ZStack {
            OnboardingPageView(page: model.page, index: model.currentIndex, count: model.pages.count, model: model)
                .id(model.currentIndex)
                .transition(pageTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .gesture(swipe)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let dx = value.predictedEndTranslation.width
                guard abs(value.translation.width) > abs(value.translation.height), abs(dx) > Self.swipeThreshold else { return }
                turn(dx < 0 ? .forward : .back)
            }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let entering: Edge = direction == .forward ? .trailing : .leading
        let leaving: Edge = direction == .forward ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: entering).combined(with: .opacity),
                           removal: .move(edge: leaving).combined(with: .opacity))
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.12)
    }

    /// The hero morphs one symbol into the next (iOS 17); under Reduce Motion it crossfades.
    private var symbolTransition: ContentTransition {
        if reduceMotion { return .opacity }
        return .symbolEffect(.replace)
    }

    /// The direction is set first and the page changed on the next turn of the run loop: a removed view leaves
    /// with the transition it was last rendered with, so both changes in one transaction would slide the old
    /// page out the wrong way whenever the reader turns around.
    private func turn(_ newDirection: Direction) {
        switch newDirection {
        case .forward: guard !model.isLastPage else { return }
        case .back: guard !model.isFirstPage else { return }
        }
        direction = newDirection
        let animation = pageAnimation
        Task { @MainActor in
            withAnimation(animation) {
                switch newDirection {
                case .forward: model.advance()
                case .back: model.back()
                }
            }
        }
    }

    // MARK: Footer: Back and Next / Start translating

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                turn(.back)
            } label: {
                Label(Self.backTitle, systemImage: "chevron.left")
                    .font(.headline)
                    .frame(minHeight: 50)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .opacity(model.isFirstPage ? 0 : 1)
            .disabled(model.isFirstPage)
            .accessibilityHidden(model.isFirstPage)
            .accessibilityLabel("Back to the previous page")

            Button {
                if model.isLastPage {
                    model.finish()
                } else {
                    turn(.forward)
                }
            } label: {
                HStack(spacing: 8) {
                    if model.isLastPage {
                        Image(systemName: "mic.fill").accessibilityHidden(true)
                    }
                    Text(Self.primaryTitle(isLastPage: model.isLastPage))
                    if !model.isLastPage {
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityLabel(model.isLastPage ? "Start translating: close the tutorial" : "Next page")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(pageAnimation, value: model.currentIndex)
    }
}

/// The thin capsule at the top: how far through, in one glance, and "Step 3 of 7" to VoiceOver.
struct OnboardingProgressBar: View {
    let progress: Double
    let step: Int
    let count: Int
    var animation: Animation = .default

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.accentColor)
                    .frame(width: max(8, geometry.size.width * progress))
            }
        }
        .frame(height: 6)
        .frame(minHeight: 44)
        .animation(animation, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of \(count)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// One page: the title (a heading to VoiceOver), one sentence, and the demo. Scrolls when Dynamic Type asks.
/// The column itself is not padded: the title and sentence take 20 pt each, and every demo pads itself, so the
/// strip and the Languages group get the same width they have on Live (393 − 2 × 16) and pack identically.
struct OnboardingPageView: View {
    let page: OnboardingPage
    let index: Int
    let count: Int
    @Bindable var model: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                demo
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page \(index + 1) of \(count), \(page.title)")
    }

    @ViewBuilder
    private var demo: some View {
        switch page {
        case .welcome:
            OnboardingDemoCard {
                OnboardingPointsList(points: OnboardingDemo.welcomePoints)
                Divider()
                Label(OnboardingDemo.privacyText, systemImage: "lock.shield")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .controls:
            OnboardingControlsDemo(model: model)
        case .transcript:
            OnboardingTranscriptDemo(model: model)
        case .twoWay:
            OnboardingTwoWayDemo(model: model)
        case .learning:
            OnboardingLearningDemo(model: model)
        case .models:
            OnboardingModelsDemo(model: model)
        case .ready:
            OnboardingDemoCard {
                OnboardingPointsList(points: OnboardingDemo.readyPoints)
                Divider()
                Text(OnboardingDemo.readyFootnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The card every demo sits in: the Live screen's card, so the tutorial looks like the app it is about. It
/// carries the page's 20 pt side margin itself (see `OnboardingPageView`).
struct OnboardingDemoCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
}

/// Lines that arrive one after another as the page lands — all at once under Reduce Motion.
struct OnboardingPointsList: View {
    let points: [OnboardingPoint]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0

    static let stagger: Duration = .milliseconds(160)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(points.enumerated()), id: \.element.id) { offset, point in
                Label {
                    Text(point.text)
                } icon: {
                    Image(systemName: point.symbol).foregroundStyle(Color.accentColor)
                }
                .font(.body)
                .opacity(revealed > offset ? 1 : 0)
                .offset(y: revealed > offset || reduceMotion ? 0 : 12)
            }
        }
        .accessibilityElement(children: .combine)
        .task {
            if reduceMotion {
                revealed = points.count
                return
            }
            for step in 1...max(1, points.count) {
                try? await Task.sleep(for: Self.stagger)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { revealed = step }
            }
        }
    }
}

/// The Live screen's Start / Stop capsule, shared by the controls page and the transcript demo: the same words
/// `LiveView.buttonTitle(for:)` gives the real one, red while running. No side margin of its own — the caller
/// places it (inside a card, or at the page's 20 pt).
struct OnboardingStartStopButton: View {
    let isRunning: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    static func title(running: Bool) -> String {
        LiveView.buttonTitle(for: running ? .running : .idle)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isRunning ? "stop.fill" : "mic.fill")
                    .accessibilityHidden(true)
                Text(Self.title(running: isRunning))
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(isRunning ? .red : .accentColor)
        .animation(.default, value: isRunning)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

// MARK: - The Live controls

/// The Live strip itself over the demo model (M11 §6): every pill, menu, the details panel and the volume slider
/// are the real views, so nothing here can drift from Live. Under the strip, the current source's line and a tip;
/// then a Start capsule that locks the pills the way a session does, and Stop that unlocks them.
struct OnboardingControlsDemo: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let tipText = "The volume applies at once; everything else is read when a session starts. This Start is a demo — nothing is recorded."
    static let lockedTipText = "A session is running: the dimmed pills say “\(LiveControlStrip.lockedText)” because ReVox read them at Start. Tap Stop to change them."
    static let startAccessibilityLabel = "Start a demo session"
    static let stopAccessibilityLabel = "Stop the demo session"
    static let startHint = "Locks the pills the way a real session does; nothing is recorded"
    static let stopHint = "Unlocks the pills"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveControlStrip(model: model.controls, showsVolumeSlider: $model.demoShowsVolumeSlider, isMoreExpanded: $model.demoShowsDetails)
            if model.demoShowsDetails {
                LiveDetailsPanel(model: model.controls)
            }
            OnboardingDemoCard {
                Label {
                    Text(LiveView.description(for: model.controls.captureMode))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: LiveView.symbol(for: model.controls.captureMode))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(symbolTransition)
                }
                .accessibilityElement(children: .combine)
                Divider()
                Text(model.controls.isRunning ? Self.lockedTipText : Self.tipText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OnboardingStartStopButton(isRunning: model.controls.isRunning,
                                      accessibilityLabel: model.controls.isRunning ? Self.stopAccessibilityLabel : Self.startAccessibilityLabel,
                                      accessibilityHint: model.controls.isRunning ? Self.stopHint : Self.startHint) {
                if model.controls.isRunning {
                    model.controls.stop()
                } else {
                    model.controls.start()
                }
            }
            .padding(.horizontal, 20)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.1), value: model.controls.state)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.1), value: model.controls.captureMode)
        .animation(reduceMotion ? nil : .default, value: model.demoShowsDetails)
    }

    private var symbolTransition: ContentTransition {
        if reduceMotion { return .opacity }
        return .symbolEffect(.replace)
    }
}

// MARK: - Start and read

/// The Live screen in miniature: a transcript whose rows slide in one by one, ages counting up under them, and
/// the same capsule that starts and stops the real thing. The script ends with a guess, which the row view greys
/// and marks Unsure (M11 §3); the caption under the rows says so for as long as the greyed row is there.
struct OnboardingTranscriptDemo: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let startAccessibilityLabel = "Start the demo"
    static let stopAccessibilityLabel = "Stop the demo"
    static let hintText = "A short conversation appears in the transcript, one phrase at a time"

    /// The guess explanation whenever the greyed row is on screen, even after Stop; otherwise what Live says.
    static func captionText(playing: Bool, lastIsGuess: Bool) -> String {
        if lastIsGuess { return OnboardingDemo.guessText }
        return playing ? OnboardingDemo.speakingText : LiveView.microphoneDescription
    }

    static func captionSymbol(playing: Bool, lastIsGuess: Bool) -> String {
        lastIsGuess ? "questionmark.circle" : "speaker.wave.2"
    }

    var body: some View {
        OnboardingDemoCard {
            // Ticks every second only while the demo runs, like the Live screen with ages on.
            TimelineView(.periodic(from: .now, by: model.isDemoPlaying ? 1 : 3_600)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    if model.demoRows.isEmpty {
                        Label(OnboardingDemo.transcriptEmptyText, systemImage: "waveform.and.mic")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                    ForEach(model.demoRows) { row in
                        LiveTranscriptRowView(row: row, now: context.date, timeDisplay: .age)
                            .transition(rowTransition)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .animation(rowAnimation, value: model.demoRows)
            }
            HStack(spacing: 6) {
                Image(systemName: Self.captionSymbol(playing: model.isDemoPlaying, lastIsGuess: model.lastDemoRowIsGuess))
                    .symbolEffect(.variableColor.iterative, isActive: model.isDemoPlaying && !model.lastDemoRowIsGuess && !reduceMotion)
                    .accessibilityHidden(true)
                Text(Self.captionText(playing: model.isDemoPlaying, lastIsGuess: model.lastDemoRowIsGuess))
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .animation(.default, value: model.isDemoPlaying)
            .animation(.default, value: model.lastDemoRowIsGuess)
            OnboardingStartStopButton(isRunning: model.isDemoPlaying,
                                      accessibilityLabel: model.isDemoPlaying ? Self.stopAccessibilityLabel : Self.startAccessibilityLabel,
                                      accessibilityHint: Self.hintText) {
                if model.isDemoPlaying {
                    model.stopDemo()
                } else {
                    model.startDemo()
                }
            }
        }
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var rowAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.25)
    }
}

// MARK: - Two-way

/// The real Languages group over the demo model: tap Two-way and the You speak / They speak pills appear beneath
/// it exactly as on Live, the reply row appears under the other person's line, and the footnote says what will be
/// spoken to whom in the languages the pills show.
struct OnboardingTwoWayDemo: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveLanguagesGroup(model: model.controls)
                .padding(.horizontal)
            OnboardingDemoCard {
                LiveTranscriptRowView(row: OnboardingDemo.theirLine)
                if model.controls.isTwoWay {
                    LiveTranscriptRowView(row: OnboardingDemo.yourReply)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                Text(model.controls.isTwoWay
                     ? OnboardingDemo.twoWayOnText(you: model.controls.ignoredLanguage, they: model.controls.theySpeak)
                     : OnboardingDemo.twoWayOffText(you: model.controls.ignoredLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.2), value: model.controls.isTwoWay)
    }
}

// MARK: - Learning

/// The same real group: tap Learn and the example rows show the words as spoken above the translation, through
/// the real row view (so its words are tappable, M11 §2). Romanize has no pill on Live, so the card keeps the
/// Settings-shaped toggle for it.
struct OnboardingLearningDemo: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveLanguagesGroup(model: model.controls)
                .padding(.horizontal)
            OnboardingDemoCard {
                Toggle("Romanize", isOn: $model.demoRomanize)
                    .frame(minHeight: 44)
                    .disabled(!model.controls.isLearning)
                    .accessibilityHint("Adds how the original sounds in Latin letters")
                Divider()
                LiveTranscriptRowView(row: SettingExamples.sampleRow(original: SettingExamples.spanishOriginal),
                                      showsOriginal: model.controls.isLearning)
                LiveTranscriptRowView(row: SettingExamples.japaneseRow,
                                      showsOriginal: model.controls.isLearning, romanizes: model.controls.isLearning && model.demoRomanize)
                Text(OnboardingDemo.learningText(learning: model.controls.isLearning, romanize: model.demoRomanize))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15), value: model.controls.isLearning)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15), value: model.demoRomanize)
    }
}

// MARK: - Models and voices

struct OnboardingModelsDemo: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        OnboardingDemoCard {
            Text("Whisper model")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                ForEach(WhisperModelID.allCases) { id in
                    chip(id)
                }
            }
            Text(OnboardingDemo.modelNote(model.demoModel))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)
            Label(OnboardingDemo.benchmarkText, systemImage: "stopwatch")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Voices")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Label(OnboardingDemo.systemVoiceText, systemImage: "speaker.wave.2")
                .font(.footnote)
            Label(OnboardingDemo.pocketVoiceText, systemImage: "arrow.down.circle")
                .font(.footnote)
            Divider()
            Toggle("Keep my model when hot", isOn: $model.demoKeepModelWhenHot)
                .frame(minHeight: 44)
                .accessibilityHint("Keeps the chosen model through a hot iPhone instead of switching to a smaller one")
            SettingExample(symbol: "thermometer.medium",
                           text: SettingExamples.keepModelWhenHot(model.demoKeepModelWhenHot, model: model.demoModel))
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.1), value: model.demoModel)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.1), value: model.demoKeepModelWhenHot)
    }

    private func chip(_ id: WhisperModelID) -> some View {
        let selected = model.demoModel == id
        return Button {
            model.demoModel = id
        } label: {
            VStack(spacing: 2) {
                Text(id.displayName).font(.subheadline.weight(.semibold))
                Text(id == OnboardingDemo.recommendedModel ? "default" : " ")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(selected ? Color.accentColor : Color.secondary)
        .accessibilityLabel(id == OnboardingDemo.recommendedModel ? "\(id.displayName), the default" : id.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
