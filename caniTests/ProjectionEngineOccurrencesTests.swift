//
//  ProjectionEngineOccurrencesTests.swift
//  caniTests
//

import XCTest
@testable import cani

final class ProjectionEngineOccurrencesTests: XCTestCase {

    // MARK: - Setup

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Toronto")!
        return cal
    }()

    private let accountId = UUID()

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var dc = DateComponents()
        dc.year = year; dc.month = month; dc.day = day
        return calendar.date(from: dc)!
    }

    private func makeTx(
        frequency:  Frequency,
        start:      Date,
        end:        Date?  = nil,
        dayOfMonth: Int?   = nil,
        dayOfWeek:  Int?   = nil
    ) -> RecurringTransaction {
        RecurringTransaction(
            accountId:  accountId,
            name:       "Test",
            amount:     -100,
            frequency:  frequency,
            startDate:  start,
            endDate:    end,
            dayOfWeek:  dayOfWeek,
            dayOfMonth: dayOfMonth
        )
    }

    private func occ(_ tx: RecurringTransaction, from: Date, to: Date) -> [Date] {
        ProjectionEngine.occurrences(of: tx, from: from, to: to, calendar: calendar)
    }

    // MARK: - oneTime

    func test_oneTime_insideWindow() {
        let tx = makeTx(frequency: .oneTime, start: date(2026, 5, 12))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [date(2026, 5, 12)])
    }

    func test_oneTime_beforeWindow() {
        let tx = makeTx(frequency: .oneTime, start: date(2026, 4, 5))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [])
    }

    func test_oneTime_atInclusiveFrom() {
        let tx = makeTx(frequency: .oneTime, start: date(2026, 5, 1))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [date(2026, 5, 1)])
    }

    func test_oneTime_atExclusiveTo() {
        // `to` est exclusif → aucune occurrence
        let tx = makeTx(frequency: .oneTime, start: date(2026, 6, 1))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [])
    }

    func test_oneTime_afterWindow() {
        let tx = makeTx(frequency: .oneTime, start: date(2026, 8, 1))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [])
    }

    // MARK: - weekly

    func test_weekly_fiveOccurrencesInMay() {
        // Débute le 1er mai → 1, 8, 15, 22, 29 mai
        let tx = makeTx(frequency: .weekly, start: date(2026, 5, 1))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 1), date(2026, 5, 8), date(2026, 5, 15),
            date(2026, 5, 22), date(2026, 5, 29)
        ])
    }

    func test_weekly_anchorBeforeWindow() {
        // Débute le 20 avril (lundi) → dans mai : 4, 11, 18, 25
        let tx = makeTx(frequency: .weekly, start: date(2026, 4, 20))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 4), date(2026, 5, 11), date(2026, 5, 18), date(2026, 5, 25)
        ])
    }

    func test_weekly_startAfterWindow() {
        let tx = makeTx(frequency: .weekly, start: date(2026, 7, 1))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [])
    }

    func test_weekly_endDateCutsOccurrences() {
        // endDate = 10 mai → seulement 1er et 8 mai
        let tx = makeTx(frequency: .weekly, start: date(2026, 5, 1), end: date(2026, 5, 10))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 1), date(2026, 5, 8)
        ])
    }

    func test_weekly_endDateOnOccurrenceIsInclusive() {
        // endDate exactement sur une occurrence → incluse
        let tx = makeTx(frequency: .weekly, start: date(2026, 5, 1), end: date(2026, 5, 15))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 1), date(2026, 5, 8), date(2026, 5, 15)
        ])
    }

    // MARK: - biweekly

    func test_biweekly_threeOccurrencesInMay() {
        // Débute le 2 mai, aux 2 semaines → 2, 16, 30 mai
        let tx = makeTx(frequency: .biweekly, start: date(2026, 5, 2))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 2), date(2026, 5, 16), date(2026, 5, 30)
        ])
    }

    func test_biweekly_anchorBeforeWindow() {
        // Débute le 15 mars, aux 2 semaines → dans mai : 10, 24
        let tx = makeTx(frequency: .biweekly, start: date(2026, 3, 15))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 10), date(2026, 5, 24)
        ])
    }

    func test_biweekly_withDayOfWeekFilterLundi() {
        // Débute le 4 mai (lundi = dayOfWeek 2 en 0-indexé : 0=dim … 6=sam)
        // Aux 2 semaines → 4, 18 mai (les deux sont des lundis)
        let tx = makeTx(frequency: .biweekly, start: date(2026, 5, 4), dayOfWeek: 2)
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 4), date(2026, 5, 18)
        ])
    }

    func test_biweekly_endDateCutsOccurrences() {
        // endDate = 17 mai → seulement 2 et 16 mai
        let tx = makeTx(frequency: .biweekly, start: date(2026, 5, 2), end: date(2026, 5, 17))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 2), date(2026, 5, 16)
        ])
    }

    func test_biweekly_periodWindowBiweekly() {
        // Fenêtre = période biweekly 30 avr → 13 mai (exclusif 14 mai)
        // Séquence depuis 2 avr : 2, 16, 30 avr, 14 mai…
        let tx = makeTx(frequency: .biweekly, start: date(2026, 4, 2))
        XCTAssertEqual(occ(tx, from: date(2026, 4, 30), to: date(2026, 5, 14)), [
            date(2026, 4, 30)
        ])
    }

    // MARK: - semimonthly

    func test_semimonthly_twoOccurrencesPerMonth() {
        let tx = makeTx(frequency: .semimonthly, start: date(2026, 1, 1))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 1), date(2026, 5, 15)
        ])
    }

    func test_semimonthly_startAfter1stBeforeWindow() {
        // Débute le 10 mai → le 1er est avant startDate, seulement le 15
        let tx = makeTx(frequency: .semimonthly, start: date(2026, 5, 10))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 15)
        ])
    }

    func test_semimonthly_startAfter15th_noneInMonth() {
        // Débute le 20 mai → aucune occurrence en mai
        let tx = makeTx(frequency: .semimonthly, start: date(2026, 5, 20))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [])
    }

    func test_semimonthly_endDateBeforeSecondOccurrence() {
        // endDate = 10 mai → seulement le 1er
        let tx = makeTx(frequency: .semimonthly, start: date(2026, 1, 1), end: date(2026, 5, 10))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 1)
        ])
    }

    func test_semimonthly_endDateOnSecondOccurrenceIsInclusive() {
        let tx = makeTx(frequency: .semimonthly, start: date(2026, 1, 1), end: date(2026, 5, 15))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [
            date(2026, 5, 1), date(2026, 5, 15)
        ])
    }

    // MARK: - monthly

    func test_monthly_basicOccurrence() {
        let tx = makeTx(frequency: .monthly, start: date(2026, 1, 12), dayOfMonth: 12)
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [date(2026, 5, 12)])
    }

    func test_monthly_regression_biweeklyPeriodSpanningTwoMonths() {
        // Régression : période biweekly 30 avr → 13 mai (exclusif 14 mai)
        // L'ancienne implémentation cherchait le 12 avril → < 30 avr → raté
        let tx = makeTx(frequency: .monthly, start: date(2026, 4, 12), dayOfMonth: 12)
        XCTAssertEqual(occ(tx, from: date(2026, 4, 30), to: date(2026, 5, 14)), [date(2026, 5, 12)])
    }

    func test_monthly_dayFallsBeforePeriodStart() {
        // Période 14 mai → 27 mai : le 12 mai est avant la fenêtre → absent
        let tx = makeTx(frequency: .monthly, start: date(2026, 1, 12), dayOfMonth: 12)
        XCTAssertEqual(occ(tx, from: date(2026, 5, 14), to: date(2026, 5, 28)), [])
    }

    func test_monthly_dayInexistentInMonth_noOccurrence() {
        // 31 en février → aucune occurrence
        let tx = makeTx(frequency: .monthly, start: date(2026, 1, 31), dayOfMonth: 31)
        XCTAssertEqual(occ(tx, from: date(2026, 2, 1), to: date(2026, 3, 1)), [])
    }

    func test_monthly_startDateAfterTargetDayInSameMonth() {
        // Débute le 20 mai, dayOfMonth = 12 → le 12 mai < startDate → absent
        let tx = makeTx(frequency: .monthly, start: date(2026, 5, 20), dayOfMonth: 12)
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [])
    }

    func test_monthly_firstOccurrenceInNextMonth() {
        // Débute le 20 mai, dayOfMonth = 12 → première occurrence en juin
        let tx = makeTx(frequency: .monthly, start: date(2026, 5, 20), dayOfMonth: 12)
        XCTAssertEqual(occ(tx, from: date(2026, 6, 1), to: date(2026, 7, 1)), [date(2026, 6, 12)])
    }

    func test_monthly_endDateOnOccurrenceIsInclusive() {
        let tx = makeTx(frequency: .monthly, start: date(2026, 1, 12), end: date(2026, 5, 12), dayOfMonth: 12)
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [date(2026, 5, 12)])
    }

    func test_monthly_endDateDayBeforeOccurrenceExcludes() {
        let tx = makeTx(frequency: .monthly, start: date(2026, 1, 12), end: date(2026, 5, 11), dayOfMonth: 12)
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [])
    }

    func test_monthly_consecutiveMonthsAllPresent() {
        // Vérifie que tous les mois de mars à juillet ont une occurrence le 12
        let tx = makeTx(frequency: .monthly, start: date(2026, 1, 12), dayOfMonth: 12)
        let months = [(3, 12), (4, 12), (5, 12), (6, 12), (7, 12)]
        for (m, d) in months {
            let result = occ(tx, from: date(2026, m, 1), to: date(2026, m == 12 ? 1 : m + 1, m == 12 ? 2027 : 1))
            XCTAssertEqual(result, [date(2026, m, d)], "Mois \(m) absent")
        }
    }

    // MARK: - quarterly

    func test_quarterly_basicOccurrence() {
        // Débute le 15 fév → 15 fév, 15 mai, 15 août, 15 nov
        let tx = makeTx(frequency: .quarterly, start: date(2026, 2, 15))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [date(2026, 5, 15)])
    }

    func test_quarterly_noOccurrenceInOtherMonths() {
        let tx = makeTx(frequency: .quarterly, start: date(2026, 2, 15))
        XCTAssertEqual(occ(tx, from: date(2026, 6, 1), to: date(2026, 7, 1)), [])
        XCTAssertEqual(occ(tx, from: date(2026, 7, 1), to: date(2026, 8, 1)), [])
    }

    func test_quarterly_multipleYears() {
        // Débute en jan 2025 → oct 2026 doit être présent
        let tx = makeTx(frequency: .quarterly, start: date(2025, 1, 10))
        XCTAssertEqual(occ(tx, from: date(2026, 10, 1), to: date(2026, 11, 1)), [date(2026, 10, 10)])
    }

    func test_quarterly_endDateCutsOccurrence() {
        // endDate = 1er mai → le 15 mai est exclu
        let tx = makeTx(frequency: .quarterly, start: date(2026, 2, 15), end: date(2026, 5, 1))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [])
    }

    // MARK: - annual

    func test_annual_sameMonthAndDay() {
        let tx = makeTx(frequency: .annual, start: date(2024, 6, 3))
        XCTAssertEqual(occ(tx, from: date(2026, 6, 1), to: date(2026, 7, 1)), [date(2026, 6, 3)])
    }

    func test_annual_wrongMonth() {
        let tx = makeTx(frequency: .annual, start: date(2024, 6, 3))
        XCTAssertEqual(occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [])
    }

    func test_annual_startYearItself() {
        let tx = makeTx(frequency: .annual, start: date(2026, 3, 1))
        XCTAssertEqual(occ(tx, from: date(2026, 3, 1), to: date(2026, 4, 1)), [date(2026, 3, 1)])
    }

    func test_annual_endDateCutsOccurrence() {
        // endDate = 1er juin 2026 → la prochaine occurrence annuelle (3 juin) est exclue
        let tx = makeTx(frequency: .annual, start: date(2024, 6, 3), end: date(2026, 6, 1))
        XCTAssertEqual(occ(tx, from: date(2026, 6, 1), to: date(2026, 7, 1)), [])
    }

    // MARK: - Bornes communes

    func test_transactionEndedBeforeWindowIsIgnored() {
        // endDate avant le début de la fenêtre → rien pour tous les types
        let freqs: [Frequency] = [.weekly, .biweekly, .monthly, .quarterly, .annual]
        for freq in freqs {
            let tx = makeTx(frequency: freq, start: date(2025, 1, 1), end: date(2026, 3, 31))
            XCTAssertEqual(
                occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [],
                "Fréquence \(freq.rawValue) devrait être vide"
            )
        }
    }

    func test_transactionStartsAfterWindowIsIgnored() {
        let freqs: [Frequency] = [.weekly, .biweekly, .monthly, .quarterly, .annual]
        for freq in freqs {
            let tx = makeTx(frequency: freq, start: date(2026, 8, 1))
            XCTAssertEqual(
                occ(tx, from: date(2026, 5, 1), to: date(2026, 6, 1)), [],
                "Fréquence \(freq.rawValue) devrait être vide"
            )
        }
    }
}
