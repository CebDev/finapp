//
//  SettingsView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

enum SettingsDestination: Hashable {
    case categories
    case payPeriod
    case general
    case profile
}

struct SettingsView: View {
    var initialDestination: SettingsDestination? = nil

    @State private var path = NavigationPath()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section(String(localized: "settings.section.categories")) {
                    NavigationLink(value: SettingsDestination.categories) {
                        Label("settings.row.categories", systemImage: "tag")
                    }
                }

                Section("Période de paie") {
                    NavigationLink(value: SettingsDestination.payPeriod) {
                        Label("Paie & alertes", systemImage: "calendar.badge.clock")
                    }
                }

                Section(String(localized: "settings.section.general")) {
                    NavigationLink(value: SettingsDestination.general) {
                        Label("settings.row.general", systemImage: "slider.horizontal.3")
                    }
                }

                Section(String(localized: "settings.section.profile")) {
                    NavigationLink(value: SettingsDestination.profile) {
                        Label("settings.row.profile", systemImage: "person.circle")
                    }
                }
            }
            .navigationTitle("settings.navigation.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: SettingsDestination.self) { dest in
                switch dest {
                case .categories:
                    CategoriesView()
                case .payPeriod:
                    PayPeriodSettingsView()
                case .general:
                    ComingSoonView(titleKey: "settings.row.general")
                case .profile:
                    ComingSoonView(titleKey: "settings.row.profile")
                }
            }
        }
        .onAppear {
            if let dest = initialDestination {
                path.append(dest)
            }
        }
    }
}

// MARK: - PayPeriodSettingsView

private struct PayPeriodSettingsView: View {
    @Query private var settingsArray: [UserSettings]
    @Environment(\.modelContext) private var context

    var body: some View {
        if let settings = settingsArray.first {
            PayPeriodForm(settings: settings)
        } else {
            ProgressView()
                .onAppear { UserSettings.seedIfNeeded(context: context) }
                .navigationTitle("Période de paie")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - PayPeriodForm

private struct PayPeriodForm: View {
    @Bindable var settings: UserSettings

    @State private var thresholdText: String = ""
    @State private var thresholdInvalid: Bool = false

    var body: some View {
        Form {
            // MARK: Fréquence de paie
            Section("Fréquence de paie") {
                Picker("Fréquence", selection: $settings.payPeriodFrequency) {
                    Text("Aux deux semaines").tag(Frequency.biweekly)
                    Text("Mensuel").tag(Frequency.monthly)
                }

                if settings.payPeriodFrequency == .biweekly {
                    Picker("Jour de paie", selection: $settings.payDayOfWeek) {
                        ForEach(weekdayOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    DatePicker(
                        "Prochaine paie",
                        selection: $settings.nextPayDate,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Locale(identifier: "fr_CA"))
                }

                if settings.payPeriodFrequency == .monthly {
                    Picker("Jour du mois", selection: $settings.payDayOfMonth) {
                        ForEach(1...31, id: \.self) { d in
                            Text("\(d)").tag(d)
                        }
                    }
                }
            }

            // MARK: Solde reporté
            Section {
                Toggle("Reprendre le solde précédent", isOn: $settings.carryForwardBalance)
                    .tint(.indigo)
            } footer: {
                Text("Actif : chaque période commence avec le solde de fin de la période précédente. Inactif : chaque période est calculée de façon isolée à partir de zéro.")
                    .font(.caption)
            }

            // MARK: Seuil d'alerte
            Section {
                HStack {
                    TextField("500", text: $thresholdText)
                        .keyboardType(.decimalPad)
                        .onChange(of: thresholdText) { _, newVal in
                            thresholdInvalid = false
                            if let parsed = parseDecimal(newVal) {
                                settings.tightThreshold = parsed
                            }
                        }
                    Text("$")
                        .foregroundStyle(.secondary)
                }
                if thresholdInvalid {
                    Label("Montant invalide", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Alerte solde bas (CAD)")
            } footer: {
                Text("Une alerte orange s'affiche quand le solde projeté tombe sous ce seuil.")
                    .font(.caption)
            }
        }
        .navigationTitle("Période de paie")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            thresholdText = "\(settings.tightThreshold)"
        }
    }

    // MARK: - Helpers

    private let weekdayOptions: [(label: String, value: Int)] = [
        ("Lundi",    1),
        ("Mardi",    2),
        ("Mercredi", 3),
        ("Jeudi",    4),
        ("Vendredi", 5),
    ]

    private func parseDecimal(_ text: String) -> Decimal? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }
}

// MARK: - Placeholder

private struct ComingSoonView: View {
    let titleKey: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("settings.placeholder.coming_soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(LocalizedStringKey(titleKey))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
