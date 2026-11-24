import Foundation
import HealthKit
import WidgetKit

/// Unified HealthKit reader & background observer for both iOS and watchOS.
@MainActor
public final class HealthKitManager: ObservableObject {
    public static let shared = HealthKitManager()

    private let store = HKHealthStore()
    @Published public var snapshot: HealthSnapshot = SharedStore.shared.loadSnapshot()
    @Published public var isAuthorized = false
    @Published public var isLoading = false

    private var observerStarted = false

    private init() {}

    public var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .basalEnergyBurned,
            .activeEnergyBurned,
            .restingHeartRate,
            .heartRate,
            .appleSleepingWristTemperature,
            .respiratoryRate,
            .oxygenSaturation,
            .vo2Max,
            .bodyMass,
            .stepCount,
            .appleExerciseTime,
            .timeInDaylight,
            .dietaryWater
        ]
        for id in quantityIDs {
            if let t = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(t)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let stand = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
            types.insert(stand)
        }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        guard let water = HKObjectType.quantityType(forIdentifier: .dietaryWater) else { return [] }
        return [water]
    }

    public func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            startHRVBackgroundObserver()
            await refreshAll()
        } catch {
            print("[PulseOS] HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    /// Registers watchOS/iOS background observer for HRV so complications auto-refresh when new samples arrive.
    public func startHRVBackgroundObserver() {
        guard isAvailable, !observerStarted,
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        observerStarted = true

        let query = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error {
                print("[PulseOS] Observer error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            Task { @MainActor in
                await self?.refreshAll()
                completionHandler()
            }
        }
        store.execute(query)

        store.enableBackgroundDelivery(for: hrvType, frequency: .hourly) { success, error in
            if let error {
                print("[PulseOS] enableBackgroundDelivery error: \(error.localizedDescription)")
            } else if success {
                print("[PulseOS] HRV background delivery enabled")
            }
        }
    }

    /// Fetches all grouped health metrics, computes personal 30-day lnSDNN state, persists to App Group, and reloads Watch complications.
    public func refreshAll() async {
        guard isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        let now = Date()
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: startOfToday) ?? now
        let yesterdayEvening = cal.date(byAdding: .hour, value: -16, to: now) ?? startOfToday

        async let hrv30d = fetchQuantitySamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: thirtyDaysAgo, end: now)
        async let restingKcal = fetchCumulativeSum(.basalEnergyBurned, unit: .kilocalorie(), start: startOfToday, end: now)
        async let activeKcal = fetchCumulativeSum(.activeEnergyBurned, unit: .kilocalorie(), start: startOfToday, end: now)
        async let hourlyCal = fetchHourlyCalories(startOfToday: startOfToday, end: now)
        async let restingHR = fetchLatestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let wristTemp = fetchLatestQuantity(.appleSleepingWristTemperature, unit: .degreeCelsius())
        async let respRate = fetchLatestQuantity(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let spo2 = fetchLatestQuantity(.oxygenSaturation, unit: .percent())
        async let vo2 = fetchLatestQuantity(.vo2Max, unit: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())))
        async let weight = fetchLatestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        async let steps = fetchCumulativeSum(.stepCount, unit: .count(), start: startOfToday, end: now)
        async let exerciseMin = fetchCumulativeSum(.appleExerciseTime, unit: .minute(), start: startOfToday, end: now)
        async let daylightMin = fetchCumulativeSum(.timeInDaylight, unit: .minute(), start: startOfToday, end: now)
        async let waterMl = fetchCumulativeSum(.dietaryWater, unit: .literUnit(with: .milli), start: startOfToday, end: now)
        async let sleepData = fetchOvernightSleep(start: yesterdayEvening, end: now)

        let hrvSamples = await hrv30d
        let todayHRV = hrvSamples.filter { $0.date >= startOfToday }
        let latestHRV = hrvSamples.last?.sdnnMs ?? snapshot.latestHRVMs

        var overnight = await sleepData
        overnight.wristTempCelsius = await wristTemp
        overnight.respiratoryRate = await respRate
        if let rawSpO2 = await spo2 {
            overnight.bloodOxygenPct = (rawSpO2 * 100.0).rounded()
        }

        let rhr = await restingHR
        let eval = HRVStateEngine.evaluate(
            latestHRVMs: latestHRV,
            history30DaysMs: hrvSamples.map(\.sdnnMs),
            overnight: overnight,
            restingHR: rhr
        )

        let updated = HealthSnapshot(
            updatedAt: now,
            latestHRVMs: latestHRV,
            baselineMeanMs: eval.baselineMeanMs,
            baselineLnMu: eval.lnMu,
            baselineLnSigma: eval.lnSigma,
            zScore: eval.zScore,
            stateScore: eval.stateScore,
            readinessScore: eval.readinessScore,
            stateLevel: eval.stateLevel,
            intradayHRV: todayHRV.isEmpty ? Array(hrvSamples.suffix(12)) : todayHRV,
            restingKcal: await restingKcal,
            activeKcal: await activeKcal,
            activeGoalKcal: snapshot.activeGoalKcal,
            hourlyCalories: await hourlyCal,
            overnight: overnight,
            restingHeartRate: rhr,
            vo2Max: await vo2,
            bodyMassKg: await weight,
            stepCount: Int(await steps),
            stepGoal: snapshot.stepGoal,
            exerciseMinutes: Int(await exerciseMin),
            standHours: snapshot.standHours,
            daylightMinutes: Int(await daylightMin),
            waterMl: await waterMl,
            waterGoalMl: snapshot.waterGoalMl
        )

        snapshot = updated
        SharedStore.shared.saveSnapshot(updated)
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func logWater(milliliters: Double) async {
        guard isAvailable,
              let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: Date(), end: Date())
        try? await store.save(sample)
        await refreshAll()
    }

    // MARK: - Low-level HealthKit Queries

    private func fetchQuantitySamples(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [HRVPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let points = (samples as? [HKQuantitySample] ?? []).map {
                    HRVPoint(date: $0.startDate, sdnnMs: $0.quantity.doubleValue(for: unit))
                }
                cont.resume(returning: points)
            }
            store.execute(query)
        }
    }

    private func fetchCumulativeSum(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let val = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                cont.resume(returning: val)
            }
            store.execute(query)
        }
    }

    private func fetchLatestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: val)
            }
            store.execute(query)
        }
    }

    private func fetchHourlyCalories(startOfToday: Date, end: Date) async -> [HourlyCaloriePoint] {
        async let restingBins = fetchHourlySums(.basalEnergyBurned, startOfToday: startOfToday, end: end)
        async let activeBins = fetchHourlySums(.activeEnergyBurned, startOfToday: startOfToday, end: end)
        let r = await restingBins
        let a = await activeBins
        return (0..<24).map { h in
            HourlyCaloriePoint(hour: h, restingKcal: r[h] ?? 0, activeKcal: a[h] ?? 0)
        }
    }

    private func fetchHourlySums(_ id: HKQuantityTypeIdentifier, startOfToday: Date, end: Date) async -> [Int: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: startOfToday, end: end, options: .strictStartDate)
        let interval = DateComponents(hour: 1)

        return await withCheckedContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startOfToday,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, _ in
                var result: [Int: Double] = [:]
                collection?.enumerateStatistics(from: startOfToday, to: end) { stats, _ in
                    let hour = Calendar.current.component(.hour, from: stats.startDate)
                    result[hour] = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                }
                cont.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private func fetchOvernightSleep(start: Date, end: Date) async -> OvernightVitals {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return .placeholder
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let items = samples as? [HKCategorySample] ?? []
                var deep = 0.0, core = 0.0, rem = 0.0, awake = 0.0
                for s in items {
                    let mins = s.endDate.timeIntervalSince(s.startDate) / 60.0
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: deep += mins
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: core += mins
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue: rem += mins
                    case HKCategoryValueSleepAnalysis.awake.rawValue: awake += mins
                    default: break
                    }
                }
                let totalAsleep = deep + core + rem
                let totalInBed = max(1, totalAsleep + awake)
                let eff = totalAsleep > 0 ? Int((totalAsleep / totalInBed * 100).rounded()) : 0
                let vitals = OvernightVitals(
                    sleepHours: totalAsleep / 60.0,
                    sleepEfficiencyPct: eff,
                    deepMinutes: Int(deep),
                    coreMinutes: Int(core),
                    remMinutes: Int(rem),
                    awakeMinutes: Int(awake),
                    sleepingHeartRate: nil,
                    wristTempCelsius: nil,
                    respiratoryRate: nil,
                    bloodOxygenPct: nil
                )
                cont.resume(returning: totalAsleep > 0 ? vitals : .placeholder)
            }
            store.execute(query)
        }
    }
}
