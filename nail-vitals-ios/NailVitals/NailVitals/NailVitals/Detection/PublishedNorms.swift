//
//  PublishedNorms.swift
//  NailVitals
//
//  Where a reading sits among healthy fingers in published studies: a
//  percentile per sign, and the Nail Vitals Index (the average of those
//  signs' z-scores). Both only describe; the result itself still comes
//  from the published cut-offs (ClubbingAssessment).
//
//  Sources (checked Oct 14):
//   - Profile angle: Bentley, Moore & Shwachman, Lancet 1976 (PMID 73793),
//     right index silhouettes of children and young adults: normal
//     168.3 +/- 3.6. The abstract's 125 subjects include patients; the
//     healthy count isn't given, so the app doesn't state one.
//   - Hyponychial angle: Husarik et al., Swiss Med Wkly 2002, side photos:
//     healthy 178.87 +/- 4.70 in 123 people.
//   - Depth ratio: no published healthy mean and SD found that we could
//     check, so no percentile; it's compared with the 1.0 cut-off only.
//  Percentiles assume the published values are normally distributed.
//

import Foundation

nonisolated enum PublishedNorms {
    nonisolated struct Norm {
        let mean: Double
        let sd: Double
        /// Who the healthy values come from, for the screen.
        let source: String
    }

    static let norms: [SignKind: Norm] = [
        .lovibond: Norm(mean: 168.3, sd: 3.6, source: "Bentley 1976, children and young adults"),
        .hyponychial: Norm(mean: 178.87, sd: 4.70, source: "Husarik 2002, 123 healthy people"),
    ]

    /// Standard deviations from the healthy average.
    static func z(_ kind: SignKind, _ value: Double) -> Double? {
        norms[kind].map { (value - $0.mean) / $0.sd }
    }

    /// Share of healthy fingers below this value, 0-100.
    static func percentile(_ kind: SignKind, _ value: Double) -> Double? {
        z(kind, value).map { 50 * (1 + erf($0 / 2.0.squareRoot())) }
    }

    /// Nail Vitals Index: the average z-score of the signs with published
    /// healthy values. 0 is the healthy average; +1 is one SD above it.
    /// Descriptive only: there is no cut-off for it.
    static func index(_ values: [SignKind: Double]) -> Double? {
        let zs = norms.keys.compactMap { kind in values[kind].flatMap { z(kind, $0) } }
        return zs.isEmpty ? nil : zs.reduce(0, +) / Double(zs.count)
    }

    /// "37th", "<1st", ">99th".
    static func percentileText(_ p: Double) -> String {
        if p < 1 { return "<1st" }
        if p > 99 { return ">99th" }
        let n = Int(p.rounded())
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
