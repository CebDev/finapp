//
//  RecurringTransaction.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-12.
//

import Foundation
import SwiftData

@Model
class RecurringTransaction {
    var id: UUID = UUID()
    var accountId: UUID = UUID()
    var name: String = ""
    var amount: Decimal = Decimal(0)
    var frequency: Frequency = Frequency.monthly
    var startDate: Date = Date()
    /// Date de fin — mutuellement exclusif avec countOfOccurrences.
    /// nil = pas de date de fin.
    var endDate: Date? = nil
    /// Nombre maximum d'occurrences — mutuellement exclusif avec endDate.
    /// nil = pas de limite par nombre.
    var countOfOccurrences: Int? = nil
    var dayOfWeek: Int? = nil
    var dayOfMonth: Int? = nil
    var isIncome: Bool = false
    /// UUID de la Category SwiftData sélectionnée (nil = non catégorisé)
    var categoryId: UUID? = nil
    var isSubscription: Bool = false
    /// true = récurrence active ; false = mise en pause sans suppression
    var isActive: Bool = true
    var logo: String = ""
    var notes: String? = nil
    /// Vrai si la récurrence est un transfert entre comptes
    var isTransfer: Bool = false
    /// UUID du compte de destination pour un transfert (nil si non-transfert)
    var transferDestinationAccountId: UUID? = nil

    init(
        id: UUID = UUID(),
        accountId: UUID,
        name: String,
        amount: Decimal,
        frequency: Frequency,
        startDate: Date,
        endDate: Date? = nil,
        countOfOccurrences: Int? = nil,
        dayOfWeek: Int? = nil,
        dayOfMonth: Int? = nil,
        isIncome: Bool = false,
        categoryId: UUID? = nil,
        isSubscription: Bool = false,
        isActive: Bool = true,
        logo: String = "",
        notes: String? = nil,
        isTransfer: Bool = false,
        transferDestinationAccountId: UUID? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.amount = amount
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.countOfOccurrences = countOfOccurrences
        self.dayOfWeek = dayOfWeek
        self.dayOfMonth = dayOfMonth
        self.isIncome = isIncome
        self.categoryId = categoryId
        self.isSubscription = isSubscription
        self.isActive = isActive
        self.logo = logo
        self.notes = notes
        self.isTransfer = isTransfer
        self.transferDestinationAccountId = transferDestinationAccountId
    }
}