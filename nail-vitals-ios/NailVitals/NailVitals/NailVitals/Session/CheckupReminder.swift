//
//  CheckupReminder.swift
//  NailVitals
//
//  The optional reminder for the next check-up: one local notification,
//  set only when the person taps the button on a report card (that tap is
//  also when iOS asks for notification permission). A prompt at the right
//  moment is what turns "check again in a few weeks" into a habit. When
//  it fires is ReminderPlan's job. Nothing is sent anywhere: the reminder
//  lives on this phone.
//

import Combine
import Foundation
import UserNotifications

final class CheckupReminder: ObservableObject {
    static let shared = CheckupReminder()
    static let identifier = "next-checkup"

    /// When the pending reminder fires; nil when there isn't one.
    @Published private(set) var scheduledDate: Date?
    /// The person was asked and said no (or turned notifications off).
    @Published private(set) var permissionDenied = false

    private var center: UNUserNotificationCenter { .current() }

    init() {
        Task { await refresh() }
    }

    /// Reads the pending reminder back from the system.
    func refresh() async {
        let pending = await center.pendingNotificationRequests()
        scheduledDate = pending.first { $0.identifier == Self.identifier }
            .flatMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
    }

    /// Asks for permission if needed, then replaces any pending reminder
    /// with one `days` days from now.
    func schedule(days: Int) {
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                permissionDenied = true
                return
            }
            permissionDenied = false
            let fire = ReminderPlan.fireDate(from: Date(), days: days)
            let content = UNMutableNotificationContent()
            content.title = "Time for your nail check-up"
            content.body = "It takes about a minute. Checking every few weeks builds your trend."
            content.sound = .default
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: Self.identifier, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            do {
                try await center.add(request)
                scheduledDate = fire
            } catch {
                scheduledDate = nil
            }
        }
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        scheduledDate = nil
    }
}
