import SwiftUI

/// Tasks & Calendar on the shelf, laid out like the reference: today on the
/// left (weekday and week number in red, a huge day number, today's items),
/// what's next grouped by day on the right, and a floating + that opens an
/// inline natural-language field. The month grid is kept as an alternate
/// layout (the grid button), and the page can pop out into its own window.
public struct CalendarPage: View {
    var isPopout: Bool
    @ObservedObject private var calendar = CalendarService.shared
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var calendarSettings = CalendarSettings.shared
    @State private var month = Calendar.current.startOfMonth(for: Date())
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var isAdding = false
    @State private var addKind: AddKind = .task
    @State private var draft = ""
    @State private var addError: String?
    @State private var isSaving = false
    @FocusState private var draftFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum AddKind { case task, event }

    public init(isPopout: Bool = false) {
        self.isPopout = isPopout
    }

    public var body: some View {
        Group {
            if !calendar.hasEventAccess && !calendar.hasReminderAccess {
                accessPrompt
            } else if calendarSettings.layout == .month {
                monthLayout
            } else {
                agendaLayout
            }
        }
        .overlay(alignment: .topTrailing) {
            // The inline field takes the top row while adding.
            if !isAdding { toolbar.transition(.opacity) }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isAdding && (calendar.hasEventAccess || calendar.hasReminderAccess) {
                addButton
                    .transition(DS.Motion.transition(reduceMotion, .scale(scale: 0.6).combined(with: .opacity)))
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isAdding)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: calendarSettings.layout)
        // A half-typed task holds the shelf open; a collapse would reset the
        // page and drop the draft with it.
        .onChange(of: isAdding) { _, adding in
            if !isPopout { AppState.shared.setEditing(adding, owner: "calendar.newTask") }
        }
        .onDisappear {
            if !isPopout { AppState.shared.setEditing(false, owner: "calendar.newTask") }
        }
        .onAppear {
            calendar.requestAccessIfNeeded()
            calendar.load(from: selected)
            calendar.loadBusyDays(from: monthDays.first ?? month)
        }
        .onChange(of: month) { _, _ in
            calendar.loadBusyDays(from: monthDays.first ?? month)
        }
        .onChange(of: calendar.hasEventAccess) { _, _ in
            calendar.loadBusyDays(from: monthDays.first ?? month)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            if calendarSettings.layout == .agenda, !Calendar.current.isDateInToday(selected) {
                CalendarTextButton("Today", filled: true, help: "Go to today") { goToToday() }
            }
            NotchCircleButton(calendarSettings.layout == .agenda ? "calendar" : "list.bullet.rectangle",
                              size: 24, iconSize: 10.5, filled: false,
                              help: calendarSettings.layout == .agenda ? "Show month grid" : "Show agenda") {
                calendarSettings.layout = calendarSettings.layout == .agenda ? .month : .agenda
                DroppyAudio.playTick()
            }
            if isPopout {
                NotchCircleButton(calendarSettings.popoutOnTop ? "pin.fill" : "pin", size: 24, iconSize: 10.5,
                                  isActive: calendarSettings.popoutOnTop, filled: false,
                                  help: "Keep calendar window on top") {
                    calendarSettings.popoutOnTop.toggle()
                }
                NotchCircleButton("xmark", size: 24, iconSize: 10, filled: false, help: "Close calendar pop-out") {
                    CalendarPopoutController.shared.close()
                }
            } else {
                NotchCircleButton("macwindow.on.rectangle", size: 24, iconSize: 10.5, filled: false,
                                  help: "Pop out calendar") {
                    CalendarPopoutController.shared.open()
                }
            }
        }
        .offset(y: -3)
    }

    private var addButton: some View {
        Button {
            beginAdding(.task)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(white: 0.16)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .help("Add a task (right-click for an event)")
        .accessibilityLabel("Add a task")
        .accessibilityAction(named: "New Event") { beginAdding(.event) }
        .contextMenu {
            Button("New Task") { beginAdding(.task) }
            Button("New Event") { beginAdding(.event) }
        }
    }

    private func beginAdding(_ kind: AddKind) {
        addError = nil
        addKind = kind
        isAdding = true
        DroppyAudio.playTick()
    }

    private func goToToday() {
        let cal = Calendar.current
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) {
            month = cal.startOfMonth(for: Date())
            selected = cal.startOfDay(for: Date())
        }
        calendar.load(from: selected)
        DroppyAudio.playTick()
    }

    // MARK: Agenda layout

    private var agendaLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            dayColumn
                .frame(width: isPopout ? 220 : (DroppyShelfMetrics.width - DroppyShelfMetrics.horizontalPadding * 2) * 0.44)
            VStack(alignment: .leading, spacing: 8) {
                if isAdding { quickAdd.transition(.opacity) }
                upcomingList
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// "Sunday (wk. 9)", the day number, and the day's items.
    private var dayColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selected.formatted(.dateTime.weekday(.wide)) + weekSuffix(selected))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(NotchPalette.calendarRed)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(selected.formatted(.dateTime.day()))
                .font(.system(size: dayEntries.isEmpty ? 64 : 50, weight: .light, design: .default).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.top, -4)
                .accessibilityLabel(selected.formatted(date: .complete, time: .omitted))
            if dayEntries.isEmpty {
                Text(Calendar.current.isDateInToday(selected) ? "Nothing else today" : "Nothing planned")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NotchPalette.secondary)
                    .padding(.top, 2)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(dayEntries) { row($0) }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private var upcomingList: some View {
        let sections = upcomingSections
        return Group {
            if sections.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(emptyTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                    if calendar.isReminderAccessDenied {
                        remindersDeniedNote
                    } else if calendar.agenda.isEmpty && !isAdding {
                        Text(calendarSettings.showTasks ? "Click + to add your first task" : "Events from Apple Calendar show here")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchPalette.tertiary)
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(sections, id: \.title) { section in
                            Text(section.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NotchPalette.secondary)
                                .lineLimit(1)
                                .padding(.trailing, section.title == sections.first?.title ? 64 : 0)
                                .padding(.top, section.title == sections.first?.title ? 0 : 6)
                            ForEach(section.entries) { row($0) }
                        }
                        if calendar.isReminderAccessDenied { remindersDeniedNote }
                    }
                    .padding(.bottom, 40) // clear of the floating +
                }
            }
        }
    }

    private var emptyTitle: String {
        switch (calendarSettings.showTasks && calendar.hasReminderAccess, calendarSettings.showEvents && calendar.hasEventAccess) {
        case (true, true): "No upcoming tasks or events"
        case (true, false): "No tasks yet"
        default: "No upcoming events"
        }
    }

    /// The selected day's items. On today that includes overdue tasks, and
    /// undated ones unless they're hidden.
    private var dayEntries: [AgendaEntry] {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(selected)
        let startOfDay = cal.startOfDay(for: selected)
        return calendar.agenda.filter { entry in
            guard let start = entry.start else { return false }
            if cal.isDate(start, inSameDayAs: selected) { return true }
            // A multi-day event running through the day.
            if entry.kind == .event, let end = entry.end, start < startOfDay, end > startOfDay { return true }
            return isToday && entry.kind == .reminder && start < startOfDay
        }
        .sorted { a, b in
            // Overdue first, then all-day, then by time.
            (a.start ?? .distantFuture) < (b.start ?? .distantFuture)
        }
    }

    private struct Section {
        let title: String
        let entries: [AgendaEntry]
    }

    /// The week after the selected day, grouped by day, then undated tasks.
    private var upcomingSections: [Section] {
        let cal = Calendar.current
        let startOfNext = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: selected)) ?? selected
        var order: [Date] = []
        var groups: [Date: [AgendaEntry]] = [:]
        for entry in calendar.agenda {
            guard let start = entry.start, start >= startOfNext else { continue }
            let day = cal.startOfDay(for: start)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(entry)
        }
        var sections = order.sorted().map { Section(title: dayTitle($0), entries: groups[$0] ?? []) }
        let undated = calendar.agenda.filter { $0.start == nil }
        if !undated.isEmpty { sections.append(Section(title: "No due date", entries: undated)) }
        return sections
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        let name: String
        if cal.isDateInTomorrow(day) { name = "Tomorrow" }
        else if cal.isDateInToday(day) { name = "Today" }
        else { name = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) }
        return name + weekSuffix(day)
    }

    private func weekSuffix(_ day: Date) -> String {
        guard calendarSettings.weekNumbers else { return "" }
        return " (wk. \(Calendar.current.component(.weekOfYear, from: day)))"
    }

    // MARK: Month layout

    private var monthLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            monthGrid
                .frame(width: isPopout ? 230 : (DroppyShelfMetrics.width - DroppyShelfMetrics.horizontalPadding * 2) * 0.46)
            VStack(alignment: .leading, spacing: 8) {
                if isAdding { quickAdd.transition(.opacity) }
                monthAgenda
            }
            .padding(.top, 26)
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(monthTitle.uppercased())
                    .font(.system(size: 14.5, weight: .heavy))
                    .foregroundStyle(NotchPalette.calendarRed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if !Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month) {
                    CalendarTextButton("Today", filled: true, help: "Go to today") { goToToday() }
                        .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .scale(scale: 0.9))))
                }
                HStack(spacing: 4) {
                    navButton("chevron.left", by: -1, help: "Previous month")
                    navButton("chevron.right", by: 1, help: "Next month")
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)

            let days = monthDays
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(NotchPalette.tertiary)
                        .padding(.bottom, 2)
                }
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    /// The year only shows once you page away from the current one.
    private var monthTitle: String {
        let cal = Calendar.current
        if cal.isDate(month, equalTo: Date(), toGranularity: .year) {
            return month.formatted(.dateTime.month(.wide))
        }
        return month.formatted(.dateTime.month(.wide).year())
    }

    private func navButton(_ name: String, by offset: Int, help: String) -> some View {
        Button {
            if let next = Calendar.current.date(byAdding: .month, value: offset, to: month) {
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { month = next }
            }
        } label: {
            Image(systemName: name)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.8))
        .help(help)
        .accessibilityLabel(help)
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        return DayCell(
            day: "\(cal.component(.day, from: day))",
            spokenDate: day.formatted(date: .complete, time: .omitted),
            isToday: cal.isDateInToday(day),
            isSelected: cal.isDate(day, inSameDayAs: selected),
            inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
            isWeekend: cal.isDateInWeekend(day),
            hasEvents: calendar.busyDays.contains(cal.dateComponents([.year, .month, .day], from: day))
        ) {
            selected = cal.startOfDay(for: day)
            calendar.load(from: selected)
            DroppyAudio.playTick()
        }
    }

    private var weekdaySymbols: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Six weeks around the visible month, starting on the locale's first weekday.
    private var monthDays: [Date] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: month)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        guard let start = cal.date(byAdding: .day, value: -lead, to: month) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// The month layout's list: the selected day and the week after it.
    private var monthAgenda: some View {
        let sections = [Section(title: dayTitle(selected), entries: dayEntries)].filter { !$0.entries.isEmpty } + upcomingSections
        return Group {
            if sections.isEmpty {
                Text(emptyTitle)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(sections, id: \.title) { section in
                            Text(section.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NotchPalette.secondary)
                                .padding(.top, section.title == sections.first?.title ? 0 : 6)
                            ForEach(section.entries) { row($0) }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ entry: AgendaEntry) -> some View {
        if entry.kind == .reminder {
            TaskRow(entry: entry)
        } else {
            EventRow(entry: entry)
        }
    }

    // MARK: Access

    private var accessPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(NotchPalette.secondary)
                .accessibilityHidden(true)
            Text("Allow access to see your events and reminders")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            CalendarTextButton("Open System Settings", size: 11, help: "Privacy & Security › Calendars and Reminders") {
                PermissionService.shared.openSettings(.calendars)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Calendars can be allowed while Reminders is not; tasks need their own ask.
    private var remindersDeniedNote: some View {
        HStack(spacing: DS.Space.sm) {
            Text("Reminders access is off")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NotchPalette.secondary)
            CalendarTextButton("Open Settings", help: "Privacy & Security › Reminders") {
                PermissionService.shared.openSettings(.reminders)
            }
        }
    }

    // MARK: Quick add

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Group {
                    if addKind == .task {
                        Circle().strokeBorder(Color.orange, lineWidth: 2)
                    } else {
                        Capsule().fill(NotchPalette.calendarRed).frame(width: 4)
                    }
                }
                .frame(width: 16, height: 16)
                TextField(addKind == .task ? "Add a task…" : "Add an event…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .focused($draftFocused)
                    .onSubmit(add)
                    .onExitCommand(perform: cancelAdding)
                    // Focus set in the same tick as `isAdding` is dropped: the
                    // field doesn't exist yet. Ask once it has appeared.
                    .task { draftFocused = true }
                Button {
                    addKind = addKind == .task ? .event : .task
                    DroppyAudio.playTick()
                } label: {
                    Text(addKind == .task ? "Task" : "Event")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .help(addKind == .task ? "Adding a task (click for an event)" : "Adding an event (click for a task)")
                .accessibilityLabel(addKind == .task ? "Adding a task" : "Adding an event")
                .accessibilityHint(addKind == .task ? "Switches to adding an event" : "Switches to adding a task")
                if isSaving {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    NotchCircleButton("xmark", size: 20, iconSize: 8, filled: false, help: "Cancel", action: cancelAdding)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.09)))
            Text(addHint)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(addError == nil ? NotchPalette.tertiary : NotchPalette.calendarRed)
                .lineLimit(1)
                .padding(.leading, 4)
        }
    }

    /// What the text will become, or the last error.
    private var addHint: String {
        if let addError { return addError }
        if addKind == .task, calendar.isReminderAccessDenied { return "Allow Reminders access to add tasks." }
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let parsed = ReminderParser.parse(text) else {
            return addKind == .task
                ? "Try \u{201C}Call Sam tomorrow 5pm #Work !!\u{201D}"
                : "Try \u{201C}Lunch with Sam Friday 1pm\u{201D}"
        }
        var parts: [String] = []
        if let date = parsed.due?.date {
            parts.append(parsed.due?.hour == nil
                         ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                         : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
        } else if addKind == .event {
            parts.append("Needs a day or time")
        }
        if let list = parsed.listName { parts.append("#\(list)") }
        if parsed.priority != 0 { parts.append(TaskPriority(eventKit: parsed.priority).title) }
        return parts.isEmpty ? "No date · \(addKind == .task ? "Task" : "Event")" : parts.joined(separator: " · ")
    }

    private func cancelAdding() {
        isAdding = false
        draft = ""
        addError = nil
    }

    private func add() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !isSaving else { return }
        isSaving = true
        addError = nil
        let kind = addKind
        Task {
            defer { isSaving = false }
            do {
                if kind == .task {
                    try await calendar.addReminder(text)
                } else {
                    try await calendar.addEvent(text)
                }
                // Stay open for the next one, like the reference.
                draft = ""
                DroppyAudio.playDropSuccess()
            } catch {
                // Keep the draft so nothing typed is lost.
                addError = error.localizedDescription
                NSSound.beep()
            }
        }
    }
}

// MARK: - Task row

/// A task: its list-coloured ring, title, time and priority marks. Ticking it
/// strikes it through; it leaves after Settings' clean-up delay.
private struct TaskRow: View {
    let entry: AgendaEntry
    @State private var checkHovered = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var priority: TaskPriority { TaskPriority(eventKit: entry.priority) }
    private var isOverdue: Bool {
        guard let start = entry.start, !entry.isCompleted else { return false }
        return entry.isAllDay ? start < Calendar.current.startOfDay(for: Date()) : start < Date()
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                ZStack {
                    Circle().fill(entry.color.opacity(checkHovered && !entry.isCompleted ? 0.28 : 0))
                    Circle().strokeBorder(entry.color, lineWidth: 2)
                    if entry.isCompleted {
                        Circle().fill(entry.color)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 17, height: 17)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            .onHover { checkHovered = $0 }
            .padding(-4.5)
            .help(entry.isCompleted ? "Mark as not done" : "Complete")
            .accessibilityLabel(entry.isCompleted ? "Mark \(entry.title) as not done" : "Complete \(entry.title)")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(entry.isCompleted ? 0.45 : 1))
                        .strikethrough(entry.isCompleted, color: .white.opacity(0.6))
                        .lineLimit(1)
                        .help(entry.title)
                    priorityButton
                }
                if let time = timeLabel {
                    Text(time)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOverdue ? NotchPalette.calendarRed : NotchPalette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(isHovered ? 0.11 : 0.08)))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isHovered)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: entry.isCompleted)
        .contextMenu { menu }
    }

    /// "!", "!!" or "!!!"; a faint "!" on hover when there's none.
    @ViewBuilder
    private var priorityButton: some View {
        if priority != .none || isHovered {
            Button {
                CalendarService.shared.setPriority(priority.next, for: entry)
                DroppyAudio.playTick()
            } label: {
                Text(priority == .none ? "!" : priority.marks)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(priority == .none ? Color.white.opacity(0.3) : Color.orange)
                    .padding(.horizontal, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            .help("Priority: \(priority.title) (click to change)")
            .accessibilityLabel("Priority: \(priority.title)")
            .accessibilityHint("Click to change")
        }
    }

    @ViewBuilder
    private var menu: some View {
        Menu("Set priority") {
            ForEach([TaskPriority.high, .medium, .low, .none], id: \.self) { level in
                Button {
                    CalendarService.shared.setPriority(level, for: entry)
                } label: {
                    if level == priority { Label(level.title, systemImage: "checkmark") } else { Text(level.title) }
                }
            }
        }
        Button("+1 Day") { CalendarService.shared.postpone(entry, by: .day) }
        Button("+1 Week") { CalendarService.shared.postpone(entry, by: .weekOfYear) }
        if entry.start != nil {
            Button("Remove Due Date") { CalendarService.shared.removeDueDate(entry) }
        }
        Divider()
        Button("Open in Reminders") { CalendarService.shared.openInCalendar(entry) }
        Divider()
        Button("Delete Task", role: .destructive) { CalendarService.shared.delete(entry) }
    }

    private func toggle() {
        DroppyAudio.playTick()
        if entry.isCompleted {
            CalendarService.shared.uncomplete(entry)
        } else if !CalendarService.shared.complete(entry) {
            NSSound.beep()
        }
    }

    private var timeLabel: String? {
        guard let start = entry.start else { return entry.calendarTitle.isEmpty ? nil : entry.calendarTitle }
        let cal = Calendar.current
        if entry.isAllDay {
            return isOverdue ? "Overdue · \(start.formatted(.dateTime.weekday(.abbreviated).day()))" : nil
        }
        let time = start.formatted(date: .omitted, time: .shortened)
        if isOverdue && !cal.isDateInToday(start) {
            return "Overdue · \(start.formatted(.dateTime.weekday(.abbreviated).day())) \(time)"
        }
        return time
    }
}

// MARK: - Event row

/// An event: a tinted card with its calendar's colour bar, the time in that
/// colour, and a Join chip when it has a meeting link. Read-only.
private struct EventRow: View {
    let entry: AgendaEntry
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            Capsule().fill(entry.color).frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let time = timeLabel {
                    Text(time)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.color.opacity(0.95))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let url = entry.joinURL {
                Button {
                    NSWorkspace.shared.open(url)
                    DroppyAudio.playTick()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill").font(.system(size: 9, weight: .bold))
                        Text("Join").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(entry.color.opacity(0.55)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .help(Self.joinTitle(url))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(entry.color.opacity(isHovered ? 0.3 : 0.22)))
        .onHover { isHovered = $0 }
        .help("\(entry.title)\n\(entry.calendarTitle) · Read-only (Apple Calendar)")
        .onTapGesture(count: 2) { CalendarService.shared.openInCalendar(entry) }
        .contextMenu {
            Button("Open in Calendar") { CalendarService.shared.openInCalendar(entry) }
            if let url = entry.joinURL {
                Button(Self.joinTitle(url)) { NSWorkspace.shared.open(url) }
                Button("Copy Meeting Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
        .accessibilityElement(children: .combine)
        // Combining swallows the Join chip and the double-click, so offer both as actions.
        .accessibilityAction(named: "Open in Calendar") { CalendarService.shared.openInCalendar(entry) }
        .accessibilityActions {
            if let url = entry.joinURL {
                Button(Self.joinTitle(url)) { NSWorkspace.shared.open(url) }
            }
        }
    }

    static func joinTitle(_ url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("zoom") { return "Join Zoom meeting" }
        if host.contains("meet.google") { return "Join Google Meet meeting" }
        if host.contains("teams") { return "Join Teams meeting" }
        if host.contains("webex") { return "Join Webex meeting" }
        return "Open meeting link"
    }

    private var timeLabel: String? {
        guard let start = entry.start else { return nil }
        if entry.isAllDay { return "All day" }
        let startText = start.formatted(date: .omitted, time: .shortened)
        if let end = entry.end, Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(startText) – \(end.formatted(date: .omitted, time: .shortened))"
        }
        return startText
    }
}

// MARK: - Day cell

/// One day in the month grid; a soft ring on hover, the red ring when selected.
private struct DayCell: View {
    let day: String
    let spokenDate: String
    let isToday: Bool
    let isSelected: Bool
    let inMonth: Bool
    let isWeekend: Bool
    let hasEvents: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(day)
                .font(.system(size: 11, weight: isToday ? .bold : .semibold))
                .foregroundStyle(
                    isToday ? .white
                        : .white.opacity(inMonth ? (isWeekend ? 0.55 : 0.92) : (isWeekend ? 0.22 : 0.28))
                )
                .frame(width: 20, height: 20)
                .background(Circle().fill(isToday ? NotchPalette.calendarRed : Color.white.opacity(isHovered ? 0.12 : 0)))
                .overlay(
                    Circle().strokeBorder(
                        NotchPalette.calendarRed.opacity(isSelected && !isToday ? 0.85 : 0),
                        lineWidth: 1.5
                    )
                )
                .overlay(alignment: .bottom) {
                    if hasEvents && !isToday {
                        Circle().fill(Color.white.opacity(0.5)).frame(width: 3, height: 3).offset(y: 3)
                    }
                }
                .frame(height: 20)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isHovered)
        .accessibilityLabel(spokenDate)
        .accessibilityValue(hasEvents ? "Has events" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Text button

/// A calendar-red text link (or small filled pill) with hover and press feedback.
private struct CalendarTextButton: View {
    let title: String
    var size: CGFloat = 10.5
    var filled = false
    var help: String?
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, size: CGFloat = 10.5, filled: Bool = false, help: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.size = size
        self.filled = filled
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(filled ? .white : NotchPalette.calendarRed.opacity(isHovered ? 1 : 0.85))
                .underline(!filled && isHovered)
                .lineLimit(1)
                .padding(.horizontal, filled ? 8 : 0)
                .frame(height: filled ? 20 : nil)
                .background {
                    if filled {
                        Capsule().fill(NotchPalette.calendarRed.opacity(isHovered ? 0.55 : 0.35))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(DroppyPressStyle(scale: 0.95))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.hover, value: isHovered)
        .optionalHelp(help)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
