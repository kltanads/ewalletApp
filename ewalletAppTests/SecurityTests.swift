//
//  SecurityTests.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import XCTest
import LocalAuthentication
import UIKit
@testable import ewalletApp

@MainActor
final class SecurityTests: XCTestCase {
    func testStoresMockSessionOnlyAfterAuthenticationAndReusesIt() async {
        let store = TokenStoreStub()
        let model = LockViewModel(authenticator: AuthenticatorStub(), tokenStore: store)
        XCTAssertEqual(model.state, .locked)
        XCTAssertNil(store.token)

        await model.unlock()
        let token = store.token
        XCTAssertNotNil(token)
        model.lock()
        await model.unlock()

        XCTAssertEqual(store.token, token)
        XCTAssertEqual(store.saves, 1)
    }

    func testFailedAuthenticationDoesNotReadOrSaveToken() async {
        let authenticator = AuthenticatorStub()
        authenticator.shouldFail = true
        let store = TokenStoreStub()
        let model = LockViewModel(authenticator: authenticator, tokenStore: store)

        await model.unlock()

        XCTAssertEqual(store.reads, 0)
        XCTAssertEqual(store.saves, 0)
    }

    func testStorageFailuresKeepWalletLocked() async {
        for failOnRead in [true, false] {
            let store = TokenStoreStub()
            store.failOnRead = failOnRead
            store.failOnSave = !failOnRead
            let model = LockViewModel(authenticator: AuthenticatorStub(), tokenStore: store)

            await model.unlock()

            guard case .failed = model.state else {
                XCTFail("Storage failure must not unlock the wallet")
                return
            }
        }
    }

    func testDefaultTimeoutLocksAtThirtySeconds() async {
        var time: TimeInterval = 0
        let model = LockViewModel(
            authenticator: AuthenticatorStub(), tokenStore: TokenStoreStub(), now: { time }
        )
        await model.unlock()
        model.didEnterBackground()
        time = 29
        model.willEnterForeground()
        XCTAssertEqual(model.state, .unlocked)

        model.didEnterBackground()
        time = 59
        model.willEnterForeground()
        XCTAssertEqual(model.state, .locked)
    }

    func testCustomTimeoutAndRepeatedBackgroundNotifications() async {
        var time: TimeInterval = 0
        let model = LockViewModel(
            authenticator: AuthenticatorStub(), tokenStore: TokenStoreStub(),
            backgroundTimeout: 5, now: { time }
        )
        await model.unlock()
        model.didEnterBackground()
        time = 4
        model.didEnterBackground()
        time = 5
        model.willEnterForeground()
        XCTAssertEqual(model.state, .locked)
    }

    func testSystemPromptDoesNotStartBackgroundTimeout() async {
        let model = LockViewModel(authenticator: AuthenticatorStub(), tokenStore: TokenStoreStub())
        await model.unlock()
        model.willEnterForeground()
        XCTAssertEqual(model.state, .unlocked)
    }

    func testBackgroundCancelsAuthenticationAndIgnoresLateSuccess() async {
        let authenticator = AuthenticatorStub()
        authenticator.suspend = true
        let store = TokenStoreStub()
        let model = LockViewModel(authenticator: authenticator, tokenStore: store)
        let started = expectation(description: "Authentication started")
        authenticator.onStart = { started.fulfill() }
        let task = Task { await model.unlock() }
        await fulfillment(of: [started], timeout: 1)

        await model.unlock()
        XCTAssertEqual(authenticator.calls, 1)
        model.didEnterBackground()
        await model.unlock()
        XCTAssertEqual(authenticator.calls, 1)
        XCTAssertEqual(authenticator.cancellations, 1)
        model.willEnterForeground()
        authenticator.continuation?.resume()
        await task.value

        XCTAssertEqual(model.state, .locked)
        XCTAssertEqual(store.reads, 0)
    }

    func testPrivacyCoverRemainsUntilLockScreenIsRestored() async throws {
        var time: TimeInterval = 0
        let model = LockViewModel(
            authenticator: AuthenticatorStub(), tokenStore: TokenStoreStub(), now: { time }
        )
        let coordinator = AppCoordinator(lockViewModel: model, service: try WalletServiceStub())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        coordinator.start(in: window)
        defer { window.isHidden = true }
        guard let navigation = window.rootViewController as? UINavigationController else {
            XCTFail("Expected navigation controller")
            return
        }
        navigation.topViewController?.loadViewIfNeeded()
        await model.unlock()
        XCTAssertTrue(navigation.topViewController is WalletViewController)

        coordinator.willResignActive()
        coordinator.willResignActive()
        XCTAssertEqual(window.subviews.filter { $0.accessibilityIdentifier == "privacyCover" }.count, 1)
        coordinator.didEnterBackground()
        time = 30
        coordinator.willEnterForeground()
        XCTAssertTrue(navigation.topViewController is LockViewController)
        XCTAssertEqual(window.subviews.last?.accessibilityIdentifier, "privacyCover")

        coordinator.didBecomeActive()
        XCTAssertFalse(window.subviews.contains { $0.accessibilityIdentifier == "privacyCover" })
    }

    func testAuthenticationErrorsHaveDistinctMessages() {
        let cases: [(LAError.Code, AuthenticationError)] = [
            (.userCancel, .cancelled), (.systemCancel, .cancelled), (.appCancel, .cancelled),
            (.biometryNotEnrolled, .notEnrolled), (.biometryNotAvailable, .unavailable),
            (.biometryLockout, .lockout), (.passcodeNotSet, .passcodeNotSet),
            (.authenticationFailed, .failed)
        ]
        for (code, expected) in cases {
            XCTAssertEqual(AuthenticationError(LAError(code)), expected)
            XCTAssertNotNil(expected.errorDescription)
        }
    }

    func testKeychainRejectsEmptyToken() {
        let store = KeychainTokenStore(service: "ewalletApp.test.\(UUID().uuidString)")
        XCTAssertThrowsError(try store.save(""))
    }
}

@MainActor
final class AuthenticatorStub: BiometricAuthenticating {
    var shouldFail = false
    var calls = 0
    var cancellations = 0
    var suspend = false
    var onStart: (() -> Void)?
    var continuation: CheckedContinuation<Void, Never>?

    func authenticate() async throws {
        calls += 1
        if suspend {
            await withCheckedContinuation {
                continuation = $0
                onStart?()
            }
        }
        if shouldFail { throw AuthenticationError.failed }
    }

    func cancel() { cancellations += 1 }
}

final class TokenStoreStub: SessionTokenStore {
    var token: String?
    var reads = 0
    var saves = 0
    var failOnRead = false
    var failOnSave = false

    func read() throws -> String? {
        reads += 1
        if failOnRead { throw KeychainTokenStore.StorageError.invalidToken }
        return token
    }

    func save(_ token: String) throws {
        if failOnSave { throw KeychainTokenStore.StorageError.invalidToken }
        self.token = token
        saves += 1
    }

    func delete() throws { token = nil }
}
