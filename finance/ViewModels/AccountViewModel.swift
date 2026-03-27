//
//  AccountViewModel.swift
//  finance
//
//  MVVM: Account & portfolio state (balances, trading type, holdings).
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AccountViewModel: ObservableObject {
    static let shared = AccountViewModel()

    @Published var checkingBalance: Double = 15000.00
    @Published var savingsBalance: Double = 50000.00
    @Published var buyingPower: Double = 10000.00
    @Published var marginBuyingPower: Double = 20000.00
    @Published var tradingType: TradingType = .cash
    @Published var totalContributions: Double = 75000.00
    @Published var ownedStocks: [OwnedStock] = [
        OwnedStock(symbol: "AAPL", name: "Apple Inc.", shares: 10, averageCost: 165.00, currentPrice: 178.52),
        OwnedStock(symbol: "MSFT", name: "Microsoft Corp.", shares: 5, averageCost: 350.00, currentPrice: 378.91)
    ]

    var currentBuyingPower: Double {
        tradingType == .cash ? buyingPower : marginBuyingPower
    }

    var netWorth: Double {
        checkingBalance + savingsBalance + buyingPower + ownedStocks.reduce(0) { $0 + $1.totalValue }
    }

    var portfolioValue: Double {
        ownedStocks.reduce(0) { $0 + $1.totalValue }
    }

    var totalReturn: Double {
        ownedStocks.reduce(0) { $0 + $1.totalReturn }
    }

    var ytdReturn: Double {
        netWorth - totalContributions
    }

    var ytdReturnPercent: Double {
        totalContributions > 0 ? (ytdReturn / totalContributions) * 100 : 0
    }

    /// Today's total gain/loss across all holdings
    var todayGainLoss: Double {
        ownedStocks.reduce(0) { $0 + $1.dailyGainLoss }
    }

    private init() {}

    /// Fetches live prices for all holdings concurrently and updates currentPrice + previousClose
    func refreshHoldingPrices() async {
        let stockService = StockService.shared
        let symbols = ownedStocks.map(\.symbol)

        // Fetch all prices concurrently
        let prices: [(String, Double, Double)] = await withTaskGroup(
            of: (String, Double, Double)?.self,
            returning: [(String, Double, Double)].self
        ) { group in
            for symbol in symbols {
                group.addTask {
                    guard let data = try? await stockService.fetchStock(symbol: symbol) else { return nil }
                    return (symbol, data.price, data.previousClose)
                }
            }
            var results: [(String, Double, Double)] = []
            for await result in group {
                if let r = result { results.append(r) }
            }
            return results
        }

        // Apply fetched prices back to holdings
        for (symbol, price, previousClose) in prices {
            if let i = ownedStocks.firstIndex(where: { $0.symbol == symbol }) {
                ownedStocks[i].currentPrice = price
                ownedStocks[i].previousClose = previousClose
            }
        }
    }

    func updateOwnedStockPrice(symbol: String, price: Double) {
        guard let index = ownedStocks.firstIndex(where: { $0.symbol == symbol }) else { return }
        ownedStocks[index].currentPrice = price
    }

    func executeTransfer(from: TransferAccount, to: TransferAccount, amount: Double) {
        let sourceBalance = balance(for: from)
        guard amount > 0, amount <= sourceBalance else { return }
        subtract(amount, from: from)
        add(amount, to: to)
    }

    func balance(for account: TransferAccount) -> Double {
        switch account {
        case .checking: return checkingBalance
        case .savings: return savingsBalance
        case .buyingPower: return buyingPower
        }
    }

    private func subtract(_ amount: Double, from account: TransferAccount) {
        switch account {
        case .checking: checkingBalance -= amount
        case .savings: savingsBalance -= amount
        case .buyingPower: buyingPower -= amount
        }
    }

    private func add(_ amount: Double, to account: TransferAccount) {
        switch account {
        case .checking: checkingBalance += amount
        case .savings: savingsBalance += amount
        case .buyingPower: buyingPower += amount
        }
    }

    func executeBuy(stock: StockData, shares: Double) {
        let cost = shares * stock.price
        if tradingType == .cash {
            buyingPower -= cost
        } else {
            marginBuyingPower -= cost
        }
        if let index = ownedStocks.firstIndex(where: { $0.symbol == stock.symbol }) {
            let existing = ownedStocks[index]
            let totalShares = existing.shares + shares
            let newAvgCost = ((existing.shares * existing.averageCost) + (shares * stock.price)) / totalShares
            ownedStocks[index] = OwnedStock(
                symbol: stock.symbol,
                name: stock.name,
                shares: totalShares,
                averageCost: newAvgCost,
                currentPrice: stock.price
            )
        } else {
            ownedStocks.append(OwnedStock(
                symbol: stock.symbol,
                name: stock.name,
                shares: shares,
                averageCost: stock.price,
                currentPrice: stock.price
            ))
        }
    }

    func executeSell(stock: StockData, shares: Double) {
        let credit = shares * stock.price
        if tradingType == .cash {
            buyingPower += credit
        } else {
            marginBuyingPower += credit
        }
        guard let index = ownedStocks.firstIndex(where: { $0.symbol == stock.symbol }) else { return }
        let remaining = ownedStocks[index].shares - shares
        if remaining <= 0 {
            ownedStocks.remove(at: index)
        } else {
            ownedStocks[index].shares = remaining
        }
    }

    func sharesOwned(for symbol: String) -> Double {
        ownedStocks.first { $0.symbol == symbol }?.shares ?? 0
    }
}

enum TransferAccount: String, CaseIterable {
    case checking = "Checking"
    case savings = "Savings"
    case buyingPower = "Buying Power"
}
