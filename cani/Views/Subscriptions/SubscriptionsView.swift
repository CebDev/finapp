//
//  SubscriptionsView.swift
//  cani
//

import SwiftUI
import SwiftData

// MARK: - Frequency helpers (contexte abonnements)

private extension Frequency {
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

// MARK: - Color(hex:)

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >>  8) & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}

// MARK: - SubscriptionsView

struct SubscriptionsView: View {
    @Query(
        filter: #Predicate<RecurringTransaction> { $0.isSubscription && !$0.isTransfer },
        sort: \RecurringTransaction.name
    )
    private var subscriptions: [RecurringTransaction]

    @State private var displayedYear:  Int = Calendar.current.component(.year,  from: Date())
    @State private var displayedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var editingTx:      RecurringTransaction? = nil
    @State private var showingAddSheet = false

    private var frCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "fr_CA")
        return cal
    }

    // Occurrences par numéro de jour pour le mois affiché
    private var dayOccurrences: [Int: [RecurringTransaction]] {
        var result: [Int: [RecurringTransaction]] = [:]
        for tx in subscriptions {
            for date in occurrences(of: tx, year: displayedYear, month: displayedMonth) {
                let day = frCalendar.component(.day, from: date)
                result[day, default: []].append(tx)
            }
        }
        return result
    }

    // Liste triée par date pour la section liste
    private var listEntries: [(tx: RecurringTransaction, date: Date)] {
        var entries: [(tx: RecurringTransaction, date: Date)] = []
        for tx in subscriptions {
            for date in occurrences(of: tx, year: displayedYear, month: displayedMonth) {
                entries.append((tx: tx, date: date))
            }
        }
        return entries.sorted { $0.date < $1.date }
    }

    private func occurrences(of tx: RecurringTransaction, year: Int, month: Int) -> [Date] {
        guard let monthStart = frCalendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let nextMonth  = frCalendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
        return ProjectionEngine.occurrences(of: tx, from: monthStart, to: nextMonth, calendar: frCalendar)
    }

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.dateFormat = "MMMM yyyy"
        guard let date = frCalendar.date(from: DateComponents(year: displayedYear, month: displayedMonth, day: 1)) else { return "" }
        return fmt.string(from: date).capitalized
    }

    private var firstWeekdayOffset: Int {
        guard let d = frCalendar.date(from: DateComponents(year: displayedYear, month: displayedMonth, day: 1)) else { return 0 }
        return frCalendar.component(.weekday, from: d) - 1
    }

    private var daysInMonth: Int {
        guard let d = frCalendar.date(from: DateComponents(year: displayedYear, month: displayedMonth, day: 1)),
              let r = frCalendar.range(of: .day, in: .month, for: d) else { return 30 }
        return r.count
    }

    private var todayDay: Int? {
        let c = frCalendar.dateComponents([.year, .month, .day], from: Date())
        guard c.year == displayedYear, c.month == displayedMonth else { return nil }
        return c.day
    }

    // Coût mensuel normalisé total
    private var totalMonthly: Decimal {
        subscriptions.reduce(.zero) { $0 + $1.frequency.normalizedMonthlyCost(amount: $1.amount) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SummaryStrip(total: totalMonthly, count: subscriptions.count)
                        .padding(.horizontal)

                    CalendarCard(
                        monthTitle:        monthTitle,
                        firstDayOffset:    firstWeekdayOffset,
                        daysInMonth:       daysInMonth,
                        todayDay:          todayDay,
                        dayOccurrences:    dayOccurrences,
                        onPreviousMonth:   { shiftMonth(by: -1) },
                        onNextMonth:       { shiftMonth(by:  1) },
                        onTxTap:           { tx in editingTx = tx }
                    )
                    .padding(.horizontal)

                    if !listEntries.isEmpty {
                        ListSection(
                            entries:  listEntries,
                            calendar: frCalendar,
                            onTap:    { tx in editingTx = tx }
                        )
                        .padding(.horizontal)
                    } else if subscriptions.isEmpty {
                        emptyState
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Abonnements")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { v in
                        shiftMonth(by: v.translation.width < 0 ? 1 : -1)
                    }
            )
        }
        .sheet(item: $editingTx) { tx in
            AddTransactionView(editingRecurring: tx)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddTransactionView(defaultRecurring: true, defaultSubscription: true)
        }
    }

    private func shiftMonth(by delta: Int) {
        guard let cur     = frCalendar.date(from: DateComponents(year: displayedYear, month: displayedMonth, day: 1)),
              let shifted = frCalendar.date(byAdding: .month, value: delta, to: cur) else { return }
        let c = frCalendar.dateComponents([.year, .month], from: shifted)
        displayedYear  = c.year  ?? displayedYear
        displayedMonth = c.month ?? displayedMonth
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Aucun abonnement")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Ajoutez une transaction récurrente et cochez « Abonnement ».")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - SummaryStrip

private struct SummaryStrip: View {
    let total: Decimal
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            SummaryStat(
                label:    "Ce mois",
                value:    CurrencyFormatter.shared.format(total),
                subtitle: "\(count) abonnement\(count == 1 ? "" : "s")"
            )
            Divider().frame(height: 44)
            SummaryStat(
                label:    "Annuel estimé",
                value:    CurrencyFormatter.shared.format(total * 12),
                subtitle: "projection"
            )
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SummaryStat: View {
    let label:    String
    let value:    String
    let subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
            Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - CalendarCard

private struct CalendarCard: View {
    let monthTitle:      String
    let firstDayOffset:  Int
    let daysInMonth:     Int
    let todayDay:        Int?
    let dayOccurrences:  [Int: [RecurringTransaction]]
    let onPreviousMonth: () -> Void
    let onNextMonth:     () -> Void
    let onTxTap:         (RecurringTransaction) -> Void

    private let columns       = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayLabels = ["D", "L", "Ma", "Me", "J", "V", "S"]

    private var totalCells: Int {
        let raw = firstDayOffset + daysInMonth
        return raw % 7 == 0 ? raw : raw + (7 - raw % 7)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Navigation mois
            HStack {
                Button(action: onPreviousMonth) {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button(action: onNextMonth) {
                    Image(systemName: "chevron.right").fontWeight(.semibold)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)

            // En-têtes jours de semaine
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Grille des jours
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<totalCells, id: \.self) { index in
                    let day: Int? = {
                        guard index >= firstDayOffset else { return nil }
                        let d = index - firstDayOffset + 1
                        return d <= daysInMonth ? d : nil
                    }()
                    DayCell(
                        day:          day,
                        transactions: day.map { dayOccurrences[$0] ?? [] } ?? [],
                        isToday:      day != nil && day == todayDay,
                        onTxTap:      onTxTap
                    )
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - DayCell

private struct DayCell: View {
    let day:          Int?
    let transactions: [RecurringTransaction]
    let isToday:      Bool
    let onTxTap:      (RecurringTransaction) -> Void

    var body: some View {
        if let day = day {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day)")
                    .font(.caption2)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 2)

                Spacer(minLength: 0)

                if !transactions.isEmpty {
                    HStack(spacing: 2) {
                        if transactions.count > 0 {
                            TxBadge(tx: transactions[0])
                                .onTapGesture { onTxTap(transactions[0]) }
                        }
                        if transactions.count > 1 {
                            TxBadge(tx: transactions[1])
                                .onTapGesture { onTxTap(transactions[1]) }
                        }
                        if transactions.count > 2 {
                            Text("+\(transactions.count - 2)")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 48)
            .padding(3)
            .background(isToday ? Color.accentColor.opacity(0.12) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
        } else {
            Color.clear.frame(height: 48)
        }
    }
}

// MARK: - TxBadge

private struct TxBadge: View {
    let tx: RecurringTransaction

    var body: some View {
        Group {
            if !tx.logo.isEmpty {
                SubscriptionLogoImage(logo: tx.logo, size: 16)
            } else {
                Text(String(tx.name.prefix(1)))
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .background(Color.indigo.opacity(0.15))
                    .foregroundStyle(Color.indigo)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - ListSection

private struct ListSection: View {
    let entries:  [(tx: RecurringTransaction, date: Date)]
    let calendar: Calendar
    let onTap:    (RecurringTransaction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                SubscriptionRow(
                    tx:       entry.tx,
                    date:     entry.date,
                    calendar: calendar,
                    onTap:    { onTap(entry.tx) }
                )
                if index < entries.count - 1 {
                    Divider().padding(.leading, 60)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - SubscriptionRow

private struct SubscriptionRow: View {
    let tx:       RecurringTransaction
    let date:     Date
    let calendar: Calendar
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Numéro du jour
                Text("\(calendar.component(.day, from: date))")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)

                // Icône
                Group {
                    if !tx.logo.isEmpty {
                        SubscriptionLogoImage(logo: tx.logo, size: 36)
                    } else {
                        Text(String(tx.name.prefix(2)).uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Color.indigo.opacity(0.12))
                            .foregroundStyle(Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Nom et fréquence
                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(tx.frequency.subLocalizedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Montant et unité
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyFormatter.shared.format(Swift.abs(tx.amount)))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(tx.frequency.subShortLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
