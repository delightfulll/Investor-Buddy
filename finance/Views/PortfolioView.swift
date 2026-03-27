//
//  PortfolioView.swift
//  finance
//
//  MVVM: Portfolio screen – binds to PortfolioViewModel and AccountViewModel.
//

import SwiftUI

struct PortfolioView: View {
    @StateObject private var portfolioVM = PortfolioViewModel()
    @StateObject private var accountVM = AccountViewModel.shared
    @StateObject private var watchlistManager = WatchlistManager.shared
    @State private var stockToDelete: StockData?
    @State private var showDeleteAlert = false
    @State private var watchlistSearchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    portfolioSummaryCard
                    holdingsSection
                    fullWatchlistSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Portfolio")
            .alert("Remove from Watchlist", isPresented: $showDeleteAlert, presenting: stockToDelete) { stock in
                Button("Remove", role: .destructive) {
                    withAnimation {
                        watchlistManager.removeSymbol(stock.symbol)
                        portfolioVM.watchlistStocks.removeAll { $0.symbol == stock.symbol }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { stock in
                Text("Are you sure you want to remove \(stock.symbol) from your watchlist?")
            }
        }
        .task {
            async let holdings: Void = accountVM.refreshHoldingPrices()
            async let watchlist: Void = portfolioVM.loadWatchlistStocks()
            _ = await (holdings, watchlist)
        }
    }

    private var portfolioSummaryCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Total Portfolio Value")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Text(accountVM.portfolioValue, format: .currency(code: "USD"))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 4) {
                        Image(systemName: accountVM.todayGainLoss >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                        Text(String(format: "%+.2f", accountVM.todayGainLoss))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(accountVM.todayGainLoss >= 0 ? .green : .red)
                }
                VStack(spacing: 2) {
                    Text("Total Return")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 4) {
                        Image(systemName: accountVM.totalReturn >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                        Text(accountVM.totalReturn, format: .currency(code: "USD"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(accountVM.totalReturn >= 0 ? .green : .red)
                }
                VStack(spacing: 2) {
                    Text("Buying Power")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(accountVM.currentBuyingPower, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue, Color.purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Holdings")
                .font(.headline)
            if accountVM.ownedStocks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "briefcase")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No holdings yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(accountVM.ownedStocks) { owned in
                        NavigationLink {
                            StockDetailView(stock: stockDataFrom(owned))
                        } label: {
                            holdingRow(owned: owned)
                        }
                        .buttonStyle(.plain)
                        if owned.id != accountVM.ownedStocks.last?.id {
                            Divider()
                                .padding(.leading, 50)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
        }
    }

    private func holdingRow(owned: OwnedStock) -> some View {
        HStack {
            Text(owned.symbol)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(owned.symbol)
                    .font(.headline)
                Text("\(String(format: "%.2f", owned.shares)) shares")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(owned.totalValue, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                // Today's gain/loss
                HStack(spacing: 2) {
                    Image(systemName: owned.dailyGainLoss >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                    Text(String(format: "%+.2f", owned.dailyGainLoss))
                        .font(.caption)
                    Text(String(format: "(%.2f%%)", abs(owned.dailyChangePercent)))
                        .font(.caption2)
                }
                .foregroundStyle(owned.dailyGainLoss >= 0 ? .green : .red)
                // Total return
                Text(String(format: "Total: %+.2f%%", owned.returnPercentage))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func stockDataFrom(_ owned: OwnedStock) -> StockData {
        StockData(
            symbol: owned.symbol,
            name: owned.name,
            price: owned.currentPrice,
            change: owned.dailyChange,
            changePercent: owned.dailyChangePercent,
            previousClose: owned.previousClose ?? owned.currentPrice,
            open: owned.currentPrice,
            dayHigh: owned.currentPrice,
            dayLow: owned.currentPrice,
            volume: 0,
            marketCap: 0
        )
    }

    private var filteredWatchlistStocks: [StockData] {
        guard !watchlistSearchText.isEmpty else { return portfolioVM.watchlistStocks }
        let query = watchlistSearchText.lowercased()
        return portfolioVM.watchlistStocks.filter {
            $0.symbol.lowercased().contains(query) || $0.name.lowercased().contains(query)
        }
    }

    private var fullWatchlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watchlist")
                .font(.headline)
            if portfolioVM.watchlistStocks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Your watchlist is empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search watchlist...", text: $watchlistSearchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !watchlistSearchText.isEmpty {
                        Button {
                            watchlistSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if filteredWatchlistStocks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No results for \"\(watchlistSearchText)\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 0) {
                        ForEach(filteredWatchlistStocks) { stock in
                            NavigationLink(value: stock) {
                                watchlistRow(stock: stock)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    stockToDelete = stock
                                    showDeleteAlert = true
                                } label: {
                                    Label("Remove from Watchlist", systemImage: "trash")
                                }
                            }
                            if stock.id != filteredWatchlistStocks.last?.id {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    .navigationDestination(for: StockData.self) { stock in
                        StockDetailView(stock: stock)
                    }
                }
            }
        }
    }

    private func watchlistRow(stock: StockData) -> some View {
        HStack {
            Text(stock.symbol)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.symbol)
                    .font(.headline)
                Text(stock.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(stock.price, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                HStack(spacing: 2) {
                    Image(systemName: stock.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                    Text(String(format: "%.2f%%", abs(stock.changePercent)))
                        .font(.caption)
                }
                .foregroundStyle(stock.change >= 0 ? .green : .red)
            }
        }
        .padding()
    }
}
