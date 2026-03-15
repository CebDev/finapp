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

                Section("Période") {
                    NavigationLink(value: SettingsDestination.payPeriod) {
                        Label("Périodes & alertes", systemImage: "calendar.badge.clock")
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
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
            .navigationDestination(for: SettingsDestination.self) { dest in
                switch dest {
                case .categories:
                    CategoriesView()
                case .payPeriod:
                    PeriodSettingsView()
                case .general:
                    ComingSoonView(titleKey: "settings.row.general")
                case .profile:
                    ProfileView()
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

// MARK: - PeriodSettingsView

private struct PeriodSettingsView: View {
    @Query private var settingsArray: [UserSettings]

    var body: some View {
        if let settings = settingsArray.first {
            PeriodSettingsForm(settings: settings)
        } else {
            ContentUnavailableView(
                "Périodes non configurées",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Accédez à l'onglet Projection pour configurer vos périodes.")
            )
            .navigationTitle("Périodes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - PeriodSettingsForm

private struct PeriodSettingsForm: View {
    @Bindable var settings: UserSettings

    @State private var thresholdText:    String = ""
    @State private var thresholdInvalid: Bool   = false

    var body: some View {
        Form {
            // MARK: Fréquence de période
            Section("Fréquence de période") {
                Picker("Fréquence", selection: $settings.payPeriodFrequency) {
                    Text("Aux deux semaines").tag(Frequency.biweekly)
                    Text("Mensuel").tag(Frequency.monthly)
                }

                if settings.payPeriodFrequency == .biweekly {
                    Picker("Jour de début", selection: $settings.periodStartDayOfWeek) {
                        ForEach(weekdayOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    DatePicker(
                        "Date de référence",
                        selection: $settings.periodAnchorDate,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Locale(identifier: "fr_CA"))
                }

                if settings.payPeriodFrequency == .monthly {
                    Picker("Début de période le", selection: $settings.periodStartDay) {
                        ForEach(1...31, id: \.self) { d in
                            Text("\(d)").tag(d)
                        }
                    }

                    if let preview = periodPreview {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        .navigationTitle("Périodes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            thresholdText = "\(settings.tightThreshold)"
        }
    }

    // MARK: - Aperçu période mensuelle

    private var periodPreview: String? {
        let day = settings.periodStartDay
        if day == 1 { return "Période calendaire : du 1er à la fin du mois" }
        return "Période du \(day) au \(day - 1) du mois suivant"
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