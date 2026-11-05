//
//  TransactionHistoryViewController.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import UIKit

@MainActor
final class TransactionHistoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let viewModel: TransactionHistoryViewModel
    private let onSelect: (Transaction) -> Void
    private let onSessionExpired: () -> Void
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let filterControl = UISegmentedControl(items: ["All", "Credit", "Debit"])
    private let refreshControl = UIRefreshControl()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let statusStack = UIStackView()
    private var loadTask: Task<Void, Never>?
    private var loadID: UUID?

    init(
        viewModel: TransactionHistoryViewModel,
        onSelect: @escaping (Transaction) -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.onSessionExpired = onSessionExpired
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureViews()
        bindViewModel()
        if viewModel.state == .idle {
            startLoading { [viewModel] in await viewModel.load() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if parent == nil {
            loadTask?.cancel()
            viewModel.cancelLoading()
        }
    }

    private func configureViews() {
        title = "Transactions"
        view.backgroundColor = .systemGroupedBackground
        filterControl.selectedSegmentIndex = 0
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterControl)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.alwaysBounceVertical = true
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        retryButton.setTitle("Retry", for: .normal)
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 8
        [spinner, messageLabel, retryButton].forEach { statusStack.addArrangedSubview($0) }

        let content = UIStackView(arrangedSubviews: [statusStack, tableView])
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            filterControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            filterControl.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            filterControl.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32)
        ])
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in self?.render(state) }
        render(viewModel.state)
    }

    private func render(_ state: TransactionHistoryViewModel.State) {
        statusStack.isHidden = state == .loaded || state == .idle
        retryButton.isHidden = true
        retryButton.setTitle("Retry", for: .normal)
        spinner.stopAnimating()
        if state != .loading { refreshControl.endRefreshing() }
        switch state {
        case .idle, .loaded:
            messageLabel.text = nil
        case .loading:
            messageLabel.text = "Loading transactions…"
            spinner.startAnimating()
        case .empty:
            messageLabel.text = "No transactions found"
            retryButton.isHidden = viewModel.nextPage == nil
            retryButton.setTitle("Load more", for: .normal)
        case .failed(let message):
            messageLabel.text = message
            retryButton.isHidden = false
        case .sessionExpired:
            messageLabel.text = "Your session has expired."
            onSessionExpired()
        }
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.transactions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "transaction")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "transaction")
        guard let transaction = viewModel.transaction(at: indexPath.row) else { return cell }
        let details = TransactionDetailViewModel(transaction: transaction)
        cell.textLabel?.text = "\(details.merchant)  \(details.amount)"
        cell.detailTextLabel?.text = "\(details.status) · \(details.date)"
        cell.textLabel?.textColor = details.isCredit ? .systemGreen : .label
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let transaction = viewModel.transaction(at: indexPath.row) else { return }
        onSelect(transaction)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard loadID == nil, indexPath.row >= viewModel.transactions.count - 5,
              viewModel.state == .loaded, viewModel.nextPage != nil else { return }
        startLoading { [viewModel] in await viewModel.loadNextPage() }
    }

    private func startLoading(_ action: @escaping @MainActor () async -> Void) {
        loadTask?.cancel()
        let id = UUID()
        loadID = id
        loadTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await action()
            guard let self, self.loadID == id else { return }
            self.loadID = nil
            self.loadTask = nil
        }
    }

    @objc private func refresh() {
        startLoading { [viewModel] in await viewModel.refresh() }
    }

    @objc private func filterChanged() {
        let filters: [TransactionFilter] = [.all, .credit, .debit]
        guard filters.indices.contains(filterControl.selectedSegmentIndex) else { return }
        let filter = filters[filterControl.selectedSegmentIndex]
        guard filter != viewModel.filter else { return }
        startLoading { [viewModel] in await viewModel.selectFilter(filter) }
    }

    @objc private func retry() {
        startLoading { [viewModel] in
            if viewModel.state == .empty {
                await viewModel.loadNextPage()
            } else {
                await viewModel.retry()
            }
        }
    }
}
