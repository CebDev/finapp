//
//  DateUtils.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import Foundation

// MARK: - Frequency — labels français

extension Frequency {
    var labelFR: String {
        switch self {
        case .weekly:      return "Hebdomadaire"
        case .biweekly:    return "Aux deux semaines"
        case .semimonthly: return "Deux fois par mois"
        case .monthly:     return "Mensuel"
        case .quarterly:   return "Trimestriel"
        case .annual:      return "Annuel"
        }
    }
}

// MARK: - Prochaine occurrence

enum DateUtils {
    /// Retourne la prochaine date d'occurrence de `transaction` strictement après `date`.
    /// Réutilise `ProjectionEngine.occurrences` mois par mois — aucune duplication de logique.
    /// Retourne nil si la transaction est terminée ou si aucune occurrence n'existe dans les 24 mois suivants.
    static func nextOccurrence(from transaction: RecurringTransaction, after date: Date) -> Date? {
        let calendar = Calendar.current
        guard
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
            let firstNext  = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else { return nil }

        // Chercher dans le mois courant d'abord (occurrence > date)
        let thisMonth = ProjectionEngine.occurrences(
            of: transaction, from: monthStart, to: firstNext, calendar: calendar
        )
        if let found = thisMonth.first(where: { $0 > date }) { return found }

        // Puis mois par mois jusqu'à 24 mois en avant
        for offset in 1...24 {
            guard
                let ms  = calendar.date(byAdding: .month, value: offset, to: monthStart),
                let nms = calendar.date(byAdding: .month, value: 1, to: ms)
            else { break }
            let occs = ProjectionEngine.occurrences(of: transaction, from: ms, to: nms, calendar: calendar)
            if let found = occs.first { return found }
        }

        return nil
    }
}
