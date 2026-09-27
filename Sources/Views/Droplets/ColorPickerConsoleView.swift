import SwiftUI
import AppKit

// Color Eyedropper Console — interactive console for this Droplet, presented inside the Droplets lane.

struct ColorPickerConsoleView: View {
    @ObservedObject var state = AppState.shared
    @State private var recentSwatches: [String] = UserDefaults.standard.stringArray(forKey: "colorSwatches") ?? []
    /// nil until something has actually been sampled.
    @State private var pickedHex: String? = UserDefaults.standard.stringArray(forKey: "colorSwatches")?.first
    private var pickedRGB: String { pickedHex.map(Self.rgbString) ?? "Pick a colour anywhere on screen" }
    private var currentColor: Color { pickedHex.map(colorFromHex) ?? .clear }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // The page header already names the Droplet ("Color Dropper").
            HStack(spacing: DS.Space.lg) {
                // Color Swatch
                Circle()
                    .fill(currentColor)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle().stroke(DS.Palette.hairlineStrong,
                                        style: StrokeStyle(lineWidth: 2, dash: pickedHex == nil ? [4, 3] : []))
                    )
                    .shadow(color: currentColor.opacity(0.5), radius: 8)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(pickedHex ?? "No colour picked yet")
                        .font(pickedHex == nil ? DS.Typo.headline : .system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(pickedHex == nil ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                        .textSelection(.enabled)
                    Text(pickedRGB)
                        .font(pickedHex == nil ? DS.Typo.caption : DS.Typo.mono)
                        .foregroundColor(DS.Palette.textSecondary)
                        .textSelection(.enabled)
                    
                    HStack(spacing: DS.Space.sm) {
                        DroppyPillButton("Pick screen colour", systemName: "eyedropper", tone: .accent,
                                         help: "Click any pixel on screen; its HEX is copied") {
                            sampleScreenColor()
                        }
                        
                        DroppyIconButton("doc.on.doc", size: 24, tone: .tonal, help: "Copy HEX to clipboard") {
                            guard let pickedHex else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(pickedHex, forType: .string)
                            DroppyAudio.playCopySuccess()
                            state.showNotification(appName: "Color Dropper", title: "Hex copied", message: "\(pickedHex) copied to clipboard")
                        }
                        .disabled(pickedHex == nil)
                    }
                }
            }
            
            // Preset palette
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Recent swatches")
                    .font(DS.Typo.caption)
                    .foregroundColor(DS.Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                
                if recentSwatches.isEmpty {
                    Text("Colours you pick will appear here")
                        .font(DS.Typo.caption)
                        .foregroundColor(DS.Palette.textSecondary)
                        .frame(height: 22)
                } else {
                    HStack(spacing: DS.Space.sm) {
                        ForEach(recentSwatches, id: \.self) { hex in
                            Button {
                                selectHex(hex)
                            } label: {
                                Circle()
                                    .fill(colorFromHex(hex))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(hex == pickedHex ? Color.white : DS.Palette.hairlineStrong,
                                                             lineWidth: hex == pickedHex ? 1.5 : 1))
                                    // A slightly larger target than the 18 pt dot.
                                    .frame(width: 22, height: 22)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(DroppyPressStyle())
                            .help(hex)
                            .accessibilityLabel("Swatch \(hex)")
                            .accessibilityAddTraits(hex == pickedHex ? .isSelected : [])
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private func sampleScreenColor() {
        let sampler = NSColorSampler()
        // The sampler steals focus; keep the island (and this console) open meanwhile.
        state.setModal(true, owner: "colorPicker.sampler")
        sampler.show { selectedNSColor in
            DispatchQueue.main.async { AppState.shared.setModal(false, owner: "colorPicker.sampler") }
            guard let hex = selectedNSColor?.sRGBHex else { return }
            
            DispatchQueue.main.async {
                self.pickedHex = hex
                self.recentSwatches.removeAll { $0 == hex }
                self.recentSwatches.insert(hex, at: 0)
                if self.recentSwatches.count > 8 { self.recentSwatches.removeLast() }
                UserDefaults.standard.set(self.recentSwatches, forKey: "colorSwatches")
                // Straight to the system clipboard, and into Tama's history through
                // the monitor's path so dedupe and the history limit still apply.
                ClipboardService.shared.copyToPasteboard(text: hex)
                ClipboardService.shared.onNewItem?(ClipboardItem(content: hex, type: .color))
                DroppyAudio.playCopySuccess()
            }
        }
    }
    
    private func selectHex(_ hex: String) {
        pickedHex = hex
        DroppyAudio.playTick()
    }
    
    private static func rgbString(_ hex: String) -> String {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard let v = Int(clean, radix: 16) else { return "rgb(—)" }
        return "rgb(\((v >> 16) & 0xFF), \((v >> 8) & 0xFF), \(v & 0xFF))"
    }

    private func colorFromHex(_ hex: String) -> Color {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard let intVal = Int(clean, radix: 16) else { return .blue }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

extension NSColor {
    /// "#RRGGBB" in sRGB, components rounded to the nearest byte (truncating
    /// turned 0.999… into FE). Shared by the Color Dropper console and ring action.
    var sRGBHex: String? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        func byte(_ c: CGFloat) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent))
    }
}
