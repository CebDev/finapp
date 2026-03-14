//
//  PeriodEngine.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import Foundation

// MARK: - PayPeriod

struct PayPeriod: Identifiable {
    let id: UUID
    /// Premier jour de la période (minuit heure locale, inclus)
    let startDate: Date
    /// Dernier jour de la période (minuit heure locale, inclus)
    let endDate: Date
    let projectedBalance: Decimal
    let previousBalance: Decimal
    /// projectedBalance - previousBalance
    let delta: Decimal
    /// Vrai si projectedBalance < settings.tightThreshold
    let isTight: Bool
    /// Vrai si referenceDate est compris dans [startDate, endDate]
    let isCurrentPeriod: Bool
    /// Récurrences ayant au moins une occurrence dans cette période
    let transactions: [RecurringTransaction]
}

// MARK: - PeriodEngine

struct PeriodEngine {

    // MARK: - API publique

    /// Génère `count` périodes de paie consécutives en commençant par la période qui contient `referenceDate`.
    ///
    /// - Biweekly : périodes de 14 jours ancrées sur `settings.nextPayDate`.
    /// - Monthly  : du 1er au dernier jour de chaque mois calendaire.
    ///
    /// Le solde de départ est la somme des `effectiveBalance` des comptes `includeInBudget == true`.
    /// La logique d'occurrences est déléguée à `ProjectionEngine.occurrences` — aucune duplication.
    static func generate(
        settings: UserSettings,
        accounts: [Account],
        recurring: [RecurringTransaction],
        count: Int,
        referenceDate: Date = .now
    ) -> [PayPeriod] {
        let calendar = Calendar.current
        let refDay   = calendar.startOfDay(for: referenceDate)

        let startingBalance = accounts
            .filter(\.includeInBudget)
            .reduce(Decimal(0)) { $0 + $1.effectiveBalance }

        let currentPeriodStart = periodStart(
            for: refDay,
            settings: settings,
            calendar: calendar
        )

        var result:         [PayPeriod] = []
        var runningBalance: Decimal     = startingBalance

        for i in 0..<count {
            // Bornes de la période i
            let (pStart, exclusiveEnd) = bounds(
                index: i,
                currentStart: currentPeriodStart,
                frequency: settings.payPeriodFrequency,
                calendar: calendar
            )
            // endDate stocké = dernier jour inclus (exclusiveEnd - 1 jour)
            let pEnd = calendar.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? exclusiveEnd

            // Accumulation via ProjectionEngine
            var activeTx: [RecurringTransaction] = []
            var delta:     Decimal               = 0

            for tx in recurring {
                let occs = ProjectionEngine.occurrences(
                    of: tx, from: pStart, to: exclusiveEnd, calendar: calendar
                )
                guard !occs.isEmpty else { continue }
                activeTx.append(tx)
                delta += tx.amount * Decimal(occs.count)
            }

            let previous       = runningBalance
            runningBalance    += delta
            let isCurrent      = pStart <= refDay && refDay <= pEnd

            result.append(PayPeriod(
                id:               UUID(),
                startDate:        pStart,
                endDate:          pEnd,
                projectedBalance: runningBalance,
                previousBalance:  previous,
                delta:            delta,
                isTight:          runningBalance < settings.tightThreshold,
                isCurrentPeriod:  isCurrent,
                transactions:     activeTx
            ))
        }

        return result
    }

    // MARK: - Calcul du début de la période courante

    private static func periodStart(
        for refDay: Date,
        settings: UserSettings,
        calendar: Calendar
    ) -> Date {
        switch settings.payPeriodFrequency {

        case .biweekly:
            // Séquence de débuts : anchor + n × 14 jours (n ∈ ℤ)
            let anchor   = calendar.startOfDay(for: settings.nextPayDate)
            let daysDiff = calendar.dateComponents([.day], from: anchor, to: refDay).day ?? 0
            let n        = floorDiv(daysDiff, 14)
            return calendar.date(byAdding: .day, value: n * 14, to: anchor) ?? refDay

        case .monthly:
            // 1er du mois courant
            return calendar.date(
                from: calendar.dateComponents([.year, .month], from: refDay)
            ) ?? refDay

        default:
            // Fallback conservateur : début du mois
            return calendar.date(
                from: calendar.dateComponents([.year, .month], from: refDay)
            ) ?? refDay
        }
    }

    // MARK: - Bornes [start, exclusiveEnd) de la période i

    /// Retourne `(start, exclusiveEnd)` où exclusiveEnd est le premier instant
    /// appartenant à la période suivante (convention identique à ProjectionEngine).
    private static func bounds(
        index: Int,
        currentStart: Date,
        frequency: Frequency,
        calendar: Calendar
    ) -> (start: Date, exclusiveEnd: Date) {
        switch frequency {

        case .biweekly:
            let start = calendar.date(byAdding: .day, value: index * 14, to: currentStart) ?? currentStart
            let end   = calendar.date(byAdding: .day, value: 14, to: start)               ?? start
            return (start, end)

        case .monthly:
            let start = calendar.date(byAdding: .month, value: index, to: currentStart) ?? currentStart
            let end   = calendar.date(byAdding: .month, value: 1,     to: start)        ?? start
            return (start, end)

        default:
            let start = calendar.date(byAdding: .month, value: index, to: currentStart) ?? currentStart
            let end   = calendar.date(byAdding: .month, value: 1,     to: start)        ?? start
            return (start, end)
        }
    }

    // MARK: - Arithmétique entière

    /// Division entière avec arrondi vers −∞ (floor), contrairement à l'opérateur `/` de Swift
    /// qui tronque vers zéro. Nécessaire pour indexer correctement les périodes passées.
    ///
    /// Exemples :
    ///   floorDiv( 7, 14) =  0  →  dans la période anchor
    ///   floorDiv(14, 14) =  1  →  période suivante
    ///   floorDiv(-3, 14) = -1  →  période précédente
    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        // Si le reste est non nul et que les signes diffèrent, on est un cran trop haut
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}
