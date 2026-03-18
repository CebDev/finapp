//
//  Frequency+Subscription.swift
//  cani
//
//  Extensions fréquence utilisées par les vues d'abonnements.
//

import Foundation

extension Frequency {
    var subShortLabel: String {
        switch self {
        case .oneTime:     return ""
        case .weekly:      return "/sem"
        case .biweekly:    return "/2 sem"
        case .semimonthly: return "/2×mois"
        case .monthly:     return "/mois"
        case .quarterly:   return "/trim"
        case .annual:      return "/an"
        }
    }

    var subLocalizedLabel: String {
        switch self {
        case .oneTime:     return "Ponctuel"
        case .weekly:      return "Hebdomadaire"
        case .biweekly:    return "Aux 2 semaines"
        case .semimonthly: return "Semi-mensuel"
        case .monthly:     return "Mensuel"
        case .quarterly:   return "Trimestriel"
        case .annual:      return "Annuel"
        }
    }

    func normalizedMonthlyCost(amount: Decimal) -> Decimal {
        let a = Swift.abs(amount)
        switch self {
        case .oneTime:     return 0
        case .weekly:      return a * 52 / 12
        case .biweekly:    return a * 26 / 12
        case .semimonthly: return a * 2
        case .monthly:     return a
        case .quarterly:   return a / 3
        case .annual:      return a / 12
        }
    }
}
