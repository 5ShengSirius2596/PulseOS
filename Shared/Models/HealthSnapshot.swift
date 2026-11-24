import Foundation

public struct HRVPoint: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let sdnnMs: Double

    public init(id: UUID = UUID(), date: Date, sdnnMs: Double) {
        self.id = id
        self.date = date
        self.sdnnMs = sdnnMs
    }
}

public struct HourlyCaloriePoint: Codable, Identifiable, Sendable {
    public let id: Int // Hour 0...23
    public let restingKcal: Double
    public let activeKcal: Double

    public init(hour: Int, restingKcal: Double, activeKcal: Double) {
        self.id = hour
        self.restingKcal = restingKcal
        self.activeKcal = activeKcal
    }
}

public struct OvernightVitals: Codable, Sendable {
    public var sleepHours: Double
    public var sleepEfficiencyPct: Int
    public var deepMinutes: Int
    public var coreMinutes: Int
    public var remMinutes: Int
    public var awakeMinutes: Int
    public var sleepingHeartRate: Double?
    public var wristTempCelsius: Double?
    public var respiratoryRate: Double?
    public var bloodOxygenPct: Double?

    public var normalCount: Int {
        var count = 0
        if let hr = sleepingHeartRate, (42...85).contains(hr) { count += 1 }
        if let temp = wristTempCelsius, (34.5...37.3).contains(temp) { count += 1 }
        if let rr = respiratoryRate, (10...22).contains(rr) { count += 1 }
        if let spo2 = bloodOxygenPct, spo2 >= 94 { count += 1 }
        return count
    }

    public static let placeholder = OvernightVitals(
        sleepHours: 6.95,
        sleepEfficiencyPct: 96,
        deepMinutes: 75,
        coreMinutes: 234,
        remMinutes: 92,
        awakeMinutes: 16,
        sleepingHeartRate: 66,
        wristTempCelsius: 35.9,
        respiratoryRate: 16.4,
        bloodOxygenPct: 95
    )
}

/// Complete local health snapshot shared between iOS App, Watch App, and Watch WidgetKit Complications.
public struct HealthSnapshot: Codable, Sendable {
    public var updatedAt: Date

    // Core HRV & Computed State
    public var latestHRVMs: Double
    public var baselineMeanMs: Double
    public var baselineLnMu: Double
    public var baselineLnSigma: Double
    public var zScore: Double
    public var stateScore: Int        // 0...100
    public var readinessScore: Int    // 0...100
    public var stateLevel: BodyStateLevel
    public var intradayHRV: [HRVPoint]

    // Prominent Calorie Statistics (Resting + Active)
    public var restingKcal: Double
    public var activeKcal: Double
    public var activeGoalKcal: Double
    public var hourlyCalories: [HourlyCaloriePoint]

    // Grouped Overnight Vitals & Sleep
    public var overnight: OvernightVitals

    // Grouped Cardio & Metabolism
    public var restingHeartRate: Double?
    public var vo2Max: Double?
    public var bodyMassKg: Double?

    // Grouped Daytime Activity & Rhythm
    public var stepCount: Int
    public var stepGoal: Int
    public var exerciseMinutes: Int
    public var standHours: Int
    public var daylightMinutes: Int
    public var waterMl: Double
    public var waterGoalMl: Double

    public var totalKcal: Double { restingKcal + activeKcal }

    public var restingRatioPct: Int {
        guard totalKcal > 0 else { return 75 }
        return Int((restingKcal / totalKcal * 100).rounded())
    }

    public var activeRatioPct: Int { max(0, 100 - restingRatioPct) }

    public static let sample = HealthSnapshot(
        updatedAt: Date(),
        latestHRVMs: 42,
        baselineMeanMs: 41,
        baselineLnMu: log(41),
        baselineLnSigma: 0.24,
        zScore: 0.1,
        stateScore: 58,
        readinessScore: 72,
        stateLevel: .balanced,
        intradayHRV: (0..<12).map { idx in
            let date = Calendar.current.date(byAdding: .hour, value: -(11 - idx) * 2, to: Date()) ?? Date()
            let vals: [Double] = [44, 48, 52, 46, 39, 47, 45, 38, 41, 36, 40, 42]
            return HRVPoint(date: date, sdnnMs: vals[idx])
        },
        restingKcal: 1680,
        activeKcal: 545,
        activeGoalKcal: 700,
        hourlyCalories: (0..<24).map { h in
            let spikes: [Double] = [0,0,0,0,0,0,0,8,18,22,12,16,38,15,10,20,24,62,88,120,64,28,0,0]
            return HourlyCaloriePoint(hour: h, restingKcal: 70, activeKcal: spikes[h])
        },
        overnight: .placeholder,
        restingHeartRate: 70,
        vo2Max: 38.2,
        bodyMassKg: 77.4,
        stepCount: 9874,
        stepGoal: 12000,
        exerciseMinutes: 16,
        standHours: 14,
        daylightMinutes: 4,
        waterMl: 1250,
        waterGoalMl: 2200
    )
}
