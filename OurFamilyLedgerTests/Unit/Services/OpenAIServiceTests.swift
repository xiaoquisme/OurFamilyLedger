import XCTest
@testable import OurFamilyLedger

final class OpenAIServiceTests: XCTestCase {

    var sut: OpenAIService!

    override func setUp() {
        super.setUp()
        let config = AIServiceConfig(
            provider: .openai,
            apiKey: "test-key",
            endpoint: "https://api.openai.com/v1",
            model: "gpt-4o-mini"
        )
        sut = OpenAIService(config: config)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - extractJSON Tests

    func testExtractJSON_withMarkdownCodeBlock_extractsJSON() {
        // Given
        let content = """
        ```json
        [{"amount": 100, "type": "expense"}]
        ```
        """

        // When
        let result = sut.extractJSON(from: content)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result, "[{\"amount\": 100, \"type\": \"expense\"}]")
    }

    func testExtractJSON_withMarkdownCodeBlockNoLanguage_extractsJSON() {
        // Given
        let content = """
        ```
        {"amount": 50.5, "type": "income"}
        ```
        """

        // When
        let result = sut.extractJSON(from: content)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result, "{\"amount\": 50.5, \"type\": \"income\"}")
    }

    func testExtractJSON_withMultilineJSON_extractsJSON() {
        // Given
        let content = """
        ```json
        [
          {
            "date": "2024-01-15",
            "amount": 128.50,
            "type": "expense",
            "category": "餐饮"
          }
        ]
        ```
        """

        // When
        let result = sut.extractJSON(from: content)

        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("\"date\": \"2024-01-15\""))
        XCTAssertTrue(result!.contains("\"amount\": 128.50"))
    }

    func testExtractJSON_withPrefixText_extractsJSON() {
        // Given
        let content = """
        Here is the parsed transaction data:

        ```json
        [{"amount": 200, "type": "expense", "category": "购物"}]
        ```

        Let me know if you need anything else.
        """

        // When
        let result = sut.extractJSON(from: content)

        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("\"amount\": 200"))
    }

    func testExtractJSON_withPlainJSON_returnsNil() {
        // Given
        let content = "[{\"amount\": 100}]"

        // When
        let result = sut.extractJSON(from: content)

        // Then
        XCTAssertNil(result, "Plain JSON without markdown should return nil")
    }

    func testExtractJSON_withEmptyContent_returnsNil() {
        // Given
        let content = ""

        // When
        let result = sut.extractJSON(from: content)

        // Then
        XCTAssertNil(result)
    }

    func testExtractJSON_withNoCodeBlock_returnsNil() {
        // Given
        let content = "This is just plain text without any code block."

        // When
        let result = sut.extractJSON(from: content)

        // Then
        XCTAssertNil(result)
    }
}
