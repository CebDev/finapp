//
//  Subscription.swift
//  cani
//

import Foundation
import SwiftData

// MARK: - SubscriptionFrequency

enum SubscriptionFrequency: String, Codable, CaseIterable {
    case weekly, biweekly, monthly, quarterly, annual

    var localizedLabel: String {
        switch self {
        case .weekly:    return "Hebdomadaire"
        case .biweekly:  return "Aux 2 semaines"
        case .monthly:   return "Mensuel"
        case .quarterly: return "Trimestriel"
        case .annual:    return "Annuel"
        }
    }

    var shortLabel: String {
        switch self {
        case .weekly:    return "/sem"
        case .biweekly:  return "/2 sem"
        case .monthly:   return "/mois"
        case .quarterly: return "/trim"
        case .annual:    return "/an"
        }
    }
}

// MARK: - Subscription

@Model
final class Subscription {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Decimal = Decimal(0)
    /// Raw backing — évite le crash SwiftData avec les enums Codable non-optionnels.
    var frequencyRaw: String = SubscriptionFrequency.monthly.rawValue
    @Transient var frequency: SubscriptionFrequency {
        get { SubscriptionFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }
    var startDate: Date = Date()
    var endDate: Date? = nil
    var dayOfMonth: Int = 1
    var dayOfWeek: Int? = nil
    var renewalMonth: Int? = nil
    var category: String = ""
    var colorHex: String = "#6366F1"
    var iconInitials: String = ""
    var notes: String? = nil
    var reminderDaysBefore: Int? = nil
    var isActive: Bool = true
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        amount: Decimal,
        frequency: SubscriptionFrequency,
        startDate: Date = Date(),
        endDate: Date? = nil,
        dayOfMonth: Int = 1,
        dayOfWeek: Int? = nil,
        renewalMonth: Int? = nil,
        category: String = "",
        colorHex: String = "#6366F1",
        iconInitials: String = "",
        notes: String? = nil,
        reminderDaysBefore: Int? = nil,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.dayOfMonth = dayOfMonth
        self.dayOfWeek = dayOfWeek
        self.renewalMonth = renewalMonth
        self.category = category
        self.colorHex = colorHex
        self.iconInitials = iconInitials.isEmpty ? String(name.prefix(2)).uppercased() : iconInitials
        self.notes = notes
        self.reminderDaysBefore = reminderDaysBefore
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

// MARK: - Calendar Logic

extension Subscription {

    private static func frCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "fr_CA")
        return cal
    }

    /// Toutes les dates de paiement dans un mois donné.
    func occurrences(inYear year: Int, month: Int) -> [Date] {
        let cal = Self.frCalendar()

        guard
            let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1)),
            let dayRange = cal.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        let lastDay = dayRange.count

        var endComps = DateComponents(year: year, month: month, day: lastDay)
        endComps.hour = 23; endComps.minute = 59; endComps.second = 59
        guard let monthEnd = cal.date(from: endComps) else { return [] }

        // L'abonnement doit chevaucher ce mois
        if startDate > monthEnd { return [] }
        if let e = endDate, e < monthStart { return [] }

        func isActiveOn(_ date: Date) -> Bool {
            date >= startDate && (endDate == nil || date <= endDate!)
        }

        switch frequency {

        case .monthly:
            let day = min(dayOfMonth, lastDay)
            guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)),
                  isActiveOn(date) else { return [] }
            return [date]

        case .quarterly:
            let sc = cal.dateComponents([.year, .month], from: startDate)
            let sy = sc.year ?? year, sm = sc.month ?? month
            let totalMonths = (year - sy) * 12 + (month - sm)
            guard totalMonths >= 0, totalMonths % 3 == 0 else { return [] }
            let day = min(dayOfMonth, lastDay)
            guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)),
                  isActiveOn(date) else { return [] }
            return [date]

        case .annual:
            let sc = cal.dateComponents([.month, .day], from: startDate)
            let targetMonth: Int
            let targetDay: Int
            if let rm = renewalMonth {
                targetMonth = rm
                targetDay = dayOfMonth
            } else {
                targetMonth = sc.month ?? month
                targetDay = sc.day ?? dayOfMonth
            }
            guard month == targetMonth else { return [] }
            let day = min(targetDay, lastDay)
            guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)),
                  isActiveOn(date) else { return [] }
            return [date]

        case .weekly:
            guard let dow = dayOfWeek else { return [] }
            var results: [Date] = []
            for d in 1...lastDay {
                guard let date = cal.date(from: DateComponents(year: year, month: month, day: d)) else { continue }
                if cal.component(.weekday, from: date) == dow, isActiveOn(date) {
                    results.append(date)
                }
            }
            return results

        case .biweekly:
            guard let dow = dayOfWeek else { return [] }
            // Ancrer sur le premier jour >= startDate correspondant au dayOfWeek voulu
            let startWD = cal.component(.weekday, from: startDate)
            let daysToAnchor = (dow - startWD + 7) % 7
            guard let anchor = cal.date(byAdding: .day, value: daysToAnchor, to: startDate) else { return [] }

            var results: [Date] = []
            for d in 1...lastDay {
                guard let date = cal.date(from: DateComponents(year: year, month: month, day: d)) else { continue }
                guard cal.component(.weekday, from: date) == dow else { continue }
                guard isActiveOn(date) else { continue }
                let diff = cal.dateComponents([.day], from: anchor, to: date).day ?? -1
                if diff >= 0, diff % 14 == 0 {
                    results.append(date)
                }
            }
            return results
        }
    }

    /// Prochaine occurrence après une date de référence.
    func nextOccurrence(after referenceDate: Date) -> Date? {
        let cal = Self.frCalendar()
        let comps = cal.dateComponents([.year, .month], from: referenceDate)
        var year = comps.year ?? 2025
        var month = comps.month ?? 1

        for _ in 0..<15 {
            for date in occurrences(inYear: year, month: month) {
                if date > referenceDate { return date }
            }
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return nil
    }

    /// Coût ramené en équivalent mensuel.
    var normalizedMonthlyCost: Decimal {
        switch frequency {
        case .weekly:    return amount * 52 / 12
        case .biweekly:  return amount * 26 / 12
        case .monthly:   return amount
        case .quarterly: return amount / 3
        case .annual:    return amount / 12
        }
    }
}
