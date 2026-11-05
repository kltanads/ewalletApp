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
    private let service: any ApiServicing
    private weak var walletViewModel: WalletViewModel?
    private weak var historyViewModel: TransactionHistoryViewModel?
    private weak var window: UIWindow?
    private var privacyCover: UIView?

    init(lockViewModel: LockViewModel, service: any ApiServicing) {
        self.lockViewModel = lockViewModel
        self.service = service
    }

    func start(in window: UIWindow) {
        self.window = window
        window.rootViewController = navigationController
        showLock()
        window.makeKeyAndVisible()
    }

    func willResignActive() {
        guard let window, privacyCover == nil else {
            return
        }
        
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
        walletViewModel?.cancelLoading()
        historyViewModel?.cancelLoading()
        let controller = LockViewController(viewModel: lockViewModel) { [weak self] in
            self?.showWallet()
        }
        navigationController.setViewControllers([controller], animated: false)
    }

    private func showWallet() {
        let viewModel = WalletViewModel(service: service)
        walletViewModel = viewModel
        let controller = WalletViewController(
            viewModel: viewModel,
            onLock: { [weak self] in
                self?.lockViewModel.lock()
                self?.showLock()
            },
            onSessionExpired: { [weak self] in
                self?.sessionExpired()
            },
            onShowHistory: { [weak self] in
                self?.showHistory()
            }
        )
        navigationController.setViewControllers([controller], animated: false)
    }

    private func showHistory() {
        let viewModel = TransactionHistoryViewModel(service: service)
        historyViewModel = viewModel
        let controller = TransactionHistoryViewController(
            viewModel: viewModel,
            onSelect: { [weak self] transaction in
                let details = TransactionDetailViewModel(transaction: transaction)
                self?.navigationController.pushViewController(
                    TransactionDetailViewController(viewModel: details), animated: true
                )
            },
            onSessionExpired: { [weak self] in self?.sessionExpired() }
        )
        navigationController.pushViewController(controller, animated: true)
    }

    private func sessionExpired() {
        lockViewModel.expireSession()
        showLock()
    }
}
