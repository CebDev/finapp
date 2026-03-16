//
//  RecurringTransactionService.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-15.
//

import Foundation
import SwiftData

// MARK: - RecurringTransactionService

/// Service responsable de la génération et de la maintenance des occurrences
/// de transactions récurrentes.
///
/// Règles fondamentales :
/// - À la création d'un RecurringTransaction → générer toutes les occurrences
///   dans [startDate, startDate + 12 mois]
/// - Quand une Transaction passe à isPaid = true → générer la prochaine occurrence
///   hors fenêtre si applicable
/// - Quand une Transaction est supprimée → même logique
/// - Modification "cette occurrence et les suivantes" → mettre à jour le
///   RecurringTransaction + toutes les Transaction futures isPaid == false
struct RecurringTransactionService {

    // MARK: - Fenêtre de génération

    /// 12 mois calendaires à partir de startDate
    private static let generationWindowMonths = 12

    // MARK: - API publique

    /// Génère toutes les occurrences d'un nouveau RecurringTransaction
    /// dans la fenêtre [startDate, startDate + 12 mois].
    /// À appeler immédiatement après l'insertion du RecurringTransaction dans le contexte.
    static func generateOccurrences(
        for recurring: RecurringTransaction,
        context: ModelContext,
        calendar: Calendar = .current
    ) {
        guard recurring.isActive else { return }

        let windowEnd = calendar.date(
            byAdding: .month,
            value: generationWindowMonths,
            to: recurring.startDate
        ) ?? recurring.startDate

        let dates = occurrenceDates(
            for: recurring,
            from: recurring.startDate,
            to: windowEnd,
            calendar: calendar
        )

        for date in dates {
            let tx = makeTransaction(for: recurring, on: date)
            context.insert(tx)
        }
    }

    /// À appeler quand une Transaction liée à un RecurringTransaction passe
    /// à isPaid = true ou est supprimée.
    /// Génère la prochaine occurrence hors fenêtre si les conditions le permettent.
    static func generateNextOccurrenceIfNeeded(
        for recurring: RecurringTransaction,
        existingTransactions: [Transaction],
        context: ModelContext,
        calendar: Calendar = .current
    ) {
        guard recurring.isActive else { return }

        // Vérifier la limite countOfOccurrences
        if let maxCount = recurring.countOfOccurrences {
            let totalGenerated = existingTransactions
                .filter { $0.recurringTransactionId == recurring.id }
                .count
            // On compte toutes les transactions générées (payées + futures)
            // Si on a déjà atteint le max, ne pas en générer une nouvelle
            if totalGenerated >= maxCount { return }
        }

        // Trouver la dernière occurrence future non payée
        let futureTxDates = existingTransactions
            .filter {
                $0.recurringTransactionId == recurring.id &&
                !$0.isPaid
            }
            .map(\.date)
            .sorted()

        // La prochaine occurrence à générer est après la dernière future connue,
        // ou après startDate + 12 mois si aucune future n'existe
        let referenceDate: Date
        if let lastFuture = futureTxDates.last {
            referenceDate = lastFuture
        } else {
            referenceDate = calendar.date(
                byAdding: .month,
                value: generationWindowMonths,
                to: recurring.startDate
            ) ?? recurring.startDate
        }

        // Calculer la prochaine occurrence après referenceDate
        guard let nextDate = nextOccurrenceDate(
            for: recurring,
            after: referenceDate,
            calendar: calendar
        ) else { return }

        // Vérifier endDate
        if let endDate = recurring.endDate,
           nextDate > endDate { return }

        // Vérifier countOfOccurrences une dernière fois avec le total actuel
        if let maxCount = recurring.countOfOccurrences {
            let currentCount = existingTransactions
                .filter { $0.recurringTransactionId == recurring.id }
                .count
            if currentCount >= maxCount { return }
        }

        let tx = makeTransaction(for: recurring, on: nextDate)
        context.insert(tx)
    }

    /// Met à jour toutes les Transaction futures non payées d'un RecurringTransaction.
    /// À appeler lors d'une modification "cette occurrence et les suivantes".
    static func updateFutureOccurrences(
        for recurring: RecurringTransaction,
        from referenceDate: Date,
        existingTransactions: [Transaction],
        context: ModelContext,
        calendar: Calendar = .current
    ) {
        // Supprimer toutes les transactions futures non payées à partir de referenceDate
        let toDelete = existingTransactions.filter {
            $0.recurringTransactionId == recurring.id &&
            !$0.isPaid &&
            $0.date >= calendar.startOfDay(for: referenceDate)
        }
        toDelete.forEach { context.delete($0) }

        // Régénérer depuis referenceDate jusqu'à startDate + 12 mois
        let windowEnd = calendar.date(
            byAdding: .month,
            value: generationWindowMonths,
            to: recurring.startDate
        ) ?? recurring.startDate

        // S'assurer que windowEnd est au moins 12 mois dans le futur
        let futureWindowEnd = max(
            windowEnd,
            calendar.date(byAdding: .month, value: generationWindowMonths, to: Date()) ?? windowEnd
        )

        let dates = occurrenceDates(
            for: recurring,
            from: referenceDate,
            to: futureWindowEnd,
            calendar: calendar
        )

        for date in dates {
            let tx = makeTransaction(for: recurring, on: date)
            context.insert(tx)
        }
    }

    /// Supprime toutes les Transaction futures non payées d'un RecurringTransaction.
    /// À appeler lors de la suppression du RecurringTransaction.
    static func deleteFutureOccurrences(
        for recurringId: UUID,
        existingTransactions: [Transaction],
        context: ModelContext
    ) {
        existingTransactions
            .filter { $0.recurringTransactionId == recurringId && !$0.isPaid }
            .forEach { context.delete($0) }
    }

    // MARK: - Calcul des dates d'occurrence

    /// Retourne toutes les dates d'occurrence dans [from, to).
    static func occurrenceDates(
        for recurring: RecurringTransaction,
        from startDate: Date,
        to endDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let anchor    = calendar.startOfDay(for: recurring.startDate)
        let fromDay   = calendar.startOfDay(for: startDate)
        let toDay     = calendar.startOfDay(for: endDate)
        let effectiveEnd = recurring.endDate.map { calendar.startOfDay(for: $0) }

        var dates: [Date] = []

        switch recurring.frequency {

        case .oneTime:
            if anchor >= fromDay && anchor < toDay {
                if let end = effectiveEnd, anchor > end { return [] }
                dates.append(anchor)
            }

        case .weekly:
            dates = stepDayDates(
                anchor: anchor, step: 7,
                from: fromDay, to: toDay,
                endDate: effectiveEnd, calendar: calendar
            )

        case .biweekly:
            dates = stepDayDates(
                anchor: anchor, step: 14,
                from: fromDay, to: toDay,
                endDate: effectiveEnd, calendar: calendar
            )

        case .semimonthly:
            dates = semimonthlyDates(
                anchor: anchor, from: fromDay, to: toDay,
                endDate: effectiveEnd, calendar: calendar
            )

        case .monthly:
            dates = monthlyDates(
                recurring: recurring, anchor: anchor,
                from: fromDay, to: toDay,
                endDate: effectiveEnd, calendar: calendar
            )

        case .quarterly:
            dates = stepMonthDates(
                anchor: anchor, step: 3,
                from: fromDay, to: toDay,
                endDate: effectiveEnd, calendar: calendar
            )

        case .annual:
            dates = stepMonthDates(
                anchor: anchor, step: 12,
                from: fromDay, to: toDay,
                endDate: effectiveEnd, calendar: calendar
            )
        }

        return dates
    }

    /// Retourne la prochaine date d'occurrence strictement après `after`.
    static func nextOccurrenceDate(
        for recurring: RecurringTransaction,
        after date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        // Chercher mois par mois jusqu'à 24 mois en avant
        let afterDay = calendar.startOfDay(for: date)
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: afterDay)
        ) else { return nil }

        for offset in 0...24 {
            guard
                let ms  = calendar.date(byAdding: .month, value: offset, to: monthStart),
                let nms = calendar.date(byAdding: .month, value: 1, to: ms)
            else { break }

            let candidates = occurrenceDates(
                for: recurring, from: ms, to: nms, calendar: calendar
            )
            if let found = candidates.first(where: { $0 > afterDay }) {
                return found
            }
        }
        return nil
    }

    // MARK: - Helpers privés — génération de dates

    private static func stepDayDates(
        anchor: Date, step: Int,
        from: Date, to: Date,
        endDate: Date?, calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []
        let rawDelta = calendar.dateComponents([.day], from: anchor, to: from).day ?? 0
        let firstN   = rawDelta <= 0 ? 0 : (rawDelta + step - 1) / step

        var n = firstN
        while true {
            guard let date = calendar.date(byAdding: .day, value: n * step, to: anchor) else { break }
            if date >= to { break }
            if let end = endDate, date > end { break }
            if date >= from { dates.append(date) }
            n += 1
        }
        return dates
    }

    private static func stepMonthDates(
        anchor: Date, step: Int,
        from: Date, to: Date,
        endDate: Date?, calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []
        let rawDelta = calendar.dateComponents([.month], from: anchor, to: from).month ?? 0
        let firstN   = rawDelta <= 0 ? 0 : (rawDelta + step - 1) / step

        var n = firstN
        while true {
            guard let date = calendar.date(byAdding: .month, value: n * step, to: anchor) else { break }
            if date >= to { break }
            if let end = endDate, date > end { break }
            if date >= from { dates.append(date) }
            n += 1
        }
        return dates
    }

    private static func semimonthlyDates(
        anchor: Date, from: Date, to: Date,
        endDate: Date?, calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []
        let compsStart = calendar.dateComponents([.year, .month], from: from)
        let compsEnd   = calendar.dateComponents([.year, .month], from: to)

        var year  = compsStart.year!
        var month = compsStart.month!

        while true {
            guard let monthDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { break }
            if monthDate >= to { break }

            for day in [1, 15] {
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
                guard date >= anchor else { continue }
                guard date >= from, date < to else { continue }
                if let end = endDate, date > end { continue }
                dates.append(date)
            }

            month += 1
            if month > 12 { month = 1; year += 1 }
            if year > (compsEnd.year ?? year) + 1 { break }
        }
        return dates
    }

    private static func monthlyDates(
        recurring: RecurringTransaction,
        anchor: Date, from: Date, to: Date,
        endDate: Date?, calendar: Calendar
    ) -> [Date] {
        let targetDay = recurring.dayOfMonth ?? calendar.component(.day, from: anchor)
        var dates: [Date] = []

        let compsStart = calendar.dateComponents([.year, .month], from: from)
        var year  = compsStart.year!
        var month = compsStart.month!

        while true {
            guard let date = clampedDate(year: year, month: month, targetDay: targetDay, calendar: calendar) else { break }
            if date >= to { break }
            if date >= anchor && date >= from {
                if let end = endDate, date > end { break }
                dates.append(date)
            }
            month += 1
            if month > 12 { month = 1; year += 1 }
            // Garde-fou : ne pas boucler indéfiniment
            if year > calendar.component(.year, from: to) + 2 { break }
        }
        return dates
    }

    // MARK: - Clamp date

    /// Retourne le `targetDay` du mois donné, clampé au dernier jour disponible.
    /// Retourne nil si la date ne peut pas être construite.
    static func clampedDate(
        year: Int, month: Int, targetDay: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard let firstOfMonth = calendar.date(
            from: DateComponents(year: year, month: month, day: 1)
        ) else { return nil }
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 28
        let clampedDay  = min(targetDay, daysInMonth)
        return calendar.date(from: DateComponents(year: year, month: month, day: clampedDay))
    }

    // MARK: - Construction d'une Transaction

    private static func makeTransaction(
        for recurring: RecurringTransaction,
        on date: Date
    ) -> Transaction {
        Transaction(
            accountId:              recurring.accountId,
            recurringTransactionId: recurring.id,
            name:                   recurring.name,
            amount:                 recurring.amount,
            date:                   date,
            categoryId:             recurring.categoryId,
            isPaid:                 false
        )
    }
}
