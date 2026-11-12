//
//  RangeBar.swift
//  NailVitals
//
//  One clubbing sign on a number line: the typical zone, the zone close to
//  the published limit, the zone past it, a tick at the limit and a marker
//  at your value. People read a position on a line more accurately than a
//  bare number, and the zones run from the "typical" color to the "worth
//  discussing" color, so the bar also says which way is which. The maths
//  is RangeScale.
//

import SwiftUI

struct RangeBar: View {
    let kind: SignKind
    /// The sign's value; nil when it wasn't measured.
    let value: Double?
    /// Shown instead of the number (e.g. "≥180°" for no cuticle dip).
    var valueText: String? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Room for the labels under the bar; grows with the text size.
    @ScaledMetric(relativeTo: .caption) private var labelHeight: CGFloat = 16

    private var state: SignState { value.map { SignState(kind.status(of: $0)) } ?? .couldntCheck }
    private var shown: String { value == nil ? "not measured" : (valueText ?? kind.formatted(value!)) }

    var body: some View {
        let scale = RangeScale(kind)
        VStack(alignment: .leading, spacing: 8) {
            // Name on the left, value on the right; stacked when they
            // don't fit (very large text).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    names
                    Spacer(minLength: 8)
                    reading
                }
                VStack(alignment: .leading, spacing: 2) {
                    names
                    reading
                }
            }
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        zone(Theme.aligned).frame(width: width * scale.nearStartFraction)
                        zone(Theme.adjusting).frame(width: width * (scale.nearEndFraction - scale.nearStartFraction))
                        zone(Theme.attention)
                    }
                    .frame(height: 10)
                    .clipShape(Capsule())
                    .offset(y: 5)
                    // The published limit.
                    Capsule()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 2, height: 20)
                        .offset(x: width * scale.limitFraction - 1)
                    if let value {
                        Circle()
                            .fill(state.color)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2.5))
                            .offset(x: min(max(width * scale.fraction(of: value) - 8, 0), width - 16), y: 2)
                    }
                    // Labels under the bar; the limit's sits under its tick.
                    Group {
                        if !typeSize.isAccessibilitySize {
                            Text("typical")
                                .frame(width: width, alignment: .leading)
                            Text("past the limit")
                                .frame(width: width, alignment: .trailing)
                        }
                        Text("limit \(kind.formattedThreshold)")
                            .fixedSize()
                            .position(x: min(max(width * scale.limitFraction, 36), width - 36), y: labelHeight / 2)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .frame(height: labelHeight)
                    .offset(y: 24)
                }
            }
            .frame(height: 24 + labelHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.plainName): \(shown), \(state.label). The limit is \(kind.formattedThreshold).")
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(kind.plainName)
                .font(.subheadline.weight(.semibold))
            Text(kind.title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var reading: some View {
        HStack(spacing: 6) {
            Text(shown)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            Image(systemName: state.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(state.color)
        }
    }

    /// Stronger on white, where pale zones wash out.
    private func zone(_ color: Color) -> some View {
        color.opacity(scheme == .light ? 0.55 : 0.45)
    }
}
