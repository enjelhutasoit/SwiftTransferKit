//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore

public struct HTTPTransferGateway: TransferGateway {
    private let endpoint: URL
    private let session: URLSession
    private let taskDelegate = TransferTaskDelegate()

    /// Creates a gateway for the simulated submission contract.
    ///
    /// Use a foreground session. Tests may inject an ephemeral session
    /// configured with a URLProtocol stub.
    public init(
        endpoint: URL,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) throws {
        guard endpoint.scheme?.lowercased() == "https",
              let host = endpoint.host,
              !host.isEmpty,
              endpoint.user == nil,
              endpoint.password == nil,
              endpoint.fragment == nil else {
            throw TransferNetworkError.invalidEndpoint
        }

        self.endpoint = endpoint
        self.session = session
    }

    public func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        let request = try makeRequest(for: transfer)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(
                for: request,
                delegate: taskDelegate
            )
        } catch let error as URLError where error.code == .timedOut {
            throw TransferNetworkError.timedOut
        } catch {
            throw TransferNetworkError.transportFailure
        }

        return try mapResponse(
            data: data,
            response: response,
            expectedIntentID: transfer.intent.id
        )
    }

    private func makeRequest(
        for transfer: JournaledTransfer
    ) throws -> URLRequest {
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            transfer.idempotencyKey.uuidString,
            forHTTPHeaderField: "Idempotency-Key"
        )

        do {
            request.httpBody = try JSONEncoder().encode(
                TransferRequestDTO(transfer: transfer)
            )
        } catch {
            throw TransferNetworkError.requestEncodingFailed
        }

        return request
    }

    private func mapResponse(
        data: Data,
        response: URLResponse,
        expectedIntentID: UUID
    ) throws -> TransferSubmissionResult {
        guard let response = response as? HTTPURLResponse else {
            throw TransferNetworkError.invalidResponse
        }

        guard response.statusCode == 202 || response.statusCode == 422 else {
            throw TransferNetworkError.unexpectedHTTPStatus(
                response.statusCode
            )
        }

        let payload: TransferResponseDTO

        do {
            payload = try JSONDecoder().decode(
                TransferResponseDTO.self,
                from: data
            )
        } catch {
            throw TransferNetworkError.invalidResponse
        }

        guard payload.intentID == expectedIntentID else {
            throw TransferNetworkError.invalidResponse
        }

        switch (response.statusCode, payload.status) {
        case (202, .accepted):
            return .accepted

        case (422, .rejected):
            return .rejected

        default:
            throw TransferNetworkError.invalidResponse
        }
    }
}

private final class TransferTaskDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
