import SwiftUI

// Settings › Shelf: Tasks & Calendar, Pomodoro, High Alert and Notes.

// MARK: - Tasks & Calendar

struct TasksCalendarSettingsSection: View {
    @ObservedObject private var calendarSettings = CalendarSettings.shared
    @ObservedObject private var calendar = CalendarService.shared

    private static let cleanupChoices: [(Int, String)] = [
        (5, "5 seconds"), (60, "1 minute"), (300, "5 minutes"), (3600, "1 hour"),
    ]
    private static let headsUpChoices: [(Int, String)] = [
        (0, "At the due time"), (5, "5 minutes before"), (10, "10 minutes before"),
        (15, "15 minutes before"), (30, "30 minutes before"), (60, "1 hour before"),
    ]

    var body: some View {
        SettingsSection("Tasks & Calendar",
                        subtitle: "Tasks and Calendar in the shelf, with Apple Reminders sync.",
                        help: "Type tasks in plain language: dates like \u{201C}tomorrow 5pm\u{201D} or \u{201C}next Friday\u{201D}, #List or @List to pick a Reminders list, and !, !! or !!! for priority. Events are read-only (Apple Calendar).") {
            VStack(spacing: 12) {
                SettingsGroup {
                    SettingsRow("Show reminders & events", anchor: "shelf.tasks.show")
                    ToggleTiles([
                        ToggleTile("Tasks", icon: "checklist", isOn: $calendarSettings.showTasks),
                        ToggleTile("Events", icon: "calendar", isOn: $calendarSettings.showEvents),
                    ])
                    SettingsDivider()
                    SettingsToggleRow("Hide undated tasks",
                                      subtitle: calendarSettings.showTasks
                                        ? "Tasks without a due date stay in Reminders but leave the page."
                                        : "Needs Tasks.",
                                      anchor: "shelf.tasks.hideUndated", isOn: $calendarSettings.hideUndated)
                        .settingsDisabled(!calendarSettings.showTasks)
                    SettingsDivider()
                    SettingsToggleRow("Week numbers", subtitle: "\u{201C}Sunday (wk. 9)\u{201D} in the day headers.",
                                      anchor: "shelf.tasks.weekNumbers", isOn: $calendarSettings.weekNumbers)
                    SettingsDivider()
                    SettingsRow("Remove completed tasks after",
                                subtitle: "Ticked tasks stay struck through until then.",
                                anchor: "shelf.tasks.cleanup") {
                        Picker("Remove completed tasks after", selection: $calendarSettings.cleanupDelay) {
                            ForEach(Self.cleanupChoices, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                SettingsGroup {
                    SettingsRow("Default list for new tasks",
                                subtitle: "A #List mention in the text wins over this.",
                                anchor: "shelf.tasks.defaultList") {
                        Picker("Default list for new tasks", selection: $calendarSettings.defaultList) {
                            Text("Reminders default").tag("")
                            ForEach(calendar.reminderLists) { Text($0.title).tag($0.id) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsRow("Default calendar",
                                subtitle: "Choose where new events and meeting reminders are added.",
                                anchor: "shelf.tasks.defaultCalendar") {
                        Picker("Default calendar", selection: $calendarSettings.defaultCalendar) {
                            Text("Calendar default").tag("")
                            ForEach(calendar.eventCalendars) { Text($0.title).tag($0.id) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                SettingsGroup {
                    SummaryDisclosureRow("Calendars",
                                         subtitle: "Choose which Apple Calendar calendars are shown.",
                                         done: calendar.eventCalendars.count - hiddenCount(calendarSettings.hiddenCalendars, in: calendar.eventCalendars),
                                         total: calendar.eventCalendars.count, unit: "shown",
                                         anchor: "shelf.tasks.calendars") {
                        CalendarChecklist(items: calendar.eventCalendars, hidden: $calendarSettings.hiddenCalendars,
                                          empty: calendar.hasEventAccess ? "No calendars found." : "Allow Calendar access to choose calendars.",
                                          needsAccess: calendar.hasEventAccess ? nil : .calendars)
                    }
                    SettingsDivider()
                    SummaryDisclosureRow("Reminder lists",
                                         subtitle: "Choose which Apple Reminders lists are shown in Tasks.",
                                         done: calendar.reminderLists.count - hiddenCount(calendarSettings.hiddenLists, in: calendar.reminderLists),
                                         total: calendar.reminderLists.count, unit: "shown",
                                         anchor: "shelf.tasks.lists") {
                        CalendarChecklist(items: calendar.reminderLists, hidden: $calendarSettings.hiddenLists,
                                          empty: calendar.hasReminderAccess ? "No reminder lists found." : "Allow Reminders access to choose lists.",
                                          needsAccess: calendar.hasReminderAccess ? nil : .reminders)
                    }
                }

                SettingsGroup {
                    SettingsToggleRow("Due alerts",
                                      subtitle: "A banner and a notch alert when a timed task is due, with a heads-up before.",
                                      help: "Configure due reminder alerts and the optional alert chime. Only tasks with a time alert; all-day tasks don't.",
                                      anchor: "shelf.tasks.dueAlerts", isOn: $calendarSettings.dueAlerts)
                    SettingsDivider()
                    SettingsRow("Heads-up", subtitle: calendarSettings.dueAlerts ? "Heads-up before reminders are due." : "Needs Due alerts.",
                                anchor: "shelf.tasks.headsUp") {
                        Picker("Heads-up", selection: $calendarSettings.headsUpMinutes) {
                            ForEach(Self.headsUpChoices, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .settingsDisabled(!calendarSettings.dueAlerts)
                    SettingsDivider()
                    SettingsToggleRow("Chime", subtitle: calendarSettings.dueAlerts ? "Play a sound when a task is due." : "Needs Due alerts.",
                                      anchor: "shelf.tasks.chime", isOn: $calendarSettings.dueChime)
                        .settingsDisabled(!calendarSettings.dueAlerts)
                    SettingsDivider()
                    SettingsToggleRow("Event progress ring",
                                      subtitle: "Show a live event progress ring in the notch.",
                                      anchor: "shelf.tasks.eventRing", isOn: $calendarSettings.eventRing)
                    SettingsDivider()
                    SettingsToggleRow("Next up in the notch",
                                      subtitle: "Show your next upcoming event or task.",
                                      anchor: "shelf.tasks.nextEvent", isOn: $calendarSettings.nextEventWing)
                    SettingsDivider()
                    SettingsToggleRow("Keep calendar window on top",
                                      subtitle: "The pop-out calendar floats above other windows.",
                                      anchor: "shelf.tasks.popout", isOn: $calendarSettings.popoutOnTop)
                    SettingsDivider()
                    // A fixed label: the controller isn't observable, so an
                    // "is it open" title would go stale.
                    SettingsRow("Pop out calendar", subtitle: "A separate window with the month and your agenda.",
                                anchor: "shelf.tasks.popoutOpen") {
                        Button("Open Calendar Window") { CalendarPopoutController.shared.bringToFront() }
                    }
                }
            }
        }
        .onAppear { calendar.reloadCalendars() }
    }

    private func hiddenCount(_ storage: String, in items: [CalendarInfo]) -> Int {
        let hidden = Set(storage.split(separator: "\n").map(String.init))
        return items.filter { hidden.contains($0.id) }.count
    }
}

/// Checkboxes for calendars or lists; stores the unticked ones, so new
/// calendars show up by default.
private struct CalendarChecklist: View {
    let items: [CalendarInfo]
    @Binding var hidden: String
    let empty: String
    /// The permission that would fill an empty list, offered as a button.
    var needsAccess: PermissionService.Kind? = nil

    private var hiddenIDs: Set<String> { Set(hidden.split(separator: "\n").map(String.init)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(empty).font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let needsAccess {
                        Button("Allow…") { PermissionService.shared.request(needsAccess) }
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            ForEach(items) { item in
                Toggle(isOn: binding(for: item.id)) {
                    HStack(spacing: 8) {
                        Circle().fill(item.color).frame(width: 9, height: 9)
                        Text(item.title)
                        if !item.source.isEmpty {
                            Text(item.source).font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
        }
        .padding(.vertical, 4)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenIDs.contains(id) },
            set: { shown in
                var set = hiddenIDs
                if shown { set.remove(id) } else { set.insert(id) }
                hidden = set.sorted().joined(separator: "\n")
            }
        )
    }
}

// MARK: - Pomodoro

struct PomodoroSettingsSection: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var pomodoroSettings = PomodoroSettings.shared
    @ObservedObject private var shortcuts = ShortcutsLibrary.shared
    @State private var confirmsMomentumReset = false

    private var missingShortcuts: [String] {
        [AppState.focusOnShortcut, AppState.focusOffShortcut].filter { !shortcuts.names.contains($0) }
    }

    var body: some View {
        SettingsSection("Pomodoro", subtitle: "Set your timer with one slider directly in the shelf.") {
            SettingsGroup {
                SettingsRow("Focus", anchor: "shelf.pomodoro") {
                    Stepper("\(pomodoroSettings.workMinutes) min", value: $pomodoroSettings.workMinutes, in: 1...180)
                }
                SettingsDivider()
                SettingsRow("Break") {
                    Stepper("\(pomodoroSettings.breakMinutes) min", value: $pomodoroSettings.breakMinutes, in: 1...60)
                }
                SettingsDivider()
                SettingsToggleRow("Enable ambient sound",
                                  subtitle: "Generated noise plays during focus sessions; the speaker button mutes it.",
                                  anchor: "shelf.pomodoro.ambient", isOn: $pomodoroSettings.ambientEnabled)
                SettingsDivider()
                SettingsRow("Ambient sound",
                            subtitle: pomodoroSettings.ambientEnabled ? "Choose your preferred ambient sound." : "Needs Enable ambient sound.",
                            anchor: "shelf.pomodoro.ambientSound") {
                    Picker("Ambient sound", selection: $pomodoroSettings.ambientSound) {
                        ForEach(AmbientSoundService.Sound.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .settingsDisabled(!pomodoroSettings.ambientEnabled)
                SettingsDivider()
                SettingsSlider("Volume", value: $pomodoroSettings.ambientVolume, in: 0...1, step: 0.05, defaultValue: 0.5,
                               anchor: "shelf.pomodoro.volume") { "\(Int($0 * 100))%" }
                    .settingsDisabled(!pomodoroSettings.ambientEnabled)
                SettingsDivider()
                SettingsToggleRow("Turn on Focus during sessions",
                                  subtitle: "Runs the \u{201C}\(AppState.focusOnShortcut)\u{201D} and \u{201C}\(AppState.focusOffShortcut)\u{201D} Shortcuts as sessions start and stop.",
                                  help: "macOS doesn't let apps switch Focus directly. In the Shortcuts app, make a shortcut named \u{201C}\(AppState.focusOnShortcut)\u{201D} with the action Set Focus › Do Not Disturb › On, and one named \u{201C}\(AppState.focusOffShortcut)\u{201D} that turns it Off.",
                                  anchor: "shelf.pomodoro.focus", isOn: $pomodoroSettings.focusShortcuts)
                if pomodoroSettings.focusShortcuts, !shortcuts.isLoading, !missingShortcuts.isEmpty {
                    HStack {
                        SettingsNote("Create \(missingShortcuts.map { "\u{201C}\($0)\u{201D}" }.joined(separator: " and ")) in Shortcuts with a Set Focus action.",
                                     icon: "exclamationmark.triangle.fill", tint: DS.Palette.warning)
                        Button("Open Shortcuts") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            }
                        }
                        .controlSize(.small)
                        .padding(.trailing, 12)
                    }
                }
                SettingsDivider()
                SettingsToggleRow("Keep timer visible in notch",
                                  subtitle: "The live countdown stays in the compact HUD, ahead of music and the Tray.",
                                  anchor: "shelf.pomodoro.visible", isOn: $pomodoroSettings.keepVisible)
                SettingsDivider()
                SettingsToggleRow("Open on hover",
                                  subtitle: "Open the shelf the moment you hover the timer.",
                                  anchor: "shelf.pomodoro.hover", isOn: $pomodoroSettings.hoverOpens)
                SettingsDivider()
                SettingsToggleRow("Momentum",
                                  subtitle: momentumSubtitle,
                                  help: "Counts the focus sessions you finish. A day with at least one keeps the streak going; missing a whole day starts it over. Only whole cycles count — a session you reset doesn't.",
                                  anchor: "shelf.pomodoro.momentum", isOn: $pomodoroSettings.showsMomentum)
                if pomodoroSettings.showsMomentum {
                    SettingsDivider()
                    SettingsRow("Best streak", subtitle: "\(state.pomodoroMomentum.bestStreak) day\(state.pomodoroMomentum.bestStreak == 1 ? "" : "s")") {
                        Button("Reset Momentum…") { confirmsMomentumReset = true }
                            .disabled(state.pomodoroMomentum == PomodoroMomentum())
                    }
                    .confirmationDialog("Reset Momentum?", isPresented: $confirmsMomentumReset) {
                        Button("Reset Momentum", role: .destructive) { state.resetPomodoroMomentum() }
                    } message: {
                        Text("Today's sessions, your current streak and your best streak all go back to zero. This can't be undone.")
                    }
                }
            }
        }
        .onAppear { if pomodoroSettings.focusShortcuts { shortcuts.refresh() } }
        .onChange(of: pomodoroSettings.focusShortcuts) { _, on in if on { shortcuts.refresh() } }
    }

    /// "3 today · 5-day streak", or an invitation before the first session.
    private var momentumSubtitle: String {
        state.pomodoroMomentum.summary(on: Date()) ?? "Finish a focus session to start a streak."
    }
}

// MARK: - High Alert

struct HighAlertSettingsSection: View {
    @ObservedObject private var highAlertSettings = HighAlertSettings.shared
    @ObservedObject private var blocker = SleepBlockerService.shared

    var body: some View {
        SettingsSection("High Alert",
                        subtitle: "Cycles between screen awake, system awake, and lid-closed modes.") {
            SettingsGroup {
                SettingsRow("Mode", anchor: "shelf.highAlert.mode")
                ChoiceTiles(HighAlertMode.allCases.map { .init($0, $0.title, icon: $0.icon) },
                            selection: $highAlertSettings.mode)
                SettingsNote(highAlertSettings.mode.summary).padding(.top, 8)
                if highAlertSettings.mode == .lidClosed {
                    SettingsNote("Lid-closed High Alert runs \u{201C}pmset -a disablesleep 1\u{201D}, which asks for an administrator password when it starts and again when it stops. While it runs your Mac won't sleep with the lid closed — keep it ventilated and on power, and don't put it in a bag.",
                                 icon: "exclamationmark.triangle.fill", tint: DS.Palette.warning)
                        .padding(.top, 6)
                }
                SettingsDivider()
                SettingsRow("System sleep",
                            subtitle: blocker.isSystemSleepDisabled
                                ? "Disabled — closing the lid won't sleep this Mac."
                                : "Enabled. Sleep Now puts this Mac to sleep.",
                            anchor: "shelf.highAlert.sleep") {
                    HStack {
                        if blocker.isSystemSleepDisabled {
                            Button("Restore") { blocker.restoreSystemSleep() }
                        }
                        Button("Sleep Now") { blocker.sleepNow() }
                    }
                }
            }
        }
        .onAppear { blocker.refreshSystemSleepStatus() }
    }
}

// MARK: - Notes

struct NotesSettingsSection: View {
    @ObservedObject private var notesSettings = NotesSettings.shared
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        SettingsSection("Notes", subtitle: "Quick notes that live in your notch.") {
            SettingsGroup {
                SettingsToggleRow("Sync with Apple Notes",
                                  subtitle: syncSubtitle,
                                  help: "Notes go to a \u{201C}Tama\u{201D} folder in Apple Notes' default account, and changes made there come back when Notes opens in the shelf. Needs permission to control Notes (Automation).",
                                  anchor: "shelf.notes.sync", isOn: $notesSettings.appleSync)
                if notesSettings.appleSync, case .unreachable = store.syncStatus {
                    SettingsDivider()
                    SettingsRow("Automation access", subtitle: "If Tama isn't allowed to control Notes, turn Notes on under Tama in Privacy & Security › Automation.",
                                icon: "exclamationmark.triangle.fill") {
                        // The Automation pane is shared by every target app.
                        Button("Open Settings…") { PermissionService.shared.openSettings(.automationMusic) }
                    }
                }
                SettingsDivider()
                SettingsToggleRow("Show formatting toolbar",
                                  subtitle: "Bold, italic, underline, headings and lists under the editor.",
                                  anchor: "shelf.notes.toolbar", isOn: $notesSettings.showToolbar)
                SettingsDivider()
                SettingsToggleRow("Grow canvas with longer notes",
                                  subtitle: "The shelf gets taller as a note does.",
                                  anchor: "shelf.notes.grow", isOn: $notesSettings.growCanvas)
            }
        }
    }

    private var syncSubtitle: String {
        guard notesSettings.appleSync else { return "Two-way sync with a \u{201C}Tama\u{201D} folder." }
        switch store.syncStatus {
        case .idle: return "Syncing with Apple Notes."
        case .syncing: return "Syncing…"
        case .unreachable: return "Couldn't reach Apple Notes."
        case .scriptFailed: return "Notes script failed. Try again from the Notes widget."
        }
    }
}
