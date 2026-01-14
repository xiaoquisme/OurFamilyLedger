import SwiftUI
import SwiftData

@main
struct OurFamilyLedgerApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            TransactionRecord.self,
            Member.self,
            Category.self,
            Ledger.self,
            RecurringTransaction.self
        ])

        // 明确禁用 CloudKit 同步，SwiftData 仅用于本地缓存
        // iCloud 用于 CSV 文件同步，不用于 SwiftData
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            #if DEBUG
            // 开发阶段：删除旧数据重新创建
            print("SwiftData migration failed, resetting database: \(error)")
            Self.deleteSwiftDataStore()

            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
            } catch {
                fatalError("Could not initialize ModelContainer after reset: \(error)")
            }
            #else
            fatalError("Could not initialize ModelContainer: \(error)")
            #endif
        }

        // 初始化默认分类
        initializeDefaultCategories()
    }

    private static func deleteSwiftDataStore() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
        for file in storeFiles {
            let url = appSupport.appending(path: file)
            try? fileManager.removeItem(at: url)
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
