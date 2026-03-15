//
//  ProjectionView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

struct ProjectionView: View {
    @Query(sort: \Account.sortOrder)         private var accounts:         [Account]
    @Query(sort: \RecurringTransaction.name) private var recurring:        [RecurringTransaction]
    @Query                                   private var settingsArray:    [UserSettings]
    @Query                                   private var allOverrides:     [TransactionOverride]
    @Query(
        filter: #Predicate<Transaction> { $0.isPaid },
        sort:   \Transaction.date
    )                                        private var allTransactions:  [Transaction]

    @State private var showTightOnly:             Bool       = false
    @State private var selectedPeriod:            PayPeriod? = nil
    @State private var showingSetupConfirmation:  Bool       = false
    @State private var showingPeriodSetup:        Bool       = false

    // MARK: - Computed

    private var settings: UserSettings? { settingsArray.first }

    private var totalBalance: Decimal {
        accounts.filter(\.includeInBudget).reduce(0) { $0 + $1.effectiveBalance }
    }

    private var allPeriods: [PayPeriod] {
        guard let s = settings else { return [] }
        return PeriodEngine.generate(
            settings:          s,
            accounts:          accounts,
            recurring:         recurring,
            count:             13,
            overrides:         allOverrides,
            transactions:      allTransactions,
            dailySamplingStep: 2
        )
    }

    private var filteredPeriods: [PayPeriod] {
        showTightOnly ? allPeriods.filter(\.isTight) : allPeriods
    }

    private var currentPeriod: PayPeriod? { allPeriods.first(where: \.isCurrentPeriod) }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if settings == nil {
                    notConfiguredState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            headerCard
                                .padding(.horizontal, 16)
                                .padding(.top, 4)

                            chartSection

                            if filteredPeriods.isEmpty {
                                emptyTightState
                            } else {
                                periodsSection
                            }
                        }
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Projection")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if settings != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showTightOnly.toggle() } label: {
                            Image(systemName: showTightOnly
                                  ? "exclamationmark.triangle.fill"
                                  : "exclamationmark.triangle")
                                .fontWeight(.medium)
                                .foregroundStyle(showTightOnly
                                                 ? Color(red: 1.0, green: 0.7, blue: 0.0)
                                                 : Color.primary)
                        }
                        .accessibilityLabel("Serrées seulement")
                    }
                }
            }
            .sheet(item: $selectedPeriod) { period in
                PeriodDetailSheet(
                    period:              period,
                    allPeriods:          allPeriods,
                    carryForwardBalance: settings?.carryForwardBalance ?? true,
                    tightThreshold:      settings?.tightThreshold ?? 500
                )
            }
            .sheet(isPresented: $showingPeriodSetup) {
                PeriodSetupSheet()
            }
            .confirmationDialog(
                "Avez-vous créé tous les comptes à suivre avec leur solde initial ?",
                isPresented: $showingSetupConfirmation,
                titleVisibility: .visible
            ) {
                Button("Oui, configurer les périodes") {
                    showingPeriodSetup = true
                }
                Button("Pas encore", role: .cancel) { }
            } message: {
                Text("Les périodes seront calculées à partir des soldes actuels de vos comptes.")
            }
        }
    }

    // MARK: - Not configured state

    private var notConfiguredState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.10))
                        .frame(width: 96, height: 96)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.indigo)
                }

                VStack(spacing: 8) {
                    Text("Projection non configurée")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Ajoutez vos comptes avec leur solde réel, puis générez les périodes pour visualiser votre projection financière.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    showingSetupConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Générer les périodes")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 28)
                    .background(Color.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header card

    private var headerCard: some View {
        ZStack(alignment: .bottomTrailing) {
            // Gradient de fond
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.25, blue: 0.90),
                            Color(red: 0.52, green: 0.18, blue: 0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint:   .bottomTrailing
                    )
                )

            // Cercles décoratifs
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 160)
                .offset(x: 30, y: 50)

            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 80)
                .offset(x: -20, y: 20)

            // Contenu
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                    Text("Solde actuel")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Text(CurrencyFormatter.shared.format(totalBalance))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)

                if let period = currentPeriod {
                    Text("Période en cours : \(shortDate(period.startDate)) — \(shortDate(period.endDate))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.70))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 155)
        .shadow(
            color: Color(red: 0.30, green: 0.25, blue: 0.90).opacity(0.40),
            radius: 18, x: 0, y: 6
        )
    }

    // MARK: - Chart section

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Évolution sur 12 mois")
                .font(.headline)
                .padding(.horizontal, 16)

            if allPeriods.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 220)
                    .padding(.horizontal, 16)
            } else {
                BalanceChartView(
                    periods:        allPeriods,
                    showFullYear:   true,
                    tightThreshold: settings?.tightThreshold ?? 500
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Periods list

    private var periodsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(showTightOnly ? "Périodes serrées" : "Toutes les périodes")
                    .font(.headline)

                Spacer()

                Text("\(filteredPeriods.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.10))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            let carryForward = settings?.carryForwardBalance ?? true
            let maxBal: Decimal = carryForward
                ? (allPeriods.map(\.projectedBalance).max() ?? 1)
                : (allPeriods.map { abs($0.delta) }.max() ?? 1)
            ForEach(filteredPeriods) { period in
                PayPeriodCard(
                    period:              period,
                    maxBalance:          maxBal,
                    onTap:               { selectedPeriod = period },
                    carryForwardBalance: carryForward
                )
            }
        }
    }

    // MARK: - Empty tight state

    private var emptyTightState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green.opacity(0.7))
            Text("Aucune période serrée")
                .font(.headline)
            Text("Toutes vos périodes sont confortables.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return f
    }()

    private func shortDate(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
            .replacingOccurrences(of: ".", with: "")
    }
}

// MARK: - Preview

#Preview {
    ProjectionView()
        .modelContainer(
            for: [Account.self, RecurringTransaction.self, UserSettings.self, Category.self],
            inMemory: true
        )
}
