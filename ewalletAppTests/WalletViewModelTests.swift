//
//  WalletViewModelTests.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import XCTest
import UIKit
@testable import ewalletApp

@MainActor
final class WalletViewModelTests: XCTestCase {
    func testLoadsBalanceCurrencyAndFiveLatestTransactions() async throws {
        let service = try WalletServiceStub(transactionCount: 8)
        let model = makeModel(service)
        var states: [WalletViewModel.State] = []
        model.onStateChange = { states.append($0) }

        await model.load()

        XCTAssertEqual(states, [.loading, .loaded])
        XCTAssertEqual(model.balanceText, "$1,234.56")
        XCTAssertEqual(model.currencyText, "USD")
        XCTAssertEqual(model.transactions.count, 5)
        XCTAssertEqual(model.transactions.first?.merchant, "Merchant 7")
        XCTAssertEqual(model.transactions.last?.merchant, "Merchant 3")
        let request = await service.lastPage
        XCTAssertEqual(request, 1)
        let filter = await service.lastFilter
        XCTAssertEqual(filter, .all)
    }

    func testBalanceVisibilityCanBeToggled() async throws {
        let model = makeModel(try WalletServiceStub())
        await model.load()
        model.toggleBalance()
        XCTAssertEqual(model.balanceText, "****")
        XCTAssertEqual(model.currencyText, "USD")
        XCTAssertTrue(model.isBalanceHidden)
        model.toggleBalance()
        XCTAssertEqual(model.balanceText, "$1,234.56")
    }

    func testEmptyTransactionsStillShowsBalance() async throws {
        let model = makeModel(try WalletServiceStub())
        await model.load()
        XCTAssertEqual(model.state, .loaded)
        XCTAssertTrue(model.transactions.isEmpty)
        XCTAssertEqual(model.balanceText, "$1,234.56")
    }

    func testErrorsShowMessagesAndCanBeRetried() async throws {
        for error in [NetworkError.offline, .timeout, .rateLimited, .server(503), .notConfigured] {
            let service = try WalletServiceStub(error: error)
            let model = makeModel(service)
            await model.load()
            guard case .failed(let message) = model.state else {
                XCTFail("Expected a retryable error")
                return
            }
            XCTAssertFalse(message.isEmpty)
            XCTAssertEqual(model.balanceText, "—")
            await service.setError(nil)
            await model.load()
            XCTAssertEqual(model.state, .loaded)
        }
    }

    func testSessionExpiryIsReportedSeparately() async throws {
        let model = makeModel(try WalletServiceStub(error: .sessionExpired))
        await model.load()
        XCTAssertEqual(model.state, .sessionExpired)
        XCTAssertTrue(model.transactions.isEmpty)
        XCTAssertEqual(model.balanceText, "—")
    }

    func testLockDiscardsAnOutstandingResponse() async throws {
        let started = expectation(description: "Wallet request started")
        let service = try WalletServiceStub(suspend: true, onStart: { started.fulfill() })
        let model = makeModel(service)
        let task = Task { await model.load() }
        await fulfillment(of: [started], timeout: 1)
        await model.load()
        model.cancelLoading()
        await service.resumeWallet()
        await task.value

        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.balanceText, "—")
        let calls = await service.walletCalls
        XCTAssertEqual(calls, 1)
    }

    func testWalletScreenRendersBalanceRowsAndEmptyHistory() async throws {
        let model = makeModel(try WalletServiceStub())
        await model.load()
        let controller = WalletViewController(viewModel: model, onLock: {}, onSessionExpired: {})
        controller.loadViewIfNeeded()
        guard let table = controller.view.subviews.first(where: { $0 is UITableView }) as? UITableView else {
            XCTFail("Expected wallet table")
            return
        }
        let balance = controller.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0))
        XCTAssertEqual(balance.textLabel?.text, "$1,234.56")
        let empty = controller.tableView(table, cellForRowAt: IndexPath(row: 0, section: 1))
        XCTAssertEqual(empty.textLabel?.text, "No transactions yet")
        model.toggleBalance()
        let masked = controller.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0))
        XCTAssertEqual(masked.textLabel?.text, "****")
        XCTAssertEqual((table.tableFooterView as? UIButton)?.isEnabled, false)
    }

    func testCoordinatorLocksAndClearsTokenOnSessionExpiry() async throws {
        let store = TokenStoreStub()
        store.token = "test-session"
        let lockModel = LockViewModel(authenticator: AuthenticatorStub(), tokenStore: store)
        let service = try WalletServiceStub(error: .sessionExpired)
        let coordinator = AppCoordinator(lockViewModel: lockModel, service: service)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            XCTFail("Expected an application scene")
            return
        }
        let window = UIWindow(windowScene: scene)
        coordinator.start(in: window)
        defer { window.isHidden = true }
        guard let navigation = window.rootViewController as? UINavigationController else {
            XCTFail("Expected navigation")
            return
        }
        navigation.topViewController?.loadViewIfNeeded()
        await lockModel.unlock()
        guard let wallet = navigation.topViewController as? WalletViewController else {
            XCTFail("Expected wallet after authentication")
            return
        }
        let expired = expectation(description: "Session expired and returned to lock")
        lockModel.onStateChange = { state in
            if case .failed = state { expired.fulfill() }
        }
        wallet.loadViewIfNeeded()
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertNil(store.token)
        XCTAssertTrue(navigation.topViewController is LockViewController)
    }

    private func makeModel(_ service: any ApiServicing) -> WalletViewModel {
        WalletViewModel(service: service, formatter: ewalletApp.Formatter(locale: Locale(identifier: "en_US")))
    }
}

actor WalletServiceStub: ApiServicing {
    private let page: TransactionPage
    private var error: NetworkError?
    private let suspend: Bool
    private let onStart: @Sendable () -> Void
    private var continuation: CheckedContinuation<Wallet, Never>?
    private(set) var walletCalls = 0
    private(set) var lastPage: Int?
    private(set) var lastFilter: TransactionFilter?

    init(
        transactionCount: Int = 0, error: NetworkError? = nil,
        suspend: Bool = false, onStart: @escaping @Sendable () -> Void = {}
    ) throws {
        let items = (0..<transactionCount).map { index in
            TransactionDTO(
                id: String(index), type: index.isMultiple(of: 2) ? .debit : .credit,
                amount: 25, currency: "USD", merchant: "Merchant \(index)",
                status: .completed, createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        page = try TransactionPage(
            dto: TransactionPageDTO(page: 1, pageSize: 20, totalPages: items.isEmpty ? 0 : 1, items: items),
            filter: .all
        )
        self.error = error
        self.suspend = suspend
        self.onStart = onStart
    }

    func fetchWallet() async throws -> Wallet {
        walletCalls += 1
        if let error { throw error }
        if suspend {
            return await withCheckedContinuation {
                continuation = $0
                onStart()
            }
        }
        return Wallet(dto: WalletDTO(balance: Decimal(123456) / 100, currency: "USD"))
    }

    func fetchTransactions(page: Int, filter: TransactionFilter) async throws -> TransactionPage {
        lastPage = page
        lastFilter = filter
        if let error { throw error }
        return self.page
    }

    func setError(_ error: NetworkError?) { self.error = error }

    func resumeWallet() {
        continuation?.resume(returning: Wallet(dto: WalletDTO(balance: Decimal(123456) / 100, currency: "USD")))
        continuation = nil
    }
}
