//
//  RecurringTransactionsView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

// MARK: - RecurringTransactionsView

struct RecurringTransactionsView: View {
    /// Pré-filtre par compte (depuis le détail d'un compte). nil = tous les comptes.
    var filterAccount: Account? = nil

    @Query(sort: \RecurringTransaction.name) private var allRecurring: [RecurringTransaction]
    @Query(sort: \Account.name)              private var accounts:      [Account]
    @Query(sort: \Category.sortOrder)        private var allCategories: [Category]
    @Environment(\.modelContext) private var context

    @State private var selectedAccountId:    UUID?                  = nil  // nil = tous
    @State private var showIncome:           Bool                   = false
    @State private var showingAddRecurring:  Bool                   = false
    @State private var editingTransaction:   RecurringTransaction?  = nil
    @State private var deletingTransaction:  RecurringTransaction?  = nil
    @State private var showingDeleteAlert:   Bool                   = false

    private var filtered: [RecurringTransaction] {
        let effectiveAccountId = filterAccount?.id ?? selectedAccountId
        return allRecurring.filter { tx in
            let matchesAccount = effectiveAccountId == nil || tx.accountId == effectiveAccountId
            let matchesType    = tx.isIncome == showIncome
            return matchesAccount && matchesType
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    showIncome ? "Aucun revenu récurrent" : "Aucune dépense récurrente",
                    systemImage: showIncome ? "arrow.down.circle" : "arrow.up.circle",
                    description: Text("Ajoutez une transaction récurrente via le bouton +.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(filtered) { tx in
                    RecurringTransactionRow(transaction: tx, categories: allCategories)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingTransaction = tx
                            } label: {
                                Label("Modifier", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                deletingTransaction = tx
                                showingDeleteAlert  = true
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                            .tint(.orange)
                        }
                }
            }
        }
        .navigationTitle("Récurrences")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAddRecurring) {
            AddTransactionView(defaultRecurring: true)
        }
        .sheet(item: $editingTransaction) { tx in
            AddTransactionView(editingRecurring: tx)
        }
        .alert(
            "Supprimer la récurrence ?",
            isPresented: $showingDeleteAlert,
            presenting: deletingTransaction
        ) { tx in
            Button("Supprimer", role: .destructive) {
                context.delete(tx)
                deletingTransaction = nil
            }
            Button("Annuler", role: .cancel) {
                deletingTransaction = nil
            }
        } message: { tx in
            Text("« \(tx.name) » sera supprimée. Les transactions passées ne seront pas affectées.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Filtre compte — masqué si on est déjà préfiltré par un compte parent
        if filterAccount == nil {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Tous les comptes") { selectedAccountId = nil }
                    Divider()
                    ForEach(accounts) { acc in
                        Button(acc.name) { selectedAccountId = acc.id }
                    }
                } label: {
                    HStack(spacing: 3) {
                        if let id = selectedAccountId, let acc = accounts.first(where: { $0.id == id }) {
                            Text(acc.name)
                        } else {
                            Text("Tous les comptes")
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingAddRecurring = true
            } label: {
                Image(systemName: "plus")
                    .fontWeight(.semibold)
            }
        }

        // Segmented Revenus / Dépenses
        ToolbarItem(placement: .principal) {
            Picker("Type", selection: $showIncome) {
                Text("Dépenses").tag(false)
                Text("Revenus").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
        }
    }
}

// MARK: - RecurringTransactionRow

private struct RecurringTransactionRow: View {
    let transaction: RecurringTransaction
    let categories:  [Category]

    private var category: Category? {
        guard let id = transaction.categoryId else { return nil }
        return categories.first { $0.id == id }
    }

    private var nextOcc: Date? {
        DateUtils.nextOccurrence(from: transaction, after: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            // Logo abonnement ou icône catégorie
            if !transaction.logo.isEmpty {
                SubscriptionLogoImage(logo: transaction.logo, size: 38)
            } else if let cat = category {
                CategoryIconBadge(icon: cat.icon, color: cat.color, size: 38)
            } else {
                CategoryIconBadge(icon: "square.dashed", color: "#98989D", size: 38)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Ligne 1 : nom + montant
                HStack {
                    Text(transaction.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(abs(transaction.amount)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(transaction.isIncome ? .green : .orange)
                }

                // Ligne 2 : fréquence · prochaine occurrence · badge fin
                HStack(spacing: 6) {
                    Text(transaction.frequency.labelFR)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let next = nextOcc {
                        Text("·")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(next, format: .dateTime.day().month(.abbreviated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let end = transaction.endDate {
                        Spacer()
                        Text("Fin \(end.formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecurringTransactionsView()
    }
    .modelContainer(
        for: [RecurringTransaction.self, Account.self, Category.self],
        inMemory: true
    )
}
