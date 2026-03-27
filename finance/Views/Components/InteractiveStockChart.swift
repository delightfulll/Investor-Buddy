//
//  InteractiveStockChart.swift
//  finance
//

import SwiftUI
import UIKit

struct InteractiveStockChart: View {
    let priceHistory: [PriceDataPoint]
    let isPositive: Bool
    @Binding var draggedPrice: Double?
    @Binding var draggedDate: Date?
    @Binding var isDragging: Bool

    @State private var selectedIndex: Int?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var chartColor: Color {
        isPositive ? .green : .red
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let points = priceHistory
            let count = points.count
            let pMin = points.map(\.close).min() ?? 0
            let pMax = points.map(\.close).max() ?? 100
            let pRange = (pMax - pMin) > 0 ? (pMax - pMin) : 1.0

            ZStack {
                Canvas { context, size in
                    guard count > 1 else { return }
                    let stepX = size.width / CGFloat(count - 1)

                    // Gradient fill
                    var fillPath = Path()
                    fillPath.move(to: CGPoint(x: 0, y: size.height))
                    for (i, point) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = size.height - CGFloat((point.close - pMin) / pRange) * size.height
                        fillPath.addLine(to: CGPoint(x: x, y: y))
                    }
                    fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                    fillPath.closeSubpath()
                    context.fill(fillPath, with: .linearGradient(
                        Gradient(colors: [chartColor.opacity(0.3), chartColor.opacity(0.0)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    ))

                    // Line
                    var linePath = Path()
                    for (i, point) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = size.height - CGFloat((point.close - pMin) / pRange) * size.height
                        if i == 0 { linePath.move(to: CGPoint(x: x, y: y)) }
                        else { linePath.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(linePath, with: .color(chartColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                // Crosshair
                if let index = selectedIndex, index < count {
                    let stepX = width / CGFloat(max(1, count - 1))
                    let x = CGFloat(index) * stepX
                    let point = points[index]
                    let y = height - CGFloat((point.close - pMin) / pRange) * height
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 1, height: height)
                        .position(x: x, y: height / 2)
                    Circle()
                        .fill(chartColor)
                        .frame(width: 12, height: 12)
                        .position(x: x, y: y)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging { haptic.prepare() }
                        isDragging = true
                        guard count > 1 else { return }
                        let stepX = width / CGFloat(count - 1)
                        let idx = Int((value.location.x / stepX).rounded())
                        let clamped = max(0, min(count - 1, idx))
                        if clamped != selectedIndex {
                            haptic.impactOccurred()
                        }
                        selectedIndex = clamped
                        draggedPrice = points[clamped].close
                        draggedDate = points[clamped].date
                    }
                    .onEnded { _ in
                        isDragging = false
                        selectedIndex = nil
                        draggedPrice = nil
                        draggedDate = nil
                    }
            )
        }
    }
}
