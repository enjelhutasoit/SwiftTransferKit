//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import Security

/// Stores one session in a service/account-scoped Keychain item.
public actor KeychainCredentialStore: CredentialStore {
    public enum Failure: Error, Equatable, Sendable {
        case invalidConfiguration
        case operationFailed
        case invalidStoredCredential
    }

    private let service: String
    private let account: String

    public init(
        service: String,
        account: String = "current-session"
    ) throws {
        guard !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidConfiguration
        }

        self.service = service
        self.account = account
    }

    public func load() async throws -> SessionCredential? {
        try Task.checkCancellation()

        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw Failure.operationFailed
        }

        guard let data = result as? Data else {
            throw Failure.invalidStoredCredential
        }

        do {
            return try JSONDecoder().decode(
                SessionCredential.self,
                from: data
            )
        } catch {
            throw Failure.invalidStoredCredential
        }
    }

    public func save(_ credential: SessionCredential) async throws {
        try Task.checkCancellation()

        let data: Data

        do {
            data = try JSONEncoder().encode(credential)
        } catch {
            throw Failure.operationFailed
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw Failure.operationFailed
        }

        var item = baseQuery
        for (key, value) in attributes {
            item[key] = value
        }

        let addStatus = SecItemAdd(item as CFDictionary, nil)

        if addStatus == errSecSuccess {
            return
        }

        // Another store instance may have inserted the item first.
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                attributes as CFDictionary
            )

            guard retryStatus == errSecSuccess else {
                throw Failure.operationFailed
            }

            return
        }

        throw Failure.operationFailed
    }

    public func delete() async throws {
        try Task.checkCancellation()

        let status = SecItemDelete(baseQuery as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.operationFailed
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
