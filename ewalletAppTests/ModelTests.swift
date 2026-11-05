//
//  ModelTests.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import XCTest
@testable import ewalletApp

@MainActor
final class ModelTests: XCTestCase {
    func testFetchWalletMapsBalanceAndCurrency() async throws {
        let client = ModelHTTPClientStub()
        let service = ApiServices(client: client)

        let wallet = try await service.fetchWallet()

        XCTAssertEqual(wallet.balance, Decimal(string: "1234.56"))
        XCTAssertEqual(wallet.currency, "USD")
        let request = await client.lastEndpoint
        guard case .wallet = request else {
            XCTFail("Expected the wallet endpoint")
            return
        }
    }

    func testFetchTransactionsMapsFiltersAndSortsNewestFirst() async throws {
        let client = ModelHTTPClientStub(page: page(items: [
            transaction(id: "older", type: .credit, date: 1),
            transaction(id: "debit", type: .debit, date: 3),
            transaction(id: "newer", type: .credit, date: 2)
        ]))
        let service = ApiServices(client: client)

        let result = try await service.fetchTransactions(page: 1, filter: .credit)

        XCTAssertEqual(result.items.map(\.id), ["newer", "older"])
        XCTAssertEqual(result.items.first?.type, .credit)
        XCTAssertEqual(result.items.first?.status, .completed)
        XCTAssertEqual(result.items.first?.merchant, "Test merchant")
        XCTAssertEqual(result.items.first?.currency, "USD")
        let request = await client.lastEndpoint
        guard case .transactions(let number, let size, let type) = request else {
            XCTFail("Expected the transactions endpoint")
            return
        }
        XCTAssertEqual(number, 1)
        XCTAssertEqual(size, 20)
        XCTAssertEqual(type, .credit)
    }

    func testDebitFilterAndAllFilter() throws {
        let dto = page(items: [transaction(type: .credit), transaction(id: "debit", type: .debit)])
        let debit = try TransactionPage(dto: dto, filter: .debit)
        let all = try TransactionPage(dto: dto, filter: .all)
        XCTAssertEqual(debit.items.map(\.id), ["debit"])
        XCTAssertEqual(all.items.count, 2)
    }

    func testPaginationUsesServerMetadataRatherThanFilteredItemCount() throws {
        let first = try TransactionPage(dto: page(items: [], totalPages: 3), filter: .all)
        let last = try TransactionPage(dto: page(items: [], number: 3, totalPages: 3), filter: .all)
        let empty = try TransactionPage(dto: page(items: [], totalPages: 0), filter: .all)
        XCTAssertEqual(first.nextPage, 2)
        XCTAssertNil(last.nextPage)
        XCTAssertNil(empty.nextPage)
    }

    func testInvalidPaginationIsRejected() throws {
        XCTAssertThrowsError(try TransactionPage(dto: page(items: [], number: 0), filter: .all)) {
            XCTAssertEqual($0 as? ModelError, .invalidPagination)
        }
        XCTAssertThrowsError(try TransactionPage(dto: page(items: [transaction()], totalPages: 0), filter: .all))
    }

    func testFetchTransactionsRejectsMismatchedResponsePage() async {
        let service = ApiServices(client: ModelHTTPClientStub(page: page(items: [], number: 2)))
        do {
            _ = try await service.fetchTransactions(page: 1, filter: .all)
            XCTFail("Expected a mismatched page to be rejected")
        } catch {
            XCTAssertEqual(error as? ModelError, .invalidPagination)
        }
    }

    func testSessionExpiryPropagatesToCaller() async {
        let client = ModelHTTPClientStub(error: .sessionExpired)
        do {
            _ = try await ApiServices(client: client).fetchWallet()
            XCTFail("Expected session expiry")
        } catch {
            XCTAssertEqual(error as? NetworkError, .sessionExpired)
        }
        do {
            _ = try await ApiServices(client: client).fetchTransactions(page: 1, filter: .all)
            XCTFail("Expected session expiry")
        } catch {
            XCTAssertEqual(error as? NetworkError, .sessionExpired)
        }
    }

    func testTransactionSignsAndCurrencyFormatting() throws {
        let formatter = Formatter(locale: Locale(identifier: "en_US"))
        let credit = try Transaction(dto: transaction(type: .credit))
        let debit = try Transaction(dto: transaction(type: .debit))
        XCTAssertEqual(credit.signedAmount, Decimal(string: "25.5"))
        XCTAssertEqual(debit.signedAmount, Decimal(string: "-25.5"))
        XCTAssertEqual(credit.formattedAmount(using: formatter), "+$25.50")
        XCTAssertEqual(debit.formattedAmount(using: formatter), "-$25.50")
        XCTAssertEqual(formatter.string(amount: 1234, currency: "JPY"), "¥1,234")
    }

    func testNegativeAmountIsRejectedInsteadOfReversingDebitSign() {
        XCTAssertThrowsError(try Transaction(dto: transaction(amount: -25))) {
            XCTAssertEqual($0 as? ModelError, .invalidAmount)
        }
    }

    func testAllTransactionStatusesMapToDomain() throws {
        for (dtoStatus, status) in [
            (TransactionStatusDTO.completed, TransactionStatus.completed),
            (.pending, .pending), (.failed, .failed)
        ] {
            let item = try Transaction(dto: transaction(status: dtoStatus))
            XCTAssertEqual(item.status, status)
        }
    }

    private func transaction(
        id: String = "tx_1", type: TransactionTypeDTO = .debit,
        date: TimeInterval = 1, amount: Decimal = 25.5,
        status: TransactionStatusDTO = .completed
    ) -> TransactionDTO {
        TransactionDTO(
            id: id, type: type, amount: amount, currency: "USD", merchant: "Test merchant",
            status: status, createdAt: Date(timeIntervalSince1970: date)
        )
    }

    private func page(items: [TransactionDTO], number: Int = 1, totalPages: Int = 3) -> TransactionPageDTO {
        TransactionPageDTO(page: number, pageSize: 20, totalPages: totalPages, items: items)
    }
}

// A test-only client; no mock backend or real network requests are used.
private actor ModelHTTPClientStub: HTTPClient {
    private let page: TransactionPageDTO
    private let error: NetworkError?
    private(set) var lastEndpoint: Endpoint?

    init(
        page: TransactionPageDTO = TransactionPageDTO(page: 1, pageSize: 20, totalPages: 0, items: []),
        error: NetworkError? = nil
    ) {
        self.page = page
        self.error = error
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response {
        lastEndpoint = endpoint
        if let error { throw error }
        let value: any Sendable
        switch endpoint {
        case .wallet: value = WalletDTO(balance: Decimal(123456) / 100, currency: "USD")
        case .transactions: value = page
        }
        guard let response = value as? Response else {
            throw NetworkError.decoding
        }
        return response
    }
}
