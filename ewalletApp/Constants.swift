//
//  Constants.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import Foundation

nonisolated enum Constants {
    static let backgroundLockTimeout: TimeInterval = 30
    static let keychainService = "com.ewalletApp.session"
    static let transactionPageSize = 20
    static let mockAPIHost = "wallet.mock"
    static let mockAPIBaseURL = "https://\(mockAPIHost)"
    static let mockResponseDelay: TimeInterval = 2
    static let apiBaseURL = URL(string: mockAPIBaseURL)
    static let requestTimeout: TimeInterval = 15
}
