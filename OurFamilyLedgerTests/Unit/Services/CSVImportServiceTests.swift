import XCTest
@testable import OurFamilyLedger

final class CSVImportServiceTests: XCTestCase {

    // MARK: - isNativeFormat Tests

    func testIsNativeFormat_withValidHeader_returnsTrue() {
        // Given
        let content = """
        id,date,amount,type,category_id,payer_id,participants,note,merchant,source,created_at,updated_at
        123,2026-01-30T01:04:50Z,25,expense,cat-id,payer-id,,交通费用,,manual,2026-01-30T01:04:50Z,2026-01-30T01:04:50Z
        """

        // When
        let result = CSVImportService.isNativeFormat(content: content)

        // Then
        XCTAssertTrue(result)
    }

    func testIsNativeFormat_withDifferentHeader_returnsFalse() {
        // Given
        let content = """
        date,description,amount,category
        2026-01-30,购物,100,日用品
        """

        // When
        let result = CSVImportService.isNativeFormat(content: content)

        // Then
        XCTAssertFalse(result)
    }

    func testIsNativeFormat_withEmptyContent_returnsFalse() {
        // Given
        let content = ""

        // When
        let result = CSVImportService.isNativeFormat(content: content)

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - parseCSVLine Tests

    func testParseCSVLine_withSimpleLine_returnsCorrectFields() {
        // Given
        let line = "field1,field2,field3"

        // When
        let result = CSVImportService.parseCSVLine(line)

        // Then
        XCTAssertEqual(result, ["field1", "field2", "field3"])
    }

    func testParseCSVLine_withQuotedComma_handlesCorrectly() {
        // Given
        let line = "field1,\"field with, comma\",field3"

        // When
        let result = CSVImportService.parseCSVLine(line)

        // Then
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[1], "field with, comma")
    }

    func testParseCSVLine_withEmptyFields_preservesEmpty() {
        // Given
        let line = "field1,,field3,"

        // When
        let result = CSVImportService.parseCSVLine(line)

        // Then
        XCTAssertEqual(result, ["field1", "", "field3", ""])
    }

    func testParseCSVLine_withChineseCharacters_handlesCorrectly() {
        // Given
        let line = "123,\"购买商品，含优惠\",餐饮"

        // When
        let result = CSVImportService.parseCSVLine(line)

        // Then
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[1], "购买商品，含优惠")
        XCTAssertEqual(result[2], "餐饮")
    }

    // MARK: - parseNativeCSV Tests

    func testParseNativeCSV_withValidContent_returnsDrafts() {
        // Given
        let content = """
        id,date,amount,type,category_id,payer_id,participants,note,merchant,source,created_at,updated_at
        353D68C8-DD7C-4438-A6C2-B48AF684F75B,2026-01-30T01:04:50Z,25,expense,D8E4159D-984A-4161-87BC-04D8D6810657,73495C4A-B68B-42BE-8436-6F17430976ED,,交通费用,,manual,2026-01-30T01:04:50Z,2026-01-30T01:04:50Z
        982C340D-115E-4A4E-90CE-F8DE419B3B14,2026-01-29T16:00:00Z,3582,income,5FE29086-3801-4771-89FF-04397C5FC7E7,73495C4A-B68B-42BE-8436-6F17430976ED,73495C4A-B68B-42BE-8436-6F17430976ED,入账住房公积金,招商银行,text,2026-01-30T01:05:03Z,2026-01-30T01:05:03Z
        """

        // When
        let drafts = CSVImportService.parseNativeCSV(content: content)

        // Then
        XCTAssertEqual(drafts.count, 2)

        // 验证第一条交易
        XCTAssertEqual(drafts[0].amount, 25)
        XCTAssertEqual(drafts[0].type, .expense)
        XCTAssertEqual(drafts[0].note, "交通费用")
        XCTAssertEqual(drafts[0].source, .manual)

        // 验证第二条交易
        XCTAssertEqual(drafts[1].amount, 3582)
        XCTAssertEqual(drafts[1].type, .income)
        XCTAssertEqual(drafts[1].note, "入账住房公积金")
        XCTAssertEqual(drafts[1].merchant, "招商银行")
        XCTAssertEqual(drafts[1].source, .text)
    }

    func testParseNativeCSV_withOnlyHeader_returnsEmpty() {
        // Given
        let content = "id,date,amount,type,category_id,payer_id,participants,note,merchant,source,created_at,updated_at"

        // When
        let drafts = CSVImportService.parseNativeCSV(content: content)

        // Then
        XCTAssertTrue(drafts.isEmpty)
    }

    func testParseNativeCSV_withInvalidDate_skipsRow() {
        // Given
        let content = """
        id,date,amount,type,category_id,payer_id,participants,note,merchant,source,created_at,updated_at
        123,invalid-date,25,expense,cat-id,payer-id,,note,,manual,2026-01-30T01:04:50Z,2026-01-30T01:04:50Z
        456,2026-01-30T01:04:50Z,50,expense,cat-id,payer-id,,valid note,,manual,2026-01-30T01:04:50Z,2026-01-30T01:04:50Z
        """

        // When
        let drafts = CSVImportService.parseNativeCSV(content: content)

        // Then
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].note, "valid note")
    }

    func testParseNativeCSV_withQuotedNote_handlesCorrectly() {
        // Given
        let content = """
        id,date,amount,type,category_id,payer_id,participants,note,merchant,source,created_at,updated_at
        123,2026-01-30T01:04:50Z,100,expense,cat-id,payer-id,,"商品总价100，优惠-10，实付90",商户名,manual,2026-01-30T01:04:50Z,2026-01-30T01:04:50Z
        """

        // When
        let drafts = CSVImportService.parseNativeCSV(content: content)

        // Then
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].note, "商品总价100，优惠-10，实付90")
    }

    func testParseNativeCSV_withDecimalAmount_handlesCorrectly() {
        // Given
        let content = """
        id,date,amount,type,category_id,payer_id,participants,note,merchant,source,created_at,updated_at
        123,2026-01-30T01:04:50Z,15.6,expense,cat-id,payer-id,,午餐,食堂,manual,2026-01-30T01:04:50Z,2026-01-30T01:04:50Z
        """

        // When
        let drafts = CSVImportService.parseNativeCSV(content: content)

        // Then
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].amount, Decimal(string: "15.6"))
    }

    // MARK: - parseNativeCSVLines Tests

    func testParseNativeCSVLines_withEmptyArray_returnsEmpty() {
        // Given
        let lines: [String] = []

        // When
        let drafts = CSVImportService.parseNativeCSVLines(lines)

        // Then
        XCTAssertTrue(drafts.isEmpty)
    }

    func testParseNativeCSVLines_withInsufficientFields_skipsRow() {
        // Given
        let lines = [
            "field1,field2,field3", // 只有3个字段，少于10个
            "123,2026-01-30T01:04:50Z,25,expense,cat-id,payer-id,,note,,manual,created,updated" // 完整的12个字段
        ]

        // When
        let drafts = CSVImportService.parseNativeCSVLines(lines)

        // Then
        XCTAssertEqual(drafts.count, 1)
    }
}
