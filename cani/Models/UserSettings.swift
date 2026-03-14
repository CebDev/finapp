//
//  UserSettings.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import Foundation
import SwiftData

@Model
class UserSettings {
    /// Fréquence de paie — .biweekly ou .monthly uniquement
    var payPeriodFrequency: Frequency = Frequency.biweekly
    /// Jour de paie pour biweekly : 0=Dim … 6=Sam, défaut 4 (Jeudi)
    var payDayOfWeek: Int = 4
    /// Jour du mois pour la paie mensuelle (1–31)
    var payDayOfMonth: Int = 1
    /// Date de la prochaine paie — anchor pour le calcul des périodes
    var nextPayDate: Date = Date()
    /// Solde projeté en dessous duquel une période est considérée "serrée"
    var tightThreshold: Decimal = 500
    /// Devise par défaut
    var currency: String = "CAD"
    /// true (défaut) : chaque période repart du solde de fin de la précédente.
    /// false : chaque période est calculée de façon isolée, à partir de zéro.
    var carryForwardBalance: Bool = true

    init() { }

    // MARK: - Singleton

    /// Retourne l'unique instance de UserSettings, ou en crée une avec les valeurs par défaut.
    @discardableResult
    static func current(context: ModelContext) -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = UserSettings()
        context.insert(settings)
        return settings
    }

    /// Insère les réglages par défaut si aucune instance n'existe encore.
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<UserSettings>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        context.insert(UserSettings())
    }
}
