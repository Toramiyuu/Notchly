import EventKit
import SwiftUI
import Combine

/// Fetches and exposes today's calendar events via EventKit.
class CalendarManager: ObservableObject {

    static let shared = CalendarManager()

    @Published var todayEvents: [EKEvent] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var showAllDayEvents: Bool = true { didSet { fetchTodayEvents() } }
    @Published var calendarFilter: Set<String> = [] { didSet { fetchTodayEvents() } }

    private let store = EKEventStore()

    var allCalendars: [EKCalendar] { store.calendars(for: .event) }

    private init() {
        checkAuthorizationAndFetch()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: .EKEventStoreChanged,
            object: store
        )
    }

    @objc private func storeChanged() {
        DispatchQueue.main.async { self.fetchTodayEvents() }
    }

    func checkAuthorizationAndFetch() {
        let status = EKEventStore.authorizationStatus(for: .event)
        DispatchQueue.main.async { self.authorizationStatus = status }

        switch status {
        case .authorized:
            fetchTodayEvents()
        case .notDetermined:
            requestAccess()
        default:
            // .denied, .restricted, .fullAccess (macOS 14+), or unknown
            if #available(macOS 14.0, *), status == .fullAccess {
                fetchTodayEvents()
            }
        }
    }

    private func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                    if granted { self?.fetchTodayEvents() }
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                    if granted { self?.fetchTodayEvents() }
                }
            }
        }
    }

    func fetchTodayEvents() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let calendars: [EKCalendar]? = calendarFilter.isEmpty ? nil :
            store.calendars(for: .event).filter { !calendarFilter.contains($0.calendarIdentifier) }

        let predicate = store.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: calendars
        )

        let events = store.events(matching: predicate)
            .filter { event in showAllDayEvents || !event.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        DispatchQueue.main.async { self.todayEvents = events }
    }

    func openEvent(_ event: EKEvent) {
        let url = URL(string: "calshow:\(event.startDate.timeIntervalSinceReferenceDate)")!
        NSWorkspace.shared.open(url)
    }
}
