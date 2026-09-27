import AppKit

/// Video Target Size: "Compress File" with the current size and a target in
/// megabytes. Returns the target, or nil when cancelled.
@MainActor
enum TargetSizeDialog {
    static func run(for item: ShelfItem) -> Double? {
        let current = Double(item.fileSize) / 1_048_576
        let alert = NSAlert()
        alert.messageText = "Compress File"
        alert.informativeText = item.name
        alert.icon = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: nil)
        alert.addButton(withTitle: "Compress")
        alert.addButton(withTitle: "Cancel")

        let width: CGFloat = 280
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 70))
        let currentLabel = NSTextField(labelWithString: "Current Size")
        currentLabel.frame = NSRect(x: 0, y: 44, width: 140, height: 18)
        let currentValue = NSTextField(labelWithString: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
        currentValue.alignment = .right
        currentValue.frame = NSRect(x: width - 140, y: 44, width: 140, height: 18)
        let targetLabel = NSTextField(labelWithString: "Target Size")
        targetLabel.frame = NSRect(x: 0, y: 8, width: 110, height: 18)
        let field = NSTextField(frame: NSRect(x: 112, y: 4, width: 120, height: 24))
        field.placeholderString = "Target size in megabytes"
        // Half the current size; a file under 2 MB gets a decimal, or the
        // suggestion (rounded up to 1) would already be too big to accept.
        field.stringValue = current >= 2
            ? String(Int((current * 0.5).rounded()))
            : String(format: "%.1f", max(0.2, current * 0.5))
        field.alignment = .right
        field.setAccessibilityLabel("Target size in megabytes")
        let unit = NSTextField(labelWithString: "MB")
        unit.frame = NSRect(x: 240, y: 8, width: 40, height: 18)
        [currentLabel, currentValue, targetLabel, field, unit].forEach(container.addSubview)
        alert.accessoryView = container
        alert.window.initialFirstResponder = field

        let state = AppState.shared
        state.setModal(true, owner: "targetSize.dialog")
        NSApp.activate(ignoringOtherApps: true)
        defer { state.setModal(false, owner: "targetSize.dialog") }
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let text = field.stringValue.replacingOccurrences(of: ",", with: ".")
            if let value = Double(text), value > 0.1, value < current {
                return value
            }
            let warning = NSAlert()
            warning.alertStyle = .warning
            warning.messageText = "Pick a smaller size"
            warning.informativeText = "Enter a number of megabytes above 0.1 and below the current \(String(format: "%.1f", current)) MB."
            warning.runModal()
        }
    }
}
