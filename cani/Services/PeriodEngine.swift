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
    /// Transactions (payées et planifiées) dans cette période
    let transactions: [Transaction]
    /// Solde projeté pour chaque jour de la période (un point par jour de startDate à endDate)
    let dailyBalances: [(date: Date, balance: Decimal)]
}

// MARK: - PeriodEngine

struct PeriodEngine {

    // MARK: - API publique

    /// Génère `count` périodes de paie consécutives en commençant par la période qui contient `referenceDate`.
    ///
    /// - Biweekly : périodes de 14 jours ancrées sur `settings.periodAnchorDate`.
    /// - Monthly  : du `settings.periodStartDay` au `periodStartDay - 1` du mois suivant,
    ///              avec clamp silencieux si le jour n'existe pas dans le mois (ex: 31 en février).
    ///
    /// Source de vérité : les `Transaction` SwiftData.
    /// - `isPaid == true`  → transaction réelle déjà comptabilisée dans `currentBalance`
    /// - `isPaid == false` → occurrence future planifiée, à intégrer dans la projection
    static func generate(
        settings: UserSettings,
        accounts: [Account],
        transactions: [Transaction],
        count: Int,
        referenceDate: Date = .now,
        dailySamplingStep: Int = 1
    ) -> [PayPeriod] {
        let calendar = Calendar.current
        let refDay   = calendar.startOfDay(for: referenceDate)

        let currentPeriodStart = periodStart(
            for: refDay,
            settings: settings,
            calendar: calendar
        )

        let budgetAccountIds = Set(accounts.filter(\.includeInBudget).map(\.id))

        // Solde de départ = solde actuel des comptes (inclut déjà toutes les transactions payées)
        let currentBalance = accounts
            .filter(\.includeInBudget)
            .reduce(Decimal(0)) { $0 + $1.budgetContribution }

        // Début de la première période générée (peut être avant la période courante,
        // ex : evolutionPeriods démarre un jour avant le début de la période courante).
        let (earliestPeriodStart, _) = bounds(
            index: 0,
            currentStart: currentPeriodStart,
            targetDay: settings.periodStartDay,
            frequency: settings.payPeriodFrequency,
            calendar: calendar
        )

        // Reconstituer le solde d'ouverture de la première période en soustrayant
        // toutes les transactions payées depuis son début — indépendamment du fait
        // que referenceDate soit dans la période courante ou dans une période passée.
        // Cela garantit que chaque période est ensuite projetée de façon homogène
        // (payées et planifiées traitées identiquement dans la boucle ci-dessous).
        let paidInWindow = transactions.filter {
            budgetAccountIds.contains($0.accountId) &&
            $0.isPaid &&
            $0.date >= earliestPeriodStart
        }
        let totalPaidDelta = paidInWindow.reduce(Decimal(0)) { $0 + $1.amount }
        let startingBalance = currentBalance - totalPaidDelta

        var result:         [PayPeriod] = []
        var runningBalance: Decimal     = startingBalance

        // Référence temporelle réelle (indépendante de referenceDate qui peut être dans le passé)
        let today = calendar.startOfDay(for: Date.now)

        for i in 0..<count {
            let (pStart, exclusiveEnd) = bounds(
                index: i,
                currentStart: currentPeriodStart,
                targetDay: settings.periodStartDay,
                frequency: settings.payPeriodFrequency,
                calendar: calendar
            )
            let pEnd = calendar.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? exclusiveEnd

            var delta:      Decimal         = 0
            var dayAmounts: [Date: Decimal] = [:]

            // Toutes les transactions de la période pour l'affichage
            let periodTxs = transactions.filter {
                budgetAccountIds.contains($0.accountId) &&
                $0.date >= pStart &&
                $0.date < exclusiveEnd
            }

            // Pour le calcul du solde : exclure les transactions non-payées dans le passé réel.
            // Les transactions isPaid == true ont été soustraites du startingBalance ci-dessus
            // et doivent être ré-intégrées ici. Les transactions futures non-payées (date > today)
            // sont des projections légitimes. Les transactions non-payées avec une date passée
            // (date <= today) ne sont pas encore dans currentBalance et ne le seront peut-être jamais —
            // on les exclut pour éviter de sur-projeter.
            let balanceTxs = periodTxs.filter { $0.isPaid || $0.date > today }

            for tx in balanceTxs {
                delta += tx.amount
                dayAmounts[calendar.startOfDay(for: tx.date), default: 0] += tx.amount
            }

            let previous    = runningBalance
            runningBalance += delta
            let isCurrent   = pStart <= refDay && refDay <= pEnd

            // Solde journalier
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
                transactions:     periodTxs,
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
            let anchor   = calendar.startOfDay(for: settings.periodAnchorDate)
            let daysDiff = calendar.dateComponents([.day], from: anchor, to: refDay).day ?? 0
            let n        = floorDiv(daysDiff, 14)
            return calendar.date(byAdding: .day, value: n * 14, to: anchor) ?? refDay

        case .monthly:
            let targetDay = settings.periodStartDay
            let refComps  = calendar.dateComponents([.year, .month], from: refDay)

            let candidateStart = clampedDate(
                year: refComps.year!, month: refComps.month!,
                targetDay: targetDay, calendar: calendar
            )

            if candidateStart <= refDay {
                return candidateStart
            } else {
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
            let startComps = calendar.dateComponents([.year, .month], from: currentStart)
            let startYear  = startComps.year!
            let startMonth = startComps.month!

            let totalMonthsStart = startMonth + index
            let year  = startYear + (totalMonthsStart - 1) / 12
            let month = ((totalMonthsStart - 1) % 12) + 1
            let start = clampedDate(year: year, month: month, targetDay: targetDay, calendar: calendar)

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

    private static func clampedDate(
        year: Int,
        month: Int,
        targetDay: Int,
        calendar: Calendar
    ) -> Date {
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let daysInMonth  = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count
        let clampedDay   = min(targetDay, daysInMonth)
        return calendar.date(from: DateComponents(year: year, month: month, day: clampedDay))!
    }

    // MARK: - Arithmétique entière

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}