//
//  ClubbingAssessment.swift
//  NailVitals
//
//  Turns the three side-view signs into one result, using the published
//  cut-offs (Myers & Farquhar, "Does this patient have clubbing?", JAMA
//  2001: "in individuals without clubbing, values for these indices do not
//  exceed 176 degrees, 192 degrees, and 1.0"): profile (Lovibond) angle,
//  hyponychial angle, phalangeal depth ratio. The same review suggests
//  further evaluation when the profile angle exceeds 180 or the ratio 1.0.
//   - Worth discussing with a doctor: at least 2 signs above their cut-off,
//     so one noisy sign can't raise a flag alone.
//   - Measure again: exactly 1 above, or 2 or more within their
//     measurement error of the cut-off. One sign merely close to its
//     cut-off doesn't count: healthy single photos often land there (the
//     profile angle read 172-176 on healthy fingers).
//   - Typical: otherwise.
//  With 3 or more readings in a session, each sign uses its middle value.
//  Plain logic only, so Tools/angle-harness can test it.
//

import Foundation

nonisolated enum SignKind: CaseIterable {
    case lovibond, hyponychial, depthRatio

    var title: String {
        switch self {
        case .lovibond: return "Profile angle"
        case .hyponychial: return "Hyponychial angle"
        case .depthRatio: return "Depth ratio"
        }
    }

    /// Above this, the sign is in the range associated with clubbing.
    var threshold: Double {
        switch self {
        case .lovibond: return 176
        case .hyponychial: return 192
        case .depthRatio: return 1.0
        }
    }

    /// About how much one photo reading of the same finger moves with pose
    /// and outline noise (repeat photos: within-person SD about 1.5-4 deg
    /// on the profile angle, 0.02-0.03 on the ratio).
    var margin: Double {
        switch self {
        case .lovibond, .hyponychial: return 3
        case .depthRatio: return 0.03
        }
    }

    /// Values outside this are measurement failures, not fingers.
    var plausibleRange: ClosedRange<Double> {
        switch self {
        case .lovibond: return 120...240
        case .hyponychial: return 140...240
        case .depthRatio: return 0.5...1.6
        }
    }

    func value(in signs: FingerSigns) -> Double? {
        let v: Double?
        switch self {
        case .lovibond: v = signs.lovibond
        case .hyponychial: v = signs.hyponychial
        case .depthRatio: v = signs.depthRatio
        }
        return v.flatMap { plausibleRange.contains($0) ? $0 : nil }
    }

    func formatted(_ value: Double) -> String {
        self == .depthRatio ? String(format: "%.2f", value) : String(format: "%.1f°", value)
    }

    var formattedThreshold: String {
        self == .depthRatio ? String(format: "%.1f", threshold) : String(format: "%.0f°", threshold)
    }

    func status(of value: Double) -> SignStatus {
        if abs(value - threshold) <= margin { return .nearThreshold }
        return value > threshold ? .above : .typical
    }
}

nonisolated enum SignStatus {
    case typical, nearThreshold, above
}

nonisolated struct ClubbingAssessment {
    nonisolated enum Verdict {
        case typical, measureAgain, worthDiscussing

        var label: String {
            switch self {
            case .typical: return "Typical range"
            case .measureAgain: return "Measure again"
            case .worthDiscussing: return "Worth discussing with a doctor"
            }
        }
    }

    static let readingsForSteadyResult = 3

    /// Each sign's headline value: the middle of the session's readings once
    /// there are enough, otherwise the latest reading.
    let values: [SignKind: Double]
    /// How many readings each headline value comes from.
    let readingCounts: [SignKind: Int]
    let verdict: Verdict
    /// Signs above their cut-off.
    let aboveCount: Int
    /// Signs within their measurement error of the cut-off.
    let nearCount: Int

    /// - Parameter readings: the session's readings, oldest first; the last
    ///   one is the reading just taken.
    init(readings: [FingerSigns]) {
        var values: [SignKind: Double] = [:], counts: [SignKind: Int] = [:]
        for kind in SignKind.allCases {
            let all = readings.compactMap { kind.value(in: $0) }
            if all.count >= Self.readingsForSteadyResult {
                values[kind] = Self.median(all)
                counts[kind] = all.count
            } else if let latest = readings.last.flatMap({ kind.value(in: $0) }) {
                values[kind] = latest
                counts[kind] = 1
            }
        }
        self.values = values
        self.readingCounts = counts

        aboveCount = values.filter { $0.value > $0.key.threshold }.count
        nearCount = values.filter { $0.key.status(of: $0.value) == .nearThreshold }.count
        let nearOrAbove = values.filter { $0.value >= $0.key.threshold - $0.key.margin }.count
        if aboveCount >= 2 {
            verdict = .worthDiscussing
        } else if aboveCount == 1 || nearOrAbove >= 2 {
            verdict = .measureAgain
        } else {
            verdict = .typical
        }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
