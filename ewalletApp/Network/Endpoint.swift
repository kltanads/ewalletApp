//
//  Endpoint.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import Foundation

nonisolated enum Endpoint: Sendable {
    case wallet
    case transactions(page: Int, pageSize: Int = Constants.transactionPageSize, type: TransactionFilter = .all)

    func makeRequest(baseURL: URL, token: String) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https" else {
            throw NetworkError.invalidRequest
        }
        components.query = nil
        components.fragment = nil

        switch self {
            case .wallet:
                components.path = "/v1/wallet"
            
            case .transactions(let page, let pageSize, let type):
                guard page > 0, pageSize > 0 else { throw NetworkError.invalidRequest }
                components.path = "/v1/transactions"
                components.queryItems = [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "pageSize", value: String(pageSize)),
                    URLQueryItem(name: "type", value: type.rawValue)
                ]
        }
        
        guard let url = components.url else { throw NetworkError.invalidRequest }
        
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Constants.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return request
    }
}

nonisolated enum TransactionFilter: String, Sendable {
    case all, credit, debit
}
