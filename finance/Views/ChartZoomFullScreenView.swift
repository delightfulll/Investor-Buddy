//
//  ChartZoomFullScreenView.swift
//  finance
//
//  Robinhood-style: full-screen chart with smooth drag and pinch zoom
//

import SwiftUI
import UIKit

// MARK: - Chart type enum
enum ChartType: String, CaseIterable {
    case line = "Line"
    case candlestick = "Candle"
}

// MARK: - Full-screen zoom chart with smooth interactions
struct ChartZoomFullScreenView: View {
    let priceHistory: [PriceDataPoint]
    let isPositive: Bool
    let symbol: String
    @Environment(\.dismiss) private var dismiss

    // Chart type toggle
    @State private var chartType: ChartType = .line
    
    // Zoom and scroll state
    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var scrollOffset: Double = 0
    @State private var baseScrollOffset: Double = 0
    
    // Crosshair state
    @State private var selectedIndex: Int?
    @State private var draggedPrice: Double?
    @State private var draggedDate: Date?
    @State private var isDragging: Bool = false
    
    // Haptic feedback for chart scrubbing
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    
    // Zoom constraints
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 5.0

    private var visibleCount: Int {
        // More zoom = fewer visible points
        // Use a minimum of 5 so zoom works on small datasets (e.g. 1M ~22 points)
        let baseCount = Double(priceHistory.count) * 0.3
        let adjusted = baseCount / Double(scale)
        return max(5, min(priceHistory.count, Int(adjusted)))
    }

    private var maxScrollOffset: Double {
        max(0, Double(priceHistory.count - visibleCount))
    }

    private var startIndex: Int {
        max(0, priceHistory.count - visibleCount - Int(scrollOffset.rounded()))
    }

    private var visiblePoints: [PriceDataPoint] {
        let start = startIndex
        let end = min(priceHistory.count, start + visibleCount)
        return Array(priceHistory[start..<end])
    }

    private var minPrice: Double {
        if chartType == .candlestick {
            return visiblePoints.map(\.low).min() ?? 0
        }
        return visiblePoints.map(\.close).min() ?? 0
    }
    
    private var maxPrice: Double {
        if chartType == .candlestick {
            return visiblePoints.map(\.high).max() ?? 100
        }
        return visiblePoints.map(\.close).max() ?? 100
    }
    
    private var priceRange: Double {
        let r = maxPrice - minPrice
        return r > 0 ? r * 1.1 : 1  // Add 10% padding
    }
    
    private var chartColor: Color { isPositive ? .green : .red }
    
    // Date formatter for axis labels
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }
    
    // Get evenly spaced date labels
    private var dateLabels: [(index: Int, date: Date)] {
        let count = visiblePoints.count
        guard count > 1 else { return [] }
        
        let labelCount = min(5, count)
        let step = max(1, (count - 1) / (labelCount - 1))
        
        var labels: [(Int, Date)] = []
        for i in stride(from: 0, to: count, by: step) {
            labels.append((i, visiblePoints[i].date))
        }
        // Always include the last point
        if let last = labels.last, last.0 != count - 1 {
            labels.append((count - 1, visiblePoints[count - 1].date))
        }
        return labels
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let w = geometry.size.width
                let scrubberHeight: CGFloat = 80
                let dateAxisHeight: CGFloat = 30
                let pickerHeight: CGFloat = 50
                let mainChartHeight = geometry.size.height - scrubberHeight - dateAxisHeight - pickerHeight
                
                VStack(spacing: 0) {
                    // Main chart area
                    ZStack(alignment: .top) {
                        if chartType == .line {
                            lineChart(width: w, height: mainChartHeight)
                        } else {
                            candlestickChart(width: w, height: mainChartHeight)
                        }
                        
                        // Price and date indicator
                        if let p = draggedPrice, let d = draggedDate {
                            VStack(spacing: 4) {
                                AnimatedPriceText(
                                    value: p,
                                    font: .system(size: 24),
                                    weight: .bold
                                )
                                Text(d, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.top, 8)
                        }
                    }
                    .frame(height: mainChartHeight)
                    .background(Color(.systemGroupedBackground))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                if !isDragging { haptic.prepare() }
                                isDragging = true
                                
                                // Calculate offset from base position
                                let pointsPerPixel = Double(visibleCount) / max(Double(w), 1)
                                let dragDelta = -Double(value.translation.width) * pointsPerPixel * 0.12
                                let newOffset = baseScrollOffset + dragDelta
                                scrollOffset = min(maxScrollOffset, max(0, newOffset))
                                
                                // Update crosshair
                                updateCrosshairFromLocation(value.location, width: w, height: mainChartHeight)
                            }
                            .onEnded { value in
                                // Calculate velocity for momentum
                                let pointsPerPixel = Double(visibleCount) / max(Double(w), 1)
                                let velocity = -Double(value.velocity.width) * pointsPerPixel * 0.015
                                
                                // Apply momentum with animation
                                let targetOffset = scrollOffset + velocity
                                let clampedTarget = min(maxScrollOffset, max(0, targetOffset))
                                
                                withAnimation(.easeOut(duration: 0.5)) {
                                    scrollOffset = clampedTarget
                                }
                                
                                // Update base offset for next drag
                                baseScrollOffset = clampedTarget
                                
                                isDragging = false
                                
                                // Clear crosshair after a short delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    if !isDragging {
                                        selectedIndex = nil
                                        draggedPrice = nil
                                        draggedDate = nil
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newScale = baseScale * value
                                scale = min(maxScale, max(minScale, newScale))
                            }
                            .onEnded { value in
                                baseScale = scale
                                // Clamp scroll offset after zoom change
                                scrollOffset = min(maxScrollOffset, scrollOffset)
                                baseScrollOffset = scrollOffset
                            }
                    )
                    
                    // Date axis labels
                    dateAxisView(width: w)
                        .frame(height: dateAxisHeight)
                        .background(Color(.systemGroupedBackground))
                    
                    // Mini scrubber chart
                    miniScrubberChart(width: w, height: scrubberHeight)
                        .background(Color(.secondarySystemGroupedBackground))
                    
                    // Chart type picker
                    Picker("Chart Type", selection: $chartType) {
                        ForEach(ChartType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(height: pickerHeight)
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle(symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            scrollOffset = 0
            baseScrollOffset = 0
            scale = 1.0
            baseScale = 1.0
        }
    }
    
    // MARK: - Date Axis View
    private func dateAxisView(width: CGFloat) -> some View {
        let count = visiblePoints.count
        return GeometryReader { geo in
            ZStack {
                ForEach(dateLabels, id: \.index) { item in
                    let stepX = chartType == .candlestick
                        ? width / CGFloat(max(1, count))
                        : width / CGFloat(max(1, count - 1))
                    let x = chartType == .candlestick
                        ? stepX * CGFloat(item.index) + stepX / 2
                        : CGFloat(item.index) * stepX
                    
                    Text(dateFormatter.string(from: item.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: x, y: geo.size.height / 2)
                }
            }
        }
    }
    
    // MARK: - Mini Scrubber Chart
    private func miniScrubberChart(width: CGFloat, height: CGFloat) -> some View {
        let totalCount = priceHistory.count
        let globalMin = chartType == .candlestick 
            ? priceHistory.map(\.low).min() ?? 0
            : priceHistory.map(\.close).min() ?? 0
        let globalMax = chartType == .candlestick
            ? priceHistory.map(\.high).max() ?? 100
            : priceHistory.map(\.close).max() ?? 100
        let globalRange = globalMax - globalMin > 0 ? (globalMax - globalMin) * 1.1 : 1
        
        // Calculate visible window position
        let windowStart = CGFloat(startIndex) / CGFloat(max(1, totalCount))
        let windowWidth = CGFloat(visibleCount) / CGFloat(max(1, totalCount))
        
        return ZStack {
            // Mini chart of all data - switches based on chart type
            Canvas { context, size in
                guard totalCount > 1 else { return }
                let padding: CGFloat = 8
                let chartHeight = size.height - padding * 2
                
                if chartType == .line {
                    // Line chart
                    let stepX = size.width / CGFloat(totalCount - 1)
                    var path = Path()
                    for (i, point) in priceHistory.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = padding + chartHeight - CGFloat((point.close - globalMin) / globalRange) * chartHeight
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    context.stroke(path, with: .color(chartColor.opacity(0.6)), lineWidth: 1.5)
                } else {
                    // Candlestick chart
                    let stepX = size.width / CGFloat(totalCount)
                    let candleWidth = max(1, stepX * 0.6)
                    
                    for (i, point) in priceHistory.enumerated() {
                        let x = stepX * CGFloat(i) + stepX / 2
                        
                        let openY = padding + chartHeight - CGFloat((point.open - globalMin) / globalRange) * chartHeight
                        let closeY = padding + chartHeight - CGFloat((point.close - globalMin) / globalRange) * chartHeight
                        let highY = padding + chartHeight - CGFloat((point.high - globalMin) / globalRange) * chartHeight
                        let lowY = padding + chartHeight - CGFloat((point.low - globalMin) / globalRange) * chartHeight
                        
                        let isUp = point.close >= point.open
                        let color = isUp ? Color.green : Color.red
                        
                        // Draw wick
                        let wickPath = Path { path in
                            path.move(to: CGPoint(x: x, y: highY))
                            path.addLine(to: CGPoint(x: x, y: lowY))
                        }
                        context.stroke(wickPath, with: .color(color.opacity(0.5)), lineWidth: 0.5)
                        
                        // Draw body
                        let bodyTop = min(openY, closeY)
                        let bodyHeight = max(1, abs(closeY - openY))
                        let bodyRect = CGRect(
                            x: x - candleWidth / 2,
                            y: bodyTop,
                            width: candleWidth,
                            height: bodyHeight
                        )
                        context.fill(Path(bodyRect), with: .color(color.opacity(0.6)))
                    }
                }
            }
            
            // Visible window indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(chartColor.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(chartColor.opacity(0.8), lineWidth: 2)
                )
                .frame(width: max(40, width * windowWidth))
                .position(
                    x: width * windowStart + (width * windowWidth) / 2,
                    y: height / 2
                )
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Map tap/drag position to scroll offset
                    let normalizedX = value.location.x / width
                    let targetStart = normalizedX * CGFloat(totalCount) - CGFloat(visibleCount) / 2
                    let newOffset = Double(totalCount - visibleCount) - Double(targetStart)
                    
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                        scrollOffset = min(maxScrollOffset, max(0, newOffset))
                    }
                }
                .onEnded { _ in
                    baseScrollOffset = scrollOffset
                }
        )
    }

    private func updateCrosshairFromLocation(_ location: CGPoint, width: CGFloat, height: CGFloat) {
        let count = visiblePoints.count
        guard count > 0, width > 0 else { return }
        
        let stepX: CGFloat
        let idx: Int
        
        if chartType == .candlestick {
            stepX = width / CGFloat(count)
            let rawIdx = Int(location.x / stepX)
            idx = min(count - 1, max(0, rawIdx))
        } else {
            guard count > 1 else { return }
            stepX = width / CGFloat(count - 1)
            guard stepX.isFinite, stepX > 0 else { return }
            let ratio = location.x / stepX
            guard ratio.isFinite else { return }
            idx = min(count - 1, max(0, Int(ratio.rounded())))
        }
        
        if idx != selectedIndex {
            haptic.impactOccurred()
        }
        selectedIndex = idx
        let point = visiblePoints[idx]
        draggedPrice = point.close
        draggedDate = point.date
    }



    // MARK: - Line Chart
    private func lineChart(width: CGFloat, height: CGFloat) -> some View {
        let count = visiblePoints.count
        let padding: CGFloat = 20
        let chartHeight = height - padding * 2
        
        return ZStack {
            Path { path in
                guard count > 1 else { return }
                let stepX = width / CGFloat(count - 1)
                path.move(to: CGPoint(x: 0, y: height - padding))
                for (i, point) in visiblePoints.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = padding + chartHeight - CGFloat((point.close - minPrice) / priceRange) * chartHeight
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: width, y: height - padding))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [chartColor.opacity(0.35), chartColor.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Path { path in
                guard count > 1 else { return }
                let stepX = width / CGFloat(count - 1)
                for (i, point) in visiblePoints.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = padding + chartHeight - CGFloat((point.close - minPrice) / priceRange) * chartHeight
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(chartColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            crosshairOverlay(width: width, height: height, padding: padding, chartHeight: chartHeight)
        }
    }
    
    // MARK: - Candlestick Chart
    private func candlestickChart(width: CGFloat, height: CGFloat) -> some View {
        let count = visiblePoints.count
        let padding: CGFloat = 20
        let chartHeight = height - padding * 2
        
        return ZStack {
            Canvas { context, size in
                guard count > 0 else { return }
                
                let candleWidth = max(2, (width / CGFloat(count)) * 0.7)
                let stepX = width / CGFloat(max(1, count))
                
                for (i, point) in visiblePoints.enumerated() {
                    let x = stepX * CGFloat(i) + stepX / 2
                    
                    let openY = padding + chartHeight - CGFloat((point.open - minPrice) / priceRange) * chartHeight
                    let closeY = padding + chartHeight - CGFloat((point.close - minPrice) / priceRange) * chartHeight
                    let highY = padding + chartHeight - CGFloat((point.high - minPrice) / priceRange) * chartHeight
                    let lowY = padding + chartHeight - CGFloat((point.low - minPrice) / priceRange) * chartHeight
                    
                    let isUp = point.close >= point.open
                    let color = isUp ? Color.green : Color.red
                    
                    // Draw wick (high to low line)
                    let wickPath = Path { path in
                        path.move(to: CGPoint(x: x, y: highY))
                        path.addLine(to: CGPoint(x: x, y: lowY))
                    }
                    context.stroke(wickPath, with: .color(color), lineWidth: 1)
                    
                    // Draw body (open to close rectangle)
                    let bodyTop = min(openY, closeY)
                    let bodyHeight = max(1, abs(closeY - openY))
                    let bodyRect = CGRect(
                        x: x - candleWidth / 2,
                        y: bodyTop,
                        width: candleWidth,
                        height: bodyHeight
                    )
                    
                    if isUp {
                        // Green candle - filled
                        context.fill(Path(bodyRect), with: .color(color))
                    } else {
                        // Red candle - filled
                        context.fill(Path(bodyRect), with: .color(color))
                    }
                }
            }
            
            crosshairOverlay(width: width, height: height, padding: padding, chartHeight: chartHeight)
        }
    }
    
    // MARK: - Crosshair Overlay
    private func crosshairOverlay(width: CGFloat, height: CGFloat, padding: CGFloat, chartHeight: CGFloat) -> some View {
        let count = visiblePoints.count
        return Group {
            if let idx = selectedIndex, idx < visiblePoints.count {
                let stepX = chartType == .candlestick 
                    ? width / CGFloat(max(1, count))
                    : width / CGFloat(max(1, count - 1))
                let x = chartType == .candlestick 
                    ? stepX * CGFloat(idx) + stepX / 2
                    : CGFloat(idx) * stepX
                let point = visiblePoints[idx]
                let y = padding + chartHeight - CGFloat((point.close - minPrice) / priceRange) * chartHeight
                
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 1, height: height)
                    .position(x: x, y: height / 2)
                Circle()
                    .fill(point.close >= point.open ? Color.green : Color.red)
                    .frame(width: 14, height: 14)
                    .position(x: x, y: y)
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .position(x: x, y: y)
            }
        }
    }
}
