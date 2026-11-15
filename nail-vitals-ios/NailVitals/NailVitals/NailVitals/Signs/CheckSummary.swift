//
//  CheckSummary.swift
//  NailVitals
//
//  The checks behind a result, summed over its readings: which passed, and
//  the measured number next to the threshold it had to meet, so "5 of 5
//  checks passed" can be opened and verified. These are checks of the
//  measurement, not of anyone's health.
//
//  Plain logic, so Tools/signs-harness can test it.
//

import Foundation

nonisolated struct CheckSummary {
    nonisolated struct Row: Identifiable, Equatable {
        let id: String
        let label: String
        /// Readings that passed, and that didn't.
        let passed: Int
        let failed: Int
        /// The measured number against its threshold.
        let detail: String?
    }

    /// One row per check that was measured on at least one reading.
    let rows: [Row]

    init(readings: [FingerSigns]) {
        let qualities = readings.compactMap(\.quality)
        var rows = ReadingQuality.Check.allCases.compactMap { check -> Row? in
            let results = qualities.compactMap { $0.passed(check) }
            guard !results.isEmpty else { return nil }
            return Row(id: check.rawValue, label: check.label,
                       passed: results.filter { $0 }.count, failed: results.filter { !$0 }.count,
                       detail: Self.detail(check, qualities))
        }
        // Readings 2 and 3 against the first (FingerIdentity); a mismatch
        // isn't counted unless the user started over with that finger.
        let prints = readings.compactMap(\.identity)
        if prints.count >= 2 {
            let failed = prints.dropFirst().filter { FingerIdentity.mismatch(first: prints[0], later: $0) != nil }.count
            rows.append(Row(id: "same", label: "Same finger each time", passed: prints.count - failed, failed: failed,
                            detail: "each reading is compared with the first"))
        }
        self.rows = rows
    }

    /// Checks every reading passed.
    var passedCount: Int { rows.filter { $0.failed == 0 }.count }

    /// "5 of 5 checks passed"; nil for results saved before checks were recorded.
    var badge: String? {
        rows.isEmpty ? nil : "\(passedCount) of \(rows.count) checks passed"
    }

    /// The weakest reading's number, next to what it needed.
    private static func detail(_ check: ReadingQuality.Check, _ qualities: [ReadingQuality]) -> String? {
        switch check {
        case .sharp:
            guard let lowest = qualities.compactMap(\.sharpness).min() else { return nil }
            return String(format: "lowest sharpness %.2f · needs %.2f or more", lowest, EdgeSharpness.minimum)
        case .contrast:
            guard let lowest = qualities.compactMap(\.backgroundContrast).min() else { return nil }
            return String(format: "lowest contrast %.0f · needs %.0f or more", lowest, BackgroundContrast.minimum)
        case .straight:
            let dip = qualities.compactMap(\.dipFlexion), pip = qualities.compactMap(\.pipFlexion)
            guard let d = dip.max(by: { abs($0) < abs($1) }) ?? pip.max(by: { abs($0) < abs($1) }) else { return nil }
            let p = pip.max(by: { abs($0) < abs($1) })
            let allowed = HandLandmarks.straightDipFlexion
            return String(format: "most bend %.0f°", d) + (p.map { String(format: " and %.0f°", $0) } ?? "")
                + String(format: " · last joint allowed %.1f° to %.1f°", allowed.lowerBound, allowed.upperBound)
        case .sideOn:
            guard let most = qualities.compactMap(\.knuckleSpread).max() else { return nil }
            return String(format: "most hand turn %.2f · needs %.2f or less", most, HandLandmarks.turnedKnuckleSpread)
        }
    }
}
