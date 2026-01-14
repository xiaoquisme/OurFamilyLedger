import Foundation
import SwiftData

/// 同步服务 - 负责 SwiftData 和 iCloud CSV 之间的数据同步
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    private let csvService = CSVService()
    private let fileManager = FileManager.default

    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private init() {}

    // MARK: - iCloud Path

    /// iCloud 容器标识符
    private let containerIdentifier = "iCloud.com.xiaoquisme.ourfamilyledger"

    /// 获取 iCloud Documents URL
    /// 使用 app 的 iCloud 容器，配合 NSUbiquitousContainerIsDocumentScopePublic=true
    /// 这样文件会在 Files app 中显示为 "一家账本" 文件夹
    private var iCloudDocumentsURL: URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            print("iCloud 容器不可用")
            return nil
        }

        let documentsURL = containerURL.appendingPathComponent("Documents")

        // 确保 Documents 目录存在
        if !fileManager.fileExists(atPath: documentsURL.path) {
            try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }

        print("iCloud Documents 路径: \(documentsURL.path)")
        return documentsURL
    }

    /// 获取默认账本文件夹 URL
    /// 直接使用 Documents 目录，因为整个容器在 Files app 中会显示为 "一家账本"
    private var defaultLedgerURL: URL? {
        return iCloudDocumentsURL
    }

    // MARK: - Write Transaction to CSV

    /// 将交易记录写入 iCloud CSV
    func writeTransaction(_ transaction: TransactionRecord, categoryName: String, payerName: String, participantNames: [String], context: ModelContext) async {
        guard let ledgerURL = defaultLedgerURL else {
            syncError = "iCloud 不可用"
            return
        }

        let yearMonth = yearMonthString(from: transaction.date)
        let fileURL = ledgerURL.appendingPathComponent("transactions_\(yearMonth).csv")

        let csv = TransactionCSV(
            id: transaction.id.uuidString,
            createdAt: dateFormatter.string(from: transaction.createdAt),
            updatedAt: dateFormatter.string(from: transaction.updatedAt),
            date: dateOnlyFormatter.string(from: transaction.date),
            amount: "\(transaction.amount)",
            type: transaction.type.rawValue,
            category: categoryName,
            payer: payerName,
            participants: participantNames.joined(separator: ";"),
            note: transaction.note,
            merchant: transaction.merchant,
            source: transaction.source.rawValue,
            ocrText: transaction.ocrText,
            currency: transaction.currency
        )

        do {
            try await csvService.appendTransaction(csv, to: fileURL)
            lastSyncTime = Date()
            syncError = nil
        } catch {
            syncError = "写入 CSV 失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Load from iCloud

    /// 从 iCloud CSV 加载所有交易到 SwiftData
    func loadFromiCloud(context: ModelContext) async {
        guard let ledgerURL = defaultLedgerURL else {
            syncError = "iCloud 不可用"
            return
        }

        isSyncing = true
        syncError = nil

        do {
            // 列出所有交易文件
            let files = try await csvService.listTransactionFiles(in: ledgerURL)

            var loadedCount = 0

            for fileName in files {
                let fileURL = ledgerURL.appendingPathComponent(fileName)
                let csvTransactions = try await csvService.readTransactions(from: fileURL)

                for csv in csvTransactions {
                    // 检查是否已存在
                    guard let uuid = UUID(uuidString: csv.id) else { continue }

                    let descriptor = FetchDescriptor<TransactionRecord>(
                        predicate: #Predicate { $0.id == uuid }
                    )

                    let existing = try? context.fetch(descriptor)
                    if existing?.isEmpty == false {
                        continue // 已存在，跳过
                    }

                    // 解析数据
                    let amount = Decimal(string: csv.amount) ?? 0
                    let type = TransactionType(rawValue: csv.type) ?? .expense
                    let source = TransactionSource(rawValue: csv.source) ?? .manual

                    // 查找或创建分类
                    let categoryId = await findOrCreateCategory(name: csv.category, context: context)

                    // 查找或创建付款人
                    let payerId = await findOrCreateMember(name: csv.payer, context: context)

                    // 查找或创建参与人
                    let participantNames = csv.participants.split(separator: ";").map { String($0) }
                    var participantIds: [UUID] = []
                    for name in participantNames {
                        if let id = await findOrCreateMember(name: name, context: context) {
                            participantIds.append(id)
                        }
                    }

                    // 创建交易记录
                    let transaction = TransactionRecord(
                        id: uuid,
                        createdAt: dateFormatter.date(from: csv.createdAt) ?? Date(),
                        updatedAt: dateFormatter.date(from: csv.updatedAt) ?? Date(),
                        date: dateOnlyFormatter.date(from: csv.date) ?? Date(),
                        amount: amount,
                        type: type,
                        categoryId: categoryId,
                        payerId: payerId,
                        participantIds: participantIds,
                        note: csv.note,
                        merchant: csv.merchant,
                        source: source,
                        ocrText: csv.ocrText,
                        currency: csv.currency
                    )

                    context.insert(transaction)
                    loadedCount += 1
                }
            }

            try? context.save()
            lastSyncTime = Date()

            if loadedCount > 0 {
                print("从 iCloud 加载了 \(loadedCount) 条交易记录")
            }

        } catch {
            syncError = "加载失败: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    // MARK: - Full Sync

    /// 完整同步：将本地数据同步到 iCloud
    func syncToiCloud(context: ModelContext) async {
        guard let ledgerURL = defaultLedgerURL else {
            syncError = "iCloud 不可用"
            return
        }

        isSyncing = true
        syncError = nil

        do {
            // 获取所有本地交易
            let descriptor = FetchDescriptor<TransactionRecord>(
                sortBy: [SortDescriptor(\.date)]
            )
            let transactions = try context.fetch(descriptor)

            // 按月分组
            var transactionsByMonth: [String: [TransactionCSV]] = [:]

            for transaction in transactions {
                let yearMonth = yearMonthString(from: transaction.date)

                // 获取分类名称
                var categoryName = ""
                if let categoryId = transaction.categoryId {
                    let catDescriptor = FetchDescriptor<Category>(
                        predicate: #Predicate { $0.id == categoryId }
                    )
                    if let category = try? context.fetch(catDescriptor).first {
                        categoryName = category.name
                    }
                }

                // 获取付款人名称
                var payerName = ""
                if let payerId = transaction.payerId {
                    let memberDescriptor = FetchDescriptor<Member>(
                        predicate: #Predicate { $0.id == payerId }
                    )
                    if let member = try? context.fetch(memberDescriptor).first {
                        payerName = member.name
                    }
                }

                // 获取参与人名称
                var participantNames: [String] = []
                for participantId in transaction.participantIds {
                    let memberDescriptor = FetchDescriptor<Member>(
                        predicate: #Predicate { $0.id == participantId }
                    )
                    if let member = try? context.fetch(memberDescriptor).first {
                        participantNames.append(member.name)
                    }
                }

                let csv = TransactionCSV(
                    id: transaction.id.uuidString,
                    createdAt: dateFormatter.string(from: transaction.createdAt),
                    updatedAt: dateFormatter.string(from: transaction.updatedAt),
                    date: dateOnlyFormatter.string(from: transaction.date),
                    amount: "\(transaction.amount)",
                    type: transaction.type.rawValue,
                    category: categoryName,
                    payer: payerName,
                    participants: participantNames.joined(separator: ";"),
                    note: transaction.note,
                    merchant: transaction.merchant,
                    source: transaction.source.rawValue,
                    ocrText: transaction.ocrText,
                    currency: transaction.currency
                )

                transactionsByMonth[yearMonth, default: []].append(csv)
            }

            // 写入文件
            for (yearMonth, csvTransactions) in transactionsByMonth {
                let fileURL = ledgerURL.appendingPathComponent("transactions_\(yearMonth).csv")
                try await csvService.writeTransactions(csvTransactions, to: fileURL)
            }

            lastSyncTime = Date()
            print("同步了 \(transactions.count) 条交易记录到 iCloud")

        } catch {
            syncError = "同步失败: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    // MARK: - Helpers

    private func yearMonthString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func findOrCreateCategory(name: String, context: ModelContext) async -> UUID? {
        guard !name.isEmpty else { return nil }

        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.name == name }
        )

        if let existing = try? context.fetch(descriptor).first {
            return existing.id
        }

        let category = Category(name: name, type: .expense)
        context.insert(category)
        return category.id
    }

    private func findOrCreateMember(name: String, context: ModelContext) async -> UUID? {
        guard !name.isEmpty else { return nil }

        let descriptor = FetchDescriptor<Member>(
            predicate: #Predicate { $0.name == name || $0.nickname == name }
        )

        if let existing = try? context.fetch(descriptor).first {
            return existing.id
        }

        let member = Member(name: name)
        context.insert(member)
        return member.id
    }

    // MARK: - Public Status Methods

    /// 获取 iCloud 容器 URL（用于设置页面显示）
    var containerURL: URL? {
        fileManager.url(forUbiquityContainerIdentifier: containerIdentifier)
    }

    /// 获取 Documents URL（用于设置页面显示）
    var documentsURL: URL? {
        iCloudDocumentsURL
    }

    /// 检查 iCloud 是否可用
    var isICloudAvailable: Bool {
        fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) != nil
    }

    /// 列出所有 CSV 文件
    func listCSVFiles() -> [(name: String, size: Int64, modifiedDate: Date?)] {
        guard let documentsURL = iCloudDocumentsURL else { return [] }

        var files: [(name: String, size: Int64, modifiedDate: Date?)] = []

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: .skipsHiddenFiles
            )

            for fileURL in contents where fileURL.pathExtension == "csv" {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                files.append((
                    name: fileURL.lastPathComponent,
                    size: Int64(resourceValues?.fileSize ?? 0),
                    modifiedDate: resourceValues?.contentModificationDate
                ))
            }
        } catch {
            print("列出文件失败: \(error)")
        }

        return files.sorted { $0.name < $1.name }
    }

    /// 清除 iCloud 容器中的所有数据
    func clearICloudData() async throws {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw NSError(domain: "SyncService", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud 容器不可用"])
        }

        let documentsURL = containerURL.appendingPathComponent("Documents")

        guard fileManager.fileExists(atPath: documentsURL.path) else {
            return // 目录不存在，无需清理
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )

            for itemURL in contents {
                try fileManager.removeItem(at: itemURL)
                print("已删除: \(itemURL.lastPathComponent)")
            }

            syncError = nil
            print("iCloud 数据已清除")
        } catch {
            syncError = "清除失败: \(error.localizedDescription)"
            throw error
        }
    }
}
