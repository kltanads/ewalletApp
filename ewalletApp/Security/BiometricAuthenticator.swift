//
//  BiometricAuthenticator.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import LocalAuthentication

@MainActor
protocol BiometricAuthenticating {
    func authenticate() async throws
    func cancel()
}

class BiometricAuthenticator: BiometricAuthenticating {
    private var activeContext: LAContext?

    func authenticate() async throws {
        let context = LAContext()
        activeContext = context
        defer {
            if activeContext === context {
                activeContext = nil
            }
        }
        var error: NSError?

        // iOS handles biometric authentication and its passcode fallback.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw AuthenticationError(error)
        }

        do {
            let authenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your wallet"
            )
            guard authenticated else { throw AuthenticationError.failed }
        } catch {
            throw (error as? AuthenticationError) ?? AuthenticationError(error)
        }
    }

    func cancel() {
        activeContext?.invalidate()
        activeContext = nil
    }
}

enum AuthenticationError: LocalizedError, Equatable {
    case cancelled
    case notEnrolled
    case unavailable
    case lockout
    case passcodeNotSet
    case failed

    init(_ error: Error?) {
        guard let error = error as? LAError else {
            self = .failed
            return
        }
        switch error.code {
        case .userCancel, .systemCancel, .appCancel: self = .cancelled
        case .biometryNotEnrolled: self = .notEnrolled
        case .biometryNotAvailable: self = .unavailable
        case .biometryLockout: self = .lockout
        case .passcodeNotSet: self = .passcodeNotSet
        default: self = .failed
        }
    }

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Authentication cancelled. Tap Unlock to try again."
        case .notEnrolled: return "Biometrics aren’t set up. Use the system passcode fallback."
        case .unavailable: return "Biometrics aren’t available. Use the system passcode fallback."
        case .lockout: return "Biometrics are locked. Use your device passcode to continue."
        case .passcodeNotSet: return "Set a device passcode in Settings before unlocking your wallet."
        case .failed: return "Authentication failed. Please try again."
        }
    }
}
