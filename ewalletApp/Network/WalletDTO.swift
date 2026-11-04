//
//  WalletDTO.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import Foundation

nonisolated struct WalletDTO: Decodable, Sendable {
    let balance: Decimal
    let currency: String
}

nonisolated struct TransactionPageDTO: Decodable, Sendable {
    let page: Int
    let pageSize: Int
    let totalPages: Int
    let items: [TransactionDTO]
}

nonisolated struct TransactionDTO: Decodable, Sendable {
    let id: String
    let type: TransactionTypeDTO
    let amount: Decimal
    let currency: String
    let merchant: String
    let status: TransactionStatusDTO
    let createdAt: Date
}

nonisolated enum TransactionTypeDTO: String, Decodable, Sendable {
    case credit, debit
}

nonisolated enum TransactionStatusDTO: String, Decodable, Sendable {
    case completed, pending, failed
}
