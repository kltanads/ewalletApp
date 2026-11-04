//
//  AppCoordinator.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import UIKit

class AppCoordinator {
    private let navigationController = UINavigationController()
    private let lockViewModel: LockViewModel
    private weak var window: UIWindow?
    private var privacyCover: UIView?

    init(lockViewModel: LockViewModel) {
        self.lockViewModel = lockViewModel
    }

    func start(in window: UIWindow) {
        self.window = window
        window.rootViewController = navigationController
        showLock()
        window.makeKeyAndVisible()
    }

    func willResignActive() {
        guard let window, privacyCover == nil else { return }
        let cover = UIView(frame: window.bounds)
        cover.backgroundColor = .systemBackground
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.accessibilityIdentifier = "privacyCover"
        window.addSubview(cover)
        privacyCover = cover
    }

    func didEnterBackground() {
        lockViewModel.didEnterBackground()
    }

    func willEnterForeground() {
        lockViewModel.willEnterForeground()
        if lockViewModel.state != .unlocked,
           !(navigationController.topViewController is LockViewController) {
            showLock()
        }
    }

    func didBecomeActive() {
        // The lock screen is restored before the privacy cover is removed.
        privacyCover?.removeFromSuperview()
        privacyCover = nil
    }

    private func showLock() {
        let controller = LockViewController(viewModel: lockViewModel) { [weak self] in
            self?.showWallet()
        }
        navigationController.setViewControllers([controller], animated: false)
    }

    private func showWallet() {
        let controller = WalletViewController { [weak self] in
            self?.lockViewModel.lock()
            self?.showLock()
        }
        navigationController.setViewControllers([controller], animated: false)
    }
}
