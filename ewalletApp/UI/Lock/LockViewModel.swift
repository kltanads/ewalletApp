//
//  LockViewModel.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import Foundation
import Darwin

@MainActor
final class LockViewModel {
    enum State: Equatable {
        case locked
        case loading
        case unlocked
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .locked {
        didSet { onStateChange?(state) }
    }

    private let authenticator: any BiometricAuthenticating
    private let tokenStore: any SessionTokenStore
    private let backgroundTimeout: TimeInterval
    private let now: () -> TimeInterval
    private var backgroundedAt: TimeInterval?
    private var attemptID: UUID?

    init(
        authenticator: any BiometricAuthenticating,
        tokenStore: any SessionTokenStore,
        backgroundTimeout: TimeInterval = Constants.backgroundLockTimeout,
        now: @escaping () -> TimeInterval = {
            // Includes device sleep and is unaffected by changes to the wall clock.
            Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
        }
    ) {
        self.authenticator = authenticator
        self.tokenStore = tokenStore
        self.backgroundTimeout = max(0, backgroundTimeout)
        self.now = now
    }

    func unlock() async {
        guard state != .loading, state != .unlocked, backgroundedAt == nil else { return }
        let id = UUID()
        attemptID = id
        state = .loading

        do {
            try await authenticator.authenticate()
            guard attemptID == id else { return }
            try Task.checkCancellation()
            // Synthetic session for the mock backend; never a real server credential.
            if try tokenStore.read() == nil {
                try tokenStore.save(UUID().uuidString)
            }
            state = .unlocked
        } catch {
            guard attemptID == id else { return }
            state = error is CancellationError ? .locked : .failed(error.localizedDescription)
        }
        attemptID = nil
    }

    func lock() {
        attemptID = nil
        authenticator.cancel()
        state = .locked
    }

    func didEnterBackground() {
        if backgroundedAt == nil {
            backgroundedAt = now()
        }
        if state == .loading { lock() }
    }

    func willEnterForeground() {
        guard let backgroundedAt else { return }
        self.backgroundedAt = nil
        let elapsed = now() - backgroundedAt

        if elapsed >= backgroundTimeout {
            lock()
        }
    }
}
