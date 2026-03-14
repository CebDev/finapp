//
//  Enums.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-12.
//

import Foundation

enum AccountType: String, Codable, CaseIterable {
    case chequing
    case savings
    case credit
    case creditCard
    case mortgage
    case investment
}

enum CreditBalanceDisplayMode: String, Codable, CaseIterable {
    /// Montant restant disponible à dépenser : (limite - solde utilisé)
    case creditAvailable
    /// Montant dû, exprimé en négatif : -solde utilisé
    case creditOwed
}

enum Frequency: String, Codable, CaseIterable {
    case weekly
    case biweekly
    case semimonthly
    case monthly
    case quarterly
    case annual
}

enum GoalType: String, Codable, CaseIterable {
    case shortTerm
    case longTerm
}

