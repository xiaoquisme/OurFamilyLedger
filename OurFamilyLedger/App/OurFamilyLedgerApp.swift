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

            // 初始化默认分类
            initializeDefaultCategories()
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

    // MARK: - Initialize Default Data

    private func initializeDefaultCategories() {
        let context = modelContainer.mainContext

        // 检查是否已有分类
        let descriptor = FetchDescriptor<Category>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0

        guard existingCount == 0 else { return }

        // 添加默认支出分类
        for (index, category) in DefaultExpenseCategory.allCases.enumerated() {
            let newCategory = category.toCategory(sortOrder: index)
            context.insert(newCategory)
        }

        // 添加默认收入分类
        for (index, category) in DefaultIncomeCategory.allCases.enumerated() {
            let newCategory = category.toCategory(sortOrder: index)
            context.insert(newCategory)
        }

        try? context.save()
    }
}
