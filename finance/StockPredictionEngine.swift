//
//  StockPredictionEngine.swift
//  finance
//
//  Comprehensive technical analysis prediction engine.
//
//  Trend:       MA/EMA/WMA, MACD, Trend Consistency, ADX, Parabolic SAR, Ichimoku Cloud
//  Momentum:    RSI, Momentum/ROC, Stochastic, CCI, Williams %R
//  Volatility:  Bollinger Bands, ATR, Keltner Channels
//  Volume:      Volume, OBV, VWAP, CMF, MFI
//  S/R:         Support/Resistance, Pivot Points, Fibonacci Retracement, Price Action
//  Mean Rev:    Z-Score, RSI Divergence
//  Candlestick: Doji, Hammer, Engulfing, Gap
//

import Foundation

struct StockPredictionEngine {

    // MARK: - Horizon

    enum Horizon: String {
        case shortTerm  = "Short-term"
        case mediumTerm = "Medium-term"
        case longTerm   = "Long-term"

        var maPeriods: (fast: Int, mid: Int, slow: Int, verySlow: Int) {
            switch self {
            case .shortTerm:  return (10, 20, 50, 200)
            case .mediumTerm: return (20, 50, 100, 200)
            case .longTerm:   return (26, 52, 100, 200)
            }
        }

        var rsiPeriod: Int {
            switch self {
            case .shortTerm:  return 14
            case .mediumTerm: return 21
            case .longTerm:   return 30
            }
        }

        var bollingerPeriod: Int {
            switch self {
            case .shortTerm:  return 20
            case .mediumTerm: return 30
            case .longTerm:   return 50
            }
        }

        var trendLabel: String { rawValue }
    }

    // MARK: - Market Regime

    enum MarketRegime {
        case trendingBull
        case trendingBear
        case ranging
        case volatile
    }

    private static func detectRegime(closes: [Double], highs: [Double], lows: [Double]) -> MarketRegime {
        let count = min(closes.count, min(highs.count, lows.count))
        guard count >= 30 else { return .ranging }

        let period = 14
        guard count >= period + 1 else { return .ranging }

        var plusDM: [Double] = [], minusDM: [Double] = [], trVals: [Double] = []
        for i in 1..<count {
            let upMove = highs[i] - highs[i-1]
            let downMove = lows[i-1] - lows[i]
            plusDM.append(upMove > downMove && upMove > 0 ? upMove : 0)
            minusDM.append(downMove > upMove && downMove > 0 ? downMove : 0)
            let hl = highs[i] - lows[i]
            let hc = abs(highs[i] - closes[i-1])
            let lc = abs(lows[i] - closes[i-1])
            trVals.append(max(hl, max(hc, lc)))
        }

        let smoothTR = ema(trVals, period: period)
        guard smoothTR > 0 else { return .ranging }
        let plusDI  = (ema(plusDM, period: period) / smoothTR) * 100
        let minusDI = (ema(minusDM, period: period) / smoothTR) * 100
        let diSum = plusDI + minusDI
        let adx = diSum > 0 ? abs(plusDI - minusDI) / diSum * 100 : 0

        let atrVal = atr(closes: closes, highs: highs, lows: lows, period: period)
        let current = closes.last ?? 1
        let atrPct = current > 0 ? (atrVal / current) * 100 : 0

        let ma20 = sma(closes, period: min(20, closes.count))
        let ma50 = sma(closes, period: min(50, closes.count))

        if atrPct > 4 && adx < 20 {
            return .volatile
        } else if adx > 25 {
            return (ma20 > ma50 && current > ma20) ? .trendingBull : .trendingBear
        } else {
            return .ranging
        }
    }

    // MARK: - Main Prediction

    /// Analyze price history and produce a prediction for a stock.
    static func predict(
        symbol: String,
        name: String,
        sector: String = "Unknown",
        currentPrice: Double,
        priceHistory: [PriceDataPoint],
        horizon: Horizon = .shortTerm
    ) -> StockPrediction {
        guard priceHistory.count >= 20 else {
            return StockPrediction(
                symbol: symbol, name: name, sector: sector,
                currentPrice: currentPrice, predictedPrice: currentPrice,
                signal: .hold, confidence: 0.1, score: 0,
                reasons: ["Insufficient data for analysis"]
            )
        }

        let opens = priceHistory.map(\.open)
        let closes = priceHistory.map(\.close)
        let highs = priceHistory.map(\.high)
        let lows = priceHistory.map(\.low)
        let volumes = priceHistory.map(\.volume)

        // ── Trend (6) ──
        var sig_ma       = movingAverageSignal(closes: closes, horizon: horizon)
        var sig_macd     = macdSignal(closes: closes)
        var sig_trend    = trendConsistencySignal(closes: closes, horizon: horizon)
        var sig_adx      = adxSignal(closes: closes, highs: highs, lows: lows, horizon: horizon)
        var sig_sar      = parabolicSARSignal(closes: closes, highs: highs, lows: lows)
        var sig_ichimoku = ichimokuSignal(closes: closes, highs: highs, lows: lows)

        // ── Momentum / Oscillators (5) ──
        var sig_rsi       = rsiSignal(closes: closes, horizon: horizon)
        var sig_momentum  = momentumSignal(closes: closes, horizon: horizon)
        var sig_stoch     = stochasticSignal(closes: closes, highs: highs, lows: lows)
        var sig_cci       = cciSignal(closes: closes, highs: highs, lows: lows)
        var sig_williams  = williamsRSignal(closes: closes, highs: highs, lows: lows)

        // ── Volatility (3) ──
        var sig_boll     = bollingerBandSignal(closes: closes, horizon: horizon)
        var sig_vol      = volatilitySignal(closes: closes, highs: highs, lows: lows)
        var sig_keltner  = keltnerChannelSignal(closes: closes, highs: highs, lows: lows)

        // ── Volume (4) ──
        var sig_volume   = volumeSignal(volumes: volumes, closes: closes)
        var sig_obv      = obvSignal(volumes: volumes, closes: closes)
        var sig_vwap     = vwapSignal(closes: closes, highs: highs, lows: lows, volumes: volumes)
        var sig_cmf      = cmfSignal(closes: closes, highs: highs, lows: lows, volumes: volumes)
        var sig_mfi      = mfiSignal(closes: closes, highs: highs, lows: lows, volumes: volumes)

        // ── Support / Resistance (4) ──
        var sig_sr       = supportResistanceSignal(closes: closes, highs: highs, lows: lows)
        var sig_pivot    = pivotPointSignal(closes: closes, highs: highs, lows: lows)
        var sig_fib      = fibonacciSignal(closes: closes, highs: highs, lows: lows)
        var sig_priceAct = priceActionSignal(closes: closes, highs: highs, lows: lows)

        // ── Mean Reversion (2) ──
        var sig_zscore   = zScoreSignal(closes: closes)
        var sig_rsiDiv   = rsiDivergenceSignal(closes: closes)

        // ── Candlestick / Pattern (2) ──
        var sig_candle   = candlestickSignal(opens: opens, closes: closes, highs: highs, lows: lows)
        var sig_gap      = gapSignal(opens: opens, closes: closes)

        // ── Regime detection ──
        let regime = detectRegime(closes: closes, highs: highs, lows: lows)

        // ── Group-based composite (decorrelates redundant signals) ──
        func groupAvg(_ scores: [Double]) -> Double {
            scores.reduce(0, +) / max(1, Double(scores.count))
        }

        let trendGroup      = groupAvg([sig_ma.score, sig_macd.score, sig_trend.score, sig_adx.score, sig_sar.score, sig_ichimoku.score])
        let momentumGroup   = groupAvg([sig_rsi.score, sig_momentum.score, sig_stoch.score, sig_cci.score, sig_williams.score])
        let volatilityGroup = groupAvg([sig_boll.score, sig_vol.score, sig_keltner.score])
        let volumeGroup     = groupAvg([sig_volume.score, sig_obv.score, sig_vwap.score, sig_cmf.score, sig_mfi.score])
        let srGroup         = groupAvg([sig_sr.score, sig_pivot.score, sig_fib.score, sig_priceAct.score])
        let meanRevGroup    = groupAvg([sig_zscore.score, sig_rsiDiv.score])
        let candleGroup     = groupAvg([sig_candle.score, sig_gap.score])

        // Base group weights (sum to 1.0)
        var wTrend = 0.25, wMomentum = 0.18, wVolatility = 0.10
        var wVolume = 0.17, wSR = 0.14, wMeanRev = 0.10, wCandle = 0.06

        // Regime-adaptive multipliers
        switch regime {
        case .trendingBull, .trendingBear:
            wTrend *= 1.4; wMomentum *= 0.75; wMeanRev *= 0.5; wVolume *= 1.15
        case .ranging:
            wTrend *= 0.6; wMomentum *= 1.4; wMeanRev *= 1.5
        case .volatile:
            wTrend *= 0.85; wMomentum *= 1.1; wVolatility *= 1.5; wMeanRev *= 0.7
        }

        // Re-normalize to 1.0
        let totalW = wTrend + wMomentum + wVolatility + wVolume + wSR + wMeanRev + wCandle
        wTrend /= totalW; wMomentum /= totalW; wVolatility /= totalW
        wVolume /= totalW; wSR /= totalW; wMeanRev /= totalW; wCandle /= totalW

        let compositeScore =
            trendGroup      * wTrend +
            momentumGroup   * wMomentum +
            volatilityGroup * wVolatility +
            volumeGroup     * wVolume +
            srGroup         * wSR +
            meanRevGroup    * wMeanRev +
            candleGroup     * wCandle

        let clampedScore = max(-100, min(100, compositeScore))

        let signal: PredictionSignal
        switch clampedScore {
        case 50...:         signal = .strongBuy
        case 20..<50:       signal = .buy
        case -20..<20:      signal = .hold
        case -50 ..< -20:   signal = .sell
        default:            signal = .strongSell
        }

        // Volatility-scaled price prediction (ATR-based instead of fixed 5%)
        let atrVal = atr(closes: closes, highs: highs, lows: lows, period: 14)
        let atrPct = currentPrice > 0 ? (atrVal / currentPrice) : 0.02
        let maxMove = max(0.02, min(0.15, atrPct * 3))
        let predictedMove = (clampedScore / 100.0) * maxMove
        let predictedPrice = currentPrice * (1.0 + predictedMove)

        // Confidence: strength-weighted agreement + cross-group consensus
        let allScores: [Double] = [
            sig_ma.score, sig_macd.score, sig_trend.score, sig_adx.score,
            sig_sar.score, sig_ichimoku.score, sig_rsi.score, sig_momentum.score,
            sig_stoch.score, sig_cci.score, sig_williams.score, sig_boll.score,
            sig_vol.score, sig_keltner.score, sig_volume.score, sig_obv.score,
            sig_vwap.score, sig_cmf.score, sig_mfi.score, sig_sr.score,
            sig_pivot.score, sig_fib.score, sig_priceAct.score, sig_zscore.score,
            sig_rsiDiv.score, sig_candle.score, sig_gap.score
        ]
        let bullishStrength = allScores.filter { $0 > 10 }.reduce(0.0, +)
        let bearishStrength = allScores.filter { $0 < -10 }.reduce(0.0) { $0 + abs($1) }
        let totalStrength = allScores.reduce(0.0) { $0 + abs($1) }
        let strengthAgreement = totalStrength > 0 ? max(bullishStrength, bearishStrength) / totalStrength : 0.5
        let avgAbsScore = totalStrength / Double(allScores.count)
        let decisiveness = min(1.0, avgAbsScore / 50.0)
        let groupScores = [trendGroup, momentumGroup, volatilityGroup, volumeGroup, srGroup, meanRevGroup, candleGroup]
        let groupsBullish = groupScores.filter { $0 > 10 }.count
        let groupsBearish = groupScores.filter { $0 < -10 }.count
        let groupAgreement = Double(max(groupsBullish, groupsBearish)) / Double(groupScores.count)
        let dataBonus = min(0.1, Double(closes.count) / 3000.0)
        let confidence = max(0.15, min(0.95,
            strengthAgreement * 0.35 +
            decisiveness * 0.2 +
            groupAgreement * 0.35 +
            dataBonus
        ))

        // Collect ALL indicator results
        let allSignals: [SignalResult] = [
            sig_ma, sig_macd, sig_trend, sig_adx, sig_sar, sig_ichimoku,
            sig_rsi, sig_momentum, sig_stoch, sig_cci, sig_williams,
            sig_boll, sig_vol, sig_keltner,
            sig_volume, sig_obv, sig_vwap, sig_cmf, sig_mfi,
            sig_sr, sig_pivot, sig_fib, sig_priceAct,
            sig_zscore, sig_rsiDiv,
            sig_candle, sig_gap
        ]

        let bullishCount = allSignals.filter { $0.score > 10 }.count
        let bearishCount = allSignals.filter { $0.score < -10 }.count
        let neutralCount = allSignals.count - bullishCount - bearishCount

        let regimeLabel: String
        switch regime {
        case .trendingBull: regimeLabel = "Trending Bull"
        case .trendingBear: regimeLabel = "Trending Bear"
        case .ranging:      regimeLabel = "Range-bound"
        case .volatile:     regimeLabel = "High Volatility"
        }

        var reasons: [String] = []
        reasons.append("Market regime: \(regimeLabel) — \(bullishCount) bullish, \(bearishCount) bearish, \(neutralCount) neutral out of \(allSignals.count) indicators")

        let sortedByStrength = allSignals
            .filter { !$0.reasons.isEmpty }
            .sorted { abs($0.score) > abs($1.score) }
        for sig in sortedByStrength.prefix(8) {
            reasons.append(sig.summary)
        }

        return StockPrediction(
            symbol: symbol, name: name, sector: sector,
            currentPrice: currentPrice, predictedPrice: predictedPrice,
            signal: signal, confidence: confidence, score: clampedScore,
            reasons: reasons
        )
    }

    // MARK: - Multi-Timeframe Aggregation

    static func aggregatePrediction(
        symbol: String,
        name: String,
        sector: String = "Unknown",
        currentPrice: Double,
        historyWindows: [(label: String, weight: Double, history: [PriceDataPoint])],
        horizon: Horizon = .shortTerm
    ) -> StockPrediction {
        guard !historyWindows.isEmpty else {
            return StockPrediction(
                symbol: symbol, name: name, sector: sector,
                currentPrice: currentPrice, predictedPrice: currentPrice,
                signal: .hold, confidence: 0.1, score: 0,
                reasons: ["No data available"]
            )
        }

        var totalWeight: Double = 0
        var weightedScore: Double = 0
        var allReasons: [String] = []
        var allConfidences: [Double] = []

        for window in historyWindows {
            guard window.history.count >= 20 else { continue }
            let prediction = predict(
                symbol: symbol, name: name, sector: sector,
                currentPrice: currentPrice, priceHistory: window.history,
                horizon: horizon
            )
            weightedScore += prediction.score * window.weight
            totalWeight += window.weight
            allConfidences.append(prediction.confidence)
            allReasons.append(contentsOf: prediction.reasons)
        }
        // Deduplicate while keeping order
        var seen = Set<String>()
        allReasons = allReasons.filter { seen.insert($0).inserted }

        guard totalWeight > 0 else {
            return StockPrediction(
                symbol: symbol, name: name, sector: sector,
                currentPrice: currentPrice, predictedPrice: currentPrice,
                signal: .hold, confidence: 0.1, score: 0,
                reasons: ["Insufficient data for analysis"]
            )
        }

        let finalScore = max(-100, min(100, weightedScore / totalWeight))
        let avgConfidence = allConfidences.isEmpty ? 0.2 : allConfidences.reduce(0, +) / Double(allConfidences.count)

        let signal: PredictionSignal
        switch finalScore {
        case 50...:       signal = .strongBuy
        case 20..<50:     signal = .buy
        case -20..<20:    signal = .hold
        case -50 ..< -20: signal = .sell
        default:          signal = .strongSell
        }

        // Volatility-scaled price prediction from the primary data window
        var maxMove = 0.05
        if let primary = historyWindows.first(where: { $0.history.count >= 20 }) {
            let h = primary.history.map(\.high)
            let l = primary.history.map(\.low)
            let c = primary.history.map(\.close)
            let atrVal = atr(closes: c, highs: h, lows: l, period: 14)
            let atrPct = currentPrice > 0 ? (atrVal / currentPrice) : 0.02
            maxMove = max(0.02, min(0.15, atrPct * 3))
        }
        let predictedMove = (finalScore / 100.0) * maxMove
        let predictedPrice = currentPrice * (1.0 + predictedMove)

        return StockPrediction(
            symbol: symbol, name: name, sector: sector,
            currentPrice: currentPrice, predictedPrice: predictedPrice,
            signal: signal, confidence: min(0.95, avgConfidence),
            score: finalScore, reasons: allReasons
        )
    }

    // ================================================================
    // MARK: - Signal Result
    // ================================================================

    private struct SignalResult {
        let name: String
        let category: String
        let score: Double   // -100 to +100
        let reasons: [String]

        var summary: String {
            let direction = score > 10 ? "Bullish" : (score < -10 ? "Bearish" : "Neutral")
            if let reason = reasons.first {
                return reason
            }
            return "\(name): \(direction)"
        }
    }

    // ================================================================
    // MARK: - TREND INDICATORS
    // ================================================================

    // MARK: Moving Average Signal (MA / EMA / WMA + Golden/Death Cross)
    private static func movingAverageSignal(closes: [Double], horizon: Horizon = .shortTerm) -> SignalResult {
        var score: Double = 0
        var reasons: [String] = []
        let current = closes.last ?? 0
        let periods = horizon.maPeriods
        let label = horizon.trendLabel

        let fastMA = sma(closes, period: min(periods.fast, closes.count))
        let midMA  = sma(closes, period: min(periods.mid, closes.count))
        let slowMA = sma(closes, period: min(periods.slow, closes.count))

        if current > fastMA { score += 20 } else { score -= 20 }

        if fastMA > midMA {
            score += 30
            reasons.append("\(label) trend bullish (\(periods.fast)-MA > \(periods.mid)-MA)")
        } else {
            score -= 30
            reasons.append("\(label) trend bearish (\(periods.fast)-MA < \(periods.mid)-MA)")
        }

        if current > slowMA {
            score += 20
            reasons.append("Price above \(periods.slow)-period MA")
        } else {
            score -= 20
        }

        if closes.count >= periods.verySlow {
            let verySlowMA = sma(closes, period: periods.verySlow)
            if slowMA > verySlowMA {
                score += 15
                reasons.append("Golden cross: \(periods.slow)-MA above \(periods.verySlow)-MA")
            } else {
                score -= 15
                reasons.append("Death cross: \(periods.slow)-MA below \(periods.verySlow)-MA")
            }
        }

        // Detect recent crossovers (more significant than static position)
        if closes.count > periods.mid + 5 {
            let prevCloses = Array(closes.dropLast(5))
            let prevFast = sma(prevCloses, period: min(periods.fast, prevCloses.count))
            let prevMid  = sma(prevCloses, period: min(periods.mid, prevCloses.count))
            if fastMA > midMA && prevFast <= prevMid {
                score += 15
                reasons.append("Recent bullish crossover (\(periods.fast)-MA crossed above \(periods.mid)-MA)")
            } else if fastMA < midMA && prevFast >= prevMid {
                score -= 15
                reasons.append("Recent bearish crossover (\(periods.fast)-MA crossed below \(periods.mid)-MA)")
            }
        }

        return SignalResult(name: "Moving Avg", category: "Trend", score: clamp(score), reasons: reasons)
    }

    // MARK: MACD Signal
    private static func macdSignal(closes: [Double]) -> SignalResult {
        guard closes.count >= 26 else { return SignalResult(name: "MACD", category: "Trend", score: 0, reasons: []) }

        let ema12 = ema(closes, period: 12)
        let ema26 = ema(closes, period: 26)
        let macdLine = ema12 - ema26
        let current = closes.last ?? 0

        var macdValues: [Double] = []
        for i in max(0, closes.count - 30)..<closes.count {
            let slice = Array(closes.prefix(i + 1))
            if slice.count >= 26 {
                macdValues.append(ema(slice, period: 12) - ema(slice, period: 26))
            }
        }
        let signalLine = macdValues.count >= 9 ? ema(macdValues, period: 9) : 0

        var score: Double = 0
        var reasons: [String] = []

        if macdLine > signalLine && macdLine > 0 {
            score = 70; reasons.append("MACD bullish — above signal line and positive")
        } else if macdLine > signalLine {
            score = 40; reasons.append("MACD crossing above signal line")
        } else if macdLine < signalLine && macdLine < 0 {
            score = -70; reasons.append("MACD bearish — below signal line and negative")
        } else {
            score = -40
        }

        if macdValues.count >= 2 {
            let histCurr = macdValues.last! - signalLine
            let histPrev = macdValues[macdValues.count - 2] - signalLine
            score += histCurr > histPrev ? 10 : -10
        }

        score += current > ema26 ? 15 : -15
        return SignalResult(name: "MACD", category: "Trend", score: clamp(score), reasons: reasons)
    }

    // MARK: Trend Consistency
    private static func trendConsistencySignal(closes: [Double], horizon: Horizon = .shortTerm) -> SignalResult {
        let lookback = min(closes.count, horizon == .longTerm ? 52 : (horizon == .mediumTerm ? 30 : 21))
        guard closes.count >= lookback else { return SignalResult(name: "Trend", category: "Trend", score: 0, reasons: []) }
        let recent = Array(closes.suffix(lookback))
        var up = 0, down = 0
        for i in 1..<recent.count { recent[i] > recent[i-1] ? (up += 1) : (down += 1) }
        let total = up + down
        guard total > 0 else { return SignalResult(name: "Trend", category: "Trend", score: 0, reasons: []) }
        let upRatio = Double(up) / Double(total)
        let label = horizon.trendLabel
        var score: Double = 0; var reasons: [String] = []
        if upRatio > 0.7 {
            score = 50; reasons.append(String(format: "\(label) uptrend: %.0f%% of periods closed higher", upRatio * 100))
        } else if upRatio > 0.55 { score = 20 }
        else if upRatio < 0.3 {
            score = -50; reasons.append(String(format: "\(label) downtrend: %.0f%% of periods closed lower", (1-upRatio)*100))
        }         else if upRatio < 0.45 { score = -20 }
        return SignalResult(name: "Trend", category: "Trend", score: clamp(score), reasons: reasons)
    }

    // MARK: ADX (Average Directional Index)
    private static func adxSignal(closes: [Double], highs: [Double], lows: [Double], horizon: Horizon = .shortTerm) -> SignalResult {
        let period = horizon == .longTerm ? 28 : (horizon == .mediumTerm ? 21 : 14)
        let count = min(closes.count, min(highs.count, lows.count))
        guard count >= period + 1 else { return SignalResult(name: "ADX", category: "Trend", score: 0, reasons: []) }

        var plusDM: [Double] = [], minusDM: [Double] = [], tr: [Double] = []
        for i in 1..<count {
            let upMove = highs[i] - highs[i-1]
            let downMove = lows[i-1] - lows[i]
            plusDM.append(upMove > downMove && upMove > 0 ? upMove : 0)
            minusDM.append(downMove > upMove && downMove > 0 ? downMove : 0)
            let hl = highs[i] - lows[i]
            let hc = abs(highs[i] - closes[i-1])
            let lc = abs(lows[i] - closes[i-1])
            tr.append(max(hl, max(hc, lc)))
        }

        guard plusDM.count >= period else { return SignalResult(name: "ADX", category: "Trend", score: 0, reasons: []) }
        let smoothTR  = ema(tr, period: period)
        let smoothPDM = ema(plusDM, period: period)
        let smoothMDM = ema(minusDM, period: period)
        guard smoothTR > 0 else { return SignalResult(name: "ADX", category: "Trend", score: 0, reasons: []) }

        let plusDI  = (smoothPDM / smoothTR) * 100
        let minusDI = (smoothMDM / smoothTR) * 100
        let diSum = plusDI + minusDI
        let dx = diSum > 0 ? abs(plusDI - minusDI) / diSum * 100 : 0

        // Approximate ADX as smoothed DX (single-pass EMA)
        var dxValues: [Double] = []
        for i in max(0, plusDM.count - period * 2)..<plusDM.count {
            let sliceTR = ema(Array(tr.prefix(i+1)), period: period)
            guard sliceTR > 0 else { continue }
            let pdi = (ema(Array(plusDM.prefix(i+1)), period: period) / sliceTR) * 100
            let mdi = (ema(Array(minusDM.prefix(i+1)), period: period) / sliceTR) * 100
            let s = pdi + mdi
            dxValues.append(s > 0 ? abs(pdi - mdi) / s * 100 : 0)
        }
        let adx = dxValues.count >= period ? ema(dxValues, period: period) : dx

        var score: Double = 0; var reasons: [String] = []

        if adx > 25 {
            // Strong trend
            if plusDI > minusDI {
                score = min(80, adx * 1.5)
                reasons.append(String(format: "ADX %.0f — strong %@ bullish trend", adx, horizon.trendLabel.lowercased()))
            } else {
                score = -min(80, adx * 1.5)
                reasons.append(String(format: "ADX %.0f — strong %@ bearish trend", adx, horizon.trendLabel.lowercased()))
            }
        } else if adx < 15 {
            score = 0
            reasons.append(String(format: "ADX %.0f — no clear trend", adx))
        } else {
            score = plusDI > minusDI ? 15 : -15
        }

        return SignalResult(name: "ADX", category: "Trend", score: clamp(score), reasons: reasons)
    }

    // MARK: Parabolic SAR
    private static func parabolicSARSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        let count = min(closes.count, min(highs.count, lows.count))
        guard count >= 10 else { return SignalResult(name: "SAR", category: "Trend", score: 0, reasons: []) }

        var isLong = closes[1] > closes[0]
        var sar = isLong ? lows[0] : highs[0]
        var ep = isLong ? highs[0] : lows[0]
        var af: Double = 0.02
        let afStep = 0.02, afMax = 0.20

        for i in 1..<count {
            sar = sar + af * (ep - sar)
            if isLong {
                if lows[i] < sar {
                    isLong = false; sar = ep; ep = lows[i]; af = afStep
                } else {
                    if highs[i] > ep { ep = highs[i]; af = min(af + afStep, afMax) }
                }
            } else {
                if highs[i] > sar {
                    isLong = true; sar = ep; ep = highs[i]; af = afStep
                } else {
                    if lows[i] < ep { ep = lows[i]; af = min(af + afStep, afMax) }
                }
            }
        }

        let current = closes.last ?? 0
        var score: Double = 0; var reasons: [String] = []
        if isLong && current > sar {
            score = 45; reasons.append("Parabolic SAR bullish — price above SAR")
        } else if !isLong && current < sar {
            score = -45; reasons.append("Parabolic SAR bearish — price below SAR")
        }
        return SignalResult(name: "SAR", category: "Trend", score: clamp(score), reasons: reasons)
    }

    // MARK: Ichimoku Cloud
    private static func ichimokuSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        let count = min(closes.count, min(highs.count, lows.count))
        guard count >= 52 else { return SignalResult(name: "Ichimoku", category: "Trend", score: 0, reasons: []) }

        func midpoint(_ h: [Double], _ l: [Double], period: Int) -> Double {
            return ((h.suffix(period).max() ?? 0) + (l.suffix(period).min() ?? 0)) / 2.0
        }

        let tenkan  = midpoint(highs, lows, period: 9)
        let kijun   = midpoint(highs, lows, period: 26)
        let senkouA = (tenkan + kijun) / 2.0
        let senkouB = midpoint(highs, lows, period: 52)
        let current = closes.last ?? 0

        var score: Double = 0; var reasons: [String] = []

        // Price vs Cloud
        let cloudTop = max(senkouA, senkouB)
        let cloudBottom = min(senkouA, senkouB)

        if current > cloudTop {
            score += 35; reasons.append("Price above Ichimoku cloud — bullish")
        } else if current < cloudBottom {
            score -= 35; reasons.append("Price below Ichimoku cloud — bearish")
        } else {
            reasons.append("Price inside Ichimoku cloud — indecisive")
        }

        // Tenkan/Kijun cross
        if tenkan > kijun { score += 20 } else { score -= 20 }

        // Cloud color (future sentiment)
        if senkouA > senkouB { score += 10 } else { score -= 10 }

        return SignalResult(name: "Ichimoku", category: "Trend", score: clamp(score), reasons: reasons)
    }

    // ================================================================
    // MARK: - MOMENTUM / OSCILLATORS
    // ================================================================

    // MARK: RSI Signal
    private static func rsiSignal(closes: [Double], horizon: Horizon = .shortTerm) -> SignalResult {
        let rsi = calculateRSI(closes: closes, period: horizon.rsiPeriod)
        var score: Double = 0; var reasons: [String] = []
        if rsi < 30 {
            score = 60 + (30 - rsi)
            reasons.append(String(format: "RSI %.0f — oversold, potential bounce", rsi))
        } else if rsi > 70 {
            score = -60 - (rsi - 70)
            reasons.append(String(format: "RSI %.0f — overbought, may pull back", rsi))
        } else {
            score = (rsi - 50) * 1.5
        }
        return SignalResult(name: "RSI", category: "Momentum", score: clamp(score), reasons: reasons)
    }

    // MARK: Momentum / ROC Signal
    private static func momentumSignal(closes: [Double], horizon: Horizon = .shortTerm) -> SignalResult {
        let (p1, p2, p3) = horizon == .longTerm ? (10, 26, 52)
                         : (horizon == .mediumTerm ? (5, 15, 30) : (5, 10, 20))
        guard closes.count >= p2 else { return SignalResult(name: "Momentum", category: "Momentum", score: 0, reasons: []) }
        let c = closes.last ?? 0
        let roc1 = closes.count >= p1 ? (c - closes[closes.count-p1]) / closes[closes.count-p1] * 100 : 0
        let roc2 = closes.count >= p2 ? (c - closes[closes.count-p2]) / closes[closes.count-p2] * 100 : 0
        let roc3 = closes.count >= p3 ? (c - closes[closes.count-p3]) / closes[closes.count-p3] * 100 : 0
        let label = horizon.trendLabel.lowercased()

        var score: Double = 0; var reasons: [String] = []
        if roc1 > 0 && roc1 > roc2/2 { score += 30 } else if roc1 < 0 && roc1 < roc2/2 { score -= 30 }
        if roc2 > 5 { score += 25; reasons.append(String(format: "Strong %@ upward momentum (%.1f%% over %d periods)", label, roc2, p2)) }
        else if roc2 < -5 { score -= 25; reasons.append(String(format: "%@ downward momentum (%.1f%% over %d periods)", horizon.trendLabel, roc2, p2)) }
        if roc3 > 0 && roc2 > 0 && roc1 > 0 { score += 15 }
        else if roc3 < 0 && roc2 < 0 && roc1 < 0 { score -= 15 }
        return SignalResult(name: "Momentum", category: "Momentum", score: clamp(score), reasons: reasons)
    }

    // MARK: Stochastic Oscillator
    private static func stochasticSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        let period = 14
        guard closes.count >= period, highs.count >= period, lows.count >= period else {
            return SignalResult(name: "Stochastic", category: "Momentum", score: 0, reasons: [])
        }
        let hh = Array(highs.suffix(period)).max() ?? 0
        let ll = Array(lows.suffix(period)).min() ?? 0
        let c = closes.last ?? 0
        let range = hh - ll
        let k = range > 0 ? ((c - ll) / range) * 100 : 50

        var score: Double = 0; var reasons: [String] = []
        if k < 20 { score = 55; reasons.append(String(format: "Stochastic %%K %.0f — oversold", k)) }
        else if k > 80 { score = -55; reasons.append(String(format: "Stochastic %%K %.0f — overbought", k)) }
        else { score = (k - 50) * 0.5 }
        return SignalResult(name: "Stochastic", category: "Momentum", score: clamp(score), reasons: reasons)
    }

    // MARK: CCI (Commodity Channel Index)
    private static func cciSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        let period = 20
        let count = min(closes.count, min(highs.count, lows.count))
        guard count >= period else { return SignalResult(name: "CCI", category: "Momentum", score: 0, reasons: []) }

        // Typical price
        var tp: [Double] = []
        for i in 0..<count { tp.append((highs[i] + lows[i] + closes[i]) / 3.0) }

        let tpSlice = Array(tp.suffix(period))
        let tpMean = tpSlice.reduce(0, +) / Double(period)
        let meanDev = tpSlice.reduce(0.0) { $0 + abs($1 - tpMean) } / Double(period)

        let cci = meanDev > 0 ? (tp.last! - tpMean) / (0.015 * meanDev) : 0

        var score: Double = 0; var reasons: [String] = []
        if cci > 200 { score = -60; reasons.append(String(format: "CCI %.0f — extremely overbought", cci)) }
        else if cci > 100 { score = -35; reasons.append(String(format: "CCI %.0f — overbought", cci)) }
        else if cci < -200 { score = 60; reasons.append(String(format: "CCI %.0f — extremely oversold", cci)) }
        else if cci < -100 { score = 35; reasons.append(String(format: "CCI %.0f — oversold", cci)) }
        else { score = -cci * 0.2 } // Mild mean-reversion
        return SignalResult(name: "CCI", category: "Momentum", score: clamp(score), reasons: reasons)
    }

    // MARK: Williams %R
    private static func williamsRSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        let period = 14
        guard closes.count >= period, highs.count >= period, lows.count >= period else {
            return SignalResult(name: "Williams %R", category: "Momentum", score: 0, reasons: [])
        }
        let hh = Array(highs.suffix(period)).max() ?? 0
        let ll = Array(lows.suffix(period)).min() ?? 0
        let c = closes.last ?? 0
        let range = hh - ll
        let wr = range > 0 ? ((hh - c) / range) * -100 : -50

        var score: Double = 0; var reasons: [String] = []
        if wr < -80 { score = 50; reasons.append(String(format: "Williams %%R %.0f — oversold", wr)) }
        else if wr > -20 { score = -50; reasons.append(String(format: "Williams %%R %.0f — overbought", wr)) }
        else { score = (wr + 50) * 0.6 }
        return SignalResult(name: "Williams %R", category: "Momentum", score: clamp(score), reasons: reasons)
    }

    // ================================================================
    // MARK: - VOLATILITY INDICATORS
    // ================================================================

    // MARK: Bollinger Bands
    private static func bollingerBandSignal(closes: [Double], horizon: Horizon = .shortTerm) -> SignalResult {
        let period = horizon.bollingerPeriod
        guard closes.count >= period else { return SignalResult(name: "Bollinger", category: "Volatility", score: 0, reasons: []) }
        let current = closes.last ?? 0
        let middle = sma(closes, period: period)
        let recentCloses = Array(closes.suffix(period))
        let variance = recentCloses.reduce(0.0) { $0 + ($1 - middle) * ($1 - middle) } / Double(period)
        let stdDev = sqrt(variance)
        let upper = middle + 2.0 * stdDev
        let lower = middle - 2.0 * stdDev
        let bw = upper - lower

        var score: Double = 0; var reasons: [String] = []
        let pctB = bw > 0 ? (current - lower) / bw : 0.5
        if pctB < 0.1 { score = 60; reasons.append("Price near lower Bollinger Band — potential reversal up") }
        else if pctB < 0.2 { score = 35 }
        else if pctB > 0.9 { score = -60; reasons.append("Price near upper Bollinger Band — potential pullback") }
        else if pctB > 0.8 { score = -35 }
        else { score = (pctB - 0.5) * -20 }

        if middle > 0 && bw / middle < 0.04 {
            reasons.append("Bollinger squeeze — low volatility, breakout likely")
        }
        return SignalResult(name: "Bollinger", category: "Volatility", score: clamp(score), reasons: reasons)
    }

    // MARK: ATR Volatility
    private static func volatilitySignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        let period = 14
        let count = min(closes.count, min(highs.count, lows.count))
        guard count >= period + 1 else { return SignalResult(name: "ATR", category: "Volatility", score: 0, reasons: []) }

        let atrVal = atr(closes: closes, highs: highs, lows: lows, period: period)
        let current = closes.last ?? 0
        guard current > 0 else { return SignalResult(name: "ATR", category: "Volatility", score: 0, reasons: []) }
        let atrPct = (atrVal / current) * 100

        var score: Double = 0; var reasons: [String] = []
        if atrPct > 5 { score = -20; reasons.append(String(format: "High volatility (ATR %.1f%%)", atrPct)) }
        else if atrPct < 1.5 { score = 10; reasons.append(String(format: "Low volatility (ATR %.1f%%) — consolidating", atrPct)) }
        return SignalResult(name: "ATR", category: "Volatility", score: clamp(score), reasons: reasons)
    }

    // MARK: Keltner Channels
    private static func keltnerChannelSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        let period = 20
        let count = min(closes.count, min(highs.count, lows.count))
        guard count >= period + 1 else { return SignalResult(name: "Keltner", category: "Volatility", score: 0, reasons: []) }

        let middle = ema(closes, period: period)
        let atrVal = atr(closes: closes, highs: highs, lows: lows, period: 10)
        let upper = middle + 2.0 * atrVal
        let lower = middle - 2.0 * atrVal
        let current = closes.last ?? 0

        var score: Double = 0; var reasons: [String] = []
        if current > upper {
            score = -40; reasons.append("Price above upper Keltner Channel — extended")
        } else if current < lower {
            score = 40; reasons.append("Price below lower Keltner Channel — oversold")
        } else {
            let range = upper - lower
            if range > 0 {
                let pos = (current - lower) / range
                score = (pos - 0.5) * -30
            }
        }
        return SignalResult(name: "Keltner", category: "Volatility", score: clamp(score), reasons: reasons)
    }

    // ================================================================
    // MARK: - VOLUME INDICATORS
    // ================================================================

    // MARK: Volume Signal (basic)
    private static func volumeSignal(volumes: [Int], closes: [Double]) -> SignalResult {
        guard volumes.count >= 10, closes.count >= 10 else { return SignalResult(name: "Volume", category: "Volume", score: 0, reasons: []) }
        let recentVol = Double(volumes.suffix(5).reduce(0, +)) / 5.0
        let avgVol = Double(volumes.suffix(20).reduce(0, +)) / min(Double(volumes.count), 20.0)
        let priceUp = (closes.last ?? 0) > (closes.dropLast().last ?? 0)

        var score: Double = 0; var reasons: [String] = []
        if recentVol > avgVol * 1.5 {
            if priceUp { score = 50; reasons.append("High volume on price increase — buying interest") }
            else { score = -50; reasons.append("High volume on decline — selling pressure") }
        } else if recentVol > avgVol * 1.2 { score = priceUp ? 25 : -25 }
        else if recentVol < avgVol * 0.5 { reasons.append("Low volume — weak conviction") }
        return SignalResult(name: "Volume", category: "Volume", score: clamp(score), reasons: reasons)
    }

    // MARK: OBV (On-Balance Volume)
    private static func obvSignal(volumes: [Int], closes: [Double]) -> SignalResult {
        guard volumes.count >= 20, closes.count >= 20 else { return SignalResult(name: "OBV", category: "Volume", score: 0, reasons: []) }
        let count = min(volumes.count, closes.count)
        var obv: [Double] = [0]
        for i in 1..<count {
            if closes[i] > closes[i-1] { obv.append(obv.last! + Double(volumes[i])) }
            else if closes[i] < closes[i-1] { obv.append(obv.last! - Double(volumes[i])) }
            else { obv.append(obv.last!) }
        }

        // OBV trend: compare recent OBV slope to price slope
        let obvRecent = Array(obv.suffix(10))
        let priceRecent = Array(closes.suffix(10))
        let obvTrend = (obvRecent.last ?? 0) - (obvRecent.first ?? 0)
        let priceTrend = (priceRecent.last ?? 0) - (priceRecent.first ?? 0)

        var score: Double = 0; var reasons: [String] = []
        if obvTrend > 0 && priceTrend > 0 {
            score = 40; reasons.append("OBV confirms uptrend — accumulation")
        } else if obvTrend < 0 && priceTrend < 0 {
            score = -40; reasons.append("OBV confirms downtrend — distribution")
        } else if obvTrend > 0 && priceTrend <= 0 {
            score = 30; reasons.append("OBV divergence — hidden buying (bullish)")
        } else if obvTrend < 0 && priceTrend >= 0 {
            score = -30; reasons.append("OBV divergence — hidden selling (bearish)")
        }
        return SignalResult(name: "OBV", category: "Volume", score: clamp(score), reasons: reasons)
    }

    // MARK: VWAP (Volume Weighted Average Price)
    private static func vwapSignal(closes: [Double], highs: [Double], lows: [Double], volumes: [Int]) -> SignalResult {
        let count = min(closes.count, min(highs.count, min(lows.count, volumes.count)))
        guard count >= 10 else { return SignalResult(name: "VWAP", category: "Volume", score: 0, reasons: []) }

        var cumTPV: Double = 0, cumVol: Double = 0
        for i in 0..<count {
            let tp = (highs[i] + lows[i] + closes[i]) / 3.0
            cumTPV += tp * Double(volumes[i])
            cumVol += Double(volumes[i])
        }
        let vwap = cumVol > 0 ? cumTPV / cumVol : 0
        let current = closes.last ?? 0

        var score: Double = 0; var reasons: [String] = []
        if current > vwap * 1.02 {
            score = 30; reasons.append("Price above VWAP — bullish institutional sentiment")
        } else if current < vwap * 0.98 {
            score = -30; reasons.append("Price below VWAP — bearish institutional sentiment")
        } else {
            score = vwap > 0 ? ((current - vwap) / vwap) * 500 : 0
        }
        return SignalResult(name: "VWAP", category: "Volume", score: clamp(score), reasons: reasons)
    }

    // MARK: CMF (Chaikin Money Flow)
    private static func cmfSignal(closes: [Double], highs: [Double], lows: [Double], volumes: [Int]) -> SignalResult {
        let period = 20
        let count = min(closes.count, min(highs.count, min(lows.count, volumes.count)))
        guard count >= period else { return SignalResult(name: "CMF", category: "Volume", score: 0, reasons: []) }

        var mfvSum: Double = 0, volSum: Double = 0
        for i in (count - period)..<count {
            let hl = highs[i] - lows[i]
            let mfm = hl > 0 ? ((closes[i] - lows[i]) - (highs[i] - closes[i])) / hl : 0
            mfvSum += mfm * Double(volumes[i])
            volSum += Double(volumes[i])
        }
        let cmf = volSum > 0 ? mfvSum / volSum : 0

        var score: Double = 0; var reasons: [String] = []
        if cmf > 0.15 { score = 50; reasons.append(String(format: "Strong buying pressure (CMF %.2f)", cmf)) }
        else if cmf > 0.05 { score = 25 }
        else if cmf < -0.15 { score = -50; reasons.append(String(format: "Strong selling pressure (CMF %.2f)", cmf)) }
        else if cmf < -0.05 { score = -25 }
        else { score = cmf * 150 }
        return SignalResult(name: "CMF", category: "Volume", score: clamp(score), reasons: reasons)
    }

    // MARK: MFI (Money Flow Index)
    private static func mfiSignal(closes: [Double], highs: [Double], lows: [Double], volumes: [Int]) -> SignalResult {
        let period = 14
        let count = min(closes.count, min(highs.count, min(lows.count, volumes.count)))
        guard count >= period + 1 else { return SignalResult(name: "MFI", category: "Volume", score: 0, reasons: []) }

        var posFlow: Double = 0, negFlow: Double = 0
        for i in (count - period)..<count {
            let tp = (highs[i] + lows[i] + closes[i]) / 3.0
            let prevTP = i > 0 ? (highs[i-1] + lows[i-1] + closes[i-1]) / 3.0 : tp
            let rawMF = tp * Double(volumes[i])
            if tp > prevTP { posFlow += rawMF } else { negFlow += rawMF }
        }
        let mfi = negFlow > 0 ? 100 - (100 / (1 + posFlow / negFlow)) : 100

        var score: Double = 0; var reasons: [String] = []
        if mfi < 20 { score = 55; reasons.append(String(format: "MFI %.0f — oversold (volume-weighted)", mfi)) }
        else if mfi > 80 { score = -55; reasons.append(String(format: "MFI %.0f — overbought (volume-weighted)", mfi)) }
        else { score = (mfi - 50) * 0.8 }
        return SignalResult(name: "MFI", category: "Volume", score: clamp(score), reasons: reasons)
    }

    // ================================================================
    // MARK: - SUPPORT / RESISTANCE
    // ================================================================

    // MARK: Support & Resistance
    private static func supportResistanceSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        guard closes.count >= 20 else { return SignalResult(name: "S/R Levels", category: "Support/Resistance", score: 0, reasons: []) }
        let current = closes.last ?? 0
        let lookback = min(closes.count, 60)
        let rHighs = Array(highs.suffix(lookback))
        let rLows = Array(lows.suffix(lookback))
        let resistance = rHighs.sorted().suffix(5).reduce(0, +) / 5.0
        let support = rLows.sorted().prefix(5).reduce(0, +) / 5.0
        let range = resistance - support
        guard range > 0 else { return SignalResult(name: "S/R Levels", category: "Support/Resistance", score: 0, reasons: []) }

        var score: Double = 0; var reasons: [String] = []
        let pos = (current - support) / range

        if current > resistance { score = 50; reasons = [String(format: "Breakout above resistance $%.2f", resistance)] }
        else if current < support { score = -50; reasons = [String(format: "Breakdown below support $%.2f", support)] }
        else if pos < 0.2 { score = 40; reasons.append(String(format: "Near support at $%.2f", support)) }
        else if pos > 0.8 { score = -30; reasons.append(String(format: "Near resistance at $%.2f", resistance)) }
        return SignalResult(name: "S/R Levels", category: "Support/Resistance", score: clamp(score), reasons: reasons)
    }

    // MARK: Pivot Points (Classic)
    private static func pivotPointSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        guard closes.count >= 2, highs.count >= 2, lows.count >= 2 else {
            return SignalResult(name: "Pivot Points", category: "Support/Resistance", score: 0, reasons: [])
        }
        // Use the previous period's data
        let prevClose = closes[closes.count - 2]
        let prevHigh = highs[highs.count - 2]
        let prevLow = lows[lows.count - 2]

        let pivot = (prevHigh + prevLow + prevClose) / 3.0
        let r1 = 2.0 * pivot - prevLow
        let s1 = 2.0 * pivot - prevHigh
        let r2 = pivot + (prevHigh - prevLow)
        let s2 = pivot - (prevHigh - prevLow)
        let current = closes.last ?? 0

        var score: Double = 0; var reasons: [String] = []
        if current > r2 { score = 50; reasons.append(String(format: "Price above R2 pivot ($%.2f) — very bullish", r2)) }
        else if current > r1 { score = 30; reasons.append(String(format: "Price above R1 pivot ($%.2f)", r1)) }
        else if current > pivot { score = 15 }
        else if current < s2 { score = -50; reasons.append(String(format: "Price below S2 pivot ($%.2f) — very bearish", s2)) }
        else if current < s1 { score = -30; reasons.append(String(format: "Price below S1 pivot ($%.2f)", s1)) }
        else if current < pivot { score = -15 }
        return SignalResult(name: "Pivot Points", category: "Support/Resistance", score: clamp(score), reasons: reasons)
    }

    // MARK: Fibonacci Retracement
    private static func fibonacciSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        let lookback = min(closes.count, 120)
        guard lookback >= 20 else { return SignalResult(name: "Fibonacci", category: "Support/Resistance", score: 0, reasons: []) }
        let rHighs = Array(highs.suffix(lookback))
        let rLows = Array(lows.suffix(lookback))
        let swingHigh = rHighs.max() ?? 0
        let swingLow = rLows.min() ?? 0
        let range = swingHigh - swingLow
        guard range > 0 else { return SignalResult(name: "Fibonacci", category: "Support/Resistance", score: 0, reasons: []) }

        let current = closes.last ?? 0
        let retracement = (swingHigh - current) / range

        // Fibonacci levels: 0.236, 0.382, 0.500, 0.618, 0.786
        var score: Double = 0; var reasons: [String] = []
        let tolerance = 0.03

        if abs(retracement - 0.618) < tolerance {
            score = 40; reasons.append("Price at 61.8% Fibonacci retracement — key support")
        } else if abs(retracement - 0.5) < tolerance {
            score = 30; reasons.append("Price at 50% Fibonacci retracement")
        } else if abs(retracement - 0.382) < tolerance {
            score = 20; reasons.append("Price at 38.2% Fibonacci retracement")
        } else if retracement < 0.236 {
            score = -20; reasons.append("Price near swing high — limited upside to Fib levels")
        } else if retracement > 0.786 {
            score = 25; reasons.append("Price near swing low — deep retracement, potential reversal")
        }
        return SignalResult(name: "Fibonacci", category: "Support/Resistance", score: clamp(score), reasons: reasons)
    }

    // MARK: Price Action (Higher Highs / Lower Lows)
    private static func priceActionSignal(closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        guard highs.count >= 10, lows.count >= 10 else { return SignalResult(name: "Price Action", category: "Support/Resistance", score: 0, reasons: []) }
        let recent = 10
        let rh = Array(highs.suffix(recent))
        let rl = Array(lows.suffix(recent))

        // Count higher highs and higher lows
        var hh = 0, hl = 0, lh = 0, ll = 0
        for i in 1..<recent {
            if rh[i] > rh[i-1] { hh += 1 } else if rh[i] < rh[i-1] { lh += 1 }
            if rl[i] > rl[i-1] { hl += 1 } else if rl[i] < rl[i-1] { ll += 1 }
        }

        var score: Double = 0; var reasons: [String] = []
        if hh >= 6 && hl >= 6 {
            score = 55; reasons.append("Strong uptrend: consistent higher highs & higher lows")
        } else if hh >= 4 && hl >= 4 {
            score = 30
        } else if lh >= 6 && ll >= 6 {
            score = -55; reasons.append("Strong downtrend: consistent lower highs & lower lows")
        } else if lh >= 4 && ll >= 4 {
            score = -30
        }
        return SignalResult(name: "Price Action", category: "Support/Resistance", score: clamp(score), reasons: reasons)
    }

    // ================================================================
    // MARK: - MEAN REVERSION
    // ================================================================

    // MARK: Z-Score Signal
    private static func zScoreSignal(closes: [Double]) -> SignalResult {
        let period = 50
        guard closes.count >= period else { return SignalResult(name: "Z-Score", category: "Mean Reversion", score: 0, reasons: []) }
        let slice = Array(closes.suffix(period))
        let mean = slice.reduce(0, +) / Double(period)
        let variance = slice.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(period)
        let stdDev = sqrt(variance)
        guard stdDev > 0 else { return SignalResult(name: "Z-Score", category: "Mean Reversion", score: 0, reasons: []) }

        let current = closes.last ?? 0
        let zScore = (current - mean) / stdDev

        var score: Double = 0; var reasons: [String] = []
        if zScore > 2.5 { score = -60; reasons.append(String(format: "Z-Score %.1f — extremely overextended", zScore)) }
        else if zScore > 1.5 { score = -35; reasons.append(String(format: "Z-Score %.1f — above mean, may revert", zScore)) }
        else if zScore < -2.5 { score = 60; reasons.append(String(format: "Z-Score %.1f — extremely undervalued vs mean", zScore)) }
        else if zScore < -1.5 { score = 35; reasons.append(String(format: "Z-Score %.1f — below mean, potential rebound", zScore)) }
        else { score = -zScore * 10 }
        return SignalResult(name: "Z-Score", category: "Mean Reversion", score: clamp(score), reasons: reasons)
    }

    // MARK: RSI Divergence
    private static func rsiDivergenceSignal(closes: [Double]) -> SignalResult {
        guard closes.count >= 30 else { return SignalResult(name: "RSI Divergence", category: "Mean Reversion", score: 0, reasons: []) }

        // Compare RSI trend to price trend over last 14 periods
        let rsiNow = calculateRSI(closes: closes, period: 14)
        let rsiPrev = calculateRSI(closes: Array(closes.dropLast(7)), period: 14)
        let priceNow = closes.last ?? 0
        let pricePrev = closes[closes.count - 8]

        var score: Double = 0; var reasons: [String] = []

        // Bullish divergence: price making lower lows but RSI making higher lows
        if priceNow < pricePrev && rsiNow > rsiPrev {
            score = 45; reasons.append("Bullish RSI divergence — momentum turning up")
        }
        // Bearish divergence: price making higher highs but RSI making lower highs
        else if priceNow > pricePrev && rsiNow < rsiPrev {
            score = -45; reasons.append("Bearish RSI divergence — momentum weakening")
        }
        return SignalResult(name: "RSI Divergence", category: "Mean Reversion", score: clamp(score), reasons: reasons)
    }

    // ================================================================
    // MARK: - CANDLESTICK / PATTERN SIGNALS
    // ================================================================

    // MARK: Candlestick Patterns (Doji, Hammer, Engulfing)
    private static func candlestickSignal(opens: [Double], closes: [Double], highs: [Double], lows: [Double]) -> SignalResult {
        let count = min(opens.count, min(closes.count, min(highs.count, lows.count)))
        guard count >= 3 else { return SignalResult(name: "Candlestick", category: "Candlestick", score: 0, reasons: []) }
        let i = count - 1 // Latest candle
        let body = abs(closes[i] - opens[i])
        let range = highs[i] - lows[i]
        let upperWick = highs[i] - max(opens[i], closes[i])
        let lowerWick = min(opens[i], closes[i]) - lows[i]
        let isBullish = closes[i] > opens[i]

        var score: Double = 0; var reasons: [String] = []

        // Doji: very small body relative to range
        if range > 0 && body / range < 0.1 {
            score = 0; reasons.append("Doji candle — indecision, possible reversal")
        }
        // Hammer: small body at top, long lower wick (bullish reversal)
        else if range > 0 && lowerWick > body * 2 && upperWick < body * 0.5 {
            score = 40; reasons.append("Hammer candle — bullish reversal signal")
        }
        // Inverted Hammer / Shooting Star
        else if range > 0 && upperWick > body * 2 && lowerWick < body * 0.5 {
            score = -40; reasons.append("Shooting star — bearish reversal signal")
        }

        // Bullish Engulfing
        if count >= 2 {
            let prevBody = abs(closes[i-1] - opens[i-1])
            let prevBearish = closes[i-1] < opens[i-1]
            if isBullish && prevBearish && body > prevBody * 1.2 &&
               closes[i] > opens[i-1] && opens[i] < closes[i-1] {
                score = 50; reasons.append("Bullish engulfing pattern — strong reversal")
            }
            // Bearish Engulfing
            let prevBullish = closes[i-1] > opens[i-1]
            if !isBullish && prevBullish && body > prevBody * 1.2 &&
               opens[i] > closes[i-1] && closes[i] < opens[i-1] {
                score = -50; reasons.append("Bearish engulfing pattern — strong reversal")
            }
        }

        return SignalResult(name: "Candlestick", category: "Candlestick", score: clamp(score), reasons: reasons)
    }

    // MARK: Gap Signal
    private static func gapSignal(opens: [Double], closes: [Double]) -> SignalResult {
        guard opens.count >= 2, closes.count >= 2 else { return SignalResult(name: "Gap", category: "Candlestick", score: 0, reasons: []) }
        let todayOpen = opens.last!
        let prevClose = closes[closes.count - 2]
        let gapPct = prevClose > 0 ? ((todayOpen - prevClose) / prevClose) * 100 : 0

        var score: Double = 0; var reasons: [String] = []
        if gapPct > 3 {
            score = 40; reasons.append(String(format: "Gap up %.1f%% — strong bullish opening", gapPct))
        } else if gapPct > 1 {
            score = 20
        } else if gapPct < -3 {
            score = -40; reasons.append(String(format: "Gap down %.1f%% — bearish opening", gapPct))
        } else if gapPct < -1 {
            score = -20
        }
        return SignalResult(name: "Gap", category: "Candlestick", score: clamp(score), reasons: reasons)
    }

    // ================================================================
    // MARK: - UTILITY FUNCTIONS
    // ================================================================

    private static func clamp(_ value: Double) -> Double {
        max(-100, min(100, value))
    }

    private static func sma(_ values: [Double], period: Int) -> Double {
        guard values.count >= period else { return values.last ?? 0 }
        return values.suffix(period).reduce(0, +) / Double(period)
    }

    private static func ema(_ values: [Double], period: Int) -> Double {
        guard !values.isEmpty else { return 0 }
        let k = 2.0 / Double(period + 1)
        var v = values.first!
        for i in 1..<values.count { v = values[i] * k + v * (1 - k) }
        return v
    }

    private static func atr(closes: [Double], highs: [Double], lows: [Double], period: Int) -> Double {
        let count = min(closes.count, min(highs.count, lows.count))
        guard count >= period + 1 else { return 0 }
        var trs: [Double] = []
        for i in 1..<count {
            let hl = highs[i] - lows[i]
            let hc = abs(highs[i] - closes[i-1])
            let lc = abs(lows[i] - closes[i-1])
            trs.append(max(hl, max(hc, lc)))
        }
        guard trs.count >= period else { return 0 }
        return trs.suffix(period).reduce(0, +) / Double(period)
    }

    private static func calculateRSI(closes: [Double], period: Int) -> Double {
        guard closes.count > period else { return 50 }
        var gains: [Double] = [], losses: [Double] = []
        for i in 1..<closes.count {
            let d = closes[i] - closes[i-1]
            gains.append(d >= 0 ? d : 0)
            losses.append(d < 0 ? abs(d) : 0)
        }
        guard gains.count >= period else { return 50 }
        var avgGain = gains.prefix(period).reduce(0, +) / Double(period)
        var avgLoss = losses.prefix(period).reduce(0, +) / Double(period)
        for i in period..<gains.count {
            avgGain = (avgGain * Double(period-1) + gains[i]) / Double(period)
            avgLoss = (avgLoss * Double(period-1) + losses[i]) / Double(period)
        }
        guard avgLoss > 0 else { return 100 }
        return 100 - (100 / (1 + avgGain / avgLoss))
    }
}
