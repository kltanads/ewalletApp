//
//  TransactionHistoryViewModelTests.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import XCTest
@testable import ewalletApp

@MainActor
final class TransactionHistoryViewModelTests: XCTestCase {
    func testPaginationMergesDuplicatesAndStopsAtLastPage() async throws {
        let service = HistoryServiceStub(pages: [
            try page(1, ids: [3, 2]), try page(2, ids: [2, 1])
        ])
        let model = TransactionHistoryViewModel(service: service)
        await model.load()
        XCTAssertEqual(model.transactions.map(\.id), ["3", "2"])
        await model.loadNextPage()
        await model.loadNextPage()
        XCTAssertEqual(model.transactions.map(\.id), ["3", "2", "1"])
        XCTAssertNil(model.nextPage)
        let requests = await service.requests
        XCTAssertEqual(requests.map(\.page), [1, 2])
    }

    func testFailedPageKeepsExistingItemsAndRetriesSamePage() async throws {
        let service = HistoryServiceStub(pages: [try page(1, ids: [3]), try page(2, ids: [1])])
        let model = TransactionHistoryViewModel(service: service)
        await model.load()
        await service.setError(.offline)
        await model.loadNextPage()
        guard case .failed = model.state else { return XCTFail("Expected an error") }
        XCTAssertEqual(model.transactions.map(\.id), ["3"])
        await service.setError(nil)
        await model.retry()
        XCTAssertEqual(model.transactions.map(\.id), ["3", "1"])
        let requests = await service.requests
        XCTAssertEqual(requests.map(\.page), [1, 2, 2])
    }

    func testRefreshReplacesPreviouslyLoadedPages() async throws {
        let service = HistoryServiceStub(pages: [try page(1, ids: [3]), try page(2, ids: [1])])
        let model = TransactionHistoryViewModel(service: service)
        await model.load()
        await model.loadNextPage()
        await model.refresh()
        XCTAssertEqual(model.transactions.map(\.id), ["3"])
        XCTAssertEqual(model.nextPage, 2)
    }

    func testFilterStartsAtPageOne() async throws {
        let service = HistoryServiceStub(pages: [try page(1, ids: [3]), try page(2, ids: [1])])
        let model = TransactionHistoryViewModel(service: service)
        await model.load()
        await model.loadNextPage()
        await model.selectFilter(.credit)
        XCTAssertEqual(model.filter, .credit)
        XCTAssertEqual(model.transactions.map(\.id), ["3"])
        let requests = await service.requests
        XCTAssertEqual(requests.last?.page, 1)
        XCTAssertEqual(requests.last?.filter, .credit)
    }

    func testEmptyPageCanContinueUsingServerPagination() async throws {
        let service = HistoryServiceStub(pages: [try page(1, ids: []), try page(2, ids: [1])])
        let model = TransactionHistoryViewModel(service: service)
        await model.load()
        XCTAssertEqual(model.state, .empty)
        await model.loadNextPage()
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.transactions.count, 1)
    }

    func testSessionExpiryClearsTransactions() async throws {
        let service = HistoryServiceStub(pages: [try page(1, ids: [3])])
        let model = TransactionHistoryViewModel(service: service)
        await model.load()
        await service.setError(.sessionExpired)
        await model.refresh()
        XCTAssertEqual(model.state, .sessionExpired)
        XCTAssertTrue(model.transactions.isEmpty)
    }

    func testOldResponseCannotOverwriteFilterResults() async throws {
        let started = expectation(description: "First request started")
        let service = HistoryServiceStub(pages: [try page(1, ids: [3])], onStart: { started.fulfill() })
        let model = TransactionHistoryViewModel(service: service)
        let first = Task { await model.load() }
        await fulfillment(of: [started], timeout: 2)
        await model.selectFilter(.debit)
        await service.resume()
        await first.value
        XCTAssertEqual(model.filter, .debit)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.transactions.map(\.id), ["3"])
    }

    func testLockDiscardsInFlightResponse() async throws {
        let started = expectation(description: "Request started")
        let service = HistoryServiceStub(pages: [try page(1, ids: [3])], onStart: { started.fulfill() })
        let model = TransactionHistoryViewModel(service: service)
        let task = Task { await model.load() }
        await fulfillment(of: [started], timeout: 2)
        model.cancelLoading()
        await service.resume()
        await task.value
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.transactions.isEmpty)
    }

    func testDetailFormatting() throws {
        guard let transaction = try page(1, ids: [3]).items.first else {
            return XCTFail("Expected a transaction")
        }
        let model = TransactionDetailViewModel(transaction: transaction,
            formatter: ewalletApp.Formatter(locale: Locale(identifier: "en_US")))
        XCTAssertEqual(model.transactionID, "3")
        XCTAssertEqual(model.amount, "+$25.00")
        XCTAssertEqual(model.type, "Credit")
        XCTAssertEqual(model.status, "Completed")
        XCTAssertFalse(model.date.isEmpty)
    }

    private func page(_ number: Int, ids: [Int]) throws -> TransactionPage {
        try TransactionPage(dto: TransactionPageDTO(page: number, pageSize: 20, totalPages: 2,
            items: ids.map { id in
                TransactionDTO(id: String(id), type: .credit, amount: 25, currency: "USD",
                    merchant: "Merchant", status: .completed, createdAt: Date(timeIntervalSince1970: Double(id)))
            }), filter: .all)
    }
}

private actor HistoryServiceStub: ApiServicing {
    struct Request: Sendable { let page: Int; let filter: TransactionFilter }
    private let pages: [TransactionPage]
    private var error: NetworkError?
    private var onStart: (@Sendable () -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var requests: [Request] = []

    init(pages: [TransactionPage], onStart: (@Sendable () -> Void)? = nil) {
        self.pages = pages
        self.onStart = onStart
    }

    func fetchWallet() async throws -> Wallet { throw NetworkError.notConfigured }

    func fetchTransactions(page: Int, filter: TransactionFilter) async throws -> TransactionPage {
        requests.append(Request(page: page, filter: filter))
        if let onStart {
            self.onStart = nil
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onStart()
            }
            // Simulate a late failure from a superseded request.
            throw NetworkError.sessionExpired
        }
        if let error { throw error }
        guard let result = pages.first(where: { $0.page == page }) else { throw NetworkError.invalidResponse }
        return result
    }

    func setError(_ error: NetworkError?) { self.error = error }
    func resume() { continuation?.resume(); continuation = nil }
}
