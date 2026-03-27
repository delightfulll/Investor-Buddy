//
//  StockDetailView.swift
//  finance
//
//  MVVM: Stock detail – binds to StockDetailViewModel.
//

import SwiftUI

// MARK: - Animated Price Text (Robinhood-style rolling numbers)
struct AnimatedPriceText: View {
    let value: Double
    let font: Font
    let weight: Font.Weight
    
    @State private var displayedValue: Double = 0
    @State private var previousValue: Double = 0
    
    init(value: Double, font: Font = .system(size: 40), weight: Font.Weight = .bold) {
        self.value = value
        self.font = font
        self.weight = weight
    }
    
    var body: some View {
        HStack(spacing: 0) {
            let priceString = formatPrice(displayedValue)
            ForEach(Array(priceString.enumerated()), id: \.offset) { index, char in
                if char.isNumber {
                    AnimatedDigit(
                        digit: char,
                        direction: displayedValue >= previousValue ? .up : .down
                    )
                    .font(font)
                    .fontWeight(weight)
                } else {
                    Text(String(char))
                        .font(font)
                        .fontWeight(weight)
                }
            }
        }
        .onChange(of: value) { oldValue, newValue in
            previousValue = displayedValue
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 20)) {
                displayedValue = newValue
            }
        }
        .onAppear {
            displayedValue = value
            previousValue = value
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: price)) ?? "$0.00"
    }
}

// MARK: - Single Animated Digit
struct AnimatedDigit: View {
    let digit: Character
    let direction: Direction
    
    enum Direction {
        case up, down
    }
    
    var body: some View {
        Text(String(digit))
            .contentTransition(.numericText(value: Double(String(digit)) ?? 0))
            .transaction { t in
                t.animation = .interpolatingSpring(stiffness: 300, damping: 20)
            }
    }
}

struct StockDetailView: View {
    let stock: StockData
    @StateObject private var vm: StockDetailViewModel
    @StateObject private var accountVM = AccountViewModel.shared
    @State private var showTradeSheet = false
    @State private var showFullScreenChart = false
    @State private var draggedPrice: Double?
    @State private var draggedDate: Date?
    @State private var isDragging = false
    @State private var showFullDescription = false

    init(stock: StockData) {
        self.stock = stock
        _vm = StateObject(wrappedValue: StockDetailViewModel(stock: stock))
    }

    private var displayPrice: Double {
        draggedPrice ?? stock.price
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                priceHeader
                chartSection
                timeRangeSelector
                if vm.sharesOwned > 0 {
                    positionSection
                }
                statsSection
                predictionOutlookSection
                companyInfoSection
                aboutSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(stock.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            tradeButton
        }
        .sheet(isPresented: $showTradeSheet) {
            StockTradingSheetView(stock: stock)
        }
        .fullScreenCover(isPresented: $showFullScreenChart) {
            ChartZoomFullScreenView(
                priceHistory: vm.priceHistory,
                isPositive: vm.priceChange >= 0,
                symbol: stock.symbol
            )
        }
        .task {
            await vm.loadData()
        }
        .onChange(of: vm.selectedTimeRange) { _, _ in
            Task { await vm.loadPriceHistory() }
        }
    }

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stock.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AnimatedPriceText(value: displayPrice)
            if let date = draggedDate {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            } else {
                HStack(spacing: 4) {
                    Image(systemName: vm.priceChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "$%.2f (%.2f%%)", abs(vm.priceChange), abs(vm.priceChangePercent)))
                    Text(vm.selectedTimeRange.rawValue)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(vm.priceChange >= 0 ? .green : .red)
            }
        }
    }

    private var chartSection: some View {
        Group {
            if vm.isLoadingHistory && vm.priceHistory.isEmpty {
                ProgressView()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else if vm.priceHistory.isEmpty {
                Text("No chart data available")
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack(alignment: .topTrailing) {
                    InteractiveStockChart(
                        priceHistory: vm.priceHistory,
                        isPositive: vm.priceChange >= 0,
                        draggedPrice: $draggedPrice,
                        draggedDate: $draggedDate,
                        isDragging: $isDragging
                    )
                    .frame(height: 200)
                    
                    // Expand chart button
                    Button {
                        showFullScreenChart = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
            }
        }
        .padding(.vertical)
    }

    private var timeRangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(StockDetailViewModel.TimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.setTimeRange(range)
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.subheadline)
                        .fontWeight(vm.selectedTimeRange == range ? .semibold : .regular)
                        .foregroundStyle(vm.selectedTimeRange == range ? .white : .blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(vm.selectedTimeRange == range ? Color.blue : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(4)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Position")
                .font(.headline)
            if let owned = accountVM.ownedStocks.first(where: { $0.symbol == stock.symbol }) {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shares")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f", owned.shares))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Market Value")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(owned.shares * stock.price, format: .currency(code: "USD"))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Avg. Cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(owned.averageCost, format: .currency(code: "USD"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Total Return")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let returnValue = (stock.price - owned.averageCost) * owned.shares
                            let returnPct = ((stock.price - owned.averageCost) / owned.averageCost) * 100
                            HStack(spacing: 4) {
                                Text(returnValue, format: .currency(code: "USD"))
                                Text("(\(String(format: "%.2f%%", returnPct)))")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(returnValue >= 0 ? .green : .red)
                        }
                    }
                }
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                statCard(label: "Open", value: String(format: "$%.2f", stock.open))
                statCard(label: "Previous Close", value: String(format: "$%.2f", stock.previousClose))
                statCard(label: "Day High", value: String(format: "$%.2f", stock.dayHigh))
                statCard(label: "Day Low", value: String(format: "$%.2f", stock.dayLow))
                statCard(label: "Volume", value: formatVolume(stock.volume))
                if let info = vm.companyInfo {
                    statCard(label: "Market Cap", value: info.marketCap)
                    statCard(label: "P/E Ratio", value: info.peRatio > 0 ? String(format: "%.2f", info.peRatio) : "N/A")
                    statCard(label: "52W High", value: String(format: "$%.2f", info.fiftyTwoWeekHigh))
                    statCard(label: "52W Low", value: String(format: "$%.2f", info.fiftyTwoWeekLow))
                    statCard(label: "Beta", value: info.beta > 0 ? String(format: "%.2f", info.beta) : "N/A")
                }
            }
        }
    }

    private func formatVolume(_ volume: Int) -> String {
        if volume >= 1_000_000_000 {
            return String(format: "%.2fB", Double(volume) / 1_000_000_000)
        } else if volume >= 1_000_000 {
            return String(format: "%.2fM", Double(volume) / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.2fK", Double(volume) / 1_000)
        } else {
            return "\(volume)"
        }
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var predictionOutlookSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.purple)
                Text("Price Outlook")
                    .font(.headline)
                Spacer()
                if vm.isLoadingPredictions {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if vm.isLoadingPredictions && vm.timeframePredictions.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Running technical analysis...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if vm.timeframePredictions.isEmpty {
                Text("Prediction unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 12) {
                    ForEach(vm.timeframePredictions) { tf in
                        let isUp = tf.prediction.predictedChange >= 0
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isUp ? Color.green : Color.red)
                                    .frame(width: 6, height: 40)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tf.label)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    HStack(spacing: 4) {
                                        Image(systemName: tf.prediction.signal.icon)
                                            .font(.caption2)
                                        Text(tf.prediction.signal.rawValue)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(tf.prediction.signal.color)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(tf.prediction.predictedPrice, format: .currency(code: "USD"))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    Text(String(format: "%+.2f%%", tf.prediction.predictedChangePercent))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(isUp ? .green : .red)
                                }
                            }

                            if let votesSummary = tf.prediction.reasons.first {
                                Text(votesSummary)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }

                            let topReasons = Array(tf.prediction.reasons.dropFirst().prefix(3))
                            if !topReasons.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(topReasons, id: \.self) { reason in
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.secondary.opacity(0.5))
                                                .frame(width: 4, height: 4)
                                            Text(reason)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isUp ? Color.green.opacity(0.4) : Color.red.opacity(0.4), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("Based on technical analysis. Not financial advice.")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var companyInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Company Info")
                .font(.headline)
            if vm.isLoadingCompany && vm.companyInfo == nil {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Loading company info...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if vm.companyInfo == nil {
                VStack(spacing: 12) {
                    Image(systemName: "building.2")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Company info unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if vm.companyInfoError != nil {
                        Button {
                            Task { await vm.loadCompanyInfo() }
                        } label: {
                            Text("Retry")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            } else if let info = vm.companyInfo {
                VStack(spacing: 12) {
                    infoRow(label: "CEO", value: info.ceo)
                    Divider()
                    infoRow(label: "Sector", value: info.sector)
                    Divider()
                    infoRow(label: "Industry", value: info.industry)
                    Divider()
                    infoRow(label: "Headquarters", value: info.headquarters)
                    Divider()
                    infoRow(label: "Employees", value: info.employees > 0 ? "\(info.employees.formatted())" : "N/A")
                    if !info.website.isEmpty {
                        Divider()
                        HStack {
                            Text("Website")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Link(info.website.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""),
                                 destination: URL(string: info.website) ?? URL(string: "https://example.com")!)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                    }
                    if info.dividend > 0 {
                        Divider()
                        infoRow(label: "Dividend Yield", value: String(format: "%.2f%%", info.dividend * 100))
                    }
                    if info.averageVolume > 0 {
                        Divider()
                        infoRow(label: "Avg. Volume", value: formatLargeNumber(info.averageVolume))
                    }
                }
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
        }
    }

    private func formatLargeNumber(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", Double(value) / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.2fK", Double(value) / 1_000)
        } else {
            return "\(value)"
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About \(stock.symbol)")
                .font(.headline)
            if let info = vm.companyInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text(info.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .lineLimit(showFullDescription ? nil : 4)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFullDescription.toggle()
                        }
                    } label: {
                        Text(showFullDescription ? "Show Less" : "Read More")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                }
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            } else if !vm.isLoadingCompany {
                Text("Description unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
        }
    }

    private var tradeButton: some View {
        Button {
            showTradeSheet = true
        } label: {
            Text("Trade")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
