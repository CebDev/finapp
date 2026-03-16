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
            UserSettings.self,
            // Subscription.self supprimé — les abonnements sont des RecurringTransaction
            // avec isSubscription == true. Décision acté dans decisions.md.
        ])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.cebdev.cani"))
        container = try! ModelContainer(for: schema, configurations: config)
        CategoryService.seedIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: Notification.Name("NSPersistentStoreRemoteChangeNotification")
                    )
                ) { _ in
                    CategoryService.deduplicateIfNeeded(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}