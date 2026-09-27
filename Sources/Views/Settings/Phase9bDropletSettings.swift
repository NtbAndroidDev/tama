import SwiftUI

// Droplet detail options for Voice Transcribe, Thunderstorm and Menu Bar
// Manager (Settings › Droplets › the droplet's page). Anchors are
// "droplet.<id>.<option>", indexed in SettingsSearch.

// MARK: - Voice Transcribe

struct VoiceTranscribeDropletSettings: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Section {
            FormShortcutRow(action: .quickRecord, title: "Quick Record",
                            help: "Start or stop a visible recording from anywhere. The recorder opens, the notch shows the time and (if on) a red mic appears in the menu bar.",
                            anchor: "droplet.voiceTranscribe.quickRecord")
            InfoToggle("External recorder",
                       info: "Use the floating panel instead of inline expansion: Quick Record opens a small recorder window you can drag anywhere, and it stays up while recording.",
                       isOn: $state.voiceFloatingRecorder)
                .settingsAnchor("droplet.voiceTranscribe.floating")
            InfoToggle("Show recording icon in menu bar",
                       info: "A red mic with the elapsed time sits in the menu bar while recording; click it to stop. It also appears whenever the island is hidden, so a recording is never invisible.",
                       isOn: $state.voiceMenuBarIcon)
                .settingsAnchor("droplet.voiceTranscribe.menuBar")
        } header: {
            Text("Recording")
        } footer: {
            Text("Recording is always shown on screen. Invisible background recording isn't offered.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Picker(selection: $state.voiceEngine) {
                ForEach(VoiceEngine.allCases) { Text($0.title).tag($0) }
            } label: {
                HStack(spacing: 6) {
                    Text("Engine")
                    InfoButton(state.voiceEngine.detail)
                }
            }
            .settingsAnchor("droplet.voiceTranscribe.engine")
            InfoToggle("Live transcription",
                       info: "Show the words while you talk. Off, the whole recording is transcribed after Stop, with a progress percentage — usually a little more accurate.",
                       isOn: $state.voiceLiveTranscription)
                .settingsAnchor("droplet.voiceTranscribe.live")
            InfoToggle("Skip result window and copy transcription instantly",
                       info: "When the text is ready it goes straight to the clipboard, with a banner, instead of the Transcription card.",
                       isOn: $state.voiceSkipResult)
                .settingsAnchor("droplet.voiceTranscribe.skipResult")
        } header: {
            Text("Transcription")
        } footer: {
            Text("Transcription uses Apple's Speech framework. OpenAI Whisper and NVIDIA Parakeet models aren't included: they need multi-hundred-megabyte model downloads and a bundled inference runtime, and Tama ships without third-party code.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Picker(selection: $state.voiceRetention) {
                ForEach(VoiceRetention.allCases) { Text($0.title).tag($0) }
            } label: {
                HStack(spacing: 6) {
                    Text("Recordings")
                    InfoButton(state.voiceRetention.detail)
                }
            }
            .settingsAnchor("droplet.voiceTranscribe.retention")
        } header: {
            Text("Storage")
        } footer: {
            Text(state.voiceRetention.detail + " Saved recordings can be transcribed again from their row or right-click menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Thunderstorm

struct ThunderstormDropletSettings: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Section {
            FormShortcutRow(action: .thunderstorm, title: "Open Thunderstorm",
                            help: "Summons the floating launcher. Type to search files, apps, System Settings, Tama settings and droplets.",
                            anchor: "droplet.thunderstorm.shortcut")
            LabeledContent("Open it now") {
                Button("Open Launcher") { ThunderstormLauncherController.shared.show() }
            }
        } header: {
            Text("Launcher")
        } footer: {
            Text("↩ opens, ⌘↩ reveals in Finder, ⌘Y Quick Look, ⌘T adds to the Tray, ⌘C copies the path and ⌘⌫ moves an app or file to the Trash (press Return to confirm). The Widgets page keeps its own Thunderstorm console too.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            InfoToggle("System commands",
                       info: "Lock Screen, Sleep, Restart, Shut Down, Log Out, Eject All Disks and Quit All Apps. The ones that close things ask for a second Return.",
                       isOn: $state.thunderstormSystemCommands)
                .settingsAnchor("droplet.thunderstorm.commands")
            InfoToggle("Web search",
                       info: "Google Search, DuckDuckGo and Wikipedia rows under the results; they open in your browser.",
                       isOn: $state.thunderstormWebSearch)
                .settingsAnchor("droplet.thunderstorm.web")
            InfoToggle("Inline web answers",
                       info: "Looks up an inline answer from DuckDuckGo's free Instant Answer API as you type, which sends what you type to DuckDuckGo. Off, a \u{201C}Look Up an Inline Answer\u{201D} row asks only when you pick it.",
                       isOn: $state.thunderstormInlineAnswers)
                .settingsAnchor("droplet.thunderstorm.answers")
        } header: {
            Text("Results")
        }
    }
}

// MARK: - Menu Bar Manager

struct MenuBarManagerDropletSettings: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var manager = MenuBarManagerService.shared
    @State private var confirmsReset = false

    var body: some View {
        Section {
            LabeledContent("Hidden section") {
                HStack(spacing: 8) {
                    Text(!manager.isRunning ? "Off" : manager.isRevealed ? "Shown" : "Hidden")
                        .foregroundStyle(.secondary)
                    Button(manager.isRevealed ? "Hide" : "Show") { manager.toggle() }
                        .disabled(!manager.isRunning)
                }
            }
            .settingsAnchor("droplet.menuBar.toggle")
            FormShortcutRow(action: .menuBarToggle, title: "Show or hide the hidden section",
                            anchor: "droplet.menuBar.shortcut")
            if manager.isMisordered {
                Label("A divider is to the right of the toggle icon, so nothing is hidden. ⌘-drag it back to the left, or reset the layout.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warning)
            }
        } header: {
            Text("Clean up your menu bar")
        } footer: {
            Text("Hold ⌘ and drag menu bar icons to the left of Tama's divider ( | ) to hide them; drag them back to the right to keep them visible. Click the toggle to show or hide them, Option-click to include the always-hidden section, right-click for more. The Clock and Control Center are managed by macOS and can't be hidden.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            InfoToggle("Always-hidden section",
                       info: "A second, dotted divider further left. Icons dragged left of it stay hidden even when the hidden section is shown; Option-click the toggle to see them.",
                       isOn: $state.menuBarAlwaysHidden)
                .settingsAnchor("droplet.menuBar.alwaysHidden")
            InfoToggle("Rehide automatically",
                       info: "Fold the icons away again after a delay. It waits while the pointer is up in the menu bar.",
                       isOn: $state.menuBarAutoRehide)
                .settingsAnchor("droplet.menuBar.rehide")
            if state.menuBarAutoRehide {
                LabeledContent("Rehide after") {
                    Stepper("\(Int(state.menuBarRehideDelay)) s", value: $state.menuBarRehideDelay, in: 2...120, step: 1)
                }
            }
            InfoToggle("Rehide when switching apps",
                       info: "Fold the icons away as soon as you switch to another app.",
                       isOn: $state.menuBarRehideOnAppSwitch)
                .settingsAnchor("droplet.menuBar.appSwitch")
        } header: {
            Text("Behavior")
        } footer: {
            Text("Only a click (or the shortcut) reveals icons: Tama doesn't watch the pointer or scrolling in the menu bar.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Picker("Toggle icon", selection: $state.menuBarToggleIcon) {
                ForEach(MenuBarToggleIcon.allCases) { icon in
                    Label(icon.title, systemImage: icon.symbol(revealed: false)).tag(icon)
                }
            }
            .settingsAnchor("droplet.menuBar.icon")
            InfoToggle("Render icon as a template",
                       info: "Template icons follow the menu bar's light or dark look; off, the toggle uses your highlight color.",
                       isOn: $state.menuBarIconTemplate)
                .settingsAnchor("droplet.menuBar.template")
            InfoToggle("Show section dividers",
                       info: "While the icons are shown, thin dividers mark where each hidden section starts. Keep this on to rearrange them.",
                       isOn: $state.menuBarShowDividers)
            LabeledContent("Layout") {
                Button("Reset Layout…") { confirmsReset = true }
                    .disabled(!manager.isRunning)
            }
            .settingsAnchor("droplet.menuBar.reset")
            .confirmationDialog("Reset the menu bar layout?", isPresented: $confirmsReset) {
                Button("Reset Layout", role: .destructive) { manager.resetLayout() }
            } message: {
                Text("Tama's toggle and dividers go back to their starting places. You may need to ⌘-drag icons past the divider again to hide them.")
            }
        } header: {
            Text("Appearance")
        }
    }
}
