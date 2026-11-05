//
//  Formatter.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import Foundation

nonisolated struct Formatter: Sendable {
    private let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func string(amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        
        if currency == "USD" {
            formatter.currencySymbol = "$"
        }
        
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(currency) \(amount)"
    }
}
