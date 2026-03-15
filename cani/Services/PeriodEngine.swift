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
    /// Solde projeté pour chaque jour de la période (un point par jour de startDate à endDate).
    let dailyBalances: [(date: Date, balance: Decimal)]
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
        referenceDate: Date = .now,
        overrides: [TransactionOverride] = [],
        transactions: [Transaction] = [],
        dailySamplingStep: Int = 1
    ) -> [PayPeriod] {
        let calendar = Calendar.current
        let refDay   = calendar.startOfDay(for: referenceDate)

        // Ancrage sur le solde réel courant — budgetContribution respecte le mode d'affichage
        // carte de crédit (creditAvailable → crédit dispo positif ; creditOwed → dette négative).
        let startingBalance = accounts
            .filter(\.includeInBudget)
            .reduce(Decimal(0)) { $0 + $1.budgetContribution }

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
            var activeTx:  [RecurringTransaction] = []
            var delta:     Decimal               = 0
            var dayAmounts: [Date: Decimal]      = [:]

            let budgetAccountIds = Set(accounts.filter(\.includeInBudget).map(\.id))

            // Période courante = i == 0 (on génère toujours à partir de la période qui contient refDay)
            let isCurrentPeriodIteration = (i == 0)

            // Période courante : inclure les opérations réelles dans le delta et remonter
            // le runningBalance au solde d'ouverture (avant ces opérations, qui sont déjà
            // dans budgetContribution). Cela donne un delta significatif visible dans PayPeriodCard.
            if isCurrentPeriodIteration {
                let realTransactions = transactions.filter {
                    budgetAccountIds.contains($0.accountId) && $0.date >= pStart && $0.date < exclusiveEnd
                }
                let realDelta = realTransactions.reduce(Decimal(0)) { $0 + $1.amount }
                delta          = realDelta
                runningBalance -= realDelta   // ramène au solde en début de période
                // Alimenter dayAmounts avec les transactions réelles
                for tx in realTransactions {
                    let day = calendar.startOfDay(for: tx.date)
                    dayAmounts[day, default: 0] += tx.amount
                }
            }

            for tx in recurring {
                let occs = ProjectionEngine.occurrences(
                    of: tx, from: pStart, to: exclusiveEnd, calendar: calendar
                )
                guard !occs.isEmpty else { continue }
                activeTx.append(tx)
                for occ in occs {
                    let normalizedOcc = calendar.startOfDay(for: occ)
                    let occOverride = overrides.first {
                        $0.recurringTransactionId == tx.id &&
                        calendar.isDate(calendar.startOfDay(for: $0.occurrenceDate), inSameDayAs: normalizedOcc)
                    }

                    // Occurrence supprimée manuellement → ignorer dans tous les cas.
                    if occOverride?.isSkipped == true { continue }
                    // Période courante : les occurrences déjà payées sont dans currentBalance — ne pas les re-compter.
                    if isCurrentPeriodIteration && occOverride?.isPaid == true { continue }

                    let amount = occOverride?.actualAmount ?? tx.amount

                    if tx.isTransfer {
                        // Transfert : calcul du delta net selon l'inclusion budgétaire des comptes
                        let sourceInBudget = budgetAccountIds.contains(tx.accountId)
                        let destInBudget   = tx.transferDestinationAccountId.map { budgetAccountIds.contains($0) } ?? false
                        // amount > 0 (montant transféré) ; source débité, destination crédité
                        if sourceInBudget  { delta -= amount; dayAmounts[normalizedOcc, default: 0] -= amount }
                        if destInBudget    { delta += amount; dayAmounts[normalizedOcc, default: 0] += amount }
                    } else {
                        delta += amount
                        dayAmounts[normalizedOcc, default: 0] += amount
                    }
                }
            }

            let previous       = runningBalance
            runningBalance    += delta
            let isCurrent      = pStart <= refDay && refDay <= pEnd

            // Solde journalier : un point tous les `dailySamplingStep` jours de pStart à pEnd.
            // On accumule les montants des jours intermédiaires pour ne pas les perdre.
            let step = max(1, dailySamplingStep)
            var runningDailyBalance = previous
            var dailySnapshots: [(date: Date, balance: Decimal)] = []
            var day = pStart
            var dayIndex = 0
            while day <= pEnd {
                runningDailyBalance += dayAmounts[day, default: 0]
                if dayIndex % step == 0 || day == pEnd {
                    dailySnapshots.append((date: day, balance: runningDailyBalance))
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                day = next
                dayIndex += 1
            }

            result.append(PayPeriod(
                id:               UUID(),
                startDate:        pStart,
                endDate:          pEnd,
                projectedBalance: runningBalance,
                previousBalance:  previous,
                delta:            delta,
                isTight:          runningBalance < settings.tightThreshold,
                isCurrentPeriod:  isCurrent,
                transactions:     activeTx,
                dailyBalances:    dailySnapshots
            ))
        }

        return result
    }

    // MARK: - API publique — début de la période courante

    /// Retourne le premier jour (minuit) de la période contenant `referenceDate`.
    static func currentPeriodStart(
        settings: UserSettings,
        referenceDate: Date = .now
    ) -> Date {
        let calendar = Calendar.current
        let refDay   = calendar.startOfDay(for: referenceDate)
        return periodStart(for: refDay, settings: settings, calendar: calendar)
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
