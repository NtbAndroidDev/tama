import SwiftUI

// System Stats Console — interactive console for this Droplet, presented inside the Droplets lane.

struct SystemStatsConsoleView: View {
    /// Observed directly: AppState holds this service but doesn't forward its changes.
    @ObservedObject private var systemMonitorUpdates = SystemMonitorService.shared
    @ObservedObject var state = AppState.shared
    @ObservedObject private var battery = BatteryService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "cpu")
                        .foregroundColor(DS.Palette.info)
                        .accessibilityHidden(true)
                    Text("Hardware usage")
                        .font(DS.Typo.title)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                
                DroppyIconButton("arrow.clockwise", size: 22, help: "Refresh now") {
                    state.systemMonitor.refreshMetrics()
                    DroppyAudio.playTick()
                }
            }
            
            VStack(spacing: DS.Space.sm) {
                // CPU Bar
                MetricRowView(
                    label: "CPU usage",
                    valueText: "\(Int(state.systemMonitor.metrics.cpuUsagePercent))%",
                    percentage: state.systemMonitor.metrics.cpuUsagePercent / 100.0,
                    tintColor: DS.Palette.info
                )
                
                // RAM Bar
                MetricRowView(
                    label: "Memory",
                    valueText: "\(String(format: "%.1f", state.systemMonitor.metrics.memoryUsedGigabytes)) / \(Int(state.systemMonitor.metrics.memoryTotalGigabytes)) GB",
                    percentage: state.systemMonitor.metrics.memoryUsagePercent / 100.0,
                    tintColor: .purple
                )
                
                // Battery Bar
                MetricRowView(
                    label: "Battery",
                    valueText: state.systemMonitor.metrics.hasBattery
                        ? "\(state.systemMonitor.metrics.batteryPercent)%\(state.systemMonitor.metrics.isCharging ? " · Charging" : "")"
                        : "AC power",
                    percentage: state.systemMonitor.metrics.hasBattery ? Double(state.systemMonitor.metrics.batteryPercent) / 100.0 : 1,
                    tintColor: !state.systemMonitor.metrics.hasBattery || state.systemMonitor.metrics.batteryPercent > 20 ? DS.Palette.success : DS.Palette.danger
                )
            }

            // Flipping it asks for an administrator password (pmset).
            Toggle(isOn: Binding(
                get: { battery.isLowPowerModeOn },
                set: { battery.setLowPowerMode($0) }
            )) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: battery.isLowPowerModeOn ? "leaf.fill" : "leaf")
                        .foregroundColor(battery.isLowPowerModeOn ? DS.Palette.warning : DS.Palette.textSecondary)
                        .accessibilityHidden(true)
                    Text("Low Power Mode")
                        .font(DS.Typo.label)
                        .foregroundStyle(DS.Palette.textPrimary)
                    if battery.isChangingLowPowerMode {
                        ProgressView().controlSize(.mini).accessibilityLabel("Changing Low Power Mode")
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(battery.isChangingLowPowerMode)
            .help("Asks for an administrator password")
            
            Spacer()
        }
        // Polling runs only while something showing the metrics is on screen.
        .onAppear { SystemMonitorService.shared.subscribe() }
        .onDisappear { SystemMonitorService.shared.unsubscribe() }
    }
}

struct MetricRowView: View {
    let label: String
    let valueText: String
    let percentage: Double
    let tintColor: Color
    
    var body: some View {
        VStack(spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                Text(label)
                    .font(DS.Typo.label)
                    .foregroundColor(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.sm)
                Text(valueText)
                    .font(DS.Typo.numeric.monospacedDigit())
                    .foregroundColor(DS.Palette.textPrimary)
                    .lineLimit(1)
            }
            
            DroppyMeter(value: percentage, tint: tintColor, height: 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
