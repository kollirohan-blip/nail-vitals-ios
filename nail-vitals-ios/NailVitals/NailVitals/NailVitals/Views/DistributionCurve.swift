//
//  DistributionCurve.swift
//  NailVitals
//
//  Where a value sits among healthy fingers in a published study: the
//  study's bell curve (its mean and standard deviation), a tick at the
//  limit, and a dot at your value. A percentile on its own reads like a
//  score; on the curve, "86th percentile" is plainly "toward the high end
//  of normal", which is what it means. Assumes the published values are
//  normally distributed, as PublishedNorms does.
//

import SwiftUI

struct DistributionCurve: View {
    let mean: Double
    let sd: Double
    let value: Double
    /// The sign's limit, marked when it falls on the curve.
    var limit: Double? = nil

    /// The curve covers this many standard deviations each side.
    private static let span = 3.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height - 4
            ZStack(alignment: .topLeading) {
                curve(w, h, closed: true)
                    .fill(Color.primary.opacity(0.07))
                curve(w, h, closed: false)
                    .stroke(Color.primary.opacity(0.35), lineWidth: 1.5)
                // The healthy average.
                Path { p in
                    p.move(to: CGPoint(x: x(mean, w), y: h))
                    p.addLine(to: CGPoint(x: x(mean, w), y: y(mean, h)))
                }
                .stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if let limit, abs(limit - mean) <= Self.span * sd {
                    Path { p in
                        p.move(to: CGPoint(x: x(limit, w), y: h))
                        p.addLine(to: CGPoint(x: x(limit, w), y: h * 0.25))
                    }
                    .stroke(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                Circle()
                    .fill(Theme.text)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    .position(x: x(value, w), y: y(value, h))
            }
        }
        .frame(height: 54)
        .accessibilityHidden(true)
    }

    private func x(_ v: Double, _ width: CGFloat) -> CGFloat {
        let z = min(max((v - mean) / sd, -Self.span), Self.span)
        return width * CGFloat((z + Self.span) / (2 * Self.span))
    }

    /// Height of the bell at `v`, peak at the top.
    private func y(_ v: Double, _ height: CGFloat) -> CGFloat {
        let z = min(max((v - mean) / sd, -Self.span), Self.span)
        return height - (height - 4) * CGFloat(exp(-z * z / 2))
    }

    private func curve(_ w: CGFloat, _ h: CGFloat, closed: Bool) -> Path {
        Path { p in
            let steps = 60
            for i in 0...steps {
                let v = mean + sd * Self.span * (2 * Double(i) / Double(steps) - 1)
                let pt = CGPoint(x: x(v, w), y: y(v, h))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            if closed {
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.closeSubpath()
            }
        }
    }
}
