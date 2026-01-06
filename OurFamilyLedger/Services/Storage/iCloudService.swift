import Foundation

/// iCloud 服务错误
enum iCloudError: LocalizedError {
    case notAvailable
    case containerNotFound
    case fileNotFound
    case syncFailed(Error)
    case conflictDetected

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "iCloud 不可用，请确保已登录 iCloud"
        case .containerNotFound:
            return "未找到 iCloud 容器"
        case .fileNotFound:
            return "文件不存在"
        case .syncFailed(let error):
            return "同步失败: \(error.localizedDescription)"
        case .conflictDetected:
            return "检测到文件冲突"
        }
    }
}

/// iCloud 同步状态
enum iCloudSyncStatus {
    case idle
    case syncing
    case synced
    case error(Error)
}

/// iCloud 服务
actor iCloudService {
    private let fileManager = FileManager.default

    // MARK: - Status

    /// 检查 iCloud 是否可用
    var isAvailable: Bool {
        fileManager.ubiquityIdentityToken != nil
    }

    /// 获取 iCloud 容器 URL
    func containerURL() -> URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)
    }

    /// 获取 Documents 目录
    func documentsURL() -> URL? {
        containerURL()?.appendingPathComponent("Documents")
    }

    // MARK: - Ledger Management

    /// 创建新账本文件夹
    func createLedger(name: String) async throws -> URL {
        guard let documentsURL = documentsURL() else {
            throw iCloudError.containerNotFound
        }

        let ledgerURL = documentsURL.appendingPathComponent(name)

        if !fileManager.fileExists(atPath: ledgerURL.path) {
            try fileManager.createDirectory(at: ledgerURL, withIntermediateDirectories: true)
        }

        return ledgerURL
    }

    /// 列出所有账本
    func listLedgers() async throws -> [URL] {
        guard let documentsURL = documentsURL() else {
            throw iCloudError.containerNotFound
        }

        let contents = try fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )

        return contents.filter { url in
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return isDirectory.boolValue
        }
    }

    // MARK: - File Operations

    /// 检查文件是否存在
    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    /// 读取文件
    func readFile(at url: URL) async throws -> Data {
        guard fileExists(at: url) else {
            throw iCloudError.fileNotFound
        }

        // 确保文件已下载
        try await downloadFileIfNeeded(at: url)

        return try Data(contentsOf: url)
    }

    /// 写入文件
    func writeFile(_ data: Data, to url: URL) async throws {
        // 确保目录存在
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try data.write(to: url, options: .atomic)
    }

    /// 删除文件
    func deleteFile(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Sync

    /// 下载文件（如果需要）
    func downloadFileIfNeeded(at url: URL) async throws {
        var isDownloaded = false

        if let resourceValues = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           let status = resourceValues.ubiquitousItemDownloadingStatus {
            isDownloaded = status == .current
        }

        if !isDownloaded {
            try fileManager.startDownloadingUbiquitousItem(at: url)

            // 等待下载完成
            for _ in 0..<30 {  // 最多等待 30 秒
                try await Task.sleep(for: .seconds(1))

                if let resourceValues = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                   let status = resourceValues.ubiquitousItemDownloadingStatus,
                   status == .current {
                    return
                }
            }
        }
    }

    /// 检测冲突文件
    func detectConflicts(at url: URL) async throws -> [URL] {
        let directory = url.deletingLastPathComponent()
        let filename = url.lastPathComponent

        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        // 查找冲突副本（通常以 " 2" 或 "conflict" 结尾）
        let conflictFiles = contents.filter { fileURL in
            let name = fileURL.lastPathComponent
            return name != filename && name.hasPrefix(filename.replacingOccurrences(of: ".csv", with: ""))
        }

        return conflictFiles
    }

    // MARK: - Sharing

    /// 获取共享 URL
    func getShareURL(for url: URL) async throws -> URL? {
        // 创建共享协调器
        var error: NSError?
        var shareURL: URL?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: url,
            options: .forUploading,
            error: &error
        ) { newURL in
            shareURL = newURL
        }

        if let error = error {
            throw iCloudError.syncFailed(error)
        }

        return shareURL
    }

    // MARK: - Metadata Query

    /// 创建元数据查询以监控文件变化
    func createMetadataQuery(for folderURL: URL) -> NSMetadataQuery {
        let query = NSMetadataQuery()
        query.searchScopes = [folderURL]
        query.predicate = NSPredicate(format: "%K == %@",
                                       NSMetadataItemFSNameKey, "*.csv")

        return query
    }
}

// MARK: - File Coordinator Helper

extension iCloudService {
    /// 使用文件协调器安全地读取文件
    func coordinatedRead(at url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(
                readingItemAt: url,
                options: [],
                error: &coordinatorError
            ) { newURL in
                do {
                    let data = try Data(contentsOf: newURL)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let error = coordinatorError {
                continuation.resume(throwing: iCloudError.syncFailed(error))
            }
        }
    }

    /// 使用文件协调器安全地写入文件
    func coordinatedWrite(_ data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinatorError
            ) { newURL in
                do {
                    try data.write(to: newURL, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let error = coordinatorError {
                continuation.resume(throwing: iCloudError.syncFailed(error))
            }
        }
    }
}
