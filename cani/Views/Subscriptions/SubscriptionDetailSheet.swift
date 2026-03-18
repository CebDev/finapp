//
//  SubscriptionDetailSheet.swift
//  cani
//
//  Modale de détail d'un abonnement — design system HomeView / ProjectionView.
//

import SwiftUI
import SwiftData

// MARK: - SubscriptionDetailSheet

struct SubscriptionDetailSheet: View {
    let tx: RecurringTransaction

    @Query private var paidTransactions: [Transaction]
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit              = false
    @State private var showingHistoryDisclaimer = false

    // MARK: - Init (filtre dynamique SwiftData)

    init(tx: RecurringTransaction) {
        self.tx = tx
        let txId = tx.id
        _paidTransactions = Query(filter: #Predicate<Transaction> { t in
            t.recurringTransactionId == txId && t.isPaid
        })
    }

    // MARK: - Computed

    private var monthlyCost: Decimal { tx.frequency.normalizedMonthlyCost(amount: tx.amount) }
    private var annualCost:  Decimal { monthlyCost * 12 }

    private var totalPaidSinceStart: Decimal {
        paidTransactions.reduce(.zero) { $0 + Swift.abs($1.amount) }
    }

    private var upcomingOccurrences: [Date] {
        var result: [Date] = []
        let cal    = Calendar.current
        let now    = Date()
        var cursor = cal.startOfDay(for: now)
        for _ in 0..<6 {
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            let dates = ProjectionEngine.occurrences(of: tx, from: cursor, to: next, calendar: cal)
            result.append(contentsOf: dates.filter { $0 >= now })
            cursor = next
        }
        return Array(result.prefix(10))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerCard
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    statsSection

                    upcomingSection

                    cancelSection
                }
                .padding(.bottom, 36)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEdit = true } label: {
                        Image(systemName: "pencil")
                            .font(.body.weight(.medium))
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddTransactionView(editingRecurring: tx)
        }
    }

    // MARK: - Header card (pattern ProjectionView.headerCard)

    private var headerCard: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.25, blue: 0.90),
                            Color(red: 0.52, green: 0.18, blue: 0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Cercles décoratifs identiques à HomeView/ProjectionView
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 160)
                .offset(x: 30, y: 50)
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 80)
                .offset(x: -20, y: 20)

            // Contenu
            HStack(alignment: .center, spacing: 16) {
                // Logo / initiales
                Group {
                    if !tx.logo.isEmpty {
                        SubscriptionLogoImage(logo: tx.logo, size: 52)
                    } else {
                        Text(String(tx.name.prefix(2)).uppercased())
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.18))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    if !tx.isActive {
                        Text("Suspendu")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.20))
                            .clipShape(Capsule())
                    }
                    Text(tx.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(tx.frequency.subLocalizedLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                // Coût mensuel mis en avant (comme le solde dans ProjectionView)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyFormatter.shared.format(monthlyCost))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    Text("/ mois")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 130)
        .shadow(
            color: Color(red: 0.30, green: 0.25, blue: 0.90).opacity(0.40),
            radius: 18, x: 0, y: 6
        )
    }

    // MARK: - Stats (2 cartes — pattern CompactAccountCard de HomeView)

    private var statsSection: some View {
        HStack(spacing: 12) {
            // Annuel
            SubStatCard(
                label: "Annuel estimé",
                value: CurrencyFormatter.shared.format(annualCost),
                icon:  "chart.bar.fill",
                color: .purple
            )

            // Depuis le début avec tooltip
            Button { showingHistoryDisclaimer = true } label: {
                SubStatCard(
                    label:   "Depuis le début",
                    value:   CurrencyFormatter.shared.format(totalPaidSinceStart),
                    icon:    "clock.fill",
                    color:   .teal,
                    hasInfo: true
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingHistoryDisclaimer) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.teal)
                        Text("Historique enregistré")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("Ce montant correspond uniquement aux transactions marquées comme payées dans l'app. Il ne reflète pas les paiements effectués avant l'utilisation de CanI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(width: 280)
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Upcoming (pattern recentOperationsSection de HomeView)

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Prochains prélèvements")
                .font(.headline)
                .padding(.leading, 16)
                .padding(.bottom, 10)

            if upcomingOccurrences.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: tx.endDate != nil ? "checkmark.circle.fill" : "calendar.badge.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(tx.endDate != nil ? Color.green.opacity(0.7) : Color.secondary.opacity(0.4))
                    Text(tx.endDate != nil ? "Abonnement terminé" : "Aucune occurrence à venir")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                .padding(.horizontal, 16)

            } else {
                // ~3,5 lignes visibles (chaque ligne ≈ 60 pt)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(upcomingOccurrences.enumerated()), id: \.offset) { idx, date in
                            UpcomingOccurrenceRow(
                                date:   date,
                                amount: tx.amount,
                                isNext: idx == 0
                            )
                            if idx < upcomingOccurrences.count - 1 {
                                Divider()
                                    .padding(.leading, 68)
                            }
                        }
                    }
                }
                .frame(height: 216)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Cancel (non actif — même style que les sections de HomeView)

    private var cancelSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 38, height: 38)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.35))
            }

            Text("Résilier cet abonnement")
                .font(.body)
                .foregroundStyle(Color.secondary.opacity(0.40))

            Spacer()

            Text("Bientôt disponible")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
    }
}

// MARK: - SubStatCard (pattern CompactAccountCard de HomeView)

private struct SubStatCard: View {
    let label:   String
    let value:   String
    let icon:    String
    let color:   Color
    var hasInfo: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(color)
                }

                Spacer()

                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.bottom, 2)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110, alignment: .leading)

            if hasInfo {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(color.opacity(0.60))
                    .padding(9)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
        )
    }
}

// MARK: - UpcomingOccurrenceRow (pattern recentTransactionRow de HomeView)

private struct UpcomingOccurrenceRow: View {
    let date:   Date
    let amount: Decimal
    let isNext: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: date)
            .replacingOccurrences(of: ".", with: "")
            .capitalized
    }

    private var daysUntil: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
            from: cal.startOfDay(for: Date()),
            to:   cal.startOfDay(for: date)
        ).day ?? 0
    }

    private var daysLabel: String {
        switch daysUntil {
        case 0:  return "Aujourd'hui"
        case 1:  return "Demain"
        default: return "Dans \(daysUntil) jours"
        }
    }

    private var amberColor: Color { Color(red: 1.0, green: 0.7, blue: 0.0) }

    var body: some View {
        HStack(spacing: 12) {
            // Icône badge — identique à recentTransactionRow (38×38, cornerRadius 10)
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isNext ? Color.indigo.opacity(0.12) : Color.secondary.opacity(0.10))
                    .frame(width: 38, height: 38)
                if isNext {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.indigo)
                } else {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(daysLabel)
                    .font(.caption)
                    .foregroundStyle(isNext ? .indigo : .secondary)
            }

            Spacer()

            Text("−\(CurrencyFormatter.shared.format(Swift.abs(amount)))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(amberColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(.systemBackground))
    }
}
