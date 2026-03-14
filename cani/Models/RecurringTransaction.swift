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
    var endDate: Date? = nil
    var dayOfWeek: Int? = nil
    var dayOfMonth: Int? = nil
    var isIncome: Bool = false
    /// UUID de la Category SwiftData sélectionnée (nil = non catégorisé)
    var categoryId: UUID? = nil
    var isSubscription: Bool = false
    var logo: String = ""
    var notes: String? = nil

    init(
        id: UUID = UUID(),
        accountId: UUID,
        name: String,
        amount: Decimal,
        frequency: Frequency,
        startDate: Date,
        endDate: Date? = nil,
        dayOfWeek: Int? = nil,
        dayOfMonth: Int? = nil,
        isIncome: Bool = false,
        categoryId: UUID? = nil,
        isSubscription: Bool = false,
        logo: String = "",
        notes: String? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.amount = amount
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.dayOfWeek = dayOfWeek
        self.dayOfMonth = dayOfMonth
        self.isIncome = isIncome
        self.categoryId = categoryId
        self.isSubscription = isSubscription
        self.logo = logo
        self.notes = notes
    }
}
