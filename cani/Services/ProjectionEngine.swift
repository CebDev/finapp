//
//  ProjectionEngine.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import Foundation

// MARK: - Type de sortie

struct ProjectionMonth {
    /// Premier jour du mois (minuit, heure locale)
    let month: Date
    let projectedBalance: Decimal
    /// Transactions récurrentes ayant au moins une occurrence ce mois-ci
    let transactions: [RecurringTransaction]
    /// Vrai si le solde projeté est en dessous du seuil (défaut : 500 $ CAD)
    let isTight: Bool
}

// MARK: - Moteur de projection

struct ProjectionEngine {

    static let defaultTightThreshold: Decimal = 500

    // MARK: - API publique

    /// Calcule la projection mensuelle sur `months` mois à partir du mois de `referenceDate`.
    /// Pas de dépendance au ModelContext — les collections sont passées en paramètre pour faciliter les tests.
    static func project(
        accounts: [Account],
        recurringTransactions: [RecurringTransaction],
        months: Int = 12,
        referenceDate: Date = Date(),
        tightThreshold: Decimal = defaultTightThreshold
    ) -> [ProjectionMonth] {
        let calendar = Calendar.current

        let startingBalance = accounts
            .filter(\.includeInBudget)
            .reduce(Decimal(0)) { $0 + $1.effectiveBalance }

        guard let firstMonthStart = firstDayOfMonth(for: referenceDate, calendar: calendar) else {
            return []
        }

        var result: [ProjectionMonth] = []
        var runningBalance = startingBalance

        for offset in 0..<months {
            guard
                let monthStart = calendar.date(byAdding: .month, value: offset, to: firstMonthStart),
                let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else { continue }

            var activeTransactions: [RecurringTransaction] = []
            var monthlyDelta = Decimal(0)

            for tx in recurringTransactions {
                let txOccurrences = occurrences(of: tx, from: monthStart, to: nextMonthStart, calendar: calendar)
                if !txOccurrences.isEmpty {
                    activeTransactions.append(tx)
                    monthlyDelta += tx.amount * Decimal(txOccurrences.count)
                }
            }

            runningBalance += monthlyDelta

            result.append(ProjectionMonth(
                month: monthStart,
                projectedBalance: runningBalance,
                transactions: activeTransactions,
                isTight: runningBalance < tightThreshold
            ))
        }

        return result
    }

    // MARK: - Génération d'occurrences (interne, exposé pour les tests)

    /// Retourne toutes les dates d'occurrence de `transaction` dans la plage `[from, to)`.
    static func occurrences(
        of transaction: RecurringTransaction,
        from monthStart: Date,
        to nextMonthStart: Date,
        calendar: Calendar = Calendar.current
    ) -> [Date] {
        let txStart = startOfDay(transaction.startDate, calendar: calendar)

        // Transaction pas encore commencée ou déjà terminée avant ce mois
        guard txStart < nextMonthStart else { return [] }
        if let end = transaction.endDate, startOfDay(end, calendar: calendar) < monthStart { return [] }

        switch transaction.frequency {
        case .oneTime:
            // Une seule occurrence à la date de départ
            return txStart >= monthStart && txStart < nextMonthStart ? [txStart] : []

        case .weekly:
            return stepDayOccurrences(
                anchor: txStart, stepDays: 7,
                from: monthStart, to: nextMonthStart, calendar: calendar
            )

        case .biweekly:
            let dates = stepDayOccurrences(
                anchor: txStart, stepDays: 14,
                from: monthStart, to: nextMonthStart, calendar: calendar
            )
            guard let targetWeekday = transaction.dayOfWeek else { return dates }
            // Filtre de sécurité — Calendar.weekday : 1=dimanche … 7=samedi → 0-indexé : 0=dimanche
            return dates.filter { calendar.component(.weekday, from: $0) - 1 == targetWeekday }

        case .semimonthly:
            return semimonthlyOccurrences(
                from: monthStart, to: nextMonthStart,
                txStart: txStart, txEnd: transaction.endDate, calendar: calendar
            )

        case .monthly:
            return monthlyOccurrences(
                transaction: transaction, txStart: txStart,
                from: monthStart, to: nextMonthStart, calendar: calendar
            )

        case .quarterly:
            return stepMonthOccurrences(
                anchor: txStart, stepMonths: 3,
                from: monthStart, to: nextMonthStart, calendar: calendar
            )

        case .annual:
            return stepMonthOccurrences(
                anchor: txStart, stepMonths: 12,
                from: monthStart, to: nextMonthStart, calendar: calendar
            )
        }
    }

    // MARK: - Helpers privés

    private static func firstDayOfMonth(for date: Date, calendar: Calendar) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }

    private static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Génère les dates de la suite `anchor + n × stepDays` dans `[from, to)`.
    /// Utilise l'arithmétique entière uniquement — aucun Double.
    private static func stepDayOccurrences(
        anchor: Date,
        stepDays: Int,
        from monthStart: Date,
        to nextMonthStart: Date,
        calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []

        // Nombre de jours calendaires entre anchor et le début du mois
        let rawDelta = calendar.dateComponents([.day], from: anchor, to: monthStart).day ?? 0

        // Premier n ≥ 0 tel que anchor + n×step ≥ monthStart
        let firstN: Int
        if rawDelta <= 0 {
            firstN = 0
        } else {
            // Plafond entier : ceil(rawDelta / stepDays)
            firstN = (rawDelta + stepDays - 1) / stepDays
        }

        var n = firstN
        while true {
            guard let date = calendar.date(byAdding: .day, value: n * stepDays, to: anchor) else { break }
            if date >= nextMonthStart { break }
            if date >= monthStart { dates.append(date) }
            n += 1
        }

        return dates
    }

    /// Génère les dates de la suite `anchor + n × stepMonths` dans `[from, to)`.
    /// Utilisé pour quarterly (3 mois) et annual (12 mois).
    private static func stepMonthOccurrences(
        anchor: Date,
        stepMonths: Int,
        from monthStart: Date,
        to nextMonthStart: Date,
        calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []

        let rawDelta = calendar.dateComponents([.month], from: anchor, to: monthStart).month ?? 0

        let firstN: Int
        if rawDelta <= 0 {
            firstN = 0
        } else {
            firstN = (rawDelta + stepMonths - 1) / stepMonths
        }

        var n = firstN
        while true {
            guard let date = calendar.date(byAdding: .month, value: n * stepMonths, to: anchor) else { break }
            if date >= nextMonthStart { break }
            if date >= monthStart { dates.append(date) }
            n += 1
        }

        return dates
    }

    /// Génère les occurrences semi-mensuelles (1er et 15 du mois) dans `[from, to)`.
    private static func semimonthlyOccurrences(
        from monthStart: Date,
        to nextMonthStart: Date,
        txStart: Date,
        txEnd: Date?,
        calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []
        let comps = calendar.dateComponents([.year, .month], from: monthStart)

        for day in [1, 15] {
            var dc = DateComponents()
            dc.year = comps.year
            dc.month = comps.month
            dc.day = day
            guard let date = calendar.date(from: dc) else { continue }
            guard date >= monthStart, date < nextMonthStart else { continue }
            guard date >= txStart else { continue }
            if let end = txEnd, startOfDay(end, calendar: calendar) < date { continue }
            dates.append(date)
        }

        return dates
    }

    /// Génère l'occurrence mensuelle dans `[from, to)` en respectant `dayOfMonth`.
    /// Si le jour n'existe pas dans le mois (ex: 31 en février), aucune occurrence n'est retournée.
    private static func monthlyOccurrences(
        transaction: RecurringTransaction,
        txStart: Date,
        from monthStart: Date,
        to nextMonthStart: Date,
        calendar: Calendar
    ) -> [Date] {
        let targetDay = transaction.dayOfMonth ?? calendar.component(.day, from: txStart)
        let comps = calendar.dateComponents([.year, .month], from: monthStart)

        var dc = DateComponents()
        dc.year = comps.year
        dc.month = comps.month
        dc.day = targetDay

        guard let date = calendar.date(from: dc) else { return [] }
        // Vérifie que la date n'a pas débordé dans un autre mois (ex: 31 → mois suivant)
        guard date >= monthStart, date < nextMonthStart else { return [] }
        guard date >= txStart else { return [] }
        if let end = transaction.endDate, startOfDay(end, calendar: calendar) < date { return [] }

        return [date]
    }
}
