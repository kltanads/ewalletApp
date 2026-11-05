//
//  WalletViewController.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import UIKit

@MainActor
final class WalletViewController: UIViewController, UITableViewDataSource {
    private let viewModel: WalletViewModel
    private let onLock: () -> Void
    private let onSessionExpired: () -> Void
    private let onShowHistory: (() -> Void)?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)
    private let balanceButton = UIButton(type: .system)
    private let historyButton = UIButton(type: .system)
    private let statusStack = UIStackView()
//    private var loadTask: Task<Void, Never>?

    init(
        viewModel: WalletViewModel,
        onLock: @escaping () -> Void,
        onSessionExpired: @escaping () -> Void,
        onShowHistory: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onLock = onLock
        self.onSessionExpired = onSessionExpired
        self.onShowHistory = onShowHistory
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

//    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        bindViewModel()
        if viewModel.state == .idle { loadWallet() }
    }

    private func configureViews() {
        title = "Wallet"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Lock", style: .plain, target: self, action: #selector(lockTapped)
        )
        
        tableView.dataSource = self
        tableView.allowsSelection = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        balanceButton.addTarget(self, action: #selector(toggleBalance), for: .touchUpInside)
        historyButton.setTitle("View full history", for: .normal)
        historyButton.addTarget(self, action: #selector(historyTapped), for: .touchUpInside)
        historyButton.frame.size.height = 56
        tableView.tableFooterView = historyButton

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        retryButton.setTitle("Retry", for: .normal)
        retryButton.addTarget(self, action: #selector(loadWallet), for: .touchUpInside)
        for button in [balanceButton, historyButton, retryButton] {
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
        }
        statusStack.axis = .vertical
        statusStack.spacing = 16
        statusStack.alignment = .center
        [spinner, messageLabel, retryButton].forEach { statusStack.addArrangedSubview($0) }
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusStack)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            statusStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            self?.updateState(state)
        }
        updateState(viewModel.state)
    }

    private func updateState(_ state: WalletViewModel.State) {
        tableView.isHidden = state != .loaded
        statusStack.isHidden = state == .loaded
        retryButton.isHidden = true
        spinner.stopAnimating()

        switch state {
        case .idle:
            messageLabel.text = nil
        case .loading:
            messageLabel.text = "Loading wallet…"
            spinner.startAnimating()
        case .loaded:
            balanceButton.setTitle(viewModel.isBalanceHidden ? "Show" : "Hide", for: .normal)
            balanceButton.accessibilityLabel = viewModel.isBalanceHidden ? "Show balance" : "Hide balance"
            balanceButton.sizeToFit()
            historyButton.isEnabled = onShowHistory != nil
            tableView.reloadData()
        case .failed(let message):
            messageLabel.text = message
            retryButton.isHidden = false
        case .sessionExpired:
            messageLabel.text = "Your session has expired."
            onSessionExpired()
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : max(1, viewModel.transactions.count)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Current balance" : "Recent transactions"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "walletRow")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "walletRow")
        cell.accessoryView = nil
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.textColor = .black
        cell.detailTextLabel?.textColor = .gray

        if indexPath.section == 0 {
            cell.textLabel?.text = viewModel.balanceText
            cell.textLabel?.font = .preferredFont(forTextStyle: .title1)
            cell.accessoryView = balanceButton
            cell.detailTextLabel?.text = viewModel.currencyText
        } else if viewModel.transactions.isEmpty {
            cell.textLabel?.text = "No transactions yet"
            cell.detailTextLabel?.text = nil
        } else {
            let transaction = viewModel.transactions[indexPath.row]
            cell.textLabel?.text = "\(transaction.merchant)  \(transaction.amount)"
            cell.detailTextLabel?.text = transaction.details
            cell.textLabel?.textColor = transaction.isCredit ? .green : .black
        }
        
        return cell
    }

    @objc private func loadWallet() {
        guard viewModel.state != .loading else {
            return
        }
        
//        loadTask?.cancel()
//
//        loadTask = Task {
//            [viewModel] in await viewModel.load()
//        }
        Task {
            await viewModel.load()
        }
        
    }

    @objc private func toggleBalance() {
        viewModel.toggleBalance()
    }
    
    @objc private func lockTapped() {
        onLock()
    }
    
    @objc private func historyTapped() {
        onShowHistory?()
    }
}
