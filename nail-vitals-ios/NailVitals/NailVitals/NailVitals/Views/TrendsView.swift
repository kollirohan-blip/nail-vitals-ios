//
//  TrendsView.swift
//  NailVitals
//
//  The Trends tab: one chart per sign across past scans (each scan's
//  middle value), with the published cut-off as a dashed line. Points take
//  the result colors; everything else stays neutral.
//

import SwiftUI
import Charts

struct TrendsView: View {
    @ObservedObject var history: ScanHistory

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if history.sessions.count < 2 {
                        EmptyStateCard(icon: "chart.xyaxis.line",
                                       title: "Trends start at two scans",
                                       text: "Each sign gets its own chart after your second scan. Scanning every few weeks shows whether anything changes.")
                            .padding(.top, 40)
                    } else {
                        ForEach(SignKind.allCases, id: \.self) { kind in
                            SignTrendCard(kind: kind, sessions: history.sessions)
                        }
                        Text("Dashed line: the published cut-off. Each point is one scan.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    SafetyNote()
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(AppBackground())
            .navigationTitle("Trends")
        }
    }
}

struct SignTrendCard: View {
    let kind: SignKind
    let sessions: [ScanSession]

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    private var points: [Point] {
        sessions.compactMap { session in
            ClubbingAssessment(readings: session.signs).values[kind].map { Point(id: session.id, date: session.date, value: $0) }
        }
    }

    /// The values and the cut-off, with some room around them.
    private var domain: ClosedRange<Double> {
        let values = points.map(\.value) + [kind.threshold]
        let pad = kind == .depthRatio ? 0.05 : 4
        return (values.min()! - pad)...(values.max()! + pad)
    }

    /// Spacing of the time labels: about four of them. Scans spread over
    /// days get a date per label, never two labels for one day (automatic
    /// ticks fall every 12 hours and print the same date twice); scans all
    /// within two days get times of day instead ("2 PM").
    private var timeAxis: (unit: Calendar.Component, count: Int, format: Date.FormatStyle) {
        guard let first = points.first?.date, let last = points.last?.date else {
            return (.day, 1, .dateTime.month(.abbreviated).day())
        }
        let hours = last.timeIntervalSince(first) / 3600
        if hours < 48 {
            return (.hour, max(1, Int((hours / 4).rounded(.up))), .dateTime.hour())
        }
        return (.day, max(1, Int((hours / 24 / 4).rounded(.up))), .dateTime.month(.abbreviated).day())
    }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.plainName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(kind.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
                Spacer()
                if let last = points.last {
                    Text("latest \(kind.formatted(last.value))")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ResultView.color(for: kind.status(of: last.value)))
                }
            }
            if points.count < 2 {
                Text("Not enough scans with this sign yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.6))
            } else {
                Chart {
                    RuleMark(y: .value("Cut-off", kind.threshold))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("cut-off \(kind.formattedThreshold)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.6))
                        }
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(kind.title, point.value))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(points) { point in
                        PointMark(x: .value("Date", point.date), y: .value(kind.title, point.value))
                            .foregroundStyle(ResultView.color(for: kind.status(of: point.value)))
                            .symbolSize(60)
                    }
                }
                .chartYScale(domain: domain)
                // Room at the ends so the first and last date labels fit.
                .chartXScale(range: .plotDimension(startPadding: 10, endPadding: 24))
                .chartXAxis {
                    let axis = timeAxis
                    AxisMarks(values: .stride(by: axis.unit, count: axis.count)) { _ in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel(format: axis.format)
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(18)
        .glassCard()
    }
}
