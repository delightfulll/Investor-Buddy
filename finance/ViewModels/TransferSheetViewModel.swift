//
//  TransferSheetViewModel.swift
//  finance
//
//  MVVM: Transfer sheet – amount, from/to account, validation, execute.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class TransferSheetViewModel: ObservableObject {
    @Published var amount: String = ""
    @Published var fromAccount: TransferAccount = .checking
    @Published var toAccount: TransferAccount = .savings
    @Published var showError = false
    @Published var errorMessage = ""

    private let accountViewModel: AccountViewModel

    init(accountViewModel: AccountViewModel = .shared) {
        self.accountViewModel = accountViewModel
    }

    func balance(for account: TransferAccount) -> Double {
        accountViewModel.balance(for: account)
    }

    func executeTransfer() -> Bool {
        guard let value = Double(amount), value > 0 else {
            errorMessage = "Please enter a valid amount"
            showError = true
            return false
        }
        let sourceBalance = accountViewModel.balance(for: fromAccount)
        if value > sourceBalance {
            errorMessage = "Insufficient funds in \(fromAccount.rawValue)"
            showError = true
            return false
        }
        accountViewModel.executeTransfer(from: fromAccount, to: toAccount, amount: value)
        return true
    }

    func fixToAccountIfNeeded() {
        if toAccount == fromAccount {
            toAccount = TransferAccount.allCases.first { $0 != fromAccount } ?? .checking
        }
    }
}
