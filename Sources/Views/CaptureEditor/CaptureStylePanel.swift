import SwiftUI

/// "Beautify" controls: a backdrop, padding, rounded corners, shadow and a
/// target aspect, applied on export and previewed live on the canvas.
struct CaptureStylePanel: View {
    @ObservedObject var model: CaptureEditorModel

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.lg) {
            Toggle(isOn: $model.backdrop.isEnabled) {
                Text("Backdrop").font(DS.Typo.labelStrong).foregroundStyle(DS.Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack(spacing: 5) {
                ForEach(BackdropPreset.allCases) { preset in
                    PresetSwatch(preset: preset, isSelected: model.backdrop.preset == preset) {
                        model.backdrop.preset = preset
                        model.backdrop.isEnabled = true
                        DroppyAudio.playTick()
                    }
                }
            }

            labeledSlider("Padding", value: $model.backdrop.padding, range: 0...160)
            labeledSlider("Corners", value: $model.backdrop.cornerRadius, range: 0...40)

            Toggle(isOn: $model.backdrop.shadow) {
                Text("Shadow").font(DS.Typo.label).foregroundStyle(DS.Palette.textSecondary)
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 2) {
                ForEach(BackdropAspect.allCases) { aspect in
                    DroppyChip(aspect.title, isSelected: model.backdrop.aspect == aspect) {
                        model.backdrop.aspect = aspect
                        model.backdrop.isEnabled = true
                        DroppyAudio.playTick()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: 44)
        .disabled(model.tool == .crop)
        .opacity(model.tool == .crop ? 0.5 : 1)
    }

    private func labeledSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(title).font(DS.Typo.label).foregroundStyle(DS.Palette.textSecondary)
            Slider(value: Binding(get: { value.wrappedValue }, set: {
                value.wrappedValue = $0.rounded()
                model.backdrop.isEnabled = true
            }), in: range)
            .controlSize(.mini)
            .frame(width: 80)
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(value.wrappedValue)) points")
        }
        .help("\(title): \(Int(value.wrappedValue)) pt")
    }
}

private struct PresetSwatch: View {
    let preset: BackdropPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if preset.colors.count > 1 {
                    LinearGradient(colors: preset.colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
                } else if let solid = preset.colors.first {
                    solid.color
                } else {
                    DS.Palette.surface2
                    Image(systemName: "circle.slash").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
                    .padding(-3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.title)
        .accessibilityLabel("Backdrop \(preset.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
