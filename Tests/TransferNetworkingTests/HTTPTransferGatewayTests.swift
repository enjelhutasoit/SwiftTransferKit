//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferNetworking
import XCTest

@MainActor
final class HTTPTransferGatewayTests: XCTestCase {
    func testSubmitMapsAcceptedResponseAndSendsStoredIdentityAndKey() async throws {
        let transfer = try makeTransfer()
        let body = responseBody(
            intentID: transfer.intent.id,
            status: "accepted"
        )
        let (gateway, endpoint) = try makeGateway(
            reply: .response(statusCode: 202, body: body)
        )

        let result = try await gateway.submit(transfer)

        XCTAssertEqual(result, .accepted)

        let requests = StubURLProtocol.registry.requests(for: endpoint)
        XCTAssertEqual(requests.count, 1)

        let captured = try XCTUnwrap(requests.first)
        XCTAssertEqual(captured.request.url, endpoint)
        XCTAssertEqual(captured.request.httpMethod, "POST")
        XCTAssertEqual(
            captured.request.value(forHTTPHeaderField: "Idempotency-Key"),
            transfer.idempotencyKey.uuidString
        )
        XCTAssertEqual(
            captured.request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        XCTAssertEqual(
            captured.request.value(forHTTPHeaderField: "Accept"),
            "application/json"
        )

        let payload = try JSONDecoder().decode(
            SubmittedPayload.self,
            from: captured.body
        )

        XCTAssertEqual(payload.intentID, transfer.intent.id)
        XCTAssertEqual(payload.minorUnits, 125_000)
        XCTAssertEqual(payload.currency, "IDR")
        XCTAssertEqual(payload.scale, 2)
    }

    func testSubmitMapsExplicitRejection() async throws {
        let transfer = try makeTransfer()
        let body = responseBody(
            intentID: transfer.intent.id,
            status: "rejected"
        )
        let (gateway, _) = try makeGateway(
            reply: .response(statusCode: 422, body: body)
        )

        let result = try await gateway.submit(transfer)

        XCTAssertEqual(result, .rejected)
    }

    func testSubmitThrowsTimeoutWithoutRetrying() async throws {
        let transfer = try makeTransfer()
        let (gateway, endpoint) = try makeGateway(
            reply: .failure(URLError(.timedOut))
        )

        await assertSubmissionError(
            .timedOut,
            gateway: gateway,
            transfer: transfer
        )

        XCTAssertEqual(
            StubURLProtocol.registry.requests(for: endpoint).count,
            1
        )
    }

    func testSubmitRedactsUnderlyingTransportError() async throws {
        let transfer = try makeTransfer()
        let underlyingError = URLError(
            .cannotConnectToHost,
            userInfo: [
                NSLocalizedDescriptionKey: "sensitive transport diagnostic"
            ]
        )
        let (gateway, _) = try makeGateway(
            reply: .failure(underlyingError)
        )

        await assertSubmissionError(
            .transportFailure,
            gateway: gateway,
            transfer: transfer
        )
    }

    func testSubmitDoesNotTreatUnexpectedHTTPStatusAsRejection() async throws {
        let transfer = try makeTransfer()
        let (gateway, _) = try makeGateway(
            reply: .response(
                statusCode: 500,
                body: Data("sensitive server diagnostic".utf8)
            )
        )

        await assertSubmissionError(
            .unexpectedHTTPStatus(500),
            gateway: gateway,
            transfer: transfer
        )
    }

    func testSubmitRejectsInvalidOrInconsistentResponses() async throws {
        let transfer = try makeTransfer()
        let otherIntentID = try XCTUnwrap(
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")
        )

        let responses: [(statusCode: Int, body: Data)] = [
            (
                202,
                Data("invalid JSON".utf8)
            ),
            (
                202,
                responseBody(intentID: otherIntentID, status: "accepted")
            ),
            (
                202,
                responseBody(intentID: transfer.intent.id, status: "rejected")
            ),
            (
                422,
                responseBody(intentID: transfer.intent.id, status: "accepted")
            ),
            (
                422,
                Data("rejection without a valid payload".utf8)
            ),
            (
                202,
                responseBody(intentID: transfer.intent.id, status: "settled")
            ),
        ]

        for response in responses {
            let (gateway, _) = try makeGateway(
                reply: .response(
                    statusCode: response.statusCode,
                    body: response.body
                )
            )

            await assertSubmissionError(
                .invalidResponse,
                gateway: gateway,
                transfer: transfer
            )
        }
    }

    func testInitializationRejectsInvalidEndpoints() throws {
        let addresses = [
            "http://example.test/transfers",
            "https://user:password@example.test/transfers",
            "https://example.test/transfers#fragment",
        ]

        for address in addresses {
            let endpoint = try XCTUnwrap(URL(string: address))

            XCTAssertThrowsError(
                try HTTPTransferGateway(endpoint: endpoint)
            ) { error in
                XCTAssertEqual(
                    error as? TransferNetworkError,
                    .invalidEndpoint
                )
            }
        }
    }

    private func makeTransfer() throws -> JournaledTransfer {
        let intentID = try XCTUnwrap(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let idempotencyKey = try XCTUnwrap(
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
        let amount = try Money(
            minorUnits: 125_000,
            currencyCode: "IDR",
            scale: 2
        )

        return JournaledTransfer(
            intent: TransferIntent(id: intentID, amount: amount),
            idempotencyKey: idempotencyKey
        )
    }

    private func responseBody(intentID: UUID, status: String) -> Data {
        Data(
            """
            {
                "intentID": "\(intentID.uuidString)",
                "status": "\(status)"
            }
            """.utf8
        )
    }

    private func makeGateway(
        reply: StubReply
    ) throws -> (HTTPTransferGateway, URL) {
        let endpoint = try XCTUnwrap(
            URL(string: "https://\(UUID().uuidString).example.test/transfers")
        )
        let registry = StubURLProtocol.registry
        registry.register(reply, for: endpoint)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        addTeardownBlock {
            session.invalidateAndCancel()
            registry.remove(endpoint)
        }

        let gateway = try HTTPTransferGateway(
            endpoint: endpoint,
            session: session
        )

        return (gateway, endpoint)
    }

    private func assertSubmissionError(
        _ expected: TransferNetworkError,
        gateway: HTTPTransferGateway,
        transfer: JournaledTransfer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await gateway.submit(transfer)
            XCTFail("Expected submission to throw.", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? TransferNetworkError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private struct SubmittedPayload: Decodable {
    let intentID: UUID
    let minorUnits: Int64
    let currency: String
    let scale: Int
}

private enum StubReply: Sendable {
    case response(statusCode: Int, body: Data)
    case failure(URLError)
}

private struct CapturedRequest: Sendable {
    let request: URLRequest
    let body: Data
}

/// Every access to mutable storage is protected by the lock.
private final class StubRegistry: @unchecked Sendable {
    private struct Entry {
        let reply: StubReply
        var requests: [CapturedRequest] = []
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]

    func register(_ reply: StubReply, for endpoint: URL) {
        lock.lock()
        defer { lock.unlock() }

        entries[endpoint] = Entry(reply: reply)
    }

    func reply(for request: URLRequest, body: Data) throws -> StubReply {
        lock.lock()
        defer { lock.unlock() }

        guard let endpoint = request.url,
              var entry = entries[endpoint] else {
            throw URLError(.resourceUnavailable)
        }

        entry.requests.append(
            CapturedRequest(request: request, body: body)
        )
        entries[endpoint] = entry
        return entry.reply
    }

    func requests(for endpoint: URL) -> [CapturedRequest] {
        lock.lock()
        defer { lock.unlock() }

        return entries[endpoint]?.requests ?? []
    }

    func remove(_ endpoint: URL) {
        lock.lock()
        defer { lock.unlock() }

        entries.removeValue(forKey: endpoint)
    }
}

/// Adds no mutable instance state; shared fixtures use the locked registry.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = StubRegistry()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let body = try requestBody()
            let reply = try Self.registry.reply(for: request, body: body)

            switch reply {
            case let .failure(error):
                client?.urlProtocol(self, didFailWithError: error)

            case let .response(statusCode, body):
                guard let url = request.url,
                      let response = HTTPURLResponse(
                        url: url,
                        statusCode: statusCode,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                      ) else {
                    throw URLError(.badServerResponse)
                }

                client?.urlProtocol(
                    self,
                    didReceive: response,
                    cacheStoragePolicy: .notAllowed
                )
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Responses are delivered synchronously; no deferred work remains.
    }

    private func requestBody() throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)

        while true {
            let count = stream.read(&buffer, maxLength: 1_024)

            guard count >= 0 else {
                throw URLError(.cannotDecodeRawData)
            }

            guard count > 0 else {
                return body
            }

            body.append(contentsOf: buffer.prefix(count))
        }
    }
}
