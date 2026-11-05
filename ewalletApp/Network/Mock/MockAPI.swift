//
//  MockAPI.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import Foundation

nonisolated enum MockAPI {
    enum Scenario {
        case success, slow, serverError, sessionExpired, rateLimited, offline, malformed, empty
    }

    static func makeSession(scenario: Scenario = .success) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false

        switch scenario {
        case .success: configuration.protocolClasses = [MockURLProtocol.self]
        case .slow: configuration.protocolClasses = [SlowMockURLProtocol.self]
        case .serverError: configuration.protocolClasses = [ServerErrorMockURLProtocol.self]
        case .sessionExpired: configuration.protocolClasses = [ExpiredMockURLProtocol.self]
        case .rateLimited: configuration.protocolClasses = [RateLimitedMockURLProtocol.self]
        case .offline: configuration.protocolClasses = [OfflineMockURLProtocol.self]
        case .malformed: configuration.protocolClasses = [MalformedMockURLProtocol.self]
        case .empty: configuration.protocolClasses = [EmptyMockURLProtocol.self]
        }
        return URLSession(configuration: configuration)
    }
}

nonisolated class MockURLProtocol: URLProtocol, @unchecked Sendable {
    class var scenario: MockAPI.Scenario { .success }
    private let lock = NSRecursiveLock()
    private var work: DispatchWorkItem?
    private var stopped = false

    // Intercept every request in this dedicated session; never fall through to a network.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        let work = DispatchWorkItem { [weak self] in self?.respond() }
        self.work = work
        let delay: Double = Self.scenario == .slow ? Constants.mockResponseDelay : 0
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
    }

    override func stopLoading() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        work?.cancel()
        work = nil
    }

    private func respond() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }

        do {
            guard let url = request.url, url.scheme == "https", url.host == Constants.mockAPIHost else {
                throw URLError(.unsupportedURL)
            }
            if Self.scenario == .offline { throw URLError(.notConnectedToInternet) }
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
            var status = 200
            var body = Data()

            if !authorization.hasPrefix("Bearer ") || authorization.count <= 7 {
                status = 401
            } else {
                switch Self.scenario {
                case .serverError: status = 503
                case .sessionExpired: status = 401
                case .rateLimited: status = 429
                case .malformed: body = Data("invalid json".utf8)
                default:
                    if request.httpMethod != "GET" {
                        status = 405
                    } else if url.path == "/v1/wallet" {
                        body = Data(#"{"balance":1234.56,"currency":"USD"}"#.utf8)
                    } else if url.path == "/v1/transactions" {
                        body = try transactionPage(url: url)
                    } else {
                        status = 404
                    }
                }
            }
            guard let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "Cache-Control": "no-store"]
            ) else { throw NetworkError.invalidResponse }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func transactionPage(url: URL) throws -> Data {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let page = Int(query.first { $0.name == "page" }?.value ?? "") ?? 1
        let pageSize = Int(query.first { $0.name == "pageSize" }?.value ?? "") ?? Constants.transactionPageSize
        let type = query.first { $0.name == "type" }?.value ?? "all"
        guard page > 0, pageSize > 0 else { throw NetworkError.invalidRequest }
        guard let file = Bundle(for: MockURLProtocol.self).url(forResource: "transactions", withExtension: "json"),
              let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]] else {
            throw NetworkError.decoding
        }
        // These are mock-server rules. Client-side domain rules belong in the Model layer.
        let items = Self.scenario == .empty ? [] : fixture.filter {
            type == "all" || $0["type"] as? String == type
        }
        let totalPages = items.isEmpty ? 0 : (items.count - 1) / pageSize + 1
        let pageItems: [[String: Any]]
        if page > totalPages {
            pageItems = []
        } else {
            let start = (page - 1) * pageSize
            pageItems = Array(items[start..<min(start + pageSize, items.count)])
        }
        return try JSONSerialization.data(withJSONObject: [
            "page": page, "pageSize": pageSize, "totalPages": totalPages, "items": pageItems
        ])
    }
}

nonisolated private final class SlowMockURLProtocol: MockURLProtocol, @unchecked Sendable {
    override class var scenario: MockAPI.Scenario { .slow }
}
nonisolated private final class ServerErrorMockURLProtocol: MockURLProtocol, @unchecked Sendable {
    override class var scenario: MockAPI.Scenario { .serverError }
}
nonisolated private final class ExpiredMockURLProtocol: MockURLProtocol, @unchecked Sendable {
    override class var scenario: MockAPI.Scenario { .sessionExpired }
}
nonisolated private final class RateLimitedMockURLProtocol: MockURLProtocol, @unchecked Sendable {
    override class var scenario: MockAPI.Scenario { .rateLimited }
}
nonisolated private final class OfflineMockURLProtocol: MockURLProtocol, @unchecked Sendable {
    override class var scenario: MockAPI.Scenario { .offline }
}
nonisolated private final class MalformedMockURLProtocol: MockURLProtocol, @unchecked Sendable {
    override class var scenario: MockAPI.Scenario { .malformed }
}
nonisolated private final class EmptyMockURLProtocol: MockURLProtocol, @unchecked Sendable {
    override class var scenario: MockAPI.Scenario { .empty }
}
