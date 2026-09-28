import SwiftUI

// MARK: - Droplet showcase
//
// The reference store puts a screenshot of the feature on the hero card and
// the droplet's page. We don't copy its images, so each droplet draws its own
// console here instead: the same shapes, meters and rows the real one puts in
// the notch, at a fixed 300 pt width that the hero and the detail page scale.
//
// The point is that somebody who has never turned a droplet on can see what it
// will look like before they do. A placeholder that says nothing is worse than
// no picture at all.

/// The width every showcase is drawn at, before it is scaled to fit.
enum ShowcaseMetrics {
    static let width: CGFloat = 300
    static let height: CGFloat = 132
}

/// The droplets `DropletShowcase` draws a console for. A droplet missing from
/// here falls back to its icon and tag, which says far less — a test keeps
/// the two lists together, so a new droplet is noticed before it ships.
enum ShowcaseCoverage {
    static let drawn: Set<String> = [
        "systemStats", "caffeine", "timer", "pomodoro", "scratchpad", "calculator",
        "aiCutout", "colorPicker", "converter", "windowSnapper", "snipper", "termiNotch",
        "thunderstorm", "ring", "ocr", "voiceTranscribe", "audioControl", "obsidian",
        "liquidMouse", "meetings", "notifications", "agents", "notchface", "appleMusic",
        "weather", "mechey", "localSend", "menuBar",
    ]
}

struct DropletShowcase: View {
    let id: String
    let symbol: String
    let name: String
    let tag: String

    init(droplet: DropletModel) {
        self.id = droplet.id
        self.symbol = droplet.iconSystemName
        self.name = droplet.name
        self.tag = droplet.tag
    }

    private var tint: Color { DropletPalette.tint(for: id) }

    var body: some View {
        content
            .frame(width: ShowcaseMetrics.width, height: ShowcaseMetrics.height, alignment: .top)
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }

    // MARK: Per droplet

    @ViewBuilder private var content: some View {
        switch id {
        case "systemStats":
            VStack(spacing: 9) {
                ShowcaseHeader(symbol: symbol, title: "System Stats", tint: tint, trailing: "Live")
                ShowcaseMeter(label: "CPU", value: 0.42, reading: "42%", tint: tint)
                ShowcaseMeter(label: "Memory", value: 0.68, reading: "11.2 / 16 GB", tint: tint)
                ShowcaseMeter(label: "Battery", value: 0.86, reading: "86% · charging", tint: .green)
            }

        case "caffeine":
            VStack(spacing: 10) {
                ShowcaseHeader(symbol: symbol, title: "High Alert", tint: tint, trailing: "On")
                HStack(spacing: 12) {
                    ShowcaseRing(progress: 0.62, tint: tint, caption: "1:47", sub: "left")
                    VStack(alignment: .leading, spacing: 6) {
                        ShowcaseChip("Display", isOn: true, tint: tint)
                        ShowcaseChip("System", isOn: true, tint: tint)
                        ShowcaseChip("Lid Closed", isOn: false, tint: tint)
                    }
                    Spacer(minLength: 0)
                }
            }

        case "timer":
            VStack(spacing: 10) {
                ShowcaseHeader(symbol: symbol, title: "Timer", tint: tint, trailing: "Countdown")
                HStack(spacing: 12) {
                    ShowcaseRing(progress: 0.35, tint: tint, caption: "08:21", sub: "of 25:00")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            ShowcasePill("5m"); ShowcasePill("10m"); ShowcasePill("25m")
                        }
                        HStack(spacing: 5) {
                            ShowcasePill("−1", tint: tint); ShowcasePill("Pause", tint: tint); ShowcasePill("+1", tint: tint)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

        case "pomodoro":
            VStack(spacing: 10) {
                ShowcaseHeader(symbol: symbol, title: "Pomodoro", tint: tint, trailing: "Focus")
                HStack(spacing: 12) {
                    ShowcaseRing(progress: 0.72, tint: tint, caption: "18:04", sub: "focus")
                    VStack(alignment: .leading, spacing: 7) {
                        ShowcaseLabel("3 of 4 sessions today")
                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { i in
                                Circle().fill(i < 3 ? tint : Color.white.opacity(0.18))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        ShowcaseLabel("🔥 6-day streak")
                    }
                    Spacer(minLength: 0)
                }
            }

        case "scratchpad":
            VStack(alignment: .leading, spacing: 8) {
                ShowcaseHeader(symbol: symbol, title: "Notes", tint: tint, trailing: "Saved")
                ShowcaseNoteLine("Ship the release notes", checked: true)
                ShowcaseNoteLine("Ask Mai about the API key", checked: false)
                ShowcaseNoteLine("Book the meeting room", checked: false)
            }

        case "calculator":
            VStack(alignment: .leading, spacing: 8) {
                ShowcaseHeader(symbol: symbol, title: "Quick Math", tint: tint, trailing: "=")
                ShowcaseField(text: "12 * (3 + 4) - sqrt(49)")
                HStack {
                    Text("77").font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                    Spacer()
                    ShowcasePill("Copy", tint: tint)
                }
            }

        case "aiCutout":
            VStack(spacing: 9) {
                ShowcaseHeader(symbol: symbol, title: "Cutout", tint: tint, trailing: "On-device")
                HStack(spacing: 10) {
                    ShowcaseImageTile(subjectTint: tint, background: true, caption: "Before")
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                    ShowcaseImageTile(subjectTint: tint, background: false, caption: "After")
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 5) {
                        ShowcaseChip("Transparent", isOn: true, tint: tint)
                        ShowcaseChip("Neon", isOn: false, tint: tint)
                    }
                }
            }

        case "colorPicker":
            VStack(alignment: .leading, spacing: 9) {
                ShowcaseHeader(symbol: symbol, title: "Color Dropper", tint: tint, trailing: "#5B8DEF")
                HStack(spacing: 7) {
                    ForEach(["5B8DEF", "F2545B", "36C79B", "F2B33D", "9B6BE3", "2B2F3A"], id: \.self) { hex in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 34, height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15)))
                    }
                }
                ShowcaseLabel("Click anywhere on screen — the hex is copied.")
            }

        case "converter":
            VStack(alignment: .leading, spacing: 8) {
                ShowcaseHeader(symbol: symbol, title: "Quick Convert", tint: tint, trailing: "HEIC → PNG")
                ShowcaseFileRow(icon: "photo", name: "IMG_4821.heic", detail: "4.2 MB", tint: tint)
                ShowcaseProgress(value: 0.64, tint: tint, caption: "Converting… 64%")
                HStack(spacing: 5) {
                    ShowcasePill("PNG", tint: tint); ShowcasePill("JPEG"); ShowcasePill("PDF"); ShowcasePill("WebP")
                }
            }

        case "windowSnapper":
            VStack(spacing: 9) {
                ShowcaseHeader(symbol: symbol, title: "Window Snap", tint: tint, trailing: "⌃⌥←")
                ShowcaseScreen(layout: .halves, tint: tint)
            }

        case "snipper":
            VStack(spacing: 9) {
                ShowcaseHeader(symbol: symbol, title: "Element Capture", tint: tint, trailing: "Area")
                ShowcaseCaptureFrame(tint: tint)
            }

        case "termiNotch":
            VStack(alignment: .leading, spacing: 8) {
                ShowcaseHeader(symbol: symbol, title: "TermiNotch", tint: tint, trailing: "zsh")
                ShowcaseTerminal(lines: [
                    ("~/tama $ ", "swift build", Color.white),
                    ("", "Compiling Tama…", Color.white.opacity(0.55)),
                    ("", "Build complete! (12.4s)", Color.green.opacity(0.85)),
                ])
            }

        case "thunderstorm":
            VStack(alignment: .leading, spacing: 8) {
                ShowcaseField(text: "kind:pdf invoice", icon: "magnifyingglass")
                ShowcaseFileRow(icon: "doc.richtext", name: "Invoice 2026-08.pdf", detail: "~/Documents", tint: tint)
                ShowcaseFileRow(icon: "doc.richtext", name: "Invoice 2026-07.pdf", detail: "~/Documents", tint: tint)
                ShowcaseLabel("↩ open · ⌘↩ reveal · ⌘T to the Tray")
            }

        case "ring":
            ShowcaseRingMenu(tint: tint)

        case "ocr":
            VStack(spacing: 9) {
                ShowcaseHeader(symbol: symbol, title: "OCR", tint: tint, trailing: "Copied")
                ShowcaseOCRFrame(tint: tint)
            }

        case "voiceTranscribe":
            VStack(alignment: .leading, spacing: 9) {
                ShowcaseHeader(symbol: symbol, title: "Voice Transcribe", tint: tint, trailing: "● 00:14")
                ShowcaseWaveform(tint: tint)
                ShowcaseLabel("\u{201C}Remind me to send the deck before Friday\u{201D}")
            }

        case "audioControl":
            VStack(spacing: 8) {
                ShowcaseHeader(symbol: symbol, title: "Audio Control", tint: tint, trailing: "Per app")
                ShowcaseMeter(label: "Music", value: 0.75, reading: "75%", tint: tint)
                ShowcaseMeter(label: "Safari", value: 1.2, reading: "120%", tint: tint)
                ShowcaseMeter(label: "Zoom", value: 0.0, reading: "Muted", tint: .gray)
            }

        case "obsidian":
            VStack(alignment: .leading, spacing: 8) {
                ShowcaseHeader(symbol: symbol, title: "Obsidian", tint: tint, trailing: "Vault")
                ShowcaseNoteLine("2026-09-23.md", checked: false, mono: true)
                ShowcaseTerminal(lines: [
                    ("- [ ] ", "Follow up with the design review", Color.white.opacity(0.8)),
                    ("- ", "Clipped: \u{201C}Liquid Glass notes\u{201D}", Color.white.opacity(0.55)),
                ])
            }

        case "liquidMouse":
            VStack(spacing: 10) {
                ShowcaseHeader(symbol: symbol, title: "LiquidMouse", tint: tint, trailing: "Ease Out")
                ShowcaseCurve(tint: tint)
            }

        case "meetings":
            VStack(spacing: 9) {
                ShowcaseHeader(symbol: symbol, title: "Meetings", tint: tint, trailing: "12:04")
                HStack(spacing: 8) {
                    ShowcaseCircleButton("mic.slash.fill", tint: .red)
                    ShowcaseCircleButton("video.fill", tint: tint)
                    ShowcaseCircleButton("phone.down.fill", tint: .red)
                    Spacer(minLength: 0)
                    ShowcaseMicLevel(tint: tint)
                }
                ShowcaseLabel("Music paused for the call · resumes after")
            }

        case "notifications":
            VStack(spacing: 7) {
                ShowcaseHeader(symbol: symbol, title: "Notifications", tint: tint, trailing: "3 new")
                ShowcaseNotification(app: "Messages", message: "Mai: on my way 👋", tint: .green)
                ShowcaseNotification(app: "Calendar", message: "Standup in 5 minutes", tint: .red)
            }

        case "agents":
            VStack(spacing: 7) {
                ShowcaseHeader(symbol: symbol, title: "Agents", tint: tint, trailing: "2 running")
                ShowcaseAgentRow(name: "Claude Code", detail: "Editing TrayPage.swift", progress: 0.6, tint: tint)
                ShowcaseAgentRow(name: "Codex", detail: "Running tests", progress: 0.25, tint: .green)
            }

        case "notchface":
            VStack(spacing: 9) {
                ShowcaseHeader(symbol: symbol, title: "Notchface", tint: tint, trailing: "Mirrored")
                ShowcaseCameraFrame(tint: tint)
            }

        case "appleMusic":
            ShowcasePlayer(tint: tint)

        case "weather":
            ShowcaseWeather(tint: tint)

        case "mechey":
            VStack(spacing: 10) {
                ShowcaseHeader(symbol: symbol, title: "Mechey", tint: tint, trailing: "Tactile")
                ShowcaseKeys(tint: tint)
            }

        case "localSend":
            VStack(spacing: 8) {
                ShowcaseHeader(symbol: symbol, title: "LocalSend", tint: tint, trailing: "Visible")
                ShowcaseFileRow(icon: "iphone", name: "Mai's iPhone", detail: "Sending 3 files", tint: tint)
                ShowcaseProgress(value: 0.42, tint: tint, caption: "12.4 MB of 29.1 MB")
            }

        case "menuBar":
            VStack(spacing: 10) {
                ShowcaseHeader(symbol: symbol, title: "Menu Bar Manager", tint: tint, trailing: "Hidden")
                ShowcaseMenuBar(tint: tint)
            }

        default:
            // Nothing hand-drawn for this one yet: its own icon, name and what
            // it does, on the droplet's tint — still something to read.
            VStack(spacing: 10) {
                ShowcaseHeader(symbol: symbol, title: name, tint: tint, trailing: nil)
                Text(tag)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Showcase parts

private struct ShowcaseHeader: View {
    let symbol: String
    let title: String
    let tint: Color
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.opacity(0.18)))
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

private struct ShowcaseLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShowcaseMeter: View {
    let label: String
    /// 0…1 normally; above 1 fills and keeps going, like a 150 % app volume.
    let value: Double
    let reading: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.system(size: 10.5, weight: .medium))
                Spacer()
                Text(reading).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct ShowcaseProgress: View {
    let value: Double
    let tint: Color
    let caption: String

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tint).frame(width: geo.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 5)
            Text(caption).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ShowcaseRing: View {
    let progress: Double
    let tint: Color
    let caption: String
    let sub: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
            Circle().trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(caption).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                Text(sub).font(.system(size: 8)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: 66, height: 66)
    }
}

private struct ShowcasePill: View {
    let title: String
    var tint: Color?
    init(_ title: String, tint: Color? = nil) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint?.opacity(0.3) ?? Color.white.opacity(0.12)))
    }
}

private struct ShowcaseChip: View {
    let title: String
    let isOn: Bool
    let tint: Color
    init(_ title: String, isOn: Bool, tint: Color) {
        self.title = title
        self.isOn = isOn
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(isOn ? tint : .white.opacity(0.35))
            Text(title).font(.system(size: 10, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? .white : .white.opacity(0.6))
        }
    }
}

private struct ShowcaseField: View {
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(text).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color.white.opacity(0.09)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
    }
}

private struct ShowcaseFileRow: View {
    let icon: String
    let name: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.09)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ShowcaseNoteLine: View {
    let text: String
    let checked: Bool
    var mono = false

    init(_ text: String, checked: Bool, mono: Bool = false) {
        self.text = text
        self.checked = checked
        self.mono = mono
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(checked ? Color.green : .white.opacity(0.35))
            Text(text)
                .font(mono ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .strikethrough(checked, color: .white.opacity(0.4))
                .foregroundStyle(.white.opacity(checked ? 0.45 : 0.85))
            Spacer(minLength: 0)
        }
    }
}

private struct ShowcaseTerminal: View {
    /// prompt, text, colour.
    let lines: [(String, String, Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 0) {
                    Text(line.0).foregroundStyle(.white.opacity(0.45))
                    Text(line.1).foregroundStyle(line.2)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10.5, design: .monospaced))
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.45)))
    }
}

private struct ShowcaseImageTile: View {
    let subjectTint: Color
    let background: Bool
    let caption: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if background {
                    LinearGradient(colors: [.blue.opacity(0.6), .teal.opacity(0.5)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    CheckerboardBackground()
                }
                Image(systemName: "person.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(subjectTint)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(caption).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

/// The transparency checkerboard, so "no background" reads as transparent.
private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 7
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.85)))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? step : 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: step, height: step)), with: .color(Color(white: 0.65)))
                    x += step * 2
                }
                y += step
                row += 1
            }
        }
    }
}

private struct ShowcaseScreen: View {
    enum Layout { case halves }
    let layout: Layout
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.55))
                .overlay(alignment: .top) { titleBar }
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.18))
                    .overlay(alignment: .top) { titleBar }
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.12))
                    .overlay(alignment: .top) { titleBar }
            }
        }
        .padding(6)
        .frame(height: 82)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    }

    private var titleBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Color.white.opacity(0.35)).frame(width: 3, height: 3)
            }
            Spacer()
        }
        .padding(5)
    }
}

private struct ShowcaseCaptureFrame: View {
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            // The selection, with its handles and its size readout.
            Rectangle()
                .strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .background(Rectangle().fill(tint.opacity(0.1)))
                .frame(width: 150, height: 54)
                .overlay(alignment: .topLeading) {
                    Text("640 × 230")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .offset(x: 4, y: -11)
                }
            // The editor's toolbar under it.
            HStack(spacing: 8) {
                ForEach(["arrow.up.left", "rectangle", "pencil.tip", "textformat", "number.circle", "drop.fill"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 9))
                }
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.65)))
            .offset(y: 44)
        }
        .frame(height: 92)
    }
}

private struct ShowcaseOCRFrame: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.1))
                VStack(alignment: .leading, spacing: 5) {
                    ForEach([46.0, 60.0, 34.0], id: \.self) { width in
                        RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.5))
                            .frame(width: width, height: 7)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(tint, lineWidth: 1))
                    }
                }
            }
            .frame(width: 92, height: 68)
            VStack(alignment: .leading, spacing: 4) {
                Text("Recognized").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                Text("Order #4821\nTotal 1.250.000 ₫")
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                ShowcasePill("Copy text", tint: tint)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ShowcaseWaveform: View {
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<34, id: \.self) { i in
                let h = 6 + abs(sin(Double(i) * 0.7)) * 26
                Capsule().fill(tint.opacity(i < 24 ? 0.9 : 0.25))
                    .frame(width: 3, height: h)
            }
        }
        .frame(height: 34, alignment: .center)
    }
}

private struct ShowcaseCurve: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for i in 1..<4 {
                let x = size.width * Double(i) / 4
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                let y = size.height * Double(i) / 4
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.1)), lineWidth: 1)
            var curve = Path()
            curve.move(to: CGPoint(x: 0, y: size.height))
            curve.addCurve(to: CGPoint(x: size.width, y: 0),
                           control1: CGPoint(x: size.width * 0.1, y: size.height * 0.2),
                           control2: CGPoint(x: size.width * 0.55, y: 0))
            context.stroke(curve, with: .color(tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .frame(height: 76)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.35)))
    }
}

private struct ShowcaseCircleButton: View {
    let symbol: String
    let tint: Color
    init(_ symbol: String, tint: Color) {
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(tint.opacity(0.85)))
    }
}

private struct ShowcaseMicLevel: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<9, id: \.self) { i in
                Capsule().fill(i < 5 ? tint : Color.white.opacity(0.18))
                    .frame(width: 3, height: 6 + Double((i % 4)) * 5)
            }
        }
    }
}

private struct ShowcaseNotification: View {
    let app: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.8))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(app).font(.system(size: 10, weight: .semibold))
                Text(message).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

private struct ShowcaseAgentRow: View {
    let name: String
    let detail: String
    let progress: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().trim(from: 0, to: 0.7)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 10.5, weight: .semibold))
                Text(detail).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Capsule().fill(Color.white.opacity(0.12))
                .frame(width: 52, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: 52 * progress, height: 4)
                }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

private struct ShowcaseCameraFrame: View {
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.45), Color.black.opacity(0.7)],
                                     startPoint: .top, endPoint: .bottom))
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.35))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15))
        }
        .frame(width: 140, height: 84)
        .overlay(alignment: .bottomTrailing) {
            Text("LIVE")
                .font(.system(size: 8, weight: .black))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Color.red.opacity(0.85)))
                .padding(6)
        }
    }
}

private struct ShowcasePlayer: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 58, height: 58)
                .overlay(Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.85)))
            VStack(alignment: .leading, spacing: 5) {
                Text("Nắng Có Còn Xuân").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("Cá Hồi Hoang").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Capsule().fill(Color.white.opacity(0.15))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(Color.white).frame(width: geo.size.width * 0.38, height: 3)
                        }
                    }
                HStack(spacing: 14) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "pause.fill")
                    Image(systemName: "forward.fill")
                    Spacer()
                    Image(systemName: "airpods.pro")
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

private struct ShowcaseWeather: View {
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("28°").font(.system(size: 34, weight: .bold, design: .rounded))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Partly cloudy").font(.system(size: 11, weight: .medium))
                    Text("H 33° · L 25° · AQI 42").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, tint)
            }
            HStack(spacing: 0) {
                ForEach([("now", "28°", "cloud.sun.fill"), ("14", "30°", "sun.max.fill"),
                         ("15", "31°", "sun.max.fill"), ("16", "29°", "cloud.rain.fill")], id: \.0) { hour in
                    VStack(spacing: 3) {
                        Text(hour.0).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
                        Image(systemName: hour.2).font(.system(size: 11))
                        Text(hour.1).font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
        }
    }
}

private struct ShowcaseKeys: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(["Q", "W", "E", "R", "T", "Y"], id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(key == "E" ? tint.opacity(0.7) : Color.white.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15)))
                    .offset(y: key == "E" ? 2 : 0)
            }
        }
        .overlay(alignment: .bottom) {
            Text("thock").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).offset(y: 14)
        }
    }
}

private struct ShowcaseMenuBar: View {
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                ForEach(["wifi", "battery.75", "clock"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.5)))
            HStack(spacing: 10) {
                ForEach(["dot.radiowaves.left.and.right", "bolt.horizontal", "cloud", "envelope", "bell"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }
            }
            Text("Hidden until you click the chevron")
                .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct ShowcaseRingMenu: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 26).frame(width: 96, height: 96)
            ForEach(Array(["scissors", "camera.viewfinder", "doc.on.clipboard", "tray.full.fill",
                           "basket.fill", "bolt.fill", "timer", "gearshape.fill"].enumerated()), id: \.offset) { index, symbol in
                let angle = Double(index) / 8 * 2 * .pi - .pi / 2
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(index == 1 ? Color.white : .white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(index == 1 ? tint : Color.white.opacity(0.1)))
                    .offset(x: cos(angle) * 48, y: sin(angle) * 48)
            }
            Image(systemName: "cursorarrow").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
        }
        .frame(height: 118)
    }
}
