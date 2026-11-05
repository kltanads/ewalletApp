//
//  WalletViewModel.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import Foundation

@MainActor
final class WalletViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
        case sessionExpired
    }

    struct TransactionInfo {
        let merchant: String
        let amount: String
        let details: String
        let isCredit: Bool
    }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var isBalanceHidden = false
    private(set) var transactions: [TransactionInfo] = []
    private var wallet: Wallet?
    private var requestID: UUID?
    private let service: any ApiServicing
    private let formatter: Formatter

    var balanceText: String {
        guard let wallet else {
            return "—"
        }
        
        return isBalanceHidden ? "****" : formatter.string(amount: wallet.balance, currency: wallet.currency)
    }

    var currencyText: String { wallet?.currency ?? "" }

    init(service: any ApiServicing, formatter: Formatter = Formatter()) {
        self.service = service
        self.formatter = formatter
    }

    func load() async {
        guard state != .loading else { return }
        let id = UUID()
        requestID = id
        state = .loading

        do {
            async let walletResponse = service.fetchWallet()
            async let transactionResponse = service.fetchTransactions(page: 1, filter: .all)
            let (wallet, page) = try await (walletResponse, transactionResponse)
            try Task.checkCancellation()
            guard requestID == id else { return }

            self.wallet = wallet
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            transactions = page.items.prefix(5).map { transaction in
                let status: String
                switch transaction.status {
                    case .completed:
                        status = "Completed"
                    case .pending:
                        status = "Pending"
                    case .failed:
                        status = "Failed"
                }
                return TransactionInfo(
                    merchant: transaction.merchant,
                    amount: transaction.formattedAmount(using: formatter),
                    details: "\(status) · \(dateFormatter.string(from: transaction.date))",
                    isCredit: transaction.type == .credit
                )
            }
            state = .loaded
        } catch {
            guard requestID == id else { return }
            wallet = nil
            transactions = []
            if error is CancellationError || Task.isCancelled {
                state = .idle
            } else if error as? NetworkError == .sessionExpired {
                state = .sessionExpired
            } else {
                state = .failed(message(for: error))
            }
        }
        requestID = nil
    }

    func toggleBalance() {
        guard state == .loaded else { return }
        isBalanceHidden.toggle()
        onStateChange?(state)
    }

    func cancelLoading() {
        requestID = nil
        wallet = nil
        transactions = []
        state = .idle
    }

    private func message(for error: Error) -> String {
        switch error as? NetworkError {
            case .offline:
                return "You’re offline. Check your connection and try again."
            case .timeout:
                return "The request timed out. Please try again."
            case .rateLimited:
                return "Too many requests. Please try again shortly."
            case .server:
                return "Wallet service is temporarily unavailable. Please try again."
            case .notConfigured:
                return "Wallet data is currently unavailable."
            default:
                return "Couldn’t load your wallet. Please try again."
        }
    }
}
