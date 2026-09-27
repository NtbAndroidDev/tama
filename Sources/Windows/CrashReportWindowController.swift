import SwiftUI
import AppKit

/// "Tama Crashed": what macOS recorded last time, and a button that puts a
/// sanitised copy on the clipboard. Nothing is sent anywhere.
@MainActor
final class CrashReportWindowController: NSObject, NSWindowDelegate {
    static let shared = CrashReportWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func show() {
        guard CrashReportService.shared.pending != nil || CrashReportService.shared.latestReport() != nil else { return }
        if window == nil {
            let size = ToolWindowMetrics.crashReportSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Tama Crashed"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.minSize = NSSize(width: 460, height: 380)
            window.isReleasedWhenClosed = false
            window.delegate = self
            let host = NSHostingView(rootView: CrashReportView { [weak self] in self?.window?.close() })
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

    /// Closing counts as read: the same crash isn't raised again next launch.
    func windowWillClose(_ notification: Notification) {
        CrashReportService.shared.dismissPending()
        window?.contentView = nil
        window = nil
    }
}

private struct CrashReportView: View {
    let close: () -> Void
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var service = CrashReportService.shared
    @AppStorage(CrashReportService.promptKey) private var prompt = true
    @State private var report: CrashReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DS.Palette.warning.gradient))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tama crashed").font(.system(size: 18, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 26)

            Text("macOS wrote a report. Copy it and paste it wherever you report the bug — Tama sends nothing by itself. Your account name, home folder and the identifiers for this Mac are taken out first.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(report?.text ?? "No crash report was found.")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(report == nil ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(SettingsStyle.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SettingsStyle.hairline))

            HStack {
                Toggle("Tell me after a crash", isOn: $prompt)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Spacer()
                if let report {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([report.url]) }
                        .help("Reveal the original report file")
                    Button("Copy Report") { CrashReportService.shared.copyToPasteboard(report) }
                        .help("Copy the report without your account name, home folder or Mac identifiers")
                }
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            }
        }
        // Esc closes it too, as it does every other Tama panel.
        .background {
            Button("", action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(minWidth: 460, minHeight: 380)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .tint(state.accentColor.color)
        .onAppear { report = service.pending ?? service.latestReport() }
    }

    private var subtitle: String {
        guard let report else { return "No report found in the last week." }
        return "\(report.headline) · \(report.date.formatted(date: .abbreviated, time: .shortened))"
    }
}
