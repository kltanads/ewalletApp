//
//  LockViewModelTests.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import XCTest
@testable import ewalletApp

@MainActor
final class LockViewModelTests: XCTestCase {
    func testSuccessfulAuthenticationUnlocksWallet() async {
        let authenticator = AuthenticatorStub()
        let viewModel = LockViewModel(authenticator: authenticator, tokenStore: TokenStoreStub())
        var states: [LockViewModel.State] = []
        viewModel.onStateChange = { states.append($0) }

        await viewModel.unlock()

        XCTAssertEqual(states, [.loading, .unlocked])
    }

    func testFailedAuthenticationCanBeRetried() async {
        let authenticator = AuthenticatorStub()
        authenticator.shouldFail = true
        let viewModel = LockViewModel(authenticator: authenticator, tokenStore: TokenStoreStub())

        await viewModel.unlock()
        guard case .failed = viewModel.state else {
            XCTFail("Expected authentication failure")
            return
        }

        authenticator.shouldFail = false
        await viewModel.unlock()
        XCTAssertEqual(viewModel.state, .unlocked)
    }

    func testDoesNotAuthenticateAgainWhenUnlocked() async {
        let authenticator = AuthenticatorStub()
        let viewModel = LockViewModel(authenticator: authenticator, tokenStore: TokenStoreStub())

        await viewModel.unlock()
        await viewModel.unlock()

        XCTAssertEqual(authenticator.calls, 1)
    }
}

