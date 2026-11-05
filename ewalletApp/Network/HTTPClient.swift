//
//  HTTPClient.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import Foundation

nonisolated protocol HTTPClient: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response
}

nonisolated final class URLSessionHTTPClient: HTTPClient {
    private let baseURL: URL?
    private let session: URLSession
    private let tokenProvider: @Sendable () async throws -> String?

    init(
        baseURL: URL?,
        session: URLSession = URLSession(configuration: .ephemeral),
        tokenProvider: @escaping @Sendable () async throws -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response {
        try Task.checkCancellation()
        guard let baseURL else { throw NetworkError.notConfigured }
        
        guard let token = try await tokenProvider(), !token.isEmpty else {
            throw NetworkError.sessionExpired
        }
        
        let request = try endpoint.makeRequest(baseURL: baseURL, token: token)
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost: throw NetworkError.offline
            case .timedOut: throw NetworkError.timeout
            default: throw NetworkError.transport(error.code)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NetworkError.transport(.unknown)
        }

        try Task.checkCancellation()
        
        guard let response = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        switch response.statusCode {
            case 200..<300:
                break
            case 401:
                throw NetworkError.sessionExpired
            case 429:
                throw NetworkError.rateLimited
            case 500..<600:
                throw NetworkError.server(response.statusCode)
            default:
                throw NetworkError.http(response.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NetworkError.decoding
        }
    }
}
