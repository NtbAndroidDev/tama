import SwiftUI

// LiquidMouse Console — smooth scrolling and a wheel-only scroll direction.

struct LiquidMouseConsoleView: View {
    @ObservedObject private var liquid = LiquidMouseService.shared
    @ObservedObject private var mice = ExternalMouseMonitor.shared
    @AppStorage(LiquidMouseService.Keys.liquidMode) private var liquidMode = false
    @AppStorage(LiquidMouseService.Keys.reverseHorizontal) private var reverseHorizontal = false
    @AppStorage(LiquidMouseService.Keys.smooth) private var smooth = false
    @AppStorage(LiquidMouseService.Keys.reverse) private var reverse = false
    @AppStorage(LiquidMouseService.Keys.speed) private var speed = 1.0
    @AppStorage(LiquidMouseService.Keys.glide) private var glide = 0.35
    // Accessibility is granted in System Settings, so re-check while it's missing.
    private let permissionPoll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private let tint = Color(red: 0.36, green: 0.78, blue: 0.95)

    /// The console's one switch flips both axes; Settings sets them apart.
    private var reverseBoth: Binding<Bool> {
        Binding(get: { reverse }, set: { reverse = $0; reverseHorizontal = $0 })
    }

    private var statusText: String {
        if !smooth && !reverse && !reverseHorizontal { return "OFF" }
        if !liquid.hasPermission { return "NEEDS ACCESS" }
        return liquid.isActive ? "ACTIVE" : "STARTING"
    }

    var body: some View {
        // The permission banner only appears while access is missing, and it
        // pushes Glide past the fixed console height, so the rows scroll.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack(spacing: DS.Space.sm) {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "computermouse.fill").foregroundColor(tint).accessibilityHidden(true)
                        Text("Mouse scrolling").font(DS.Typo.title)
                            .foregroundColor(DS.Palette.textPrimary)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                    Text(statusText)
                        .font(DS.Typo.micro)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.xxs)
                        .background(liquid.isActive ? DS.Palette.success.opacity(0.22) : DS.Palette.surface2)
                        .foregroundColor(liquid.isActive ? DS.Palette.success : ((smooth || reverse || reverseHorizontal) ? DS.Palette.warning : DS.Palette.textSecondary))
                        .clipShape(Capsule())
                        .accessibilityLabel("Status: \(statusText.lowercased())")
                }

                HStack(spacing: DS.Space.sm) {
                    Circle()
                        .fill(mice.hasExternalMouse ? DS.Palette.success : DS.Palette.textTertiary)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(mice.hasExternalMouse ? mice.mice.joined(separator: ", ") : "No external mouse connected")
                        .font(DS.Typo.label)
                        .foregroundColor(DS.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(mice.hasExternalMouse
                      ? "\(mice.mice.joined(separator: ", ")). Trackpads and Magic Mouse are left alone."
                      : "Trackpads and Magic Mouse are left alone.")

                if (smooth || reverse || reverseHorizontal) && !liquid.hasPermission {
                    // Same permission card as Mechey's and Audio Control's.
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "lock.shield.fill").foregroundColor(DS.Palette.warning)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("\(PermissionService.accessibilityName) needed")
                                .font(DS.Typo.labelStrong)
                                .foregroundColor(DS.Palette.textPrimary)
                            Text("Tama needs it to smooth and reverse scroll events.")
                                .font(DS.Typo.caption)
                                .foregroundColor(DS.Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        DroppyPillButton("Grant", systemName: "lock.open", tone: .accent,
                                         help: "Allow Tama to smooth and reverse scroll events") { liquid.requestPermission() }
                    }
                    .padding(DS.Space.md)
                    .dsSurface(1, radius: DS.Radius.sm, borderColor: DS.Palette.warning.opacity(0.4))
                }

                row("Smooth scrolling", systemName: "water.waves", isOn: $smooth)
                row("Liquid Mode", systemName: "drop.fill", isOn: $liquidMode)
                    .disabled(!smooth)
                    .opacity(smooth ? 1 : 0.45)
                row("Reverse mouse wheel", systemName: "arrow.up.arrow.down", isOn: reverseBoth)
                Text("Flips only the mouse wheel, so natural scrolling can stay on for the trackpad.")
                    .font(DS.Typo.caption)
                    .foregroundColor(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                slider("Speed", value: $speed, range: 0.5...3, label: String(format: "%.1f×", speed))
                    .disabled(!smooth)
                    .opacity(smooth ? 1 : 0.45)
                slider("Glide", value: $glide, range: 0.15...0.8, label: glide < 0.28 ? "Short" : (glide < 0.5 ? "Medium" : "Long"))
                    .disabled(!smooth)
                    .opacity(smooth ? 1 : 0.45)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            ExternalMouseMonitor.shared.start()
            LiquidMouseService.shared.start()
            liquid.refreshPermission()
        }
        .onReceive(permissionPoll) { _ in
            if !liquid.hasPermission { liquid.refreshPermission() }
        }
    }

    private func row(_ title: String, systemName: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title).font(DS.Typo.headline).foregroundColor(DS.Palette.textPrimary)
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(title)
                .font(DS.Typo.label)
                .foregroundColor(DS.Palette.textSecondary)
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: range)
                .controlSize(.mini)
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue(label)
            Text(label)
                .font(DS.Typo.numeric)
                .monospacedDigit()
                .foregroundColor(DS.Palette.textSecondary)
                .frame(width: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}
