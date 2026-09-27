import SwiftUI
import AppKit

// Quick Math Console — interactive console for this Droplet, presented inside the Droplets lane.

struct QuickMathConsoleView: View {
    /// Not observed: nothing here is drawn from AppState, and observing it
    /// redrew this console on every change anywhere in the app.
    private var state: AppState { AppState.shared }
    /// Typed here, not bound to `state.quickMathExpression`: an AppState write
    /// per keystroke redrew every view observing it. Saved back on Return, on
    /// a preset and when the console goes, so it's there next time it opens.
    @State private var expression = ""
    /// nil when the expression can't be evaluated.
    @State private var resultString: String? = "0"
    @FocusState private var fieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "function")
                        .foregroundColor(DS.Palette.success)
                        .accessibilityHidden(true)
                    Text("Expression solver")
                        .font(DS.Typo.title)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Type an expression; Return copies the result.")
                    .font(DS.Typo.label)
                    .foregroundColor(DS.Palette.textSecondary)
                    .accessibilityHidden(true)
                
                HStack(spacing: DS.Space.sm) {
                    TextField("e.g. 45 * 12 + 8", text: $expression)
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .accessibilityLabel("Expression")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.sm)
                        .background(DS.Palette.surface1)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .onChange(of: expression) { _, expr in
                            evaluate(expr)
                        }
                        .onSubmit {
                            state.quickMathExpression = expression
                            copyResult()
                        }
                    
                    Text("=")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Palette.textSecondary)
                        .accessibilityHidden(true)
                    
                    // Neutral rather than red: a half-typed expression isn't an error yet.
                    Text(resultString ?? "Invalid expression")
                        .font(resultString == nil ? DS.Typo.label : .system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(resultString == nil ? DS.Palette.textSecondary : DS.Palette.success)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.sm)
                        .background(resultString == nil ? DS.Palette.surface1 : DS.Palette.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .textSelection(.enabled)
                        .optionalHelp(resultString)
                        .accessibilityLabel(resultString.map { "Result: \($0)" } ?? "Invalid expression")
                }
            }
            
            // Math Preset Chips
            HStack(spacing: DS.Space.sm) {
                ForEach(["45 * 12 + 8", "(150 + 25) * 4", "2048 / 8", "125 * 3.5"], id: \.self) { sample in
                    Button(sample) {
                        expression = sample
                        state.quickMathExpression = sample
                        evaluate(sample)
                        DroppyAudio.playTick()
                    }
                    .font(DS.Typo.mono)
                    .lineLimit(1)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xxs)
                    .background(DS.Palette.surface1)
                    .foregroundColor(DS.Palette.textSecondary)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .buttonStyle(DroppyPressStyle(scale: 0.95))
                    .help("Try \(sample)")
                }
                Spacer()
            }
            
            HStack(spacing: DS.Space.sm) {
                DroppyPillButton("Copy result", systemName: "doc.on.doc", tone: .tonal,
                                 help: "Copy the result (Return)", action: copyResult)
                    .disabled(resultString == nil)
                
                Spacer()
            }
            
            Spacer()
        }
        .onAppear {
            expression = state.quickMathExpression
            evaluate(expression)
        }
        // A half-typed expression holds the shelf open.
        .onChange(of: fieldFocused) { _, focused in
            state.setEditing(focused, owner: "droplet.quickMath.field")
        }
        .onDisappear {
            // @Published fires even for the same value; skip a no-op redraw.
            if state.quickMathExpression != expression { state.quickMathExpression = expression }
            state.clearEditing(withPrefix: "droplet.quickMath")
        }
    }
    
    /// Shared by the button and Return in the field.
    private func copyResult() {
        guard let resultString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultString, forType: .string)
        DroppyAudio.playCopySuccess()
        state.showNotification(appName: "Quick Math", title: "Result copied", message: "\(resultString) copied to the clipboard")
    }

    private func evaluate(_ expr: String) {
        let clean = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            resultString = "0"
            return
        }
        resultString = MathEvaluator.evaluate(clean).map(MathEvaluator.format)
    }
}
