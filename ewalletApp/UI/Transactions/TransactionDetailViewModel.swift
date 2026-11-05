//
//  TransactionDetailViewModel.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import Foundation

@MainActor
struct TransactionDetailViewModel {
    let merchant: String
    let amount: String
    let currency: String
    let type: String
    let status: String
    let date: String
    let transactionID: String
    let isCredit: Bool

    init(transaction: Transaction, formatter: Formatter = Formatter()) {
        merchant = transaction.merchant
        amount = transaction.formattedAmount(using: formatter)
        currency = transaction.currency
        isCredit = transaction.type == .credit
        type = isCredit ? "Credit" : "Debit"
        transactionID = transaction.id
        switch transaction.status {
        case .completed: status = "Completed"
        case .pending: status = "Pending"
        case .failed: status = "Failed"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        date = dateFormatter.string(from: transaction.date)
    }
}
