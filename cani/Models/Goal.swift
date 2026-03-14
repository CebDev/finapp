//
//  Goal.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-12.
//

import Foundation
import SwiftData

@Model
class Goal {
    var id: UUID = UUID()
    var name: String = ""
    var targetAmount: Decimal = Decimal(0)
    var currentAmount: Decimal = Decimal(0)
    var deadline: Date? = nil
    var type: GoalType = GoalType.shortTerm
    var linkedAccountId: UUID? = nil
    var emoji: String = "🎯"

    init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Decimal,
        currentAmount: Decimal = 0,
        deadline: Date? = nil,
        type: GoalType = .shortTerm,
        linkedAccountId: UUID? = nil,
        emoji: String = "🎯"
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.deadline = deadline
        self.type = type
        self.linkedAccountId = linkedAccountId
        self.emoji = emoji
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: currentAmount / targetAmount).doubleValue
        return min(ratio, 1.0)
    }

    var isCompleted: Bool {
        currentAmount >= targetAmount
    }
}
