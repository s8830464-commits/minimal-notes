import XCTest
@testable import NotesApp

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("Handler is not set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class AIServiceTests: XCTestCase {
    private var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        mockSession = nil
        super.tearDown()
    }

    func testMissingAPIKeyThrowsError() async {
        let service = AIService(session: mockSession)
        do {
            _ = try await service.fixErrors(in: "Привет мир", apiKey: "  ")
            XCTFail("Expected missingAPIKey error")
        } catch let error as AIError {
            switch error {
            case .missingAPIKey:
                XCTAssertNotNil(error.errorDescription)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testEmptyTextThrowsError() async {
        let service = AIService(session: mockSession)
        do {
            _ = try await service.fixErrors(in: "   ", apiKey: "valid-key")
            XCTFail("Expected emptyText error")
        } catch let error as AIError {
            switch error {
            case .emptyText:
                XCTAssertNotNil(error.errorDescription)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSuccessfulOpenRouterResponseReturnsCleanText() async throws {
        let expectedCorrected = "Привет, мир! Всё отлично."
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
                "id": "gen-123",
                "choices": [
                    {
                        "message": {
                            "role": "assistant",
                            "content": "\(expectedCorrected)"
                        }
                    }
                ]
            }
            """
            return (response, Data(json.utf8))
        }

        let service = AIService(session: mockSession)
        let result = try await service.fixErrors(in: "привет мир все отлично", apiKey: "test-key")
        XCTAssertEqual(result, expectedCorrected)
    }

    func testServerErrorMessageIsCaptured() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
                "error": {
                    "message": "Invalid API Key",
                    "code": 401
                }
            }
            """
            return (response, Data(json.utf8))
        }

        let service = AIService(session: mockSession)
        do {
            _ = try await service.fixErrors(in: "Текст", apiKey: "bad-key")
            XCTFail("Expected error")
        } catch let error as AIError {
            switch error {
            case .serverError(let msg):
                XCTAssertTrue(msg.contains("Invalid API Key"))
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
