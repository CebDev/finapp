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
    /// Fréquence de période — .biweekly ou .monthly uniquement
    var payPeriodFrequency: Frequency = Frequency.biweekly
    /// Biweekly — jour de la semaine de début de période : 0=Dim … 6=Sam, défaut 4 (Jeudi)
    var periodStartDayOfWeek: Int = 4
    /// Biweekly — date de référence pour ancrer la séquence de périodes
    var periodAnchorDate: Date = Date()
    /// Monthly — jour du mois où commence chaque période (1–31, clampé au dernier jour du mois)
    /// Ex: 15 → période du 15 au 14 du mois suivant. 1 → période calendaire.
    var periodStartDay: Int = 1
    /// Solde projeté en dessous duquel une période est considérée "serrée"
    var tightThreshold: Decimal = 500
    /// Devise par défaut
    var currency: String = "CAD"
    /// true (défaut) : chaque période repart du solde de fin de la précédente.
    /// false : chaque période est calculée de façon isolée, à partir de zéro.
    var carryForwardBalance: Bool = true

    init() { }

    // MARK: - Singleton

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

    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<UserSettings>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        context.insert(UserSettings())
    }
}