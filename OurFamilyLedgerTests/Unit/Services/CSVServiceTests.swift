import XCTest
@testable import OurFamilyLedger

/// Tests for CSVService
final class CSVServiceTests: XCTestCase {
    private var csvService: CSVService!
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        csvService = CSVService()

        // Create a temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        csvService = nil
        tempDirectory = nil

        try await super.tearDown()
    }

    // MARK: - Transaction Tests

    func testReadTransactions_emptyFile_returnsEmptyArray() async throws {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("transactions_test.csv")
        // File doesn't exist

        // When
        let transactions = try await csvService.readTransactions(from: fileURL)

        // Then
        XCTAssertTrue(transactions.isEmpty)
    }

    func testReadTransactions_validCSV_parsesCorrectly() async throws {
        // Given
        let csvContent = """
        id,created_at,updated_at,date,amount,type,category,payer,participants,note,merchant,source,ocr_text,currency
        123e4567-e89b-12d3-a456-426614174000,2024-01-15T10:00:00Z,2024-01-15T10:00:00Z,2024-01-15,100.50,支出,餐饮,爸爸,爸爸;妈妈,午餐,海底捞,manual,,CNY
        """
        let fileURL = tempDirectory.appendingPathComponent("transactions_2024-01.csv")
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // When
        let transactions = try await csvService.readTransactions(from: fileURL)

        // Then
        XCTAssertEqual(transactions.count, 1)
        let transaction = transactions[0]
        XCTAssertEqual(transaction.id, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(transaction.amount, "100.50")
        XCTAssertEqual(transaction.type, "支出")
        XCTAssertEqual(transaction.category, "餐饮")
        XCTAssertEqual(transaction.payer, "爸爸")
        XCTAssertEqual(transaction.participants, "爸爸;妈妈")
        XCTAssertEqual(transaction.merchant, "海底捞")
    }

    func testWriteTransactions_validData_createsFile() async throws {
        // Given
        let transaction = TransactionCSV(
            id: UUID().uuidString,
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: "2024-01-15T10:00:00Z",
            date: "2024-01-15",
            amount: "50.00",
            type: "支出",
            category: "交通",
            payer: "测试用户",
            participants: "测试用户",
            note: "打车",
            merchant: "滴滴",
            source: "manual",
            ocrText: nil,
            currency: "CNY"
        )
        let fileURL = tempDirectory.appendingPathComponent("transactions_2024-01.csv")

        // When
        try await csvService.writeTransactions([transaction], to: fileURL)

        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // Verify content can be read back
        let readTransactions = try await csvService.readTransactions(from: fileURL)
        XCTAssertEqual(readTransactions.count, 1)
        XCTAssertEqual(readTransactions[0].amount, "50.00")
    }

    func testParseTransactionsFromContent_quotedFields_handlesCorrectly() async throws {
        // Given - CSV with quoted fields containing commas
        let csvContent = """
        id,created_at,updated_at,date,amount,type,category,payer,participants,note,merchant,source,ocr_text,currency
        abc123,2024-01-15T10:00:00Z,2024-01-15T10:00:00Z,2024-01-15,100.00,支出,餐饮,测试,"测试;用户2","备注, 含逗号",商户,manual,,CNY
        """

        // When
        let transactions = try await csvService.parseTransactionsFromContent(csvContent)

        // Then
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0].note, "备注, 含逗号")
        XCTAssertEqual(transactions[0].participants, "测试;用户2")
    }

    func testAppendTransaction_addsToExistingFile() async throws {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("transactions_2024-01.csv")
        let initialTransaction = TransactionCSV(
            id: "id1",
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: "2024-01-15T10:00:00Z",
            date: "2024-01-15",
            amount: "50.00",
            type: "支出",
            category: "餐饮",
            payer: "用户1",
            participants: "用户1",
            note: "",
            merchant: "",
            source: "manual",
            ocrText: nil,
            currency: "CNY"
        )
        try await csvService.writeTransactions([initialTransaction], to: fileURL)

        let newTransaction = TransactionCSV(
            id: "id2",
            createdAt: "2024-01-16T10:00:00Z",
            updatedAt: "2024-01-16T10:00:00Z",
            date: "2024-01-16",
            amount: "100.00",
            type: "支出",
            category: "购物",
            payer: "用户2",
            participants: "用户2",
            note: "",
            merchant: "",
            source: "manual",
            ocrText: nil,
            currency: "CNY"
        )

        // When
        try await csvService.appendTransaction(newTransaction, to: fileURL)

        // Then
        let transactions = try await csvService.readTransactions(from: fileURL)
        XCTAssertEqual(transactions.count, 2)
    }

    func testDeleteTransaction_removesFromFile() async throws {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("transactions_2024-01.csv")
        let transactions = [
            TransactionCSV(
                id: "id1",
                createdAt: "2024-01-15T10:00:00Z",
                updatedAt: "2024-01-15T10:00:00Z",
                date: "2024-01-15",
                amount: "50.00",
                type: "支出",
                category: "餐饮",
                payer: "用户",
                participants: "用户",
                note: "",
                merchant: "",
                source: "manual",
                ocrText: nil,
                currency: "CNY"
            ),
            TransactionCSV(
                id: "id2",
                createdAt: "2024-01-16T10:00:00Z",
                updatedAt: "2024-01-16T10:00:00Z",
                date: "2024-01-16",
                amount: "100.00",
                type: "支出",
                category: "购物",
                payer: "用户",
                participants: "用户",
                note: "",
                merchant: "",
                source: "manual",
                ocrText: nil,
                currency: "CNY"
            )
        ]
        try await csvService.writeTransactions(transactions, to: fileURL)

        // When
        try await csvService.deleteTransaction(id: "id1", from: fileURL)

        // Then
        let remainingTransactions = try await csvService.readTransactions(from: fileURL)
        XCTAssertEqual(remainingTransactions.count, 1)
        XCTAssertEqual(remainingTransactions[0].id, "id2")
    }

    // MARK: - Member Tests

    func testReadWriteMembers_roundTrip() async throws {
        // Given
        let member = MemberCSV(
            id: UUID().uuidString,
            name: "测试用户",
            nickname: "小测",
            role: "member",
            avatarColor: "blue",
            iCloudIdentifier: nil,
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: "2024-01-15T10:00:00Z"
        )
        let fileURL = tempDirectory.appendingPathComponent("members.csv")

        // When
        try await csvService.writeMembers([member], to: fileURL)
        let readMembers = try await csvService.readMembers(from: fileURL)

        // Then
        XCTAssertEqual(readMembers.count, 1)
        XCTAssertEqual(readMembers[0].name, "测试用户")
        XCTAssertEqual(readMembers[0].nickname, "小测")
    }

    // MARK: - Category Tests

    func testReadWriteCategories_roundTrip() async throws {
        // Given
        let category = CategoryCSV(
            id: UUID().uuidString,
            name: "餐饮",
            icon: "fork.knife",
            color: "gray",
            type: "支出",
            isDefault: "true",
            sortOrder: "0",
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: "2024-01-15T10:00:00Z"
        )
        let fileURL = tempDirectory.appendingPathComponent("categories.csv")

        // When
        try await csvService.writeCategories([category], to: fileURL)
        let readCategories = try await csvService.readCategories(from: fileURL)

        // Then
        XCTAssertEqual(readCategories.count, 1)
        XCTAssertEqual(readCategories[0].name, "餐饮")
        XCTAssertEqual(readCategories[0].icon, "fork.knife")
    }

    // MARK: - Utility Tests

    func testYearMonthString_formatsCorrectly() async {
        // Given
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-03-15")!

        // When
        let result = await csvService.yearMonthString(from: date)

        // Then
        XCTAssertEqual(result, "2024-03")
    }

    func testListTransactionFiles_findsCorrectFiles() async throws {
        // Given
        // Create some test files
        let file1 = tempDirectory.appendingPathComponent("transactions_2024-01.csv")
        let file2 = tempDirectory.appendingPathComponent("transactions_2024-02.csv")
        let otherFile = tempDirectory.appendingPathComponent("members.csv")

        try "test".write(to: file1, atomically: true, encoding: .utf8)
        try "test".write(to: file2, atomically: true, encoding: .utf8)
        try "test".write(to: otherFile, atomically: true, encoding: .utf8)

        // When
        let files = try await csvService.listTransactionFiles(in: tempDirectory)

        // Then
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains("transactions_2024-01.csv"))
        XCTAssertTrue(files.contains("transactions_2024-02.csv"))
        XCTAssertFalse(files.contains("members.csv"))
    }
}
