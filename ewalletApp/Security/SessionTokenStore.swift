//
//  SessionTokenStore.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import Foundation
import Security

protocol SessionTokenStore {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

struct KeychainTokenStore: SessionTokenStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "session-token",
            kSecAttrSynchronizable as String: false
        ]
    }

    func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw StorageError.invalidToken
        }
        return token
    }

    func save(_ token: String) throws {
        guard !token.isEmpty else { throw StorageError.invalidToken }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StorageError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw StorageError.keychain(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError.keychain(status)
        }
    }

    enum StorageError: LocalizedError {
        case keychain(OSStatus)
        case invalidToken

        var errorDescription: String? {
            "Couldn’t access your secure session. Check that a device passcode is set and try again."
        }
    }
}
