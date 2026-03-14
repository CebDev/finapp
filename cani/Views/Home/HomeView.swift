//
//  HomeView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Account.sortOrder)         private var accounts:      [Account]
    @Query(sort: \RecurringTransaction.name) private var recurring:     [RecurringTransaction]
    @Query(sort: \Category.sortOrder)        private var allCategories: [Category]
    @Query                                   private var settingsArray: [UserSettings]
    @Query                                   private var allOverrides:  [TransactionOverride]
    @Query(
        filter: #Predicate<Transaction> { $0.isPast },
        sort:   \Transaction.date,
        order:  .reverse
    )                                        private var allPastTransactions: [Transaction]

    @AppStorage("selectedTab") private var selectedTab: Int = 0

    @State private var showingAccounts      = false
    @State private var showingSettings      = false
    @State private var settingsDestination: SettingsDestination? = nil
    @State private var heroAppeared         = false
    @State private var selectedPeriod:      PayPeriod? = nil
    @State private var showingOpMenu        = false
    @State private var menuTargetOp:        UpcomingOperation? = nil
    @State private var editingRecurring:    RecurringTransaction? = nil
    @State private var editingOccurrence:   RecurringTransaction? = nil
    @State private var editingOccDate:      Date = Date()
    @State private var markingAsPaid:       RecurringTransaction? = nil
    @State private var markingAsPaidDate:   Date = Date()
    @State private var selectedAccount:     Account? = nil

    // MARK: - Computed

    private var totalBalance: Decimal {
        accounts.filter(\.includeInBudget).reduce(0) { $0 + $1.effectiveBalance }
    }

    private var budgetAccountCount: Int { accounts.filter(\.includeInBudget).count }
    private var positiveAccountCount: Int { accounts.filter { $0.effectiveBalance > 0 }.count }

    private var settings: UserSettings? { settingsArray.first }

    /// 5 périodes à partir de la période courante (pour chart + cards).
    private var allPeriods: [PayPeriod] {
        guard let s = settings else { return [] }
        return PeriodEngine.generate(
            settings:     s,
            accounts:     accounts,
            recurring:    recurring,
            count:        5,
            overrides:    allOverrides,
            transactions: allPastTransactions
        )
    }

    /// Période courante + 2 suivantes, max 3.
    private var upcomingPeriods: [PayPeriod] {
        let idx = allPeriods.firstIndex(where: \.isCurrentPeriod) ?? 0
        let end = min(idx + 3, allPeriods.count)
        return Array(allPeriods[idx..<end])
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heroCard
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    accountsSection

                    if !allPeriods.isEmpty {
                        evolutionSection
                        upcomingPeriodsSection
                    }

                    if !recentTransactions.isEmpty {
                        recentOperationsSection
                    }

                    upcomingOperationsSection
                }
                .padding(.bottom, 36)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("home.navigation.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingAccounts = true
                        } label: {
                            Label("home.menu.manage_accounts", systemImage: "creditcard")
                        }

                        Button {
                            settingsDestination = .categories
                            showingSettings = true
                        } label: {
                            Label("home.menu.categories", systemImage: "tag")
                        }

                        Divider()

                        Button {
                            settingsDestination = .payPeriod
                            showingSettings = true
                        } label: {
                            Label("Période de paie", systemImage: "calendar.badge.clock")
                        }

                        Button {
                            settingsDestination = .general
                            showingSettings = true
                        } label: {
                            Label("home.menu.settings", systemImage: "slider.horizontal.3")
                        }

                        Button {
                            settingsDestination = .profile
                            showingSettings = true
                        } label: {
                            Label("home.menu.profile", systemImage: "person.circle")
                        }
                    } label: {
                        Image(systemName: "gear")
                            .fontWeight(.medium)
                    }
                }
            }
            .sheet(isPresented: $showingAccounts) {
                AccountsView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(initialDestination: settingsDestination)
            }
            .sheet(item: $selectedPeriod) { period in
                PeriodDetailSheet(
                    period:              period,
                    allPeriods:          allPeriods,
                    carryForwardBalance: settings?.carryForwardBalance ?? true,
                    tightThreshold:      settings?.tightThreshold ?? 500
                )
            }
            .confirmationDialog(
                menuTargetOp?.name ?? "",
                isPresented: $showingOpMenu,
                titleVisibility: .visible
            ) {
                Button("Modifier toutes les occurrences à venir") {
                    editingRecurring = menuTargetOp?.recurringTransaction
                    menuTargetOp     = nil
                }
                Button("Modifier uniquement cette occurrence") {
                    if let op = menuTargetOp {
                        editingOccDate   = op.date
                        editingOccurrence = op.recurringTransaction
                    }
                    menuTargetOp = nil
                }
                Divider()
                Button("Marquer comme payé") {
                    if let op = menuTargetOp {
                        markingAsPaidDate = op.date
                        markingAsPaid     = op.recurringTransaction
                    }
                    menuTargetOp = nil
                }
                Button("Annuler", role: .cancel) {
                    menuTargetOp = nil
                }
            }
            .sheet(item: $editingRecurring) { tx in
                AddTransactionView(editingRecurring: tx)
            }
            .sheet(item: $editingOccurrence) { tx in
                AddTransactionView(
                    editingOccurrenceRecurring: tx,
                    editingOccurrenceDate: editingOccDate
                )
            }
            .sheet(item: $markingAsPaid) { tx in
                MarkAsPaidSheet(transaction: tx, occurrenceDate: markingAsPaidDate)
            }
            .sheet(item: $selectedAccount) { account in
                AccountTransactionsSheet(account: account, categories: allCategories)
            }
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.15)) {
                    heroAppeared = true
                }
            }
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 24)
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

            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.07))
                        .frame(width: 200)
                        .offset(x: geo.size.width - 60, y: -60)

                    Circle()
                        .fill(.white.opacity(0.05))
                        .frame(width: 110)
                        .offset(x: geo.size.width - 110, y: geo.size.height - 20)

                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(.white.opacity(0.12))
                            .frame(width: CGFloat(4 + i * 2))
                            .offset(
                                x: CGFloat(20 + i * 18),
                                y: geo.size.height - CGFloat(16 + i * 8)
                            )
                    }
                }
            }
            .clipped()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                    Text("home.hero.total_balance")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Text(CurrencyFormatter.shared.format(totalBalance))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .opacity(heroAppeared ? 1 : 0)
                    .offset(y: heroAppeared ? 0 : 12)

                if !accounts.isEmpty {
                    HStack(spacing: 10) {
                        HeroPill(icon: "building.2",       value: "\(budgetAccountCount)",  labelKey: "home.hero.in_budget")
                        HeroPill(icon: "arrow.up.circle",  value: "\(positiveAccountCount)", labelKey: "home.hero.positive")
                    }
                    .opacity(heroAppeared ? 1 : 0)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 175)
        .shadow(color: Color(red: 0.30, green: 0.25, blue: 0.90).opacity(0.45), radius: 18, x: 0, y: 6)
    }

    // MARK: - Accounts section

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("accounts.navigation.title")
                    .font(.headline)
                    .padding(.leading, 16)

                Spacer()

                if !accounts.isEmpty {
                    Button("home.accounts.see_all") { showingAccounts = true }
                        .font(.subheadline)
                        .foregroundStyle(.indigo)
                        .padding(.trailing, 16)
                }
            }

            if accounts.isEmpty {
                emptyAccountsView
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                            CompactAccountCard(account: account)
                                .opacity(heroAppeared ? 1 : 0)
                                .offset(y: heroAppeared ? 0 : 16)
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(0.25 + Double(index) * 0.06),
                                    value: heroAppeared
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 18))
                                .onTapGesture { selectedAccount = account }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Évolution section

    private var evolutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Évolution")
                    .font(.headline)
                    .padding(.leading, 16)

                Spacer()

                Button("Voir tout →") { selectedTab = 1 }
                    .font(.subheadline)
                    .foregroundStyle(.indigo)
                    .padding(.trailing, 16)
            }

            BalanceChartView(
                periods:        allPeriods,
                showFullYear:   false,
                tightThreshold: settings?.tightThreshold ?? 500
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Prochaines périodes section

    private var upcomingPeriodsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Prochaines périodes")
                .font(.headline)
                .padding(.leading, 16)
                .padding(.bottom, 8)

            let carryForward = settings?.carryForwardBalance ?? true
            let maxBal: Decimal = carryForward
                ? (upcomingPeriods.map(\.projectedBalance).max() ?? 1)
                : (upcomingPeriods.map { abs($0.delta) }.max() ?? 1)
            ForEach(upcomingPeriods) { period in
                PayPeriodCard(
                    period:              period,
                    maxBalance:          maxBal,
                    onTap:               { selectedPeriod = period },
                    carryForwardBalance: carryForward
                )
            }
        }
    }

    // MARK: - Dernières opérations section

    private var recentTransactions: [Transaction] {
        Array(allPastTransactions.prefix(5))
    }

    private var recentOperationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Dernières opérations")
                .font(.headline)
                .padding(.leading, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(recentTransactions) { tx in
                    recentTransactionRow(tx)
                    if tx.id != recentTransactions.last?.id {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
        }
    }

    private func recentTransactionRow(_ tx: Transaction) -> some View {
        let isIncome   = tx.amount > 0
        let isTransfer = tx.isTransfer
        let cat        = tx.categoryId.flatMap { id in allCategories.first { $0.id == id } }
        let label      = recentTransactionLabel(tx)
        let accountName = accounts.first(where: { $0.id == tx.accountId })?.name ?? ""

        return HStack(spacing: 12) {
            // Icône
            if isTransfer {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.indigo.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.indigo)
                }
            } else if let cat {
                CategoryIconBadge(icon: cat.icon, color: cat.color, size: 38)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.10))
                        .frame(width: 38, height: 38)
                    Image(systemName: isIncome ? "arrow.down.circle" : "arrow.up.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isIncome ? Color.green : amberColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(shortDate(tx.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !accountName.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text(accountName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if isTransfer {
                Text(CurrencyFormatter.shared.format(abs(tx.amount)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
            } else {
                Text((isIncome ? "+" : "−") + CurrencyFormatter.shared.format(abs(tx.amount)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isIncome ? Color.green : amberColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(.systemBackground))
    }

    private func recentTransactionLabel(_ tx: Transaction) -> String {
        if tx.isTransfer {
            let destName = tx.transferDestinationAccountId
                .flatMap { id in accounts.first { $0.id == id } }?.name
            return destName.map { "Transfert → \($0)" } ?? "Transfert"
        }
        if let recurId = tx.recurringTransactionId,
           let recurring = recurring.first(where: { $0.id == recurId }) {
            return recurring.name
        }
        if let notes = tx.notes, !notes.isEmpty { return notes }
        if let cat = tx.categoryId.flatMap({ id in allCategories.first { $0.id == id } }) { return cat.name }
        return tx.amount > 0 ? "Revenu" : "Dépense"
    }

    private static let recentDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return f
    }()

    private func shortDate(_ date: Date) -> String {
        Self.recentDateFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private var amberColor: Color { Color(red: 1.0, green: 0.7, blue: 0.0) }

    // MARK: - Prochaines opérations section

    private var upcomingOperationsSection: some View {
        let ops = UpcomingOperationsService.next(
            5,
            from: recurring,
            categories: allCategories,
            overrides: allOverrides
        )
        return VStack(alignment: .leading, spacing: 0) {
            Text("Prochaines opérations")
                .font(.headline)
                .padding(.leading, 16)
                .padding(.bottom, 8)

            if ops.isEmpty {
                Text("Aucune opération planifiée")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(ops) { op in
                        UpcomingOperationRow(operation: op)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                menuTargetOp  = op
                                showingOpMenu = true
                            }
                        if op.id != ops.last?.id {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Empty accounts state

    private var emptyAccountsView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.indigo.opacity(0.15), .purple.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 6) {
                Text("home.empty.title")
                    .font(.headline)
                Text("home.empty.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingAccounts = true
            } label: {
                Label("accounts.add.button", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(.indigo)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Hero stat pill

private struct HeroPill: View {
    let icon: String
    let value: String
    let labelKey: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            Text(LocalizedStringKey(labelKey))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.14))
        .clipShape(Capsule())
    }
}

// MARK: - Compact account card

private struct CompactAccountCard: View {
    let account: Account
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    // Plus d'opacité en dark pour que l'icône ressorte du fond sombre
                    .fill(account.type.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: account.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(account.type.accentColor)
            }

            Spacer()

            Text(verbatim: account.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.bottom, 2)

            Text(CurrencyFormatter.shared.format(account.effectiveBalance))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(account.effectiveBalance >= 0 ? Color.primary : Color.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(width: 145, height: 118)
        .background(
            RoundedRectangle(cornerRadius: 18)
                // secondarySystemGroupedBackground = blanc en light, #1C1C1E en dark
                // — couleur sémantique correcte pour une carte sur fond groupé
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(
                    color: colorScheme == .dark
                        ? .clear
                        : .black.opacity(0.07),
                    radius: 10, x: 0, y: 3
                )
        )
        // Contour subtil en dark mode pour remplacer visuellement l'ombre
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .modelContainer(
            for: [Account.self, RecurringTransaction.self, UserSettings.self, Category.self],
            inMemory: true
        )
}
