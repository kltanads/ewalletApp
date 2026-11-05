//
//  TransactionHistoryViewModel.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import Foundation

@MainActor
final class TransactionHistoryViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
        case sessionExpired
    }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var transactions: [Transaction] = []
    private(set) var filter: TransactionFilter = .all
    private(set) var nextPage: Int? = 1
    private var failedRequest: (page: Int, replace: Bool)?
    private var requestID: UUID?
    private let service: any ApiServicing

    init(service: any ApiServicing) {
        self.service = service
    }

    func load() async {
        guard state == .idle else { return }
        await fetch(page: 1, replace: true)
    }

    func loadNextPage() async {
        guard state == .loaded || state == .empty, let nextPage else { return }
        await fetch(page: nextPage, replace: false)
    }

    func refresh() async {
        await fetch(page: 1, replace: true)
    }

    func selectFilter(_ filter: TransactionFilter) async {
        guard self.filter != filter else { return }
        self.filter = filter
        transactions = []
        nextPage = 1
        await fetch(page: 1, replace: true)
    }

    func retry() async {
        guard case .failed = state, let failedRequest else { return }
        await fetch(page: failedRequest.page, replace: failedRequest.replace)
    }

    func cancelLoading() {
        requestID = nil
        failedRequest = nil
        transactions = []
        nextPage = 1
        state = .idle
    }

    func transaction(at index: Int) -> Transaction? {
        guard transactions.indices.contains(index) else { return nil }
        return transactions[index]
    }

    private func fetch(page: Int, replace: Bool) async {
        let id = UUID()
        requestID = id
        failedRequest = nil
        state = .loading

        do {
            let response = try await service.fetchTransactions(page: page, filter: filter)
            try Task.checkCancellation()
            guard requestID == id else { return }
            guard response.page == page else { throw ModelError.invalidPagination }
            transactions = response.merging(with: replace ? [] : transactions)
            nextPage = response.nextPage
            state = transactions.isEmpty ? .empty : .loaded
        } catch {
            guard requestID == id else { return }
            if error is CancellationError || Task.isCancelled {
                state = transactions.isEmpty ? .idle : .loaded
            } else if error as? NetworkError == .sessionExpired {
                transactions = []
                nextPage = nil
                state = .sessionExpired
            } else {
                failedRequest = (page, replace)
                state = .failed(message(for: error))
            }
        }
        requestID = nil
    }

    private func message(for error: Error) -> String {
        switch error as? NetworkError {
        case .offline: return "You’re offline. Check your connection and try again."
        case .timeout: return "The request timed out. Please try again."
        case .rateLimited: return "Too many requests. Please try again shortly."
        case .server: return "Transaction history is temporarily unavailable. Please try again."
        case .notConfigured: return "Transaction data is currently unavailable."
        default: return "Couldn’t load transactions. Please try again."
        }
    }
}
