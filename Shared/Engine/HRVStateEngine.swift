import Foundation

/// Pure local physiological scoring engine using personal 30-day log-transformed HRV (lnSDNN) baseline.
public enum HRVStateEngine {
    public struct EvaluationResult: Sendable {
        public let baselineMeanMs: Double
        public let lnMu: Double
        public let lnSigma: Double
        public let zScore: Double
        public let stateScore: Int
        public let readinessScore: Int
        public let stateLevel: BodyStateLevel
    }

    /// Evaluates current HRV against the user's 30-day history (falls back to prior when < 7 samples).
    public static func evaluate(
        latestHRVMs: Double,
        history30DaysMs: [Double],
        overnight: OvernightVitals,
        restingHR: Double?
    ) -> EvaluationResult {
        let validHistory = history30DaysMs.filter { $0 >= 8 && $0 <= 250 }
        let lnMu: Double
        let lnSigma: Double
        let baselineMeanMs: Double

        if validHistory.count >= 7 {
            let logs = validHistory.map { log($0) }
            let mu = logs.reduce(0, +) / Double(logs.count)
            let variance = logs.reduce(0) { $0 + pow($1 - mu, 2) } / Double(logs.count)
            lnMu = mu
            lnSigma = max(0.15, sqrt(variance))
            baselineMeanMs = exp(mu)
        } else {
            // Cold-start prior until 7+ personal samples accumulate
            lnMu = log(42.0)
            lnSigma = 0.25
            baselineMeanMs = 42.0
        }

        let clampedLatest = max(8.0, min(250.0, latestHRVMs))
        let z = (log(clampedLatest) - lnMu) / lnSigma

        // Map Z-score to 5 physiological tiers
        var level: BodyStateLevel
        if z < -1.2 {
            level = .highStress
        } else if z < -0.5 {
            level = .mildStress
        } else if z <= 0.5 {
            level = .balanced
        } else if z <= 1.2 {
            level = .relaxed
        } else {
            level = .peak
        }

        // Downgrade one tier if sleeping wrist temp is markedly elevated (>= 37.3°C) or SpO2 is low (< 93%)
        let vitalsWarning = (overnight.wristTempCelsius ?? 36.0) >= 37.3 || (overnight.bloodOxygenPct ?? 97.0) < 93.0
        if vitalsWarning, level.rawValue > 0, let downgraded = BodyStateLevel(rawValue: level.rawValue - 1) {
            level = downgraded
        }

        let stateScore = Int(max(5, min(100, (55.0 + z * 24.0).rounded())))

        // Composite Morning Readiness: HRV (45%) + Sleep Efficiency (25%) + Overnight Vitals (30%)
        let sleepComponent = Double(min(100, max(30, overnight.sleepEfficiencyPct))) * 0.25
        let hrvComponent = Double(stateScore) * 0.45
        let vitalsComponent = (Double(overnight.normalCount) / 4.0) * 100.0 * 0.30
        let hrPenalty = (restingHR ?? 65) > 85 ? 8.0 : 0.0
        let readiness = Int(max(20, min(100, (hrvComponent + sleepComponent + vitalsComponent - hrPenalty).rounded())))

        return EvaluationResult(
            baselineMeanMs: baselineMeanMs,
            lnMu: lnMu,
            lnSigma: lnSigma,
            zScore: z,
            stateScore: stateScore,
            readinessScore: readiness,
            stateLevel: level
        )
    }
}
