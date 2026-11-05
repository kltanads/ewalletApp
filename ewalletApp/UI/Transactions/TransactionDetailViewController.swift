//
//  TransactionDetailViewController.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/4.
//

import UIKit

@MainActor
final class TransactionDetailViewController: UITableViewController {
    private let viewModel: TransactionDetailViewModel
    private var rows: [(title: String, value: String)] {
        [
            ("Merchant", viewModel.merchant), ("Amount", viewModel.amount),
            ("Currency", viewModel.currency), ("Type", viewModel.type),
            ("Status", viewModel.status), ("Date", viewModel.date),
            ("Transaction ID", viewModel.transactionID)
        ]
    }

    init(viewModel: TransactionDetailViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
    
        configureViews()
    }

    private func configureViews() {
        title = "Transaction details"
        tableView.allowsSelection = false
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.value
        cell.textLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }
}
