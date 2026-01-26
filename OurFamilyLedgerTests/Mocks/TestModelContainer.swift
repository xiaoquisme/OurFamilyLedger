import Foundation
import SwiftData
@testable import OurFamilyLedger

/// Helper for creating in-memory model containers for testing
enum TestModelContainer {
    /// Creates an in-memory model container for testing
    @MainActor
    static func create() throws -> ModelContainer {
        let schema = Schema([
            TransactionRecord.self,
            Member.self,
            OurFamilyLedger.Category.self,
            Ledger.self,
            RecurringTransaction.self,
            AccountingReminder.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    /// Creates a model context from an in-memory container
    @MainActor
    static func createContext() throws -> ModelContext {
        let container = try create()
        return container.mainContext
    }
}
