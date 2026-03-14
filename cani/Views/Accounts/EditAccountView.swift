//
//  EditAccountView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

struct EditAccountView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var name: String
    @State private var type: AccountType
    @State private var balanceText: String
    @State private var selectedIcon: String
    @State private var iconManuallySelected: Bool
    @State private var includeInBudget: Bool
    @State private var creditLimitText: String
    @State private var balanceDisplayMode: CreditBalanceDisplayMode
    @State private var balanceInvalid = false

    init(account: Account) {
        self.account = account
        _name = State(initialValue: account.name)
        _type = State(initialValue: account.type)
        _balanceText = State(initialValue: "\(account.currentBalance)")
        _selectedIcon = State(initialValue: account.icon)
        _iconManuallySelected = State(initialValue: true)
        _includeInBudget = State(initialValue: account.includeInBudget)
        _creditLimitText = State(initialValue: account.creditLimit.map { "\($0)" } ?? "")
        _balanceDisplayMode = State(initialValue: account.creditBalanceDisplayMode)
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        parseDecimal(balanceText) != nil &&
        (type != .creditCard || parseDecimal(creditLimitText) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Informations générales
                Section(String(localized: "add_account.section.information")) {
                    TextField(String(localized: "add_account.name.placeholder"), text: $name)
                        .autocorrectionDisabled()

                    Picker(String(localized: "add_account.type.label"), selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .onChange(of: type) { _, newType in
                        if !iconManuallySelected {
                            selectedIcon = newType.defaultIcon
                        }
                    }
                }

                // MARK: Solde actuel
                Section {
                    HStack {
                        TextField(String(localized: "common.amount_placeholder"), text: $balanceText)
                            .keyboardType(.decimalPad)
                            .onChange(of: balanceText) { _, _ in
                                balanceInvalid = false
                            }
                        Text("common.currency_symbol")
                            .foregroundStyle(.secondary)
                    }

                    if balanceInvalid {
                        Label("add_account.balance.invalid", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("add_account.balance.title")
                } footer: {
                    Text("add_account.balance.footer")
                        .font(.caption)
                }

                // MARK: Limite de crédit — type credit (existant)
                if type == .credit {
                    Section("add_account.credit_limit.title") {
                        HStack {
                            TextField(String(localized: "common.amount_placeholder"), text: $creditLimitText)
                                .keyboardType(.decimalPad)
                            Text("common.currency_symbol")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: Carte de crédit — limite (obligatoire) + mode d'affichage
                if type == .creditCard {
                    Section {
                        HStack {
                            TextField(String(localized: "common.amount_placeholder"), text: $creditLimitText)
                                .keyboardType(.decimalPad)
                            Text("common.currency_symbol")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("add_account.credit_limit.title")
                    } footer: {
                        Text("add_account.credit_limit.required_footer")
                            .font(.caption)
                    }

                    Section("add_account.balance_mode.section") {
                        ForEach(CreditBalanceDisplayMode.allCases, id: \.self) { mode in
                            Button {
                                balanceDisplayMode = mode
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: balanceDisplayMode == mode
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .foregroundStyle(balanceDisplayMode == mode ? Color.indigo : .secondary)
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LocalizedStringKey(mode.localizationKey))
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text(LocalizedStringKey(mode.descriptionKey))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // MARK: Icône
                Section("add_account.icon.section") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                        spacing: 10
                    ) {
                        ForEach(availableIcons, id: \.symbol) { item in
                            Button {
                                selectedIcon = item.symbol
                                iconManuallySelected = true
                            } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 11)
                                            .fill(
                                                selectedIcon == item.symbol
                                                    ? type.accentColor
                                                    : Color(.secondarySystemBackground)
                                            )
                                            .frame(height: 50)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 11)
                                                    .strokeBorder(
                                                        selectedIcon == item.symbol
                                                            ? type.accentColor
                                                            : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )
                                        Image(systemName: item.symbol)
                                            .font(.system(size: 20))
                                            .foregroundStyle(
                                                selectedIcon == item.symbol
                                                    ? .white
                                                    : type.accentColor
                                            )
                                    }
                                    Text(LocalizedStringKey(item.labelKey))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: selectedIcon)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // MARK: Budget
                Section {
                    Toggle("add_account.include_in_budget", isOn: $includeInBudget)
                        .tint(.indigo)
                } footer: {
                    Text("add_account.include_in_budget.footer")
                        .font(.caption)
                }
            }
            .navigationTitle("edit_account.navigation.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
                }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        guard let balance = parseDecimal(balanceText) else {
            balanceInvalid = true
            return
        }

        let creditLimit: Decimal? = ((type == .credit || type == .creditCard) && !creditLimitText.isEmpty)
            ? parseDecimal(creditLimitText)
            : nil

        account.name = name.trimmingCharacters(in: .whitespaces)
        account.type = type
        account.currentBalance = balance
        account.includeInBudget = includeInBudget
        account.creditBalanceDisplayMode = type == .creditCard ? balanceDisplayMode : .creditAvailable
        account.creditLimit = creditLimit
        account.icon = selectedIcon

        dismiss()
    }

    /// Accepte les virgules (fr_CA) et les points (en) comme séparateur décimal.
    private func parseDecimal(_ text: String) -> Decimal? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "") // espace insécable
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Account.self, configurations: config)
    let sample = Account(
        name: "Compte chèques",
        type: .chequing,
        currentBalance: 1250.00,
        includeInBudget: true,
        creditBalanceDisplayMode: .creditAvailable,
        creditLimit: nil,
        icon: AccountType.chequing.defaultIcon
    )
    container.mainContext.insert(sample)
    return EditAccountView(account: sample)
        .modelContainer(container)
}
