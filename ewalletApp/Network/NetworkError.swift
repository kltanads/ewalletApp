//
//  NetworkError.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import Foundation

nonisolated enum NetworkError: Error, Equatable {
    case invalidRequest
    case invalidResponse
    case sessionExpired
    case rateLimited
    case server(Int)
    case http(Int)
    case decoding
    case offline
    case timeout
    case transport(URLError.Code)
}
