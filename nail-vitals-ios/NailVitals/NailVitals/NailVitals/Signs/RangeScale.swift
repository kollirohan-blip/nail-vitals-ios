//
//  RangeScale.swift
//  NailVitals
//
//  Where a value sits on its sign's number line (RangeBar): the shown
//  range, the published limit, and the "close to the limit" zone, which is
//  the same margin the verdict uses (SignKind.margin). People read number
//  lines more accurately than bare numbers, so each sign gets one.
//
//  Plain maths, so Tools/signs-harness can test it.
//

import Foundation

nonisolated struct RangeScale {
    let kind: SignKind
    /// The values the bar shows; anything outside is pinned to an end.
    let range: ClosedRange<Double>

    init(_ kind: SignKind) {
        self.kind = kind
        switch kind {
        case .lovibond: range = 150...200
        case .hyponychial: range = 165...210
        case .depthRatio: range = 0.70...1.20
        }
    }

    /// 0 at the bar's left end, 1 at its right end.
    func fraction(of value: Double) -> Double {
        let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return min(1, max(0, f))
    }

    /// The published limit.
    var limitFraction: Double { fraction(of: kind.threshold) }
    /// Where "close to the limit" starts and ends.
    var nearStartFraction: Double { fraction(of: kind.threshold - kind.margin) }
    var nearEndFraction: Double { fraction(of: kind.threshold + kind.margin) }
}
