//
//  Simulation.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-12.
//

import Foundation
import SwiftData

@Model
class Simulation {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var isActive: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

@Model
class SimulationTransaction {
    var id: UUID = UUID()
    var simulationId: UUID = UUID()
    var amount: Decimal = Decimal(0)
    var frequency: Frequency = Frequency.monthly
    var startDate: Date = Date()
    var endDate: Date? = nil
    var label: String = ""

    init(
        id: UUID = UUID(),
        simulationId: UUID,
        amount: Decimal,
        frequency: Frequency,
        startDate: Date,
        endDate: Date? = nil,
        label: String
    ) {
        self.id = id
        self.simulationId = simulationId
        self.amount = amount
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.label = label
    }
}
