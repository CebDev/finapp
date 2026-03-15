//
//  UpcomingOperationsService.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import Foundation

// MARK: - UpcomingOperation

struct UpcomingOperation: Identifiable {
    let id: UUID
    let name: String
    let amount: Decimal
    let date: Date
    let category: Category?
    let recurringTransaction: RecurringTransaction
    var isPaid: Bool = false
}

// MARK: - UpcomingOperationsService

enum UpcomingOperationsService {

    /// Retourne les `count` prochaines occurrences de transactions récurrentes actives,
    /// triées chronologiquement, dans une fenêtre de 60 jours à partir de `after`.
    ///
    /// Une transaction est active si : startDate <= after ET (endDate == nil OU endDate >= after).
    /// La logique d'occurrences est déléguée à `ProjectionEngine.occurrences` — aucune duplication.
    static func next(
        _ count: Int,
        from recurring: [RecurringTransaction],
        categories: [Category] = [],
        overrides: [TransactionOverride] = [],
        after: Date = .now
    ) -> [UpcomingOperation] {
        let calendar    = Calendar.current
        let windowStart = calendar.startOfDay(for: after)
        guard let windowEnd = calendar.date(byAdding: .day, value: 60, to: windowStart) else { return [] }

        var ops: [UpcomingOperation] = []

        for tx in recurring {
            let occs = ProjectionEngine.occurrences(
                of: tx, from: windowStart, to: windowEnd, calendar: calendar
            )

            // Trouver la première occurrence non-supprimée
            var chosenOcc:      Date?                = nil
            var chosenOverride: TransactionOverride? = nil
            for occ in occs {
                let normalized = calendar.startOfDay(for: occ)
                let ov = overrides.first {
                    $0.recurringTransactionId == tx.id &&
                    calendar.isDate(calendar.startOfDay(for: $0.occurrenceDate), inSameDayAs: normalized)
                }
                if ov?.isSkipped == true { continue }
                chosenOcc      = occ
                chosenOverride = ov
                break
            }
            guard let first = chosenOcc else { continue }

            let effectiveAmount = chosenOverride?.actualAmount ?? tx.amount
            let isPaid          = chosenOverride?.isPaid == true

            let cat = tx.categoryId.flatMap { id in categories.first { $0.id == id } }
            ops.append(UpcomingOperation(
                id:                   UUID(),
                name:                 tx.name,
                amount:               effectiveAmount,
                date:                 first,
                category:             cat,
                recurringTransaction: tx,
                isPaid:               isPaid
            ))
        }

        return ops
            .sorted { $0.date < $1.date }
            .prefix(count)
            .map { $0 }
    }
}
