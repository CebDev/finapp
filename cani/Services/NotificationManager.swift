//
//  NotificationManager.swift
//  cani
//

import Foundation
import UserNotifications

// MARK: - NotificationManager

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func permissionStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Scheduling

    func scheduleNotifications(for subscription: Subscription) async {
        let status = await permissionStatus()
        switch status {
        case .denied:
            return
        case .notDetermined:
            guard await requestPermission() else { return }
        default:
            break
        }

        guard let reminderDays = subscription.reminderDaysBefore, reminderDays > 0 else { return }
        guard subscription.isActive else { return }

        await cancelNotifications(for: subscription)

        let center = UNUserNotificationCenter.current()
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "fr_CA")

        guard let horizon = cal.date(byAdding: .month, value: 13, to: now) else { return }

        let startComps = cal.dateComponents([.year, .month], from: now)
        var year = startComps.year ?? 2025
        var month = startComps.month ?? 1

        while let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              monthStart <= horizon {
            for occurrence in subscription.occurrences(inYear: year, month: month) {
                guard let notifDay = cal.date(byAdding: .day, value: -reminderDays, to: occurrence) else { continue }

                var triggerComps = cal.dateComponents([.year, .month, .day], from: notifDay)
                triggerComps.hour = 9
                triggerComps.minute = 0
                triggerComps.second = 0

                guard
                    let fireDate = cal.date(from: triggerComps),
                    fireDate > now,
                    fireDate <= horizon
                else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Renouvellement à venir — \(subscription.name)"
                content.body = "\(CurrencyFormatter.shared.format(subscription.amount)) sera prélevé \(Self.dayLabel(reminderDays)), le \(Self.formatDate(occurrence))."
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                let identifier = "finapp.sub.\(subscription.id.uuidString).\(Int(fireDate.timeIntervalSince1970))"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                try? await center.add(request)
            }

            month += 1
            if month > 12 { month = 1; year += 1 }
        }
    }

    func cancelNotifications(for subscription: Subscription) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let prefix = "finapp.sub.\(subscription.id.uuidString)"
        let ids = pending.compactMap { $0.identifier.hasPrefix(prefix) ? $0.identifier : nil }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func rescheduleAll(subscriptions: [Subscription]) async {
        for subscription in subscriptions {
            await scheduleNotifications(for: subscription)
        }
    }

    // MARK: - Private helpers

    static func dayLabel(_ days: Int) -> String {
        switch days {
        case 1:  return "demain"
        case 3:  return "dans 3 jours"
        case 7:  return "dans 1 semaine"
        case 30: return "dans 1 mois"
        default: return "dans \(days) jours"
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.setLocalizedDateFormatFromTemplate("dMMMM")
        return fmt.string(from: date)
    }
}
