import SwiftUI
import SwiftData

@main
struct OurFamilyLedgerApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                TransactionRecord.self,
                Member.self,
                Category.self,
                Ledger.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
