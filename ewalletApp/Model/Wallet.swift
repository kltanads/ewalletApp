//
//  Wallet.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import Foundation

nonisolated struct Wallet: Equatable, Sendable {
    let balance: Decimal
    let currency: String

    init(dto: WalletDTO) {
        balance = dto.balance
        currency = dto.currency
    }
}
