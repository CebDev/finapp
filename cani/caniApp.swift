//
//  caniApp.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-12.
//

import SwiftUI
import SwiftData

@main
struct caniApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([
            Account.self,
            RecurringTransaction.self,
            Transaction.self,
            Goal.self,
            Simulation.self,
            SimulationTransaction.self,
            Category.self,
            UserSettings.self
        ])
        // CloudKit désactivé en dev — activer après configuration des entitlements iCloud dans Xcode
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.cebdev.cani"))
        //let config = ModelConfiguration(schema: schema)
        container = try! ModelContainer(for: schema, configurations: config)
        CategoryService.seedIfNeeded(context: container.mainContext)
        UserSettings.seedIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
