//
//  AccountsView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

struct AccountsView: View {
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Environment(\.modelContext) private var context

    @State private var showingAddAccount = false
    @State private var accountToDelete: Account?
    @State private var showingDeleteAlert = false
    @State private var accountToEdit: Account?

    private var totalBalance: Decimal {
        accounts
            .filter(\.includeInBudget)
            .reduce(Decimal(0)) { $0 + $1.effectiveBalance }
    }

    private var totalAssets: Decimal {
        accounts
            .filter { $0.type.isAsset }
            .reduce(Decimal(0)) { $0 + $1.effectiveBalance }
    }

    private var totalLiabilities: Decimal {
        accounts
            .filter { $0.type.isLiability }
            .reduce(Decimal(0)) { $0 + Swift.abs(min($1.effectiveBalance, 0)) }
    }

    private var deleteConfirmationMessage: String {
        guard let accountToDelete else { return "" }
        return String(
            format: String(localized: "accounts.delete.message"),
            locale: Locale.current,
            accountToDelete.name
        )
    }

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var reordered = accounts
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, account) in reordered.enumerated() {
            account.sortOrder = index
        }
    }

    private var accountsCountTitle: String {
        String(
            format: String(localized: "accounts.list.count"),
            locale: Locale.current,
            accounts.count
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    emptyState
                } else {
                    accountList
                }
            }
            .navigationTitle("accounts.navigation.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView()
            }
            .sheet(item: $accountToEdit) { account in
                EditAccountView(account: account)
            }
            .alert(
                String(localized: "accounts.delete.title"),
                isPresented: $showingDeleteAlert,
                presenting: accountToDelete
            ) { account in
                Button("common.delete", role: .destructive) {
                    context.delete(account)
                    accountToDelete = nil
                }
                Button("common.cancel", role: .cancel) {
                    accountToDelete = nil
                }
            } message: { _ in
                Text(deleteConfirmationMessage)
            }
        }
    }

    // MARK: - Account list

    private var accountList: some View {
        List {
            Section {
                TotalBalanceCard(balance: totalBalance)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                AssetsLiabilitiesCard(assets: totalAssets, liabilities: totalLiabilities)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }

            Section {
                ForEach(accounts) { account in
                    AccountCard(account: account)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                accountToEdit = account
                            } label: {
                                Label("common.edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                accountToDelete = account
                                showingDeleteAlert = true
                            } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                            .tint(.orange)
                        }
                }
                .onMove(perform: moveAccounts)
            } header: {
                Text(accountsCountTitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.indigo.opacity(0.55))

            VStack(spacing: 6) {
                Text("accounts.empty.title")
                    .font(.title3.weight(.semibold))
                Text("accounts.empty.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingAddAccount = true
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TotalBalanceCard

private struct TotalBalanceCard: View {
    let balance: Decimal

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Decorative circle
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 140, height: 140)
                .offset(x: 30, y: 40)

            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 90, height: 90)
                .offset(x: -10, y: 30)

            VStack(alignment: .leading, spacing: 6) {
                Label("accounts.total_balance.title", systemImage: "dollarsign.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))

                Text(CurrencyFormatter.shared.format(balance))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                Text("accounts.total_balance.subtitle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 120)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color(red: 0.5, green: 0.2, blue: 0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .indigo.opacity(0.35), radius: 12, x: 0, y: 4)
    }
}

// MARK: - AssetsLiabilitiesCard

private struct AssetsLiabilitiesCard: View {
    let assets:      Decimal
    let liabilities: Decimal

    var netWorth: Decimal { assets - liabilities }

    var body: some View {
        HStack(spacing: 0) {
            // Actifs
            VStack(alignment: .leading, spacing: 4) {
                Label("Actifs", systemImage: "arrow.up.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.teal)
                Text(CurrencyFormatter.shared.format(assets))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Séparateur vertical
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(width: 0.5, height: 44)
                .padding(.horizontal, 12)

            // Passifs
            VStack(alignment: .trailing, spacing: 4) {
                Label("Passifs", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                Text(liabilities == 0 ? "—" : CurrencyFormatter.shared.format(liabilities))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - AccountCard

private struct AccountCard: View {
    let account: Account

    var body: some View {
        HStack(spacing: 14) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(account.type.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: account.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(account.type.accentColor)
            }

            // Name + type label
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: account.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(account.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Balance
            Text(CurrencyFormatter.shared.format(account.effectiveBalance))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(account.effectiveBalance >= 0 ? Color.indigo : Color.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - AccountType — extensions vue

extension AccountType {
    var isAsset: Bool {
        switch self {
        case .chequing, .savings, .investment: return true
        case .credit, .creditCard, .mortgage:  return false
        }
    }

    var isLiability: Bool { !isAsset }

    var displayName: String {
        switch self {
        case .chequing:   return String(localized: "account.type.chequing")
        case .savings:    return String(localized: "account.type.savings")
        case .credit:     return String(localized: "account.type.credit")
        case .creditCard: return String(localized: "account.type.creditCard")
        case .mortgage:   return String(localized: "account.type.mortgage")
        case .investment: return String(localized: "account.type.investment")
        }
    }

    var accentColor: Color {
        switch self {
        case .chequing:   return .indigo
        case .savings:    return .teal
        case .credit:     return .orange
        case .creditCard: return Color(red: 0.95, green: 0.45, blue: 0.05)
        case .mortgage:   return .purple
        case .investment: return .green
        }
    }

    var labelFR: String {
        switch self {
        case .chequing:   return "Compte chèques"
        case .savings:    return "Épargne"
        case .credit:     return "Crédit"
        case .creditCard: return "Carte de crédit"
        case .mortgage:   return "Hypothèque"
        case .investment: return "Investissement"
        }
    }

    var defaultIcon: String {
        switch self {
        case .chequing:   return "banknote"
        case .savings:    return "building.columns"
        case .credit:     return "creditcard"
        case .creditCard: return "creditcard.fill"
        case .mortgage:   return "house.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Preview

#Preview {
    AccountsView()
        .modelContainer(for: Account.self, inMemory: true)
}
