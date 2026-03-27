//
//  HomeView.swift
//  finance
//
//  MVVM: Home screen view – binds to HomeViewModel and AccountViewModel.
//

import SwiftUI
import Combine
struct HomeView: View {
    private let userName = "Vinay"
    @StateObject private var homeVM = HomeViewModel()
    @StateObject private var accountVM = AccountViewModel.shared
    @StateObject private var watchlistManager = WatchlistManager.shared
    @StateObject private var recommendVM = StockRecommendationViewModel()
    @State private var showTransferSheet = false
    @State private var stockToDelete: StockData?
    @State private var showDeleteAlert = false
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    welcomeSection
                    tradingTypeSection
                    netWorthCard
                    performanceSection
                    accountsSection
                    buyingPowerSection
                    recommendedStocksSection
                    marketMoversSection
                    preciousMetalsSection
                    watchlistSection
                    riskDisclaimerSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Finance")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await homeVM.loadData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .fontWeight(.medium)
                    }
                }
            }
            .sheet(isPresented: $showTransferSheet) {
                TransferSheetView()
            }
            .alert("Remove from Watchlist", isPresented: $showDeleteAlert, presenting: stockToDelete) { stock in
                Button("Remove", role: .destructive) {
                    withAnimation {
                        watchlistManager.removeSymbol(stock.symbol)
                        homeVM.stocks.removeAll { $0.symbol == stock.symbol }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { stock in
                Text("Are you sure you want to remove \(stock.symbol) from your watchlist?")
            }
        }
        .task {
            await homeVM.loadData()
            if !recommendVM.hasLoaded {
                await recommendVM.loadRecommendations()
            }
        }
        .onReceive(refreshTimer) { _ in
            Task { await homeVM.loadData() }
        }
    }

    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back,")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(userName)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.blue)
            if let lastUpdated = homeVM.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var tradingTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trading Account")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(TradingType.allCases, id: \.self) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            accountVM.tradingType = type
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type == .cash ? "dollarsign.circle.fill" : "chart.line.uptrend.xyaxis.circle.fill")
                                .font(.title2)
                            Text(type.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(type == .cash ? "No leverage" : "2x leverage")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(accountVM.tradingType == type ? Color.blue : Color.white)
                        .foregroundStyle(accountVM.tradingType == type ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            if accountVM.tradingType == .margin {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Margin trading involves higher risk. You may lose more than your initial investment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var netWorthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Net Worth")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            Text(accountVM.netWorth, format: .currency(code: "USD"))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private var performanceSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // YTD Performance
                VStack(alignment: .leading, spacing: 8) {
                    Text("YTD Performance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(accountVM.ytdReturn, format: .currency(code: "USD"))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(accountVM.ytdReturn >= 0 ? .green : .red)
                    HStack(spacing: 4) {
                        Image(systemName: accountVM.ytdReturn >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                        Text(String(format: "%.2f%%", accountVM.ytdReturnPercent))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(accountVM.ytdReturn >= 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)

                // Contributions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contributions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(accountVM.totalContributions, format: .currency(code: "USD"))
                        .font(.title3)
                        .fontWeight(.semibold)
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption2)
                        Text("Total Deposited")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }

            // Portfolio return
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio Return")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: accountVM.totalReturn >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                        Text(accountVM.totalReturn, format: .currency(code: "USD"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(accountVM.totalReturn >= 0 ? .green : .red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Portfolio Value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(accountVM.portfolioValue, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .padding()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts")
                    .font(.headline)
                Spacer()
                Button("Transfer") { showTransferSheet = true }
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            HStack(spacing: 12) {
                accountCard(name: "Checking", icon: "creditcard.fill", balance: accountVM.checkingBalance, color: .blue)
                accountCard(name: "Savings", icon: "banknote.fill", balance: accountVM.savingsBalance, color: .green)
            }
        }
    }

    private func accountCard(name: String, icon: String, balance: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(balance, format: .currency(code: "USD"))
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var buyingPowerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Investing")
                .font(.headline)
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(accountVM.tradingType == .cash ? "Cash Buying Power" : "Margin Buying Power")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if accountVM.tradingType == .margin {
                                Text("2x")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(accountVM.currentBuyingPower, format: .currency(code: "USD"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Button {
                        showTransferSheet = true
                    } label: {
                        Text("Add Funds")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
                if accountVM.tradingType == .margin {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cash Balance")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(accountVM.buyingPower, format: .currency(code: "USD"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Margin Used")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(accountVM.marginBuyingPower - accountVM.buyingPower, format: .currency(code: "USD"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
    }

    private var recommendedStocksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Recommended For You")
                    .font(.headline)
                Spacer()
                if recommendVM.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if recommendVM.hasLoaded {
                    Button {
                        Task {
                            recommendVM.recommendations = []
                            await recommendVM.loadRecommendations()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundStyle(.purple)
                    }
                }
            }

            if recommendVM.isLoading && recommendVM.recommendations.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(recommendVM.loadingStatus.isEmpty ? "Scanning today's market..." : recommendVM.loadingStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if recommendVM.recommendations.isEmpty {
                Text("No recommendations available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Top picks (buy/strong buy only)
                let topPicks = recommendVM.recommendations.filter { $0.score > 15 }.prefix(10)
                if !topPicks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.circle.fill")
                                .foregroundStyle(.green)
                            Text("Top Picks")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(topPicks) { prediction in
                                    NavigationLink {
                                        StockDetailView(stock: stockDataFrom(prediction))
                                    } label: {
                                        predictionCard(prediction: prediction)
                                    }
                                    .buttonStyle(.plain)
                                    .onAppear { haptic.impactOccurred() }
                                }
                            }
                        }
                    }
                }

                // Stocks to watch (sell signals)
                let caution = recommendVM.recommendations.filter { $0.score < -15 }.prefix(5)
                if !caution.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Use Caution")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(caution) { prediction in
                                    NavigationLink {
                                        StockDetailView(stock: stockDataFrom(prediction))
                                    } label: {
                                        predictionCard(prediction: prediction)
                                    }
                                    .buttonStyle(.plain)
                                    .onAppear { haptic.impactOccurred() }
                                }
                            }
                        }
                    }
                }
            }

            // Disclaimer
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("Based on technical analysis. Not financial advice.")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
        }
    }

    private func predictionCard(prediction: StockPrediction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text(prediction.symbol)
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text(prediction.signal.rawValue)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(prediction.signal.color)
                    .clipShape(Capsule())
            }
            Text(prediction.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Sector badge
            Text(prediction.sector)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(sectorColor(prediction.sector))
                .clipShape(Capsule())

            Spacer()

            // Price info
            Text(prediction.currentPrice, format: .currency(code: "USD"))
                .font(.subheadline)
                .fontWeight(.semibold)

            // Predicted change
            HStack(spacing: 2) {
                Image(systemName: prediction.predictedChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                Text(String(format: "%+.2f%%", prediction.predictedChangePercent))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(prediction.predictedChange >= 0 ? .green : .red)

            // Confidence bar
            VStack(alignment: .leading, spacing: 2) {
                Text("Confidence")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(prediction.signal.color)
                            .frame(width: geo.size.width * prediction.confidence)
                    }
                }
                .frame(height: 4)
            }

            // Top reason
            if let reason = prediction.reasons.first {
                Text(reason)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 160, height: 190, alignment: .leading)
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(prediction.signal.color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func stockDataFrom(_ prediction: StockPrediction) -> StockData {
        StockData(
            symbol: prediction.symbol,
            name: prediction.name,
            price: prediction.currentPrice,
            change: prediction.predictedChange,
            changePercent: prediction.predictedChangePercent,
            previousClose: prediction.currentPrice - prediction.predictedChange,
            open: prediction.currentPrice,
            dayHigh: prediction.currentPrice,
            dayLow: prediction.currentPrice,
            volume: 0,
            marketCap: 0
        )
    }

    private func sectorColor(_ sector: String) -> Color {
        switch sector {
        case "Technology": return .blue
        case "Energy": return .orange
        case "Healthcare": return .pink
        case "Financial Services": return .indigo
        case "Consumer Cyclical": return .purple
        case "Consumer Defensive": return .teal
        case "Industrials": return .gray
        case "Basic Materials": return .brown
        case "Real Estate": return .cyan
        case "Utilities": return .yellow
        case "Communication Services": return .mint
        default: return .secondary
        }
    }

    private var marketMoversSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Market")
                .font(.headline)
            if homeVM.isLoadingMovers && homeVM.topGainers.isEmpty && homeVM.topLosers.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .foregroundStyle(.green)
                        Text("Top Gainers")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(homeVM.topGainers.prefix(5)) { stock in
                                NavigationLink {
                                    MoverStockDetailView(moverStock: stock)
                                } label: {
                                    moverCard(stock: stock, isGainer: true)
                                }
                                .buttonStyle(.plain)
                                .onAppear { haptic.impactOccurred() }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.down.right.circle.fill")
                            .foregroundStyle(.red)
                        Text("Top Losers")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(homeVM.topLosers.prefix(5)) { stock in
                                NavigationLink {
                                    MoverStockDetailView(moverStock: stock)
                                } label: {
                                    moverCard(stock: stock, isGainer: false)
                                }
                                .buttonStyle(.plain)
                                .onAppear { haptic.impactOccurred() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func moverCard(stock: MoverStock, isGainer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stock.symbol)
                .font(.headline)
                .fontWeight(.bold)
            Text(stock.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(stock.price, format: .currency(code: "USD"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isGainer ? Color.green : Color.red, lineWidth: 1.5)
                )
            HStack(spacing: 2) {
                Image(systemName: isGainer ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                Text(String(format: "%.2f%%", abs(stock.changePercent)))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isGainer ? .green : .red)
        }
        .frame(width: 120, height: 100, alignment: .leading)
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var preciousMetalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Precious Metals")
                .font(.headline)
            if homeVM.isLoadingMetals && homeVM.metals.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(homeVM.metals) { metal in
                        NavigationLink {
                            StockDetailView(stock: metal.asStockData)
                        } label: {
                            metalCard(metal: metal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func metalCard(metal: MetalQuote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(metal.symbol)
                    .font(.title2)
                Text(metal.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(metal.price, format: .currency(code: "USD"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            HStack(spacing: 2) {
                Image(systemName: metal.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                Text(String(format: "%+.2f (%.2f%%)", metal.change, abs(metal.changePercent)))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(metal.change >= 0 ? .green : .red)
            Text(metal.unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Watchlist")
                    .font(.headline)
                Spacer()
                if homeVM.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            if homeVM.stocks.isEmpty && !homeVM.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.blue.opacity(0.5))
                    Text("No stocks in your watchlist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Go to Search tab to add stocks")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(homeVM.stocks.prefix(5)) { stock in
                        NavigationLink(value: stock) {
                            stockRow(stock: stock)
                        }
                        .buttonStyle(.plain)
                        .onAppear { haptic.impactOccurred() }
                        .contextMenu {
                            Button(role: .destructive) {
                                stockToDelete = stock
                                showDeleteAlert = true
                            } label: {
                                Label("Remove from Watchlist", systemImage: "trash")
                            }
                        }
                        if stock.id != homeVM.stocks.prefix(5).last?.id {
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
                if homeVM.stocks.count > 5 {
                    Text("View all in Portfolio tab")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func stockRow(stock: StockData) -> some View {
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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(stock.change >= 0 ? Color.green : Color.red, lineWidth: 1.5)
                    )
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

    private var riskDisclaimerSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.vertical, 8)
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("INVESTMENT RISK DISCLOSURE")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.secondary)
                Text("Securities products are not FDIC insured, are not bank guaranteed, and may lose value. Investing involves risk, including possible loss of principal. Past performance does not guarantee future results.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Text("This app is for educational purposes only and does not constitute financial advice. Consult a licensed financial advisor before making investment decisions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
}
