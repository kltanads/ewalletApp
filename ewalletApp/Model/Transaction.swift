//
//  Transaction.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import Foundation

nonisolated struct Transaction: Equatable, Sendable, Identifiable {
    let id: String
    let type: TransactionType
    let amount: Decimal
    let currency: String
    let merchant: String
    let status: TransactionStatus
    let date: Date

    var signedAmount: Decimal {
        type == .credit ? amount : -amount
    }

    init(dto: TransactionDTO) throws {
        guard !dto.amount.isNaN, dto.amount >= 0 else {
            throw ModelError.invalidAmount
        }
        id = dto.id
        type = dto.type == .credit ? .credit : .debit
        amount = dto.amount
        currency = dto.currency
        merchant = dto.merchant
        date = dto.createdAt

        switch dto.status {
        case .completed: status = .completed
        case .pending: status = .pending
        case .failed: status = .failed
        }
    }

    func formattedAmount(using formatter: Formatter = Formatter()) -> String {
        let sign = type == .credit ? "+" : "-"
        return sign + formatter.string(amount: amount, currency: currency)
    }
}

nonisolated struct TransactionPage: Equatable, Sendable {
    let items: [Transaction]
    let page: Int
    let pageSize: Int
    let totalPages: Int

    var nextPage: Int? {
        page < totalPages ? page + 1 : nil
    }

    func merging(with existing: [Transaction]) -> [Transaction] {
        var byID: [String: Transaction] = [:]
        for transaction in existing + items {
            byID[transaction.id] = transaction
        }
        return byID.values.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date > $1.date
        }
    }

    init(dto: TransactionPageDTO, filter: TransactionFilter) throws {
        guard dto.page > 0, dto.pageSize > 0, dto.totalPages >= 0,
              dto.items.count <= dto.pageSize,
              dto.page <= dto.totalPages || dto.items.isEmpty else {
            throw ModelError.invalidPagination
        }
        page = dto.page
        pageSize = dto.pageSize
        totalPages = dto.totalPages
        items = try dto.items.map { try Transaction(dto: $0) }
            .filter { filter.includes($0) }
            .sorted {
                if $0.date == $1.date { return $0.id < $1.id }
                return $0.date > $1.date
            }
    }
}

nonisolated enum TransactionType: Sendable {
    case credit, debit
}

nonisolated enum TransactionStatus: Sendable {
    case completed, pending, failed
}

nonisolated enum TransactionFilter: Sendable, CaseIterable {
    case all, credit, debit

    func includes(_ transaction: Transaction) -> Bool {
        switch self {
        case .all: return true
        case .credit: return transaction.type == .credit
        case .debit: return transaction.type == .debit
        }
    }
}

nonisolated enum ModelError: Error, Equatable {
    case invalidAmount
    case invalidPagination
}
