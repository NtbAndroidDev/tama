import SwiftUI

// Meetings Console — mic, camera, screen share and hang up for the call
// you're in, plus a quick task field and meeting notes while a call runs.

struct MeetingsConsoleView: View {
    @ObservedObject private var meetings = MeetingControlService.shared
    @ObservedObject private var state = AppState.shared
    @State private var taskText = ""
    @State private var isSavingTask = false
    @FocusState private var taskFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header
            // Seven apps are supported and their names are long, so the row
            // scrolls rather than squeezing the chips past legibility.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(meetings.available) { app in
                        DroppyChip(app.name, isSelected: meetings.target?.id == app.id,
                                   help: "Send camera, share and hang up to \(app.name)") {
                            meetings.targetID = app.id
                            DroppyAudio.playTick()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            MeetingControlsRow(size: 46, showsLabels: !meetings.callState.isInCall)

            if meetings.callState.isInCall {
                taskField
            } else {
                Text("Mute turns off \(meetings.inputName.isEmpty ? "the microphone" : meetings.inputName) for every app, so it works in any call. Camera, share and hang up use \(meetings.target?.name ?? "the app")'s shortcuts or menus and need \(PermissionService.accessibilityName).")
                    .font(DS.Typo.caption)
                    .foregroundColor(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            MeetingControlService.shared.start()
            meetings.refreshApps()
            meetings.refresh()
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            switch meetings.callState {
            case let .inCall(appID, since):
                Image(systemName: "phone.fill").foregroundStyle(DS.Palette.success).accessibilityHidden(true)
                Text(since, style: .timer)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(DS.Palette.success)
                    .accessibilityLabel("Call time")
                Text(MeetingApp.all.first { $0.id == appID }?.name ?? "Call")
                    .font(DS.Typo.labelStrong)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                MicLevelBars(tint: DS.Palette.success, isMuted: meetings.isMicMuted)
            case .watching:
                statusLine("Watching for meetings…", icon: "eye")
            case .sleeping:
                statusLine("Sleeping until a supported meeting app launches.", icon: "moon.zzz")
            }
        }
    }

    private func statusLine(_ text: String, icon: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: icon).foregroundStyle(DS.Palette.textSecondary).accessibilityHidden(true)
            Text(text).font(DS.Typo.label).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// "Capture reminders mid-call": the Tasks parser (dates, #List, !!)
    /// straight into Reminders, and a Meeting Notes note.
    private var taskField: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "checklist").foregroundStyle(DS.Palette.textSecondary).accessibilityHidden(true)
            TextField("Add a task… (e.g. Send the deck tomorrow 5pm)", text: $taskText)
                .textFieldStyle(.plain)
                .font(DS.Typo.body)
                .accessibilityLabel("New task")
                .focused($taskFocused)
                .onSubmit(addTask)
                .disabled(isSavingTask)
                // A half-typed task holds the shelf open.
                .onChange(of: taskFocused) { _, focused in
                    AppState.shared.setEditing(focused, owner: "droplet.meetings.task")
                }
            if isSavingTask { ProgressView().controlSize(.mini).accessibilityLabel("Adding the task") }
            DroppyPillButton("Meeting Notes", systemName: "note.text", tone: .plain,
                             help: "Start a note for this meeting in Notes") { openMeetingNotes() }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(DS.Palette.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private func addTask() {
        let text = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSavingTask else { return }
        isSavingTask = true
        Task { @MainActor in
            do {
                try await CalendarService.shared.addReminder(text)
                taskText = ""
                DroppyAudio.playTick()
                let parsed = ReminderParser.parse(text)?.title ?? text
                state.showNotification(appName: "Meetings", title: "Task added", message: parsed,
                                       icon: "checklist", duration: 2.5)
            } catch {
                state.showNotification(appName: "Meetings", title: "Couldn't add the task",
                                       message: error.localizedDescription, icon: "exclamationmark.triangle")
            }
            isSavingTask = false
        }
    }

    private func openMeetingNotes() {
        let name: String
        if case let .inCall(appID, _) = meetings.callState {
            name = MeetingApp.all.first { $0.id == appID }?.name ?? "Call"
        } else {
            name = meetings.target?.name ?? "Meeting"
        }
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        let id = NotesStore.shared.create("Meeting Notes — \(name), \(stamp)\n")
        NotesStore.shared.requestedNoteID = id
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.activeDropletID = "scratchpad" }
    }
}

/// The four round meeting buttons; shared by the console and the home card.
/// Red fills mean "off": a muted mic, a camera that isn't streaming.
struct MeetingControlsRow: View {
    var size: CGFloat
    var showsLabels = true
    @ObservedObject private var meetings = MeetingControlService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let hangUpFill = Color(red: 0.36, green: 0.07, blue: 0.08)

    var body: some View {
        let app = meetings.target
        let inCall = meetings.callState.isInCall
        let cameraOff = inCall && meetings.isCameraOn == false
        HStack(spacing: size * 0.3) {
            control(meetings.isMicMuted ? "mic.slash.fill" : "mic.fill",
                    title: meetings.isMicMuted ? "Unmute" : "Mute",
                    fill: meetings.isMicMuted ? DS.Palette.danger : NotchPalette.control, enabled: true) {
                meetings.toggleMic()
            }
            control(cameraOff ? "video.slash.fill" : "video.fill",
                    title: cameraOff ? "Turn on camera" : "Turn off camera",
                    fill: cameraOff ? DS.Palette.danger : NotchPalette.control,
                    enabled: app?.camera != nil || (app.map { !$0.isBrowser } ?? false)) {
                meetings.send(.camera)
            }
            control("rectangle.on.rectangle", title: "Share", fill: NotchPalette.control, enabled: app?.share != nil) {
                meetings.send(.share)
            }
            control("phone.down.fill", title: app?.isBrowser == true ? "Leave" : "Hang up", fill: Self.hangUpFill,
                    enabled: app?.leave != nil || (app.map { !$0.isBrowser } ?? false)) {
                meetings.hangUp()
            }
        }
        .frame(maxWidth: .infinity)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: meetings.isMicMuted)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: cameraOff)
    }

    private func control(_ symbol: String, title: String, fill: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 5) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: size, height: size)
                    .background(Circle().fill(fill))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.86))
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
            .help(enabled ? title : "\(meetings.target?.name ?? "This app") has no shortcut for this")
            .accessibilityLabel(title)
            if showsLabels {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
    }
}
