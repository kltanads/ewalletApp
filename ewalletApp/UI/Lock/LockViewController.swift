//
//  LockViewController.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import UIKit

@MainActor
class LockViewController: UIViewController {
    private let viewModel: LockViewModel
    private let onUnlock: () -> Void
    private let messageLabel = UILabel()
    private let unlockButton = UIButton(type: .system)

    init(viewModel: LockViewModel, onUnlock: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onUnlock = onUnlock
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        bindViewModel()
    }

    private func configureViews() {
        title = "E-Wallet"
        view.backgroundColor = .systemBackground

        messageLabel.font = .preferredFont(forTextStyle: .title2)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        unlockButton.setTitle("Unlock wallet", for: .normal)
        unlockButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        unlockButton.titleLabel?.adjustsFontForContentSizeCategory = true
        unlockButton.addTarget(self, action: #selector(unlockTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [messageLabel, unlockButton])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            self?.render(state)
        }
        render(viewModel.state)
    }

    private func render(_ state: LockViewModel.State) {
        unlockButton.isEnabled = state != .loading && state != .unlocked

        switch state {
        case .locked:
            messageLabel.text = "Wallet locked"
        case .loading:
            messageLabel.text = "Authenticating…"
        case .unlocked:
            onUnlock()
        case .failed(let message):
            messageLabel.text = message
        }
    }

    @objc private func unlockTapped() {
        Task { [viewModel] in
            await viewModel.unlock()
        }
    }
}
