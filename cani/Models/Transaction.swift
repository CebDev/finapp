//
//  Transaction.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-12.
//

import Foundation
import SwiftData

@Model
class Transaction {
    var id: UUID = UUID()
    var accountId: UUID = UUID()
    var recurringTransactionId: UUID? = nil
    var amount: Decimal = Decimal(0)
    var date: Date = Date()
    var isPast: Bool = true
    var isConfirmed: Bool = true
    /// UUID de la Category SwiftData sélectionnée (nil = non catégorisé)
    var categoryId: UUID? = nil
    var notes: String? = nil
    /// Vrai si la transaction est un transfert entre comptes
    var isTransfer: Bool = false
    /// UUID du compte de destination pour un transfert (nil si non-transfert)
    var transferDestinationAccountId: UUID? = nil

    init(
        id: UUID = UUID(),
        accountId: UUID,
        recurringTransactionId: UUID? = nil,
        amount: Decimal,
        date: Date,
        isPast: Bool = true,
        isConfirmed: Bool = true,
        categoryId: UUID? = nil,
        notes: String? = nil,
        isTransfer: Bool = false,
        transferDestinationAccountId: UUID? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.recurringTransactionId = recurringTransactionId
        self.amount = amount
        self.date = date
        self.isPast = isPast
        self.isConfirmed = isConfirmed
        self.categoryId = categoryId
        self.notes = notes
        self.isTransfer = isTransfer
        self.transferDestinationAccountId = transferDestinationAccountId
    }
}
