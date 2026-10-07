import AppKit
import EventKit
import ServiceManagement
import SwiftUI

enum AccessState {
    case unknown, granted, denied
}

enum MenuBarTimeStyle: String, CaseIterable, Identifiable {
    case startTime, countdown
    var id: String { rawValue }

    var label: String {
        switch self {
        case .startTime: return "Start Time (3:00 PM)"
        case .countdown: return "Time Until (in 25m)"
        }
    }
}

/// One account (iCloud, Google, Exchange, On My Mac, …) and its calendars or reminder lists.
struct SourceGroup: Identifiable {
    let id: String
    let title: String
    let kind: EKSourceType
    let calendars: [EKCalendar]

    var isGoogle: Bool {
        let t = title.lowercased()
        return t.contains("google") || t.contains("gmail")
    }

    var kindLabel: String {
        if isGoogle { return "Google" }
        switch kind {
        case .local: return "On My Mac"
        case .exchange: return "Exchange"
        case .calDAV: return title.lowercased().contains("icloud") ? "iCloud" : "CalDAV"
        case .mobileMe: return "iCloud"
        case .subscribed: return "Subscribed"
        case .birthdays: return "Birthdays"
        @unknown default: return "Other"
        }
    }

    var systemImage: String {
        if isGoogle { return "globe" }
        switch kind {
        case .local: return "desktopcomputer"
        case .exchange: return "building.2"
        case .calDAV, .mobileMe: return title.lowercased().contains("icloud") ? "icloud" : "globe"
        case .subscribed: return "antenna.radiowaves.left.and.right"
        case .birthdays: return "gift"
        @unknown default: return "calendar"
        }
    }
}

@MainActor
final class CalendarModel: ObservableObject {
    let store = EKEventStore()
    private let cal = Calendar.current

    @Published var calendarAccess: AccessState = .unknown
    @Published var reminderAccess: AccessState = .unknown

    @Published var displayedMonth = Date()
    @Published var selectedDate = Date()
    @Published var now = Date()

    @Published var dayEvents: [EKEvent] = []
    @Published var upcomingEvents: [EKEvent] = []
    @Published var daysWithEvents: Set<Date> = []
    @Published var reminders: [EKReminder] = []

    @Published var eventSources: [SourceGroup] = []
    @Published var reminderSources: [SourceGroup] = []

    /// Stored as hidden (not visible) so newly added calendars show up by default.
    @Published var hiddenCalendarIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: "hiddenCalendarIDs") }
    }

    @Published var showNextEventInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showNextEventInMenuBar, forKey: "showNextEventInMenuBar") }
    }

    @Published var menuBarTimeStyle: MenuBarTimeStyle {
        didSet { UserDefaults.standard.set(menuBarTimeStyle.rawValue, forKey: "menuBarTimeStyle") }
    }

    /// While an event is in progress, switch the menu bar to the next event this many
    /// minutes before it starts. 0 = keep showing the current event until it ends.
    @Published var switchToNextMinutes: Int {
        didSet { UserDefaults.standard.set(switchToNextMinutes, forKey: "switchToNextMinutes") }
    }

    private var timer: Timer?
    private var syncTimer: Timer?

    init() {
        showNextEventInMenuBar = UserDefaults.standard.object(forKey: "showNextEventInMenuBar") as? Bool ?? true
        menuBarTimeStyle = UserDefaults.standard.string(forKey: "menuBarTimeStyle")
            .flatMap(MenuBarTimeStyle.init(rawValue:)) ?? .startTime
        switchToNextMinutes = UserDefaults.standard.integer(forKey: "switchToNextMinutes")
        hiddenCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendarIDs") ?? [])

        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadAll() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.goToToday() }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.loadUpcoming()
            }
        }

        // Nudge remote accounts (Google, Exchange, …) to sync more often than macOS's own schedule.
        syncTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.refreshSourcesIfNecessary() }
        }

        Task { await requestAccess() }
    }

    // MARK: - Access

    func requestAccess() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            calendarAccess = .granted
        case .notDetermined:
            let ok = (try? await store.requestFullAccessToEvents()) ?? false
            calendarAccess = ok ? .granted : .denied
        default:
            calendarAccess = .denied
        }

        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            reminderAccess = .granted
        case .notDetermined:
            let ok = (try? await store.requestFullAccessToReminders()) ?? false
            reminderAccess = ok ? .granted : .denied
        default:
            reminderAccess = .denied
        }

        reloadAll()
    }

    func openPrivacySettings(for pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Loading

    /// Shows what's cached now, and asks accounts to sync. Anything new arrives
    /// via .EKEventStoreChanged, which calls reloadAll() again.
    func refresh() {
        store.refreshSourcesIfNecessary()
        reloadAll()
    }

    func reloadAll() {
        now = Date()
        loadSources()
        loadDayEvents()
        loadMonthDots()
        loadUpcoming()
        loadReminders()
    }

    // MARK: - Calendar selection

    private func loadSources() {
        eventSources = calendarAccess == .granted ? groups(for: .event) : []
        reminderSources = reminderAccess == .granted ? groups(for: .reminder) : []
    }

    private func groups(for type: EKEntityType) -> [SourceGroup] {
        Dictionary(grouping: store.calendars(for: type), by: { $0.source?.sourceIdentifier ?? "" })
            .compactMap { id, calendars in
                let source = calendars.first?.source
                return SourceGroup(
                    id: id,
                    title: source?.title ?? "Other",
                    kind: source?.sourceType ?? .local,
                    calendars: calendars.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    })
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func visibleCalendars(for type: EKEntityType) -> [EKCalendar] {
        store.calendars(for: type).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
    }

    func isVisible(_ calendar: EKCalendar) -> Bool {
        !hiddenCalendarIDs.contains(calendar.calendarIdentifier)
    }

    func setVisible(_ calendar: EKCalendar, _ visible: Bool) {
        if visible { hiddenCalendarIDs.remove(calendar.calendarIdentifier) }
        else { hiddenCalendarIDs.insert(calendar.calendarIdentifier) }
        reloadAll()
    }

    func isVisible(_ group: SourceGroup) -> Bool {
        group.calendars.contains(where: isVisible)
    }

    func setVisible(_ group: SourceGroup, _ visible: Bool) {
        let ids = group.calendars.map(\.calendarIdentifier)
        if visible { hiddenCalendarIDs.subtract(ids) }
        else { hiddenCalendarIDs.formUnion(ids) }
        reloadAll()
    }

    func openInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Events

    private func loadDayEvents() {
        let calendars = visibleCalendars(for: .event)
        guard calendarAccess == .granted, !calendars.isEmpty else { dayEvents = []; return }
        let start = cal.startOfDay(for: selectedDate)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        dayEvents = store.events(matching: predicate).sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.startDate < $1.startDate
        }
    }

    private func loadMonthDots() {
        let calendars = visibleCalendars(for: .event)
        guard calendarAccess == .granted, !calendars.isEmpty else { daysWithEvents = []; return }
        let days = gridDays()
        guard let first = days.first, let last = days.last else { return }
        let end = cal.date(byAdding: .day, value: 1, to: last)!
        let predicate = store.predicateForEvents(withStart: first, end: end, calendars: calendars)

        var result = Set<Date>()
        for event in store.events(matching: predicate) {
            var day = cal.startOfDay(for: max(event.startDate, first))
            let eventEnd = min(event.endDate, end)
            repeat {
                result.insert(day)
                day = cal.date(byAdding: .day, value: 1, to: day)!
            } while day < eventEnd
        }
        daysWithEvents = result
    }

    private func loadUpcoming() {
        let calendars = visibleCalendars(for: .event)
        guard calendarAccess == .granted, !calendars.isEmpty else { upcomingEvents = []; return }
        let end = cal.date(byAdding: .day, value: 7, to: now)!
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        upcomingEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
    }

    private func loadReminders() {
        let lists = visibleCalendars(for: .reminder)
        guard reminderAccess == .granted, !lists.isEmpty else { reminders = []; return }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: lists)
        store.fetchReminders(matching: predicate) { [weak self] result in
            let items = result ?? []
            Task { @MainActor in
                guard let self else { return }
                self.reminders = items.sorted { a, b in
                    switch (self.dueDate(of: a), self.dueDate(of: b)) {
                    case let (x?, y?): return x < y
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return a.title < b.title
                    }
                }
            }
        }
    }

    // MARK: - Reminder actions

    func dueDate(of reminder: EKReminder) -> Date? {
        reminder.dueDateComponents.flatMap { cal.date(from: $0) }
    }

    func isOverdue(_ reminder: EKReminder) -> Bool {
        guard let due = dueDate(of: reminder) else { return false }
        let hasTime = reminder.dueDateComponents?.hour != nil
        return hasTime ? due < now : due < cal.startOfDay(for: now)
    }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        withAnimation { reminders.removeAll { $0 === reminder } }
    }

    func addReminder(title: String, dueToday: Bool) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        // Prefer the default list, but not if the user has hidden it (the new reminder would vanish).
        let defaultList = store.defaultCalendarForNewReminders()
        let list = defaultList.flatMap { isVisible($0) ? $0 : nil }
            ?? visibleCalendars(for: .reminder).first { $0.allowsContentModifications }
            ?? defaultList
        guard !trimmed.isEmpty, let list else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = list
        if dueToday {
            reminder.dueDateComponents = cal.dateComponents([.year, .month, .day], from: now)
        }
        try? store.save(reminder, commit: true)
        loadReminders()
    }

    // MARK: - Month navigation

    func gridDays() -> [Date] {
        let monthStart = cal.dateInterval(of: .month, for: displayedMonth)!.start
        let weekday = cal.component(.weekday, from: monthStart)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -offset, to: monthStart)!
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: gridStart)! }
    }

    func shiftMonth(_ delta: Int) {
        displayedMonth = cal.date(byAdding: .month, value: delta, to: displayedMonth)!
        loadMonthDots()
    }

    func select(_ date: Date) {
        selectedDate = date
        if !cal.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = date
            loadMonthDots()
        }
        loadDayEvents()
    }

    func goToToday() {
        now = Date()
        displayedMonth = now
        selectedDate = now
        reloadAll()
    }

    // MARK: - Menu bar title

    var menuBarTitle: String {
        guard showNextEventInMenuBar else {
            return now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        guard let next = menuBarEvent else { return "" }

        let title = next.title.map { $0.count > 24 ? String($0.prefix(23)) + "…" : $0 } ?? "Event"

        if menuBarTimeStyle == .countdown {
            if next.startDate <= now { return "Now · \(title)" }
            return "\(countdown(to: next.startDate)) \(title)"
        }

        let time = next.startDate.formatted(date: .omitted, time: .shortened)
        let day: String
        if next.startDate <= now || cal.isDateInToday(next.startDate) { day = "" }
        else if cal.isDateInTomorrow(next.startDate) { day = "Tomorrow " }
        else { day = next.startDate.formatted(.dateTime.weekday(.abbreviated)) + " " }
        return "\(day)\(time) \(title)"
    }

    /// The event shown in the menu bar: normally the current (or else next) event, but
    /// the next one takes over `switchToNextMinutes` before it starts.
    private var menuBarEvent: EKEvent? {
        guard let first = upcomingEvents.first else { return nil }
        guard switchToNextMinutes > 0, first.startDate <= now,
              let next = upcomingEvents.first(where: { $0.startDate > now })
        else { return first }
        let lead = TimeInterval(switchToNextMinutes * 60)
        return next.startDate.timeIntervalSince(now) <= lead ? next : first
    }

    /// "in 25m", "in 2h 15m", "in 1d 3h"
    private func countdown(to date: Date) -> String {
        let mins = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if mins < 60 { return "in \(mins)m" }
        if mins < 24 * 60 {
            let (h, m) = (mins / 60, mins % 60)
            return m == 0 ? "in \(h)h" : "in \(h)h \(m)m"
        }
        let (d, h) = (mins / (24 * 60), (mins % (24 * 60)) / 60)
        return h == 0 ? "in \(d)d" : "in \(d)d \(h)h"
    }

    // MARK: - Misc

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("MenuCal: launch at login change failed: \(error)")
            }
            objectWillChange.send()
        }
    }

    func openApp(bundleID: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
