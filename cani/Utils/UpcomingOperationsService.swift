//
//  UpcomingOperationsService.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import Foundation

// MARK: - UpcomingOperation

struct UpcomingOperation: Identifiable {
    let id:          UUID
    let name:        String
    let amount:      Decimal
    let date:        Date
    let category:    Category?
    let transaction: Transaction
    let logo:        String?    // non-nil si abonnement avec logo
    let isIncome:    Bool
    let accountName: String?    // nom du compte source
    var isPaid:      Bool = false
}

// MARK: - UpcomingOperationsService

enum UpcomingOperationsService {

    /// Retourne les `count` prochaines transactions non payées,
    /// triées chronologiquement, dans une fenêtre de 60 jours à partir de `after`.
    static func next(
        _ count: Int,
        from transactions: [Transaction],
        categories:  [Category]             = [],
        recurringTx: [RecurringTransaction] = [],
        accounts:    [Account]              = [],
        after: Date = .now
    ) -> [UpcomingOperation] {
        let calendar    = Calendar.current
        let windowStart = calendar.startOfDay(for: after)
        guard let windowEnd = calendar.date(byAdding: .day, value: 60, to: windowStart) else { return [] }

        return transactions
            .filter {
                !$0.isPaid &&
                $0.date >= windowStart &&
                $0.date <  windowEnd
            }
            .sorted { $0.date < $1.date }
            .prefix(count)
            .map { tx in
                let cat  = tx.categoryId.flatMap { id in categories.first { $0.id == id } }
                let rt   = tx.recurringTransactionId.flatMap { rid in recurringTx.first { $0.id == rid } }
                let logo: String? = (rt?.isSubscription == true && !(rt?.logo ?? "").isEmpty)
                    ? rt?.logo
                    : nil
                let accountName = accounts.first(where: { $0.id == tx.accountId })?.name
                return UpcomingOperation(
                    id:          UUID(),
                    name:        tx.name,
                    amount:      tx.amount,
                    date:        tx.date,
                    category:    cat,
                    transaction: tx,
                    logo:        logo,
                    isIncome:    tx.amount > 0,
                    accountName: accountName,
                    isPaid:      tx.isPaid
                )
            }
    }
}