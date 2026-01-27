import XCTest
@testable import OurFamilyLedger

/// Tests for SyncService helper functions and MergeResult
final class SyncServiceTests: XCTestCase {

    // MARK: - MergeResult Tests

    func testMergeResult_initialization() {
        // Given/When
        let result = MergeResult(
            mergedTransactions: [],
            conflicts: [],
            addedCount: 5,
            updatedCount: 3,
            deletedCount: 1
        )

        // Then
        XCTAssertEqual(result.addedCount, 5)
        XCTAssertEqual(result.updatedCount, 3)
        XCTAssertEqual(result.deletedCount, 1)
        XCTAssertTrue(result.mergedTransactions.isEmpty)
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    func testMergeResult_withTransactions() {
        // Given
        let transactions = [
            createTestTransaction(id: "1"),
            createTestTransaction(id: "2")
        ]

        // When
        let result = MergeResult(
            mergedTransactions: transactions,
            conflicts: [],
            addedCount: 2,
            updatedCount: 0,
            deletedCount: 0
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 2)
    }

    // MARK: - ConflictType Tests

    func testConflictType_bothModified() {
        let type = ConflictType.both_modified
        XCTAssertNotNil(type)
    }

    func testConflictType_deletedModified() {
        let type = ConflictType.deleted_modified
        XCTAssertNotNil(type)
    }

    func testConflictType_duplicateAdd() {
        let type = ConflictType.duplicate_add
        XCTAssertNotNil(type)
    }

    // MARK: - ConflictResolution Tests

    func testConflictResolution_keepLocal() {
        let resolution = ConflictResolution.keepLocal
        XCTAssertNotNil(resolution)
    }

    func testConflictResolution_keepRemote() {
        let resolution = ConflictResolution.keepRemote
        XCTAssertNotNil(resolution)
    }

    func testConflictResolution_keepBoth() {
        let resolution = ConflictResolution.keepBoth
        XCTAssertNotNil(resolution)
    }

    func testConflictResolution_keepNewest() {
        let resolution = ConflictResolution.keepNewest
        XCTAssertNotNil(resolution)
    }

    // MARK: - ConflictRecord Tests

    func testConflictRecord_initialization() {
        // Given
        let local = createTestTransaction(id: "1")
        let remote = createTestTransaction(id: "1")
        let time = Date()

        // When
        let record = ConflictRecord(
            type: .both_modified,
            localRecord: local,
            remoteRecord: remote,
            conflictTime: time
        )

        // Then
        XCTAssertEqual(record.type, .both_modified)
        XCTAssertEqual(record.localRecord.id, "1")
        XCTAssertNotNil(record.remoteRecord)
        XCTAssertEqual(record.conflictTime, time)
    }

    func testConflictRecord_withNilRemote() {
        // Given
        let local = createTestTransaction(id: "1")

        // When
        let record = ConflictRecord(
            type: .deleted_modified,
            localRecord: local,
            remoteRecord: nil,
            conflictTime: Date()
        )

        // Then
        XCTAssertNil(record.remoteRecord)
    }

    // MARK: - TransactionCSV Tests

    func testTransactionCSV_initialization() {
        // Given/When
        let csv = TransactionCSV(
            id: "test-id",
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: "2024-01-15T11:00:00Z",
            date: "2024-01-15",
            amount: "100.50",
            type: "支出",
            category: "餐饮",
            payer: "张三",
            participants: "张三;李四",
            note: "午餐",
            merchant: "餐厅",
            source: "manual",
            ocrText: nil,
            currency: "CNY"
        )

        // Then
        XCTAssertEqual(csv.id, "test-id")
        XCTAssertEqual(csv.amount, "100.50")
        XCTAssertEqual(csv.category, "餐饮")
        XCTAssertEqual(csv.payer, "张三")
        XCTAssertEqual(csv.participants, "张三;李四")
        XCTAssertEqual(csv.currency, "CNY")
    }

    func testTransactionCSV_withOCRText() {
        // Given/When
        let csv = TransactionCSV(
            id: "test-id",
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: "2024-01-15T11:00:00Z",
            date: "2024-01-15",
            amount: "50.00",
            type: "支出",
            category: "购物",
            payer: "测试",
            participants: "测试",
            note: "",
            merchant: "",
            source: "ocr",
            ocrText: "OCR识别的文本内容",
            currency: "CNY"
        )

        // Then
        XCTAssertEqual(csv.source, "ocr")
        XCTAssertEqual(csv.ocrText, "OCR识别的文本内容")
    }

    // MARK: - iCloudSyncStatus Tests

    func testICloudSyncStatus_idle() {
        let status = iCloudSyncStatus.idle
        XCTAssertNotNil(status)
    }

    func testICloudSyncStatus_syncing() {
        let status = iCloudSyncStatus.syncing
        XCTAssertNotNil(status)
    }

    func testICloudSyncStatus_synced() {
        let status = iCloudSyncStatus.synced
        XCTAssertNotNil(status)
    }

    func testICloudSyncStatus_error() {
        let error = NSError(domain: "Test", code: 1, userInfo: nil)
        let status = iCloudSyncStatus.error(error)
        XCTAssertNotNil(status)
    }

    // MARK: - Helper Methods

    private func createTestTransaction(
        id: String,
        date: String = "2024-01-15",
        amount: String = "100",
        updatedAt: String = "2024-01-15T10:00:00Z"
    ) -> TransactionCSV {
        TransactionCSV(
            id: id,
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: updatedAt,
            date: date,
            amount: amount,
            type: "支出",
            category: "餐饮",
            payer: "测试用户",
            participants: "测试用户",
            note: "",
            merchant: "",
            source: "manual",
            ocrText: nil,
            currency: "CNY"
        )
    }
}
