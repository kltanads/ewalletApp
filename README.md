# Secure E-Wallet

A UIKit + MVVM take-home app with biometric unlock, a wallet overview, and paginated transaction history. It uses a local mock API; no backend account, API key, or third-party dependency is required.

## Setup

1. Open `ewalletApp.xcodeproj` in Xcode and select the `ewalletApp` scheme.
2. Choose an iPhone simulator or a physical iPhone, then Run (`⌘R`). The app target supports iOS 17.6 and later. The last verified test run used the installed Xcode 27.1 SDK and an iOS 27 simulator; 
3. On a physical device, select your own signing team and configure a device passcode. Enroll Face ID or Touch ID to test biometric unlock. In Simulator, use its biometric simulation controls to enroll and supply a matching or nonmatching result. Verify the native passcode fallback on a physical device.
4. Tap Unlock. After successful local authentication, the app creates a synthetic session token if one does not already exist and stores it in Keychain.

The current composition root selects `.slow`, which delays each mock request by two seconds. Wallet balance and recent transactions are fetched concurrently.

## Features

- Face ID / Touch ID with the system device-passcode fallback.
- Locked on launch, manual locking, and locking on return after at least 30 seconds in the background.
- A privacy cover while the app is inactive.
- Balance masking and the five most recent transactions.
- Full history with All / Credit / Debit filters, 20-item pages, pull-to-refresh, retry, and transaction details.
- Loading, empty, offline, error, and session-expired states. HTTP 401 clears the session and returns to the lock screen.

## Architecture

```text
SceneDelegate — composition root
  ├── KeychainTokenStore + BiometricAuthenticator → LockViewModel
  ├── URLSessionHTTPClient → ApiServices → Wallet / History ViewModels
  └── AppCoordinator → UIKit view controllers

UI → Model → Network
```

| Area | Responsibility |
| --- | --- |
| `UI` | View controllers render state and forward user actions. ViewModels expose state through closures and do not import UIKit. |
| `Model` | `Wallet`, `Transaction`, DTO mapping, sorting, merging pages, and money formatting. `ApiServices` implements `ApiServicing` for both wallet and history. |
| `Network` | `HTTPClient`, HTTPS request construction, DTO decoding, and typed errors. `MockAPI` intercepts the dedicated URLSession through URLProtocol. |
| `Security` | Protocol wrappers for LocalAuthentication and Keychain storage. |
| `App` | `AppCoordinator` owns navigation, privacy covering, and lock transitions. |

Dependencies are passed through initializers. `SceneDelegate` constructs the concrete services once for the scene. The coordinator creates screens and their ViewModels using those dependencies.

State updates use closures and async/await. ViewModels run on the main actor; network and domain types use explicit nonisolated declarations where appropriate. Request identifiers prevent superseded responses from replacing current data after refresh, filter changes, or locking.

Money uses `Decimal`. Transaction amounts are stored as nonnegative values; credit/debit determines the display sign. The history merges by transaction ID and sorts newest first. Filtering also happens in the mock server before pagination, so page counts reflect the selected type.

## Mock API

The mock session intercepts all requests and rejects unexpected hosts instead of reaching the internet. It uses the same request-building, URLSession, decoding, and error-mapping path as a real service.

- `GET /v1/wallet`: balance and currency.
- `GET /v1/transactions?page=1&pageSize=20&type=all`: paginated transactions; type also accepts `credit` and `debit`.
- Both requests include a bearer token read from Keychain.
- `Network/Mock/transactions.json` contains 60 synthetic transactions, giving three unfiltered pages and two pages per type.

Change the session in `SceneDelegate.swift` to select a scenario, then rebuild and run:

```swift
session: MockAPI.makeSession(scenario: .success),
```

| Scenario | Result |
| --- | --- |
| `.success` | Wallet and transaction data without an intentional delay. |
| `.slow` | Successful responses delayed by two seconds; currently selected. |
| `.serverError` | HTTP 503. |
| `.sessionExpired` | HTTP 401. |
| `.rateLimited` | HTTP 429. |
| `.offline` | Simulated network-unavailable error. |
| `.malformed` | Invalid JSON to exercise decoding errors. |
| `.empty` | Empty transaction history. |

Scenarios apply to every request in that session. Retrying `.serverError` continues to fail; switch back to `.success` and rerun to return to successful responses. This version does not contain the newer one-time page-2 failure.

`Constants.swift` contains the background timeout, page size, request timeout, mock host, and slow-response delay. For a real backend, replace the mock session and URL, implement real session provisioning, and verify its response contract. The generated UUID is not a server credential.

## Tests

In Xcode, use Product → Test (`⌘U`). To run the unit-test target from the project directory:

```sh
xcodebuild -project ewalletApp.xcodeproj \
  -scheme ewalletApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:ewalletAppTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

Replace the simulator name with one installed locally. Available destinations can be listed with:

```sh
xcodebuild -project ewalletApp.xcodeproj -scheme ewalletApp -showdestinations
```

The last completed unit-test run passed 52 tests. Coverage includes unlock outcomes and background timing, privacy/session handling, request construction and error mapping, mock pagination/filtering, mapping and formatting, wallet states, and history refresh/retry/stale-response handling. Tests use protocol doubles or the local URLProtocol stub and require no external server or real biometric authentication. The separate UI-test target still contains starter tests rather than complete user-flow coverage.

For manual checks, unlock the app, hide/show the balance, open history, scroll through all pages, change filters, refresh, and open details. Background the app for less than and more than 30 seconds, inspect the app-switcher cover, and test the error scenarios above.

## Security decisions

- Tokens are stored with `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`; they are not synchronized or stored in UserDefaults or source code. The mock accepts any nonempty bearer value and does not perform real authorization.
- LocalAuthentication uses `.deviceOwnerAuthentication`, leaving biometrics and passcode fallback to iOS. The app never reads the device passcode.
- Background elapsed time uses a monotonic clock that includes device sleep. On return after the timeout, the coordinator restores the lock screen before removing the privacy cover.
- Balance and transaction data remain in memory. The bundled JSON is synthetic fixture data, not a cache of user financial data. The mock uses an ephemeral session with caching and cookies disabled.
- Requests require HTTPS and the app does not weaken App Transport Security. The mock does not exercise an actual TLS connection. No token or financial-data logging is added.

An already-unlocked wallet can be viewed by someone holding a stolen unlocked phone until it is manually locked or the background timeout applies. There is no foreground inactivity timeout. A person who knows the device passcode can use the allowed fallback.

Changing biometric enrollment does not invalidate the stored token: the Keychain item is not bound to `biometryCurrentSet`. A production design would need to decide whether enrollment changes should revoke the session and how that interacts with passcode fallback.

There is no jailbreak detection, and app-level controls cannot guarantee protection on a compromised device. A production backend would need session revocation, expiry, authorization, and risk controls.

Certificate pinning is not implemented. For a production wallet, evaluate it against the threat model and the operational cost of certificate rotation and recovery; it is not a substitute for server-side security.

## Limitations and next steps

- This is a demo, with no login, token refresh, real payments, or server-side session validation. After a simulated expiry, unlocking can create another demo token.
- Data is not persisted for offline use. Mock errors are selected in code rather than through a runtime scenario picker.
- The minimum app deployment target is iOS 17.6; iOS 15–17.5 compatibility has not been implemented. The project-level deployment default remains 27.0, while app and test targets explicitly use 17.6.
- Physical-device biometric/passcode behavior and the full navigation flow still need manual verification. Dynamic Type, VoiceOver, small-screen layouts, and rotation need a dedicated UI pass.
- Add meaningful end-to-end UI tests and replace starter tests. Production work would also include real session provisioning and broader transport/security validation.

## AI assistance

OpenAI Codex assisted with refactoring, unit tests, and documentation. The test results above describe automated validation; they do not establish production security or replace a code walkthrough and physical-device testing.
