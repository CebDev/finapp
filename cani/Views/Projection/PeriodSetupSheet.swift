//
//  PeriodSetupSheet.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-14.
//

import SwiftUI
import SwiftData

struct PeriodSetupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    // MARK: - Form state

    @State private var frequency:      Frequency = .biweekly
    @State private var payDayOfWeek:   Int       = 4        // Jeudi
    @State private var nextPayDate:    Date       = Date()
    @State private var payDayOfMonth:  Int        = 1
    @State private var tightThreshold: String     = "500"
    @State private var carryForward:   Bool       = true

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                introSection
                frequencySection
                alertSection
                balanceSection
            }
            .navigationTitle("Configuration des périodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Générer") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.indigo.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.indigo)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prêt à projeter")
                            .font(.headline)
                        Text("Configurez votre rythme de paie")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Les périodes seront générées à partir des soldes actuels de vos comptes. Assurez-vous d'avoir créé tous vos comptes avant de continuer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.vertical, 6)
        }
    }

    private var frequencySection: some View {
        Section("Fréquence de paie") {
            Picker("Fréquence", selection: $frequency) {
                Text("Aux deux semaines").tag(Frequency.biweekly)
                Text("Mensuel").tag(Frequency.monthly)
            }

            if frequency == .biweekly {
                Picker("Jour de paie", selection: $payDayOfWeek) {
                    ForEach(weekdayOptions, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                DatePicker(
                    "Prochaine paie",
                    selection: $nextPayDate,
                    displayedComponents: .date
                )
                .environment(\.locale, Locale(identifier: "fr_CA"))
            }

            if frequency == .monthly {
                Picker("Jour du mois", selection: $payDayOfMonth) {
                    ForEach(1...31, id: \.self) { d in
                        Text("\(d)").tag(d)
                    }
                }
            }
        }
    }

    private var alertSection: some View {
        Section {
            HStack {
                TextField("500", text: $tightThreshold)
                    .keyboardType(.decimalPad)
                Text("CAD")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Alerte solde bas")
        } footer: {
            Text("Une alerte orange s'affiche quand le solde projeté tombe sous ce seuil.")
                .font(.caption)
        }
    }

    private var balanceSection: some View {
        Section {
            Toggle("Reprendre le solde précédent", isOn: $carryForward)
                .tint(.indigo)
        } footer: {
            Text("Actif : chaque période commence avec le solde de fin de la période précédente.")
                .font(.caption)
        }
    }

    // MARK: - Save

    private func save() {
        let threshold: Decimal = {
            let normalized = tightThreshold
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: " ", with: "")
            return Decimal(string: normalized) ?? 500
        }()

        let settings                  = UserSettings()
        settings.payPeriodFrequency   = frequency
        settings.payDayOfWeek         = payDayOfWeek
        settings.nextPayDate          = nextPayDate
        settings.payDayOfMonth        = payDayOfMonth
        settings.tightThreshold       = threshold
        settings.carryForwardBalance  = carryForward
        context.insert(settings)
        try? context.save()
        dismiss()
    }

    // MARK: - Helpers

    private let weekdayOptions: [(label: String, value: Int)] = [
        ("Lundi",    1),
        ("Mardi",    2),
        ("Mercredi", 3),
        ("Jeudi",    4),
        ("Vendredi", 5),
    ]
}
