import XCTest
@testable import OurFamilyLedger

/// Tests for ConflictResolver
final class ConflictResolverTests: XCTestCase {
    private var conflictResolver: ConflictResolver!

    override func setUp() async throws {
        try await super.setUp()
        conflictResolver = ConflictResolver()
    }

    override func tearDown() async throws {
        conflictResolver = nil
        try await super.tearDown()
    }

    // MARK: - Merge Tests

    func testMerge_noConflicts_mergesBothLists() async {
        // Given
        let localTransactions = [
            createTestTransaction(id: "id1", amount: "100")
        ]
        let remoteTransactions = [
            createTestTransaction(id: "id2", amount: "200")
        ]

        // When
        let result = await conflictResolver.merge(
            local: localTransactions,
            remote: remoteTransactions
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 2)
        XCTAssertEqual(result.conflicts.count, 0)
        XCTAssertEqual(result.addedCount, 1)
    }

    func testMerge_sameRecordIdenticalContent_keepsOne() async {
        // Given
        let transaction = createTestTransaction(id: "id1", amount: "100")
        let localTransactions = [transaction]
        let remoteTransactions = [transaction]

        // When
        let result = await conflictResolver.merge(
            local: localTransactions,
            remote: remoteTransactions
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 1)
        XCTAssertEqual(result.conflicts.count, 0)
    }

    func testMerge_sameRecordDifferentContent_keepsNewest() async {
        // Given
        let olderTime = "2024-01-15T10:00:00Z"
        let newerTime = "2024-01-15T11:00:00Z"

        let localTransaction = createTestTransaction(
            id: "id1",
            amount: "100",
            updatedAt: olderTime
        )
        let remoteTransaction = createTestTransaction(
            id: "id1",
            amount: "150",
            updatedAt: newerTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepNewest
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 1)
        XCTAssertEqual(result.mergedTransactions[0].amount, "150")
        XCTAssertEqual(result.conflicts.count, 0)
    }

    func testMerge_conflictingRecords_sameTimestamp_reportsConflict() async {
        // Given
        let sameTime = "2024-01-15T10:00:00Z"

        let localTransaction = createTestTransaction(
            id: "id1",
            amount: "100",
            note: "Local version",
            updatedAt: sameTime
        )
        let remoteTransaction = createTestTransaction(
            id: "id1",
            amount: "150",
            note: "Remote version",
            updatedAt: sameTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepBoth
        )

        // Then
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts[0].type, .both_modified)
    }

    func testMerge_keepLocalStrategy_prefersLocal() async {
        // Given
        let sameTime = "2024-01-15T10:00:00Z"

        let localTransaction = createTestTransaction(
            id: "id1",
            amount: "100",
            updatedAt: sameTime
        )
        let remoteTransaction = createTestTransaction(
            id: "id1",
            amount: "200",
            updatedAt: sameTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepLocal
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 1)
        XCTAssertEqual(result.mergedTransactions[0].amount, "100")
        XCTAssertEqual(result.conflicts.count, 0)
    }

    func testMerge_keepRemoteStrategy_prefersRemote() async {
        // Given
        let sameTime = "2024-01-15T10:00:00Z"

        let localTransaction = createTestTransaction(
            id: "id1",
            amount: "100",
            updatedAt: sameTime
        )
        let remoteTransaction = createTestTransaction(
            id: "id1",
            amount: "200",
            updatedAt: sameTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepRemote
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 1)
        XCTAssertEqual(result.mergedTransactions[0].amount, "200")
        XCTAssertEqual(result.conflicts.count, 0)
    }

    func testMerge_onlyLocalRecords_preservesAll() async {
        // Given
        let localTransactions = [
            createTestTransaction(id: "id1", amount: "100"),
            createTestTransaction(id: "id2", amount: "200"),
            createTestTransaction(id: "id3", amount: "300")
        ]
        let remoteTransactions: [TransactionCSV] = []

        // When
        let result = await conflictResolver.merge(
            local: localTransactions,
            remote: remoteTransactions
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 3)
        XCTAssertEqual(result.addedCount, 0)
    }

    func testMerge_onlyRemoteRecords_addsAll() async {
        // Given
        let localTransactions: [TransactionCSV] = []
        let remoteTransactions = [
            createTestTransaction(id: "id1", amount: "100"),
            createTestTransaction(id: "id2", amount: "200")
        ]

        // When
        let result = await conflictResolver.merge(
            local: localTransactions,
            remote: remoteTransactions
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 2)
        XCTAssertEqual(result.addedCount, 2)
    }

    func testMerge_resultsAreSortedByDate() async {
        // Given
        let localTransactions = [
            createTestTransaction(id: "id1", date: "2024-01-15"),
            createTestTransaction(id: "id3", date: "2024-01-17")
        ]
        let remoteTransactions = [
            createTestTransaction(id: "id2", date: "2024-01-16")
        ]

        // When
        let result = await conflictResolver.merge(
            local: localTransactions,
            remote: remoteTransactions
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 3)
        // Results should be sorted by date descending
        XCTAssertEqual(result.mergedTransactions[0].date, "2024-01-17")
        XCTAssertEqual(result.mergedTransactions[1].date, "2024-01-16")
        XCTAssertEqual(result.mergedTransactions[2].date, "2024-01-15")
    }

    // MARK: - Edge Cases

    func testMerge_emptyBothLists_returnsEmptyResult() async {
        // When
        let result = await conflictResolver.merge(
            local: [],
            remote: []
        )

        // Then
        XCTAssertTrue(result.mergedTransactions.isEmpty)
        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.deletedCount, 0)
    }

    func testMerge_localNewerThanRemote_keepsLocal() async {
        // Given
        let newerTime = "2024-01-15T12:00:00Z"
        let olderTime = "2024-01-15T10:00:00Z"

        let localTransaction = createTestTransaction(
            id: "id1",
            amount: "300",
            updatedAt: newerTime
        )
        let remoteTransaction = createTestTransaction(
            id: "id1",
            amount: "200",
            updatedAt: olderTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepNewest
        )

        // Then
        XCTAssertEqual(result.mergedTransactions[0].amount, "300")
    }

    func testMerge_differentCategories_detectsConflict() async {
        // Given
        let sameTime = "2024-01-15T10:00:00Z"

        let localTransaction = createTestTransactionWithCategory(
            id: "id1",
            category: "餐饮",
            updatedAt: sameTime
        )
        let remoteTransaction = createTestTransactionWithCategory(
            id: "id1",
            category: "购物",
            updatedAt: sameTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepBoth
        )

        // Then
        XCTAssertEqual(result.conflicts.count, 1)
    }

    func testMerge_differentMerchants_detectsConflict() async {
        // Given
        let sameTime = "2024-01-15T10:00:00Z"

        let localTransaction = createTestTransactionWithMerchant(
            id: "id1",
            merchant: "商家A",
            updatedAt: sameTime
        )
        let remoteTransaction = createTestTransactionWithMerchant(
            id: "id1",
            merchant: "商家B",
            updatedAt: sameTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepBoth
        )

        // Then
        XCTAssertEqual(result.conflicts.count, 1)
    }

    func testMerge_differentParticipants_detectsConflict() async {
        // Given
        let sameTime = "2024-01-15T10:00:00Z"

        let localTransaction = createTestTransactionWithParticipants(
            id: "id1",
            participants: "张三",
            updatedAt: sameTime
        )
        let remoteTransaction = createTestTransactionWithParticipants(
            id: "id1",
            participants: "张三;李四",
            updatedAt: sameTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepBoth
        )

        // Then
        XCTAssertEqual(result.conflicts.count, 1)
    }

    func testMerge_manyTransactions_performsCorrectly() async {
        // Given
        var localTransactions: [TransactionCSV] = []
        var remoteTransactions: [TransactionCSV] = []

        for i in 0..<50 {
            localTransactions.append(createTestTransaction(id: "local-\(i)", amount: "\(i * 10)"))
        }
        for i in 0..<50 {
            remoteTransactions.append(createTestTransaction(id: "remote-\(i)", amount: "\(i * 20)"))
        }

        // When
        let result = await conflictResolver.merge(
            local: localTransactions,
            remote: remoteTransactions
        )

        // Then
        XCTAssertEqual(result.mergedTransactions.count, 100)
        XCTAssertEqual(result.addedCount, 50)
    }

    func testMerge_keepNewestWithSameTimestamp_prefersLocal() async {
        // Given - when timestamps are exactly the same, keepNewest should prefer local (>=)
        let sameTime = "2024-01-15T10:00:00Z"

        let localTransaction = createTestTransaction(
            id: "id1",
            amount: "100",
            updatedAt: sameTime
        )
        let remoteTransaction = createTestTransaction(
            id: "id1",
            amount: "200",
            updatedAt: sameTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepNewest
        )

        // Then - with same timestamp and different content, local is preferred
        XCTAssertEqual(result.mergedTransactions.count, 1)
        XCTAssertEqual(result.mergedTransactions[0].amount, "100")
    }

    func testMerge_invalidTimestamp_usesDistantPast() async {
        // Given
        let localTransaction = createTestTransaction(
            id: "id1",
            amount: "100",
            updatedAt: "invalid-date"
        )
        let remoteTransaction = createTestTransaction(
            id: "id1",
            amount: "200",
            updatedAt: "2024-01-15T10:00:00Z"
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction],
            strategy: .keepNewest
        )

        // Then - remote should be kept because local has invalid (distant past) date
        XCTAssertEqual(result.mergedTransactions[0].amount, "200")
    }

    func testMerge_countsUpdatedRecords() async {
        // Given
        let olderTime = "2024-01-15T10:00:00Z"
        let newerTime = "2024-01-15T11:00:00Z"

        let localTransaction = createTestTransaction(
            id: "id1",
            amount: "100",
            updatedAt: olderTime
        )
        let remoteTransaction = createTestTransaction(
            id: "id1",
            amount: "150",
            updatedAt: newerTime
        )

        // When
        let result = await conflictResolver.merge(
            local: [localTransaction],
            remote: [remoteTransaction]
        )

        // Then
        XCTAssertEqual(result.updatedCount, 1)
    }

    // MARK: - Helper Methods

    private func createTestTransactionWithCategory(
        id: String,
        category: String,
        updatedAt: String = "2024-01-15T10:00:00Z"
    ) -> TransactionCSV {
        TransactionCSV(
            id: id,
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: updatedAt,
            date: "2024-01-15",
            amount: "100",
            type: "支出",
            category: category,
            payer: "测试用户",
            participants: "测试用户",
            note: "",
            merchant: "",
            source: "manual",
            ocrText: nil,
            currency: "CNY"
        )
    }

    private func createTestTransactionWithMerchant(
        id: String,
        merchant: String,
        updatedAt: String = "2024-01-15T10:00:00Z"
    ) -> TransactionCSV {
        TransactionCSV(
            id: id,
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: updatedAt,
            date: "2024-01-15",
            amount: "100",
            type: "支出",
            category: "餐饮",
            payer: "测试用户",
            participants: "测试用户",
            note: "",
            merchant: merchant,
            source: "manual",
            ocrText: nil,
            currency: "CNY"
        )
    }

    private func createTestTransactionWithParticipants(
        id: String,
        participants: String,
        updatedAt: String = "2024-01-15T10:00:00Z"
    ) -> TransactionCSV {
        TransactionCSV(
            id: id,
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: updatedAt,
            date: "2024-01-15",
            amount: "100",
            type: "支出",
            category: "餐饮",
            payer: "测试用户",
            participants: participants,
            note: "",
            merchant: "",
            source: "manual",
            ocrText: nil,
            currency: "CNY"
        )
    }

    private func createTestTransaction(
        id: String,
        date: String = "2024-01-15",
        amount: String = "100",
        note: String = "",
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
            note: note,
            merchant: "",
            source: "manual",
            ocrText: nil,
            currency: "CNY"
        )
    }
}
