//
//  ApiServices.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import Foundation

nonisolated protocol ApiServicing: Sendable {
    func fetchWallet() async throws -> Wallet
    func fetchTransactions(page: Int, filter: TransactionFilter) async throws -> TransactionPage
}

nonisolated struct ApiServices: ApiServicing {
    private let client: any HTTPClient

    init(client: any HTTPClient) {
        self.client = client
    }

    func fetchWallet() async throws -> Wallet {
        let dto: WalletDTO = try await client.send(.wallet)
        
        guard !dto.balance.isNaN else {
            throw ModelError.invalidAmount
        }
        
        return Wallet(dto: dto)
    }

    func fetchTransactions(page: Int, filter: TransactionFilter) async throws -> TransactionPage {
        guard page > 0 else {
            throw ModelError.invalidPagination
        }
        
        let queryType: TransactionQueryType
        switch filter {
            case .all:
                queryType = .all
            
            case .credit:
                queryType = .credit
            
            case .debit:
                queryType = .debit
        }

        let dto: TransactionPageDTO = try await client.send(
            .transactions(page: page, pageSize: Constants.transactionPageSize, type: queryType)
        )
        
        guard dto.page == page, dto.pageSize == Constants.transactionPageSize else {
            throw ModelError.invalidPagination
        }
        
        return try TransactionPage(dto: dto, filter: filter)
    }
}
