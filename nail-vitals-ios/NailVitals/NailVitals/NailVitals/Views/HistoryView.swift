//
//  HistoryView.swift
//  NailVitals
//
//  The History tab as a small dashboard: one trend chart for the finger
//  you measure, with a picker for the sign, the latest value against the
//  one before (and whether the change is within the usual day-to-day
//  range), then every assessment on this phone, newest first. Only the
//  numbers are kept, never photos. Deleting everything lives in Settings.
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: ScanHistory

    @AppStorage("measuredHand") private var hand: MeasuredHand = .right
    @State private var kind: SignKind = .lovibond
    @Environment(\.startAssessment) private var startAssessment

    /// Assessments of the finger you measure, oldest first.
    private var sameFinger: [ScanSession] { history.sessions.filter { $0.hand == hand.rawValue } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.component) {
                    if history.sessions.isEmpty {
                        emptyState
                    } else {
                        trend
                        assessments
                    }
                    SafetyNote()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.tight)
            }
            .background(AppBackground())
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { SessionDetailView(history: history, id: $0) }
        }
    }

    // MARK: - Trend

    private var trend: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    SectionLabel("Your trend")
                    Spacer()
                    fingerPicker
                }
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    SectionLabel("Your trend")
                    fingerPicker
                }
            }
            Picker("Sign", selection: $kind) {
                ForEach(SignKind.allCases, id: \.self) { Text($0.plainName).tag($0) }
            }
            .pickerStyle(.segmented)

            let points = sameFinger.compactMap { session -> (date: Date, value: Double)? in
                session.report.assessment.values[kind].map { (session.date, $0) }
            }
            if points.count >= 2 {
                SignTrendCard(kind: kind, sessions: sameFinger)
                comparison(points)
            } else {
                ExampleTrendCard(message: "Your \(kind.plainName.lowercased()) trend appears after 2 assessments of your \(hand.label.lowercased()) index finger. \(points.count == 1 ? "You have 1 so far." : "")")
            }
        }
    }

    private var fingerPicker: some View {
        Picker("Finger", selection: $hand) {
            ForEach(MeasuredHand.allCases, id: \.self) { Text("\($0.label) index").tag($0) }
        }
        .pickerStyle(.menu)
        .tint(Theme.accent)
    }

    /// The latest value against the one before.
    private func comparison(_ points: [(date: Date, value: Double)]) -> some View {
        let latest = points[points.count - 1], previous = points[points.count - 2]
        return VStack(alignment: .leading, spacing: 4) {
            Text(CheckupWording.comparison(kind, latest: latest.value, previous: previous.value, previousDate: previous.date))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(CheckupWording.changeNote(kind, latest: latest.value, previous: previous.value))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.normal)
        .glassCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }

    // MARK: - List

    private var assessments: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            SectionLabel("Assessments")
            ForEach(history.sessions.reversed()) { session in
                NavigationLink(value: session.id) {
                    SessionRow(session: session)
                }
                .buttonStyle(.pressableCard)
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.normal) {
            ExampleTrendCard(message: "After two assessments, your trend appears here: each sign over time, with the published limit and the typical zone.")
            Text("Each assessment takes about a minute. Only the numbers are saved, on this phone.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start your first assessment", action: startAssessment)
                .buttonStyle(.primaryAction)
        }
        .padding(.top, Spacing.tight)
    }
}

/// A faded, clearly labelled example of what a trend looks like, for
/// before there is one. No numbers: it's a picture of the idea, not data.
struct ExampleTrendCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.normal) {
            HStack {
                Text("Example")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                Spacer()
            }
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                // A gently varying line under a dashed limit, in gray.
                let ys: [CGFloat] = [0.70, 0.62, 0.66, 0.58, 0.63, 0.60]
                ZStack {
                    Rectangle()
                        .fill(Theme.aligned.opacity(0.08))
                        .frame(height: h * 0.55)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h * 0.3))
                        p.addLine(to: CGPoint(x: w, y: h * 0.3))
                    }
                    .stroke(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Path { p in
                        for (i, y) in ys.enumerated() {
                            let pt = CGPoint(x: w * CGFloat(i) / CGFloat(ys.count - 1), y: h * y)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(ys.indices, id: \.self) { i in
                        Circle()
                            .fill(Color.primary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .position(x: w * CGFloat(i) / CGFloat(ys.count - 1), y: h * ys[i])
                    }
                }
            }
            .frame(height: 110)
            .accessibilityHidden(true)
            Text(message.trimmingCharacters(in: .whitespaces))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.normal)
        .glassCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example trend. \(message)")
    }
}
