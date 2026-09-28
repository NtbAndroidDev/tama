import SwiftUI
import AppKit

/// The first-run welcome tour. Shown once (until `hasCompletedOnboarding` is
/// set) and replayable from Settings › About › Introduction.
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    public static let shared = OnboardingWindowController()

    static let completedKey = "hasCompletedOnboarding"

    private var window: NSWindow?

    private override init() { super.init() }

    /// Shows the tour if it hasn't been finished before.
    public func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.completedKey) else { return }
        show()
    }

    public func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.delegate = self
            let host = NSHostingView(rootView: OnboardingView { [weak self] in self?.finish() })
            // The window sets its own frame and minSize, so SwiftUI must not also
            // push content-size extrema onto it — that feedback is what AppKit
            // aborts with an "Update Constraints in Window" throw.
            host.sizingOptions = []
            window.contentView = host
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        // Closing it early still counts as seen; it's in About to replay.
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        // A fresh tour starts on the first step next time.
        window?.contentView = nil
        window = nil
    }
}

// MARK: - Tour

private enum OnboardingStep: Int, CaseIterable {
    case welcome, style, drag, workspace, widgets, permissions, settings, done

    /// What the dots read out, and the tooltip on each one.
    var label: String {
        switch self {
        case .welcome: "Welcome"
        case .style: "Display style"
        case .drag: "Dropping files"
        case .workspace: "Tray, Basket and clipboard"
        case .widgets: "Widgets"
        case .permissions: "Permissions"
        case .settings: "The menu"
        case .done: "All set"
        }
    }
}

private struct OnboardingView: View {
    let onFinish: () -> Void
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var generalSettings = GeneralSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @ObservedObject private var permissions = PermissionService.shared
    @State private var step: OnboardingStep = .welcome
    /// Flips on the last step so its checkmark bounces once.
    @State private var celebrated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(step)
                    .transition(DS.Motion.transition(reduceMotion, .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity))))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 40)
            footer
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.2)
            }
            .ignoresSafeArea()
        )
        .tint(themeSettings.accentColor.color)
        .frame(width: 600, height: 520)
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome:
            VStack(spacing: 14) {
                Spacer()
                Text("Hey there! 👋").font(.system(size: 40, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Hey there!")
                Text("Welcome to Tama").font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary)
                Text("Your notch becomes a shelf for files, music, widgets and your clipboard. This takes a minute.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Spacer()
            }
        case .style:
            VStack(spacing: 14) {
                title("Choose your display style", "How Tama sits at the top of your screen.")
                SettingsGroup {
                    PreviewCardPicker([
                        PreviewCardOption(IslandStyle.notchAttached, "Notch", subtitle: "Carved black silhouette"),
                        PreviewCardOption(IslandStyle.floatingPill, "Island", subtitle: "Floating pill surface"),
                    ], selection: $generalSettings.islandStyle, thumbnailHeight: 80) { style in
                        DisplayStyleThumbnail(style: style)
                    }
                }
                if state.notchHeight > 0 {
                    Text("This Mac has a notch, so Tama wraps around it here. Island applies on displays without one.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
        case .drag:
            VStack(spacing: 18) {
                title("Drag files to your notch or island",
                      "They wait in the Tray until you drag them out again. Drop onto a tile to share a link, AirDrop or convert.")
                DragDemo()
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer(minLength: 0)
            }
        case .workspace:
            VStack(spacing: 16) {
                title("Everything you're carrying, in one place",
                      "The Tray holds what you drop. A Basket follows you across Spaces. The clipboard remembers what you copied.")
                VStack(spacing: 8) {
                    featureRow("tray.full.fill", "Tray",
                               "Drop files on the notch and they wait there. Drag them out into any app.")
                    featureRow("basket.fill", "Floating Basket",
                               "Shake a drag — or press \(keys(.toggleBasket)) — and a Basket flies in to catch it.")
                    featureRow("doc.on.clipboard.fill", "Clipboard",
                               "\(keys(.toggleClipboard)) opens your history. ⌘F searches it, even the words inside screenshots.")
                }
                Spacer(minLength: 0)
            }
        case .widgets:
            VStack(spacing: 16) {
                title("Widgets live on the third page",
                      "Timers, capture, notes, a terminal, the weather — pick the ones you want and ignore the rest.")
                WidgetSampler()
                Text("Turn them on in Settings › Droplets. Each one can have its own shortcut, and the ones you use most can sit beside the shelf as a button.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
                Spacer(minLength: 0)
            }
        case .permissions:
            VStack(spacing: 14) {
                title("A few permissions", "Grant what you need now, or later in Settings › General.")
                ScrollView {
                    SettingsGroup {
                        ForEach([PermissionService.Kind.accessibility, .screenRecording, .calendars, .notifications], id: \.self) { kind in
                            PermissionRow(kind: kind, status: permissions.status(kind),
                                          needsRelaunch: kind == .screenRecording && permissions.screenRecordingNeedsRelaunch)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                            if kind != .notifications { SettingsDivider() }
                        }
                    }
                }
                .onAppear { permissions.refresh() }
            }
        case .settings:
            VStack(spacing: 18) {
                Spacer()
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 180, height: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(["Open Shelf", "Clipboard", "Settings…"], id: \.self) { item in
                            Text(item).font(.system(size: 12, weight: item == "Settings…" ? .semibold : .regular))
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(item == "Settings…" ? themeSettings.accentColor.color : .clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    .padding(6)
                    .frame(width: 150)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .offset(x: 110, y: 22)
                    Image(systemName: "cursorarrow.click.2").font(.system(size: 20)).offset(x: 96, y: 8)
                }
                .frame(width: 280, height: 130, alignment: .topLeading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("The notch's right-click menu, with Settings… in it")
                Text("Right-click the Notch or Island to access Settings anytime")
                    .font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
                Text("The same menu opens pages, the clipboard and the Basket.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            }
        case .done:
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(themeSettings.accentColor.color)
                    .symbolEffect(.bounce, value: celebrated)
                    .accessibilityHidden(true)
                Text("You're all set!").font(.system(size: 30, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text("Click the notch to open the shelf. The guide explains every part of it, and the menu bar icon opens both.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Spacer()
            }
            .onAppear {
                // The value never changed while it was fixed to `step == .done`,
                // so the bounce never played; Reduce Motion keeps it still.
                if !reduceMotion { celebrated = true }
                celebrate()
            }
        }
    }

    /// A recorded shortcut, or a plain description when none is set, so the
    /// tour never promises keys that would do nothing.
    private func keys(_ action: ShortcutAction) -> String {
        GlobalShortcutService.shared.display(for: action) ?? "its shortcut"
    }

    private func featureRow(_ icon: String, _ heading: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeSettings.accentColor.color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: 430, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func title(_ text: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(text).font(.system(size: 22, weight: .bold)).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            // The left slot keeps one width whatever it holds, so the dots
            // stay put instead of sliding as the buttons change.
            HStack(spacing: 8) {
                if step != .welcome && step != .done {
                    Button("Back") { go(-1) }
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Previous step (⌘[)")
                }
                if step != .done {
                    Button("Skip") { onFinish() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                        .help("Close the tour (Esc). Settings › About › Introduction replays it.")
                }
            }
            .frame(width: 130, alignment: .leading)

            Spacer()
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.self) { s in
                    Button { jump(to: s) } label: {
                        Circle()
                            .fill(s == step ? Color.white : Color.white.opacity(s.rawValue < step.rawValue ? 0.45 : 0.22))
                            .frame(width: 7, height: 7)
                            .contentShape(Circle().inset(by: -5))
                    }
                    .buttonStyle(.plain)
                    .help(s.label)
                    .accessibilityLabel(s.label)
                    .accessibilityAddTraits(s == step ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count): \(step.label)")
            Spacer()

            HStack(spacing: 8) {
                switch step {
                case .welcome:
                    Button("Get Started") { go(1) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                case .done:
                    Button("Open the Guide") {
                        onFinish()
                        UserGuideWindowController.shared.show()
                    }
                    Button("Start Using Tama") { onFinish() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                default:
                    Button("Continue") { go(1) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
            // Wide enough for the last step's two large buttons side by side
            // without truncating either label.
            .frame(width: 280, alignment: .trailing)
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    /// A dot jumps straight to its step. Nothing here has to be done in
    /// order, and someone who only wants the permissions page shouldn't have
    /// to press Continue five times to reach it.
    private func jump(to target: OnboardingStep) {
        guard target != step else { return }
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { step = target }
        DroppyAudio.playTick()
    }

    private func go(_ delta: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { step = next }
        DroppyAudio.playTick()
    }

    /// A short haptic flourish for the finale (on a Force Touch trackpad).
    private func celebrate() {
        guard generalSettings.hapticFeedback else { return }
        let performer = NSHapticFeedbackManager.defaultPerformer
        for (index, pattern) in [NSHapticFeedbackManager.FeedbackPattern.levelChange, .alignment, .levelChange].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
                performer.perform(pattern, performanceTime: .now)
            }
        }
        if generalSettings.soundEffects { NSSound(named: "Glass")?.play() }
    }
}

/// A file icon gliding up into a notch, then the notch unfolding into drop
/// tiles, on a loop. Still under Reduce Motion.
private struct DragDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.7 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.2) / 3.2
            let travel = min(t / 0.6, 1)
            let eased = 1 - pow(1 - travel, 3)
            let open = t > 0.55
            ZStack(alignment: .top) {
                PreviewWallpaper()
                NotchWithEarsShape(cornerRadius: open ? 16 : 8, earRadius: 6)
                    .fill(Color.black)
                    .frame(width: open ? 300 : 120, height: open ? 70 : 22)
                    .overlay(alignment: .bottom) {
                        if open {
                            HStack(spacing: 8) {
                                ForEach(["tray.and.arrow.down.fill", "link", "dot.radiowaves.left.and.right", "arrow.triangle.2.circlepath"], id: \.self) {
                                    Image(systemName: $0)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 56, height: 34)
                                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .animation(reduceMotion ? nil : DS.Motion.fluid, value: open)
                Image(systemName: "doc.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
                    .offset(x: 90 - 90 * eased, y: 150 - 110 * eased)
                    .opacity(t > 0.62 ? 0 : 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A file dragged onto the notch, which opens into drop tiles")
    }
}

/// A still of the Widgets page: a row of droplet glyphs with the page dots
/// underneath, drawn the way the real row is so the tour matches what the
/// person will find on the third page.
private struct WidgetSampler: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var generalSettings = GeneralSettings.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlighted = 0

    private let icons: [(String, String)] = [
        ("camera.viewfinder", "Capture"), ("timer", "Timer"), ("note.text", "Scratchpad"),
        ("bolt.fill", "Thunderstorm"), ("cloud.sun.fill", "Weather"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                    VStack(spacing: 5) {
                        Image(systemName: icon.0)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(index == highlighted ? themeSettings.accentColor.color : .white.opacity(0.75))
                            .frame(width: 52, height: 52)
                            .background(Color.white.opacity(index == highlighted ? 0.14 : 0.07),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text(icon.1).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { page in
                    Circle().fill(Color.white.opacity(page == 0 ? 0.8 : 0.25)).frame(width: 5, height: 5)
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: 430)
        .task {
            guard !reduceMotion else { return }
            // A slow sweep along the row, so the page reads as live rather
            // than as a screenshot. It stops when the step is left.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                withAnimation(DS.Motion.snap) { highlighted = (highlighted + 1) % icons.count }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Widgets page, showing five droplet icons and its page dots")
    }
}
