import Foundation

/// 冲突类型
enum ConflictType {
    case both_modified    // 双方都修改了同一条记录
    case deleted_modified // 一方删除，另一方修改
    case duplicate_add    // 双方添加了相同 ID 的记录
}

/// 冲突记录
struct ConflictRecord {
    let type: ConflictType
    let localRecord: TransactionCSV
    let remoteRecord: TransactionCSV?
    let conflictTime: Date
}

/// 合并结果
struct MergeResult {
    let mergedTransactions: [TransactionCSV]
    let conflicts: [ConflictRecord]
    let addedCount: Int
    let updatedCount: Int
    let deletedCount: Int
}

/// 冲突解决策略
enum ConflictResolution {
    case keepLocal      // 保留本地版本
    case keepRemote     // 保留远程版本
    case keepBoth       // 保留两个版本（创建新记录）
    case keepNewest     // 保留最新修改的版本
}

/// 冲突解决服务
actor ConflictResolver {
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Merge

    /// 合并两个交易列表
    func merge(
        local: [TransactionCSV],
        remote: [TransactionCSV],
        strategy: ConflictResolution = .keepNewest
    ) async -> MergeResult {
        var merged: [TransactionCSV] = []
        var conflicts: [ConflictRecord] = []
        var addedCount = 0
        var updatedCount = 0
        var deletedCount = 0

        // 创建索引
        let localIndex = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteIndex = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })

        let allIds = Set(localIndex.keys).union(Set(remoteIndex.keys))

        for id in allIds {
            let localRecord = localIndex[id]
            let remoteRecord = remoteIndex[id]

            switch (localRecord, remoteRecord) {
            case let (.some(local), .some(remote)):
                // 两边都有，检查是否有冲突
                let result = resolveConflict(local: local, remote: remote, strategy: strategy)
                if let conflict = result.conflict {
                    conflicts.append(conflict)
                }
                if let record = result.resolved {
                    merged.append(record)
                    if record.updatedAt != local.updatedAt {
                        updatedCount += 1
                    }
                }

            case let (.some(local), .none):
                // 只有本地有（远程可能删除了，或本地新增）
                merged.append(local)

            case let (.none, .some(remote)):
                // 只有远程有（本地可能删除了，或远程新增）
                merged.append(remote)
                addedCount += 1

            case (.none, .none):
                // 不应该发生
                break
            }
        }

        // 按日期排序
        merged.sort { $0.date > $1.date }

        return MergeResult(
            mergedTransactions: merged,
            conflicts: conflicts,
            addedCount: addedCount,
            updatedCount: updatedCount,
            deletedCount: deletedCount
        )
    }

    // MARK: - Conflict Resolution

    private func resolveConflict(
        local: TransactionCSV,
        remote: TransactionCSV,
        strategy: ConflictResolution
    ) -> (resolved: TransactionCSV?, conflict: ConflictRecord?) {
        // 如果内容相同，直接返回
        if areEqual(local, remote) {
            return (local, nil)
        }

        // 解析更新时间
        let localTime = dateFormatter.date(from: local.updatedAt) ?? Date.distantPast
        let remoteTime = dateFormatter.date(from: remote.updatedAt) ?? Date.distantPast

        // 如果时间相同但内容不同，是真正的冲突
        if abs(localTime.timeIntervalSince(remoteTime)) < 1 {
            let conflict = ConflictRecord(
                type: .both_modified,
                localRecord: local,
                remoteRecord: remote,
                conflictTime: Date()
            )
            return resolveWithStrategy(local: local, remote: remote, strategy: strategy, conflict: conflict)
        }

        // 选择最新的版本
        if localTime > remoteTime {
            return (local, nil)
        } else {
            return (remote, nil)
        }
    }

    private func resolveWithStrategy(
        local: TransactionCSV,
        remote: TransactionCSV,
        strategy: ConflictResolution,
        conflict: ConflictRecord
    ) -> (resolved: TransactionCSV?, conflict: ConflictRecord?) {
        switch strategy {
        case .keepLocal:
            return (local, nil)

        case .keepRemote:
            return (remote, nil)

        case .keepBoth:
            // 返回冲突，让用户决定
            return (local, conflict)

        case .keepNewest:
            let localTime = dateFormatter.date(from: local.updatedAt) ?? Date.distantPast
            let remoteTime = dateFormatter.date(from: remote.updatedAt) ?? Date.distantPast

            if localTime >= remoteTime {
                return (local, nil)
            } else {
                return (remote, nil)
            }
        }
    }

    private func areEqual(_ a: TransactionCSV, _ b: TransactionCSV) -> Bool {
        return a.date == b.date &&
               a.amount == b.amount &&
               a.category == b.category &&
               a.payer == b.payer &&
               a.participants == b.participants &&
               a.note == b.note &&
               a.merchant == b.merchant
    }

    // MARK: - Conflict File Detection

    /// 检测 iCloud 冲突文件
    func detectiCloudConflicts(at folderURL: URL) async throws -> [URL] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: folderURL.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.ubiquitousItemHasUnresolvedConflictsKey],
            options: .skipsHiddenFiles
        )

        var conflictFiles: [URL] = []

        for url in contents {
            if let resourceValues = try? url.resourceValues(forKeys: [.ubiquitousItemHasUnresolvedConflictsKey]),
               let hasConflicts = resourceValues.ubiquitousItemHasUnresolvedConflicts,
               hasConflicts {
                conflictFiles.append(url)
            }
        }

        return conflictFiles
    }

    /// 获取文件的所有版本
    func getFileVersions(at url: URL) -> [NSFileVersion] {
        return NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
    }

    /// 解决文件版本冲突
    func resolveFileConflict(at url: URL, keepingVersion: NSFileVersion?) async throws {
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []

        if let keepVersion = keepingVersion {
            // 用选择的版本替换当前文件
            try keepVersion.replaceItem(at: url)
        }

        // 标记所有冲突版本为已解决
        for version in versions {
            version.isResolved = true
        }

        // 删除旧版本
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}

// MARK: - Sync Manager

/// 同步管理器
@MainActor
final class SyncManager: ObservableObject {
    @Published var syncStatus: iCloudSyncStatus = .idle
    @Published var pendingConflicts: [ConflictRecord] = []

    private let csvService = CSVService()
    private let iCloudService = iCloudService()
    private let conflictResolver = ConflictResolver()

    private var metadataQuery: NSMetadataQuery?

    // MARK: - Sync

    /// 执行同步
    func sync(ledgerURL: URL) async {
        syncStatus = .syncing

        do {
            // 检测冲突文件
            let conflictFiles = try await conflictResolver.detectiCloudConflicts(at: ledgerURL)

            for conflictFile in conflictFiles {
                // 获取版本
                let versions = await conflictResolver.getFileVersions(at: conflictFile)

                if versions.isEmpty {
                    continue
                }

                // 读取当前版本和冲突版本
                let currentData = try await iCloudService.readFile(at: conflictFile)
                guard let currentContent = String(data: currentData, encoding: .utf8) else {
                    continue
                }

                // 解析当前版本
                // TODO: 实现具体的解析和合并逻辑

                // 标记冲突为已解决
                try await conflictResolver.resolveFileConflict(at: conflictFile, keepingVersion: nil)
            }

            syncStatus = .synced
        } catch {
            syncStatus = .error(error)
        }
    }

    // MARK: - File Monitoring

    /// 开始监控文件变化
    func startMonitoring(ledgerURL: URL) {
        stopMonitoring()

        metadataQuery = NSMetadataQuery()
        metadataQuery?.searchScopes = [ledgerURL]
        metadataQuery?.predicate = NSPredicate(format: "%K ENDSWITH %@", NSMetadataItemFSNameKey, ".csv")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: metadataQuery
        )

        metadataQuery?.start()
    }

    /// 停止监控
    func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        // 处理文件变化通知
        Task {
            // TODO: 实现增量同步
        }
    }
}
