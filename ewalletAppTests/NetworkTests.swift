//
//  NetworkTests.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import XCTest
@testable import ewalletApp

@MainActor
final class NetworkTests: XCTestCase {
    func testRequestContainsAuthenticationAndPagination() throws {
        guard let url = URL(string: "https://wallet.mock") else {
            XCTFail("Invalid test URL")
            return
        }
        let request = try Endpoint.transactions(page: 2, type: .debit)
            .makeRequest(baseURL: url, token: "test-token")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/transactions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        guard let requestURL = request.url,
              let query = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems else {
            XCTFail("Expected pagination query")
            return
        }
        XCTAssertEqual(query.first { $0.name == "page" }?.value, "2")
        XCTAssertEqual(query.first { $0.name == "pageSize" }?.value, "20")
        XCTAssertEqual(query.first { $0.name == "type" }?.value, "debit")
    }

    func testRejectsHTTPAndInvalidPage() throws {
        guard let insecure = URL(string: "http://wallet.mock"),
              let secure = URL(string: "https://wallet.mock") else {
            XCTFail("Invalid test URLs")
            return
        }
        XCTAssertThrowsError(try Endpoint.wallet.makeRequest(baseURL: insecure, token: "test")) {
            XCTAssertEqual($0 as? NetworkError, .invalidRequest)
        }
        XCTAssertThrowsError(try Endpoint.transactions(page: 0).makeRequest(baseURL: secure, token: "test"))
        XCTAssertThrowsError(try Endpoint.transactions(page: 1, pageSize: 0).makeRequest(baseURL: secure, token: "test"))
    }

    func testWalletDecodesDecimalAmount() async throws {
        let session = MockAPI.makeSession()
        defer { session.invalidateAndCancel() }
        let client = try makeClient(session: session)

        let wallet: WalletDTO = try await client.send(.wallet)

        XCTAssertEqual(wallet.balance, Decimal(string: "1234.56"))
        XCTAssertEqual(wallet.currency, "USD")
    }

    func testPaginationReturnsSixtyUniqueTransactionsNewestFirst() async throws {
        let session = MockAPI.makeSession()
        defer { session.invalidateAndCancel() }
        let client = try makeClient(session: session)
        var items: [TransactionDTO] = []
        for page in 1...3 {
            let response: TransactionPageDTO = try await client.send(.transactions(page: page))
            XCTAssertEqual(response.page, page)
            XCTAssertEqual(response.pageSize, 20)
            XCTAssertEqual(response.totalPages, 3)
            XCTAssertEqual(response.items.count, 20)
            items += response.items
        }
        XCTAssertEqual(Set(items.map(\.id)).count, 60)
        XCTAssertEqual(items.map(\.createdAt), items.map(\.createdAt).sorted(by: >))
        XCTAssertEqual(items.first?.createdAt, ISO8601DateFormatter().date(from: "2026-10-20T08:30:00Z"))
        XCTAssertEqual(items.first?.amount, Decimal(string: "12.5"))
        let beyondLast: TransactionPageDTO = try await client.send(.transactions(page: 4))
        XCTAssertTrue(beyondLast.items.isEmpty)
    }

    func testFiltersApplyBeforePagination() async throws {
        let session = MockAPI.makeSession()
        defer { session.invalidateAndCancel() }
        let client = try makeClient(session: session)
        for filter in [TransactionQueryType.credit, .debit] {
            let first: TransactionPageDTO = try await client.send(.transactions(page: 1, type: filter))
            let second: TransactionPageDTO = try await client.send(.transactions(page: 2, type: filter))
            XCTAssertEqual(first.totalPages, 2)
            XCTAssertEqual(first.items.count, 20)
            XCTAssertEqual(second.items.count, 10)
            XCTAssertTrue((first.items + second.items).allSatisfy { $0.type.rawValue == filter.rawValue })
        }
    }

    func testEmptyScenarioReturnsNoTransactions() async throws {
        let session = MockAPI.makeSession(scenario: .empty)
        defer { session.invalidateAndCancel() }
        let response: TransactionPageDTO = try await makeClient(session: session).send(.transactions(page: 1))
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertEqual(response.totalPages, 0)
    }

    func testMapsMockErrorsToTypedErrors() async throws {
        let cases: [(MockAPI.Scenario, NetworkError)] = [
            (.sessionExpired, .sessionExpired), (.rateLimited, .rateLimited),
            (.serverError, .server(503)), (.offline, .offline), (.malformed, .decoding)
        ]
        for (scenario, expected) in cases {
            let session = MockAPI.makeSession(scenario: scenario)
            defer { session.invalidateAndCancel() }
            do {
                let _: WalletDTO = try await makeClient(session: session).send(.wallet)
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? NetworkError, expected)
            }
        }
    }

    func testTokenIsReadForEveryRequest() async throws {
        let session = MockAPI.makeSession()
        defer { session.invalidateAndCancel() }
        let tokens = TestTokenSource()
        let client = try makeClient(session: session, tokenProvider: { await tokens.read() })
        let _: WalletDTO = try await client.send(.wallet)
        await tokens.clear()

        do {
            let _: WalletDTO = try await client.send(.wallet)
            XCTFail("Expected session expiry after token removal")
        } catch {
            XCTAssertEqual(error as? NetworkError, .sessionExpired)
        }
        let reads = await tokens.reads
        XCTAssertEqual(reads, 2)
    }

    func testSlowResponseCanBeCancelled() async throws {
        let session = MockAPI.makeSession(scenario: .slow)
        defer { session.invalidateAndCancel() }
        let client = try makeClient(session: session)
        let task = Task { () -> WalletDTO in try await client.send(.wallet) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testSlowScenarioEventuallySucceeds() async throws {
        let session = MockAPI.makeSession(scenario: .slow)
        defer { session.invalidateAndCancel() }
        let client = try makeClient(session: session)
        let start = ContinuousClock.now
        let _: WalletDTO = try await client.send(.wallet)
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .milliseconds(1500))
    }

    private func makeClient(
        session: URLSession,
        tokenProvider: @escaping @Sendable () async throws -> String? = { "test-token" }
    ) throws -> URLSessionHTTPClient {
        guard let url = URL(string: "https://wallet.mock") else {
            XCTFail("Invalid test URL")
            throw NetworkError.invalidRequest
        }
        return URLSessionHTTPClient(baseURL: url, session: session, tokenProvider: tokenProvider)
    }
}

private actor TestTokenSource {
    var token: String? = "test-token"
    var reads = 0

    func read() -> String? {
        reads += 1
        return token
    }

    func clear() { token = nil }
}
