import SwiftUI
import AppKit

/// A borderless floating panel that can take Esc without activating Tama.
private final class FloatingMediaPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

@MainActor
private func makeFloatingPanel(size: CGSize, autosave: String) -> FloatingMediaPanel {
    let panel = FloatingMediaPanel(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovableByWindowBackground = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    if !panel.setFrameUsingName(autosave), let screen = NSScreen.main {
        // First time: top right, under the menu bar.
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 24, y: frame.maxY - size.height - 24))
    }
    panel.setFrameAutosaveName(autosave)
    CaptureExclusion.register(panel)
    return panel
}

// MARK: - Floating lyrics

/// The lyrics pop-out: a small window with the current line and its
/// neighbours on the artwork's colours, pinned above other windows unless
/// unpinned. Opened from the lyrics card's expand button.
@MainActor
final class LyricsWindowController {
    static let shared = LyricsWindowController()

    private var panel: FloatingMediaPanel?
    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        let panel = self.panel ?? makeFloatingPanel(size: DroppyShelfMetrics.lyricsWindowSize, autosave: "TamaLyricsWindow")
        self.panel = panel
        panel.onEscape = { [weak self] in self?.close() }
        let host = NSHostingView(rootView: FloatingLyricsView())
        host.sizingOptions = []
        panel.contentView = host
        applyPin()
        LyricsService.shared.load(for: MediaService.shared.currentTrack)
        panel.orderFrontRegardless()
        DroppyAudio.playTick()
    }

    func close() {
        panel?.orderOut(nil)
        // Built only while it shows: an ordered-out view would keep redrawing.
        panel?.contentView = nil
    }

    /// "Keep lyrics window on top": above everything, or a normal window.
    func applyPin() {
        panel?.level = AppState.shared.lyricsWindowPinned ? .floating : .normal
    }

    /// "Bring floating lyrics to front".
    func bringToFront() {
        guard let panel, panel.isVisible else { return show() }
        panel.orderFrontRegardless()
    }
}

private struct FloatingLyricsView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var media = MediaService.shared
    @ObservedObject private var lyrics = LyricsService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: ArtworkPalette {
        ArtworkPalette.current(media.currentTrack) ?? ArtworkPalette(primary: Color(white: 0.35), secondary: Color(white: 0.12))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text("Lyrics")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                DroppyIconButton(state.lyricsWindowPinned ? "pin.fill" : "pin", size: 24, tone: .tonal,
                                 isActive: state.lyricsWindowPinned,
                                 help: state.lyricsWindowPinned ? "Stop keeping lyrics window on top" : "Keep lyrics window on top") {
                    state.lyricsWindowPinned.toggle()
                    LyricsWindowController.shared.applyPin()
                    DroppyAudio.playTick()
                }
                DroppyIconButton("xmark", size: 24, tone: .tonal, help: "Close lyrics pop-out") {
                    LyricsWindowController.shared.close()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            LyricsThreeLines(fontSize: 15)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: DroppyShelfMetrics.lyricsWindowSize.width, height: DroppyShelfMetrics.lyricsWindowSize.height)
        .background(
            ZStack {
                Color.black
                LinearGradient(colors: [palette.primary.opacity(0.42), palette.secondary.opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: palette)
        .onChange(of: "\(media.currentTrack.title)|\(media.currentTrack.artist)") { _, _ in
            LyricsService.shared.load(for: media.currentTrack)
        }
    }
}

/// Previous, current and next line, centred; the current one bright. Used
/// by the pop-out window. States use the reference's wording.
struct LyricsThreeLines: View {
    var fontSize: CGFloat
    @ObservedObject private var lyrics = LyricsService.shared
    @ObservedObject private var media = MediaService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch lyrics.state {
        case .idle:
            note("Play a song to see lyrics", "Synced lyrics appear here when a song is active.")
        case .disabled:
            note("Lyrics are looked up online", "Turn on Settings › Shelf › Fetch lyrics online to see them.")
        case .loading:
            note("Loading lyrics...", nil)
        case .instrumental:
            note("♪ Instrumental", "This track has no words.")
        case .notFound:
            note("No lyrics for this song", nil)
        case .failed:
            note("Synced lyrics aren't available right now.", nil)
        case .offline:
            note("No Internet Connection", "Connect to Wi-Fi, Ethernet, or Personal Hotspot to continue.")
        case let .loaded(result):
            if result.isSynced {
                TimelineView(.animation(minimumInterval: 0.2, paused: !media.currentTrack.isPlaying)) { context in
                    let index = result.lineIndex(at: media.livePosition(at: context.date) + 0.15)
                    lines(result, current: index)
                }
            } else {
                note("No synced lyrics found", "This track doesn’t have timed lyrics.")
            }
        }
    }

    private func lines(_ result: Lyrics, current: Int?) -> some View {
        let index = current ?? -1
        let text: (Int) -> String = { i in
            guard result.lines.indices.contains(i) else { return " " }
            let words = result.lines[i].text
            return words.isEmpty ? "♪" : words
        }
        return VStack(spacing: 14) {
            Text(text(index - 1))
                .font(.system(size: fontSize - 2, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text(index < 0 ? "♪" : text(index))
                .font(.system(size: fontSize + 1, weight: .bold))
                .foregroundStyle(.white)
                .id(index)
                .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .move(edge: .bottom))))
            Text(text(index + 1))
                .font(.system(size: fontSize - 2, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: index)
    }

    private func note(_ title: String, _ subtitle: String?) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: - Expanded artwork

/// Settings › HUDs › Live album artwork: clicking the cover opens it large,
/// drifting slowly while the song plays. macOS doesn't hand apps Music's
/// animated covers, so the motion is Tama's own. Esc or ✕ closes it.
@MainActor
final class ArtworkWindowController {
    static let shared = ArtworkWindowController()

    private var panel: FloatingMediaPanel?
    private init() {}

    func show() {
        let side = DroppyShelfMetrics.artworkWindowSide
        let panel = self.panel ?? makeFloatingPanel(size: CGSize(width: side, height: side + 64), autosave: "TamaArtworkWindow")
        self.panel = panel
        panel.level = .floating
        panel.onEscape = { [weak self] in self?.close() }
        let host = NSHostingView(rootView: ExpandedArtworkView())
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
        panel.makeKey()
        DroppyAudio.playTick()
    }

    func close() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }
}

private struct ExpandedArtworkView: View {
    @ObservedObject private var media = MediaService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private var track: MediaTrack { media.currentTrack }
    private let side = DroppyShelfMetrics.artworkWindowSide

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = track.artworkImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(drift && track.isPlaying && !reduceMotion ? 1.08 : 1.0)
                            .offset(x: drift && track.isPlaying && !reduceMotion ? -6 : 0,
                                    y: drift && track.isPlaying && !reduceMotion ? -4 : 0)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 9).repeatForever(autoreverses: true), value: drift)
                    } else {
                        AlbumArtView(image: nil, size: side, radius: 0)
                    }
                }
                .frame(width: side, height: side)
                .clipped()
                DroppyIconButton("xmark", size: 28, tone: .tonal, help: "Close expanded artwork") {
                    ArtworkWindowController.shared.close()
                }
                .padding(12)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.hasTrack ? track.title : "Not playing")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                Spacer()
                DroppyIconButton(track.isPlaying ? "pause.fill" : "play.fill", size: 32, tone: .tonal,
                                 help: track.isPlaying ? "Pause" : "Play") { media.togglePlayPause() }
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
        }
        .frame(width: side)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .onAppear { drift = true }
    }
}
