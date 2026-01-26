import Foundation
import CloudKit
import SwiftUI

/// CloudKit 共享错误
enum CloudKitSharingError: LocalizedError {
    case containerNotAvailable
    case shareCreationFailed(Error)
    case shareFetchFailed(Error)
    case shareAcceptFailed(Error)
    case notShared

    var errorDescription: String? {
        switch self {
        case .containerNotAvailable:
            return "CloudKit 容器不可用"
        case .shareCreationFailed(let error):
            return "创建共享失败: \(error.localizedDescription)"
        case .shareFetchFailed(let error):
            return "获取共享信息失败: \(error.localizedDescription)"
        case .shareAcceptFailed(let error):
            return "接受共享邀请失败: \(error.localizedDescription)"
        case .notShared:
            return "此账本未被共享"
        }
    }
}

/// 共享状态
enum SharingStatus: Equatable {
    case notShared
    case pending
    case shared(participantCount: Int)
    case error(String)

    static func == (lhs: SharingStatus, rhs: SharingStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notShared, .notShared), (.pending, .pending):
            return true
        case (.shared(let l), .shared(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}

/// CloudKit 共享服务
@MainActor
final class CloudKitSharingService: ObservableObject {
    @Published var sharingStatus: SharingStatus = .notShared
    @Published var currentShare: CKShare?

    private let container: CKContainer
    private let cloudService: iCloudService

    init() {
        self.container = CKContainer(identifier: "iCloud.com.xiaoquisme.ourfamilyledger")
        self.cloudService = iCloudService()
    }

    // MARK: - Share Creation

    /// 创建共享账本
    func createSharedLedger(name: String) async throws -> URL {
        // 创建账本文件夹
        let ledgerURL = try await cloudService.createLedger(name: name)

        sharingStatus = .pending

        return ledgerURL
    }

    // MARK: - Share Discovery

    /// 发现可用的共享账本
    /// 对于 iCloud Documents 共享，需要通过文件系统发现共享的文件夹
    func discoverSharedLedgers() async throws -> [CKShare.Metadata] {
        // iCloud Documents 的共享通过 Files app 或邀请链接进行
        // 这里返回空数组，因为实际的发现需要用户手动接受邀请
        // 或通过 Files app 浏览共享文件夹
        return []
    }

    /// 获取可用的共享文件夹（从 iCloud Documents）
    func getSharedLedgerFolders() async throws -> [URL] {
        guard let documentsURL = await cloudService.documentsURL() else {
            return []
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: documentsURL.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isUbiquitousItemKey],
            options: .skipsHiddenFiles
        )

        return contents.filter { url in
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return isDirectory.boolValue
        }
    }

    // MARK: - Share Acceptance

    /// 接受共享邀请
    func acceptShare(from url: URL) async throws {
        do {
            let metadata = try await container.shareMetadata(for: url)
            try await container.accept(metadata)
            sharingStatus = .shared(participantCount: 1)
        } catch {
            throw CloudKitSharingError.shareAcceptFailed(error)
        }
    }

    /// 接受共享元数据
    func acceptShare(metadata: CKShare.Metadata) async throws {
        do {
            try await container.accept(metadata)
            sharingStatus = .shared(participantCount: 1)
        } catch {
            throw CloudKitSharingError.shareAcceptFailed(error)
        }
    }

    // MARK: - Share Management

    /// 获取当前共享状态
    func checkSharingStatus(for folderURL: URL) async {
        // iCloud Documents 的共享通过文件系统属性检查
        let resourceValues = try? folderURL.resourceValues(forKeys: [.isUbiquitousItemKey])
        if resourceValues?.isUbiquitousItem == true {
            sharingStatus = .shared(participantCount: 1)
        } else {
            sharingStatus = .notShared
        }
    }

    /// 获取共享链接
    func getShareURL() -> URL? {
        return currentShare?.url
    }

    /// 停止共享
    func stopSharing(for folderURL: URL) async throws {
        guard let share = currentShare else {
            throw CloudKitSharingError.notShared
        }

        let database = container.privateCloudDatabase
        _ = try await database.modifyRecords(saving: [], deleting: [share.recordID])

        currentShare = nil
        sharingStatus = .notShared
    }
}

// MARK: - UICloudSharingController Wrapper

#if canImport(UIKit)
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onCompletion: ((Result<Void, Error>) -> Void)?

    init(share: CKShare, container: CKContainer = CKContainer(identifier: "iCloud.com.xiaoquisme.ourfamilyledger"), onCompletion: ((Result<Void, Error>) -> Void)? = nil) {
        self.share = share
        self.container = container
        self.onCompletion = onCompletion
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        var onCompletion: ((Result<Void, Error>) -> Void)?

        init(onCompletion: ((Result<Void, Error>) -> Void)?) {
            self.onCompletion = onCompletion
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onCompletion?(.failure(error))
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onCompletion?(.success(()))
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onCompletion?(.success(()))
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            return "家庭账本"
        }
    }
}
#endif
