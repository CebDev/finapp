//
//  Account.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-12.
//

import Foundation
import SwiftData

@Model
class Account {
    var id: UUID = UUID()
    var name: String = ""
    var type: AccountType = AccountType.chequing
    var currentBalance: Decimal = Decimal(0)
    var includeInBudget: Bool = true
    var isShortTermReserve: Bool = false
    var creditLimit: Decimal? = nil
    /// Raw backing pour SwiftData — évite le cast crash sur enums Codable non-optionnels.
    var creditBalanceDisplayModeRaw: String? = CreditBalanceDisplayMode.creditAvailable.rawValue
    @Transient var creditBalanceDisplayMode: CreditBalanceDisplayMode {
        get { creditBalanceDisplayModeRaw.flatMap(CreditBalanceDisplayMode.init(rawValue:)) ?? .creditAvailable }
        set { creditBalanceDisplayModeRaw = newValue.rawValue }
    }
    var icon: String = "creditcard"
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    /// Contribution au solde de départ de la projection budgétaire.
    /// Diffère de effectiveBalance pour les cartes de crédit en mode creditOwed :
    /// la dette est déjà négative dans currentBalance → pas besoin de l'inverser.
    var budgetContribution: Decimal {
        switch type {
        case .creditCard:
            switch creditBalanceDisplayMode {
            case .creditAvailable:
                return effectiveBalance   // crédit disponible (positif)
            case .creditOwed:
                return currentBalance     // dette (négatif) réduit le budget
            }
        default:
            return currentBalance
        }
    }

    /// Solde effectif selon le type de compte et le mode d'affichage choisi.
    /// C'est cette valeur qui doit être utilisée partout pour l'affichage et la projection.
    var effectiveBalance: Decimal {
        switch type {
        case .creditCard:
            // currentBalance est négatif (ex: -500 = 500$ utilisés)
            switch creditBalanceDisplayMode {
            case .creditAvailable:
                return (creditLimit ?? Decimal(0)) + currentBalance
            case .creditOwed:
                return -currentBalance
            }
        default:
            return currentBalance
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        currentBalance: Decimal = 0,
        includeInBudget: Bool = true,
        isShortTermReserve: Bool = false,
        creditBalanceDisplayMode: CreditBalanceDisplayMode = .creditAvailable,
        creditLimit: Decimal? = nil,
        icon: String = "creditcard",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currentBalance = currentBalance
        self.includeInBudget = includeInBudget
        self.isShortTermReserve = isShortTermReserve
        self.creditBalanceDisplayModeRaw = creditBalanceDisplayMode.rawValue
        self.creditLimit = creditLimit
        self.icon = icon
        self.createdAt = createdAt
    }
}
