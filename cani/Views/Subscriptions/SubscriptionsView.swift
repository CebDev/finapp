//
//  SubscriptionsView.swift
//  cani
//

import SwiftUI
import SwiftData

// MARK: - Color(hex:) extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - SubscriptionsView

struct SubscriptionsView: View {
    @Query(filter: #Predicate<Subscription> { $0.isActive }, sort: \Subscription.name)
    private var subscriptions: [Subscription]

    @State private var displayedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var displayedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var editingSubscription: Subscription? = nil
    @State private var showingAddSheet = false

    private var frCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "fr_CA")
        return cal
    }

    // Occurrences par jour pour le mois affiché
    private var daySubscriptions: [Int: [(Subscription, Date)]] {
        var result: [Int: [(Subscription, Date)]] = [:]
        for sub in subscriptions {
            for date in sub.occurrences(inYear: displayedYear, month: displayedMonth) {
                let day = frCalendar.component(.day, from: date)
                result[day, default: []].append((sub, date))
            }
        }
        return result
    }

    // Liste triée par date pour la section liste
    private var listEntries: [(sub: Subscription, date: Date)] {
        var entries: [(sub: Subscription, date: Date)] = []
        for sub in subscriptions {
            for date in sub.occurrences(inYear: displayedYear, month: displayedMonth) {
                entries.append((sub: sub, date: date))
            }
        }
        return entries.sorted { $0.date < $1.date }
    }

    // Titre du mois affiché
    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.dateFormat = "MMMM yyyy"
        guard let date = frCalendar.date(from: DateComponents(year: displayedYear, month: displayedMonth, day: 1)) else { return "" }
        return fmt.string(from: date).capitalized
    }

    // Jour de la semaine du 1er du mois (0 = Dim, 6 = Sam)
    private var firstWeekdayOffset: Int {
        guard let firstDay = frCalendar.date(from: DateComponents(year: displayedYear, month: displayedMonth, day: 1)) else { return 0 }
        return frCalendar.component(.weekday, from: firstDay) - 1
    }

    // Nombre de jours dans le mois affiché
    private var daysInMonth: Int {
        guard let firstDay = frCalendar.date(from: DateComponents(year: displayedYear, month: displayedMonth, day: 1)),
              let range = frCalendar.range(of: .day, in: .month, for: firstDay) else { return 30 }
        return range.count
    }

    // Aujourd'hui est-il dans le mois affiché?
    private var todayDay: Int? {
        let now = Date()
        let comps = frCalendar.dateComponents([.year, .month, .day], from: now)
        guard comps.year == displayedYear, comps.month == displayedMonth else { return nil }
        return comps.day
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SummaryStrip(subscriptions: subscriptions)
                        .padding(.horizontal)

                    CalendarCard(
                        monthTitle: monthTitle,
                        firstWeekdayOffset: firstWeekdayOffset,
                        daysInMonth: daysInMonth,
                        todayDay: todayDay,
                        daySubscriptions: daySubscriptions,
                        onPreviousMonth: { shiftMonth(by: -1) },
                        onNextMonth: { shiftMonth(by: 1) },
                        onSubscriptionTap: { sub in editingSubscription = sub }
                    )
                    .padding(.horizontal)

                    if !listEntries.isEmpty {
                        ListSection(
                            entries: listEntries,
                            onTap: { sub in editingSubscription = sub }
                        )
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Abonnements")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        if value.translation.width < 0 { shiftMonth(by: 1) }
                        else { shiftMonth(by: -1) }
                    }
            )
        }
        .sheet(item: $editingSubscription) { sub in
            SubscriptionEditSheet(subscription: sub)
        }
        .sheet(isPresented: $showingAddSheet) {
            SubscriptionEditSheet(subscription: nil)
        }
    }

    private func shiftMonth(by delta: Int) {
        guard let current = frCalendar.date(from: DateComponents(year: displayedYear, month: displayedMonth, day: 1)),
              let shifted = frCalendar.date(byAdding: .month, value: delta, to: current) else { return }
        let comps = frCalendar.dateComponents([.year, .month], from: shifted)
        displayedYear = comps.year ?? displayedYear
        displayedMonth = comps.month ?? displayedMonth
    }
}

// MARK: - SummaryStrip

private struct SummaryStrip: View {
    let subscriptions: [Subscription]

    private var totalMonthly: Decimal {
        subscriptions.reduce(.zero) { $0 + $1.normalizedMonthlyCost }
    }

    var body: some View {
        HStack(spacing: 0) {
            SummaryStat(
                label: "Ce mois",
                value: CurrencyFormatter.shared.format(totalMonthly),
                subtitle: "normalisé"
            )
            Divider().frame(height: 44)
            SummaryStat(
                label: "Annuel estimé",
                value: CurrencyFormatter.shared.format(totalMonthly * 12),
                subtitle: "projection"
            )
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SummaryStat: View {
    let label: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - CalendarCard

private struct CalendarCard: View {
    let monthTitle: String
    let firstWeekdayOffset: Int
    let daysInMonth: Int
    let todayDay: Int?
    let daySubscriptions: [Int: [(Subscription, Date)]]
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onSubscriptionTap: (Subscription) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayLabels = ["D", "L", "M", "M", "J", "V", "S"]

    // Total cells = offset + jours du mois, arrondi au multiple de 7 supérieur
    private var totalCells: Int {
        let raw = firstWeekdayOffset + daysInMonth
        return raw % 7 == 0 ? raw : raw + (7 - raw % 7)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Navigation mois
            HStack {
                Button(action: onPreviousMonth) {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text(monthTitle)
                    .font(.headline)
                Spacer()
                Button(action: onNextMonth) {
                    Image(systemName: "chevron.right")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 4)

            // En-têtes jours de la semaine
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
                    let day: Int? = index < firstWeekdayOffset ? nil : {
                        let d = index - firstWeekdayOffset + 1
                        return d <= daysInMonth ? d : nil
                    }()

                    DayCell(
                        day: day,
                        subscriptions: day.map { daySubscriptions[$0] ?? [] } ?? [],
                        isToday: day != nil && day == todayDay,
                        onSubscriptionTap: onSubscriptionTap
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
    let day: Int?
    let subscriptions: [(Subscription, Date)]
    let isToday: Bool
    let onSubscriptionTap: (Subscription) -> Void

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

                if !subscriptions.isEmpty {
                    HStack(spacing: 2) {
                        if subscriptions.count > 0 {
                            SubscriptionBadge(sub: subscriptions[0].0)
                                .onTapGesture { onSubscriptionTap(subscriptions[0].0) }
                        }
                        if subscriptions.count > 1 {
                            SubscriptionBadge(sub: subscriptions[1].0)
                                .onTapGesture { onSubscriptionTap(subscriptions[1].0) }
                        }
                        if subscriptions.count > 2 {
                            Text("+\(subscriptions.count - 2)")
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

// MARK: - SubscriptionBadge

private struct SubscriptionBadge: View {
    let sub: Subscription

    var body: some View {
        Text(String((sub.iconInitials.isEmpty ? sub.name : sub.iconInitials).prefix(1)))
            .font(.system(size: 9, weight: .semibold))
            .frame(width: 16, height: 16)
            .background(Color(hex: sub.colorHex).opacity(0.15))
            .foregroundStyle(Color(hex: sub.colorHex))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - ListSection

private struct ListSection: View {
    let entries: [(sub: Subscription, date: Date)]
    let onTap: (Subscription) -> Void

    private var frCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "fr_CA")
        return cal
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                SubscriptionListRow(
                    sub: entry.sub,
                    date: entry.date,
                    calendar: frCalendar,
                    onTap: { onTap(entry.sub) }
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

// MARK: - SubscriptionListRow

private struct SubscriptionListRow: View {
    let sub: Subscription
    let date: Date
    let calendar: Calendar
    let onTap: () -> Void

    private var dayNumber: Int {
        calendar.component(.day, from: date)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Numéro du jour
                Text("\(dayNumber)")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)

                // Icône
                Text(String((sub.iconInitials.isEmpty ? sub.name : sub.iconInitials).prefix(2)))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: sub.colorHex).opacity(0.15))
                    .foregroundStyle(Color(hex: sub.colorHex))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Nom et fréquence
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(sub.frequency.localizedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Montant et unité
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyFormatter.shared.format(sub.amount))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(sub.frequency.shortLabel)
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
