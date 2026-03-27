//
//  StockTradingSheetViewModel.swift
//  finance
//
//  MVVM: Trade sheet – buy/sell, shares, validation, execute.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class StockTradingSheetViewModel: ObservableObject {
    enum OrderType: String, CaseIterable {
        case buy = "Buy"
        case sell = "Sell"
    }

    let stock: StockData
    @Published var orderType: OrderType = .buy
    @Published var shares: String = ""
    @Published var showConfirmation = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let accountViewModel: AccountViewModel

    var sharesOwned: Double {
        accountViewModel.sharesOwned(for: stock.symbol)
    }

    var estimatedCost: Double {
        (Double(shares) ?? 0) * stock.price
    }

    init(stock: StockData, accountViewModel: AccountViewModel = .shared) {
        self.stock = stock
        self.accountViewModel = accountViewModel
    }

    func validateAndConfirm() {
        guard let shareCount = Double(shares), shareCount > 0 else {
            errorMessage = "Please enter a valid number of shares"
            showError = true
            return
        }
        if orderType == .buy {
            if estimatedCost > accountViewModel.currentBuyingPower {
                errorMessage = "Insufficient buying power. You need \(estimatedCost.formatted(.currency(code: "USD"))) but only have \(accountViewModel.currentBuyingPower.formatted(.currency(code: "USD")))"
                showError = true
                return
            }
        } else {
            if shareCount > sharesOwned {
                errorMessage = "You only own \(String(format: "%.2f", sharesOwned)) shares of \(stock.symbol)"
                showError = true
                return
            }
        }
        showConfirmation = true
    }

    func executeOrder() {
        guard let shareCount = Double(shares) else { return }
        if orderType == .buy {
            accountViewModel.executeBuy(stock: stock, shares: shareCount)
        } else {
            accountViewModel.executeSell(stock: stock, shares: shareCount)
        }
    }
}
