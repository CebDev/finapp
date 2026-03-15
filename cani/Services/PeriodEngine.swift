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
    /// Solde projeté pour chaque jour de la période (un point par jour de startDate à endDate)
    let dailyBalances: [(date: Date, balance: Decimal)]
}

// MARK: - PeriodEngine

struct PeriodEngine {

    // MARK: - API publique

    /// Génère `count` périodes de paie consécutives en commençant par la période qui contient `referenceDate`.
    ///
    /// - Biweekly : périodes de 14 jours ancrées sur `settings.nextPayDate`.
    /// - Monthly  : du `settings.periodStartDay` au `periodStartDay - 1` du mois suivant,
    ///              avec clamp silencieux si le jour n'existe pas dans le mois (ex: 31 en février).
    ///
    /// Le solde de départ est la somme des `budgetContribution` des comptes `includeInBudget == true`.
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
            let (pStart, exclusiveEnd) = bounds(
                index: i,
                currentStart: currentPeriodStart,
                targetDay: settings.periodStartDay,
                frequency: settings.payPeriodFrequency,
                calendar: calendar
            )
            let pEnd = calendar.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? exclusiveEnd

            var activeTx:   [RecurringTransaction] = []
            var delta:      Decimal                = 0
            var dayAmounts: [Date: Decimal]        = [:]

            let budgetAccountIds        = Set(accounts.filter(\.includeInBudget).map(\.id))
            let isCurrentPeriodIteration = (i == 0)

            // Période courante : intégrer les transactions réelles (isPaid == true) dans le delta
            // et ramener le runningBalance au solde d'ouverture.
            if isCurrentPeriodIteration {
                let realTransactions = transactions.filter {
                    budgetAccountIds.contains($0.accountId) &&
                    $0.isPaid &&
                    $0.date >= pStart &&
                    $0.date < exclusiveEnd
                }
                let realDelta = realTransactions.reduce(Decimal(0)) { $0 + $1.amount }
                delta          = realDelta
                runningBalance -= realDelta
                for tx in realTransactions {
                    let day = calendar.startOfDay(for: tx.date)
                    dayAmounts[day, default: 0] += tx.amount
                }
            }

            for tx in recurring {
                // Ignorer les récurrences mises en pause
                guard tx.isActive else { continue }

                let occs = ProjectionEngine.occurrences(
                    of: tx, from: pStart, to: exclusiveEnd, calendar: calendar
                )
                guard !occs.isEmpty else { continue }
                activeTx.append(tx)

                for occ in occs {
                    let normalizedOcc = calendar.startOfDay(for: occ)
                    let occOverride = overrides.first {
                        $0.recurringTransactionId == tx.id &&
                        calendar.isDate(
                            calendar.startOfDay(for: $0.occurrenceDate),
                            inSameDayAs: normalizedOcc
                        )
                    }

                    if occOverride?.isSkipped == true { continue }
                    if isCurrentPeriodIteration && occOverride?.isPaid == true { continue }

                    let amount = occOverride?.actualAmount ?? tx.amount

                    if tx.isTransfer {
                        let sourceInBudget = budgetAccountIds.contains(tx.accountId)
                        let destInBudget   = tx.transferDestinationAccountId
                            .map { budgetAccountIds.contains($0) } ?? false
                        if sourceInBudget {
                            delta -= amount
                            dayAmounts[normalizedOcc, default: 0] -= amount
                        }
                        if destInBudget {
                            delta += amount
                            dayAmounts[normalizedOcc, default: 0] += amount
                        }
                    } else {
                        delta += amount
                        dayAmounts[normalizedOcc, default: 0] += amount
                    }
                }
            }

            let previous    = runningBalance
            runningBalance += delta
            let isCurrent   = pStart <= refDay && refDay <= pEnd

            // Solde journalier : un point tous les `dailySamplingStep` jours de pStart à pEnd.
            let step = max(1, dailySamplingStep)
            var runningDailyBalance = previous
            var dailySnapshots: [(date: Date, balance: Decimal)] = []
            var day      = pStart
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
            let anchor   = calendar.startOfDay(for: settings.periodAnchorDate)
            let daysDiff = calendar.dateComponents([.day], from: anchor, to: refDay).day ?? 0
            let n        = floorDiv(daysDiff, 14)
            return calendar.date(byAdding: .day, value: n * 14, to: anchor) ?? refDay

        case .monthly:
            // La période commence le `periodStartDay` du mois.
            // Si ce jour est après refDay, la période a commencé le mois précédent.
            let targetDay = settings.periodStartDay
            let refComps  = calendar.dateComponents([.year, .month], from: refDay)

            let candidateStart = clampedDate(
                year: refComps.year!, month: refComps.month!,
                targetDay: targetDay, calendar: calendar
            )

            if candidateStart <= refDay {
                return candidateStart
            } else {
                // On est avant le jour de début dans ce mois → la période a commencé le mois d'avant
                let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: candidateStart)!
                let prevComps     = calendar.dateComponents([.year, .month], from: prevMonthDate)
                return clampedDate(
                    year: prevComps.year!, month: prevComps.month!,
                    targetDay: targetDay, calendar: calendar
                )
            }

        default:
            return calendar.date(
                from: calendar.dateComponents([.year, .month], from: refDay)
            ) ?? refDay
        }
    }

    // MARK: - Bornes [start, exclusiveEnd) de la période i

    /// Retourne `(start, exclusiveEnd)` où exclusiveEnd est le premier instant
    /// appartenant à la période suivante.
    private static func bounds(
        index: Int,
        currentStart: Date,
        targetDay: Int,
        frequency: Frequency,
        calendar: Calendar
    ) -> (start: Date, exclusiveEnd: Date) {
        switch frequency {

        case .biweekly:
            let start = calendar.date(byAdding: .day, value: index * 14, to: currentStart) ?? currentStart
            let end   = calendar.date(byAdding: .day, value: 14, to: start) ?? start
            return (start, end)

        case .monthly:
            // Avancer de `index` mois depuis currentStart, en reclampant à chaque fois.
            // Nécessaire car currentStart peut être le 28 (clamped depuis 31 en fév)
            // mais le mois suivant peut avoir 31 jours — on veut rester sur le targetDay original.
            let startComps = calendar.dateComponents([.year, .month], from: currentStart)
            let startYear  = startComps.year!
            let startMonth = startComps.month!

            // Mois de début de la période i
            let totalMonthsStart = startMonth + index
            let year  = startYear + (totalMonthsStart - 1) / 12
            let month = ((totalMonthsStart - 1) % 12) + 1
            let start = clampedDate(year: year, month: month, targetDay: targetDay, calendar: calendar)

            // Mois de début de la période i+1 (= exclusiveEnd)
            let totalMonthsEnd = startMonth + index + 1
            let yearEnd  = startYear + (totalMonthsEnd - 1) / 12
            let monthEnd = ((totalMonthsEnd - 1) % 12) + 1
            let end = clampedDate(year: yearEnd, month: monthEnd, targetDay: targetDay, calendar: calendar)

            return (start, end)

        default:
            let start = calendar.date(byAdding: .month, value: index, to: currentStart) ?? currentStart
            let end   = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (start, end)
        }
    }

    // MARK: - Clamp utilitaire

    /// Retourne le `targetDay` du mois donné, clampé au dernier jour disponible.
    /// Ex: targetDay=31, month=février → retourne le 28 (ou 29 en bissextile).
    private static func clampedDate(
        year: Int,
        month: Int,
        targetDay: Int,
        calendar: Calendar
    ) -> Date {
        let firstOfMonth  = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let daysInMonth   = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count
        let clampedDay    = min(targetDay, daysInMonth)
        return calendar.date(from: DateComponents(year: year, month: month, day: clampedDay))!
    }

    // MARK: - Arithmétique entière

    /// Division entière avec arrondi vers −∞ (floor).
    /// Nécessaire pour indexer correctement les périodes biweekly passées.
    ///
    /// Exemples :
    ///   floorDiv( 7, 14) =  0  →  dans la période anchor
    ///   floorDiv(14, 14) =  1  →  période suivante
    ///   floorDiv(-3, 14) = -1  →  période précédente
    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}