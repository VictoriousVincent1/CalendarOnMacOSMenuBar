import EventKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: CalendarModel
    @State private var showingCalendarPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showingCalendarPicker {
                CalendarPickerView(isPresented: $showingCalendarPicker)
            } else {
                MonthView()
                Divider()
                EventsSection()
                Divider()
                RemindersSection()
                Divider()
                FooterView(showingCalendarPicker: $showingCalendarPicker)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { model.refresh() }
    }
}

// MARK: - Month grid

struct MonthView: View {
    @EnvironmentObject var model: CalendarModel
    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(model.displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { model.shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Button("Today") { model.goToToday() }
                Button { model.shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 16)
                }
                ForEach(model.gridDays(), id: \.self) { day in
                    DayCell(day: day)
                }
            }
        }
    }
}

struct DayCell: View {
    @EnvironmentObject var model: CalendarModel
    let day: Date
    private let cal = Calendar.current

    var body: some View {
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: model.selectedDate)
        let inMonth = cal.isDate(day, equalTo: model.displayedMonth, toGranularity: .month)
        let hasEvents = model.daysWithEvents.contains(cal.startOfDay(for: day))

        Button { model.select(day) } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : inMonth ? Color.primary : Color.secondary.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isToday ? Color.red : Color.clear))
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: isSelected && !isToday ? 1.5 : 0))
                Circle()
                    .fill(hasEvents ? Color.secondary : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Events

struct EventsSection: View {
    @EnvironmentObject var model: CalendarModel

    private var heading: String {
        let cal = Calendar.current
        if cal.isDateInToday(model.selectedDate) { return "Today" }
        if cal.isDateInTomorrow(model.selectedDate) { return "Tomorrow" }
        return model.selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: heading, systemImage: "calendar")

            if model.calendarAccess == .denied {
                AccessPrompt(what: "Calendar", pane: "Privacy_Calendars")
            } else if model.dayEvents.isEmpty {
                Text("No events").font(.callout).foregroundStyle(.secondary)
            } else {
                CappedScrollView(maxHeight: 180) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.dayEvents, id: \.calendarItemIdentifier) { event in
                            EventRow(event: event)
                        }
                    }
                }
            }
        }
    }
}

struct EventRow: View {
    @EnvironmentObject var model: CalendarModel
    let event: EKEvent

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    var body: some View {
        let isPast = !event.isAllDay && event.endDate < model.now
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.calendar.color))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled").font(.callout.weight(.medium)).lineLimit(1)
                Text(timeText).font(.caption).foregroundStyle(.secondary)
                if let location = event.location, !location.isEmpty {
                    Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(isPast ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.openApp(bundleID: "com.apple.iCal") }
    }
}

// MARK: - Reminders

struct RemindersSection: View {
    @EnvironmentObject var model: CalendarModel
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Reminders", systemImage: "checklist")

            if model.reminderAccess == .denied {
                AccessPrompt(what: "Reminders", pane: "Privacy_Reminders")
            } else {
                if model.reminders.isEmpty {
                    Text("All done 🎉").font(.callout).foregroundStyle(.secondary)
                } else {
                    CappedScrollView(maxHeight: 180) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.reminders, id: \.calendarItemIdentifier) { reminder in
                                ReminderRow(reminder: reminder)
                            }
                        }
                    }
                }

                HStack {
                    Image(systemName: "plus.circle").foregroundStyle(.secondary)
                    TextField("New reminder for today", text: $newTitle)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            model.addReminder(title: newTitle, dueToday: true)
                            newTitle = ""
                        }
                }
                .font(.callout)
            }
        }
    }
}

struct ReminderRow: View {
    @EnvironmentObject var model: CalendarModel
    let reminder: EKReminder

    private var dueText: String? {
        guard let due = model.dueDate(of: reminder) else { return nil }
        let hasTime = reminder.dueDateComponents?.hour != nil
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(due) { day = "Today" }
        else if cal.isDateInTomorrow(due) { day = "Tomorrow" }
        else if cal.isDateInYesterday(due) { day = "Yesterday" }
        else { day = due.formatted(.dateTime.month(.abbreviated).day()) }
        return hasTime ? "\(day), \(due.formatted(date: .omitted, time: .shortened))" : day
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.complete(reminder) } label: {
                Image(systemName: "circle")
                    .foregroundStyle(Color(nsColor: reminder.calendar.color))
            }
            .buttonStyle(.plain)
            .help("Mark as completed")

            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title ?? "Untitled").font(.callout).lineLimit(2)
                if let dueText {
                    Text(dueText)
                        .font(.caption)
                        .foregroundStyle(model.isOverdue(reminder) ? Color.red : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared bits

/// A ScrollView sized to its content (up to `maxHeight`). A bare ScrollView in a menu bar
/// window has no intrinsic height and can collapse to nothing when its rows load late.
struct CappedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
        }
        .frame(height: min(max(contentHeight, 1), maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct AccessPrompt: View {
    @EnvironmentObject var model: CalendarModel
    let what: String
    let pane: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MenuCal needs access to \(what).").font(.callout)
            Button("Open Privacy Settings…") { model.openPrivacySettings(for: pane) }
                .buttonStyle(.link)
        }
    }
}

struct FooterView: View {
    @EnvironmentObject var model: CalendarModel
    @Binding var showingCalendarPicker: Bool

    var body: some View {
        HStack {
            Menu {
                Button("Choose Calendars…") { showingCalendarPicker = true }
                Divider()
                Toggle("Show next event in menu bar", isOn: $model.showNextEventInMenuBar)
                Picker("Menu Bar Shows", selection: $model.menuBarTimeStyle) {
                    ForEach(MenuBarTimeStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .disabled(!model.showNextEventInMenuBar)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }))
                Divider()
                Button("Open Calendar") { model.openApp(bundleID: "com.apple.iCal") }
                Button("Open Reminders") { model.openApp(bundleID: "com.apple.reminders") }
                Divider()
                Button("Quit MenuCal") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            Button { showingCalendarPicker = true } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderless)
            .help("Choose calendars")

            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh")
        }
    }
}

// MARK: - Calendar picker

struct CalendarPickerView: View {
    @EnvironmentObject var model: CalendarModel
    @Binding var isPresented: Bool
    @State private var entity: EKEntityType = .event

    var body: some View {
        let groups = entity == .event ? model.eventSources : model.reminderSources

        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Text("Calendars").font(.headline)
                HStack {
                    Button { isPresented = false } label: { Label("Done", systemImage: "chevron.left") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
            }

            Picker("", selection: $entity) {
                Text("Calendars").tag(EKEntityType.event)
                Text("Reminder Lists").tag(EKEntityType.reminder)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if groups.isEmpty {
                Text("No accounts found. Check that MenuCal has access in Privacy Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                CappedScrollView(maxHeight: 380) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groups) { group in
                            SourceGroupView(group: group)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Missing Google or another account? Add it in Internet Accounts and turn on Calendars\(entity == .reminder ? " / Reminders" : "").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Internet Accounts…") { model.openInternetAccounts() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}

struct SourceGroupView: View {
    @EnvironmentObject var model: CalendarModel
    let group: SourceGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: group.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.title).font(.callout.weight(.semibold)).lineLimit(1)
                    if group.kindLabel != group.title {
                        Text(group.kindLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.isVisible(group) },
                    set: { model.setVisible(group, $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("Show or hide every calendar in this account")
            }

            ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                Toggle(isOn: Binding(
                    get: { model.isVisible(calendar) },
                    set: { model.setVisible(calendar, $0) })
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(nsColor: calendar.color))
                            .frame(width: 8, height: 8)
                        Text(calendar.title).font(.callout).lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 22)
            }
        }
    }
}
