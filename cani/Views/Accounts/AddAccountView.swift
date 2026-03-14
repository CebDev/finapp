//
//  AddAccountView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

struct IconOption {
    let symbol: String
    let labelKey: String
}

let availableIcons: [IconOption] = [
    IconOption(symbol: "banknote",                  labelKey: "add_account.icon.cash"),
    IconOption(symbol: "creditcard",                labelKey: "add_account.icon.card"),
    IconOption(symbol: "building.columns",          labelKey: "add_account.icon.bank"),
    IconOption(symbol: "house.fill",                labelKey: "add_account.icon.house"),
    IconOption(symbol: "chart.line.uptrend.xyaxis", labelKey: "add_account.icon.investment"),
    IconOption(symbol: "dollarsign.circle.fill",    labelKey: "add_account.icon.dollar"),
    IconOption(symbol: "bag.fill",                  labelKey: "add_account.icon.shopping"),
    IconOption(symbol: "car.fill",                  labelKey: "add_account.icon.car"),
    IconOption(symbol: "briefcase.fill",            labelKey: "add_account.icon.work"),
    IconOption(symbol: "chart.pie.fill",            labelKey: "add_account.icon.budget"),
]

struct AddAccountView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: AccountType = .chequing
    @State private var balanceText = ""
    @State private var selectedIcon = AccountType.chequing.defaultIcon
    @State private var iconManuallySelected = false
    @State private var includeInBudget = true
    @State private var creditLimitText = ""
    @State private var balanceDisplayMode: CreditBalanceDisplayMode = .creditAvailable
    @State private var balanceInvalid = false

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
                    HStack(spacing: 4) {
                        if isNegativeBalanceType {
                            Text("−")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
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
                    if isNegativeBalanceType {
                        Text("Entrez le montant dû. Le solde sera automatiquement traité comme négatif dans la projection.")
                            .font(.caption)
                    } else {
                        Text("add_account.balance.footer")
                            .font(.caption)
                    }
                }

                // MARK: Limite de crédit — type credit (existant, inchangé)
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
            .navigationTitle("add_account.navigation.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    // MARK: - Actions

    private var isNegativeBalanceType: Bool {
        type == .credit || type == .creditCard || type == .mortgage
    }

    private func save() {
        guard let rawBalance = parseDecimal(balanceText) else {
            balanceInvalid = true
            return
        }
        let balance = isNegativeBalanceType ? -abs(rawBalance) : rawBalance

        let creditLimit: Decimal? = ((type == .credit || type == .creditCard) && !creditLimitText.isEmpty)
            ? parseDecimal(creditLimitText)
            : nil

        let account = Account(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            currentBalance: balance,
            includeInBudget: includeInBudget,
            creditBalanceDisplayMode: type == .creditCard ? balanceDisplayMode : .creditAvailable,
            creditLimit: creditLimit,
            icon: selectedIcon
        )

        context.insert(account)
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

// MARK: - CreditBalanceDisplayMode — extensions vue

extension CreditBalanceDisplayMode {
    var localizationKey: String {
        switch self {
        case .creditAvailable: return "account.credit_balance_mode.available"
        case .creditOwed:      return "account.credit_balance_mode.owed"
        }
    }

    var descriptionKey: String {
        switch self {
        case .creditAvailable: return "add_account.balance_mode.available.description"
        case .creditOwed:      return "add_account.balance_mode.owed.description"
        }
    }
}

// MARK: - Preview

#Preview {
    AddAccountView()
        .modelContainer(for: Account.self, inMemory: true)
}
