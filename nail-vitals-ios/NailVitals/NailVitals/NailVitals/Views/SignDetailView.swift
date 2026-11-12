//
//  SignDetailView.swift
//  NailVitals
//
//  One sign's page, opened from the report card. In order: the value and
//  its state, what it means, why the app thinks so (the readings and the
//  checks behind them), how accurate the measurement is (our own test
//  numbers, validation.json), your earlier results, and the published
//  range it's compared with. Photos aren't kept, so the proof is the
//  numbers and checks of each reading.
//

import SwiftUI

struct SignDetailView: View {
    let sign: NailSign
    /// The check-up's side readings, oldest first.
    let readings: [FingerSigns]
    /// Results for the signs other than clubbing.
    var extra: [SignResult] = []
    /// Earlier check-ups, newest first, for "Your recent results".
    var recent: [ScanSession] = []

    @State private var shownAngle = ResultGauge.minAngle
    @State private var showScience = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var report: CheckupReport {
        CheckupReport(readings: readings, extra: extra, enabled: SignAvailability.enabled.union([sign]))
    }
    private var result: SignResult? { report.results.first { $0.sign == sign } }

    var body: some View {
        let report = self.report
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if sign == .clubbing {
                    clubbing(report)
                } else {
                    other
                }
                SafetyNote()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(AppBackground())
        .navigationTitle(sign.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScience) { AboutMeasurementsView() }
    }

    // MARK: - Clubbing

    @ViewBuilder
    private func clubbing(_ report: CheckupReport) -> some View {
        let assessment = report.assessment
        let steady = readings.count >= ClubbingAssessment.readingsForSteadyResult
        if let result, result.state != .couldntCheck, let angle = assessment.values[.lovibond] ?? assessment.values.values.first {
            VStack(spacing: 10) {
                if assessment.values[.lovibond] != nil {
                    ResultGauge(angle: shownAngle)
                        .frame(width: 260, height: 150)
                        .accessibilityHidden(true)
                }
                Text(result.valueText ?? "—")
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Text(report.noDip ? "No cuticle dip: Lovibond's sign" : "Nail angle (profile / Lovibond)")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                StatePill(state: result.state)
                if steady {
                    Text("Middle of \(readings.count) readings")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .glassCard()
            .onAppear {
                guard !reduceMotion else { shownAngle = angle; return }
                withAnimation(.spring(response: 1.1, dampingFraction: 0.8)) { shownAngle = angle }
            }

            card("What it means") {
                Text(ResultView.verdictDetail(assessment, steady: steady, noDip: report.noDip))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(SignKind.allCases, id: \.self) { kind in
                    SignChip(kind: kind, value: assessment.values[kind],
                             valueText: kind == .lovibond && report.noDip ? "≥180°" : nil)
                }
            }

            card("Why the app thinks so") {
                Text("The result comes from these readings and the checks each one passed. Photos aren't kept.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                readingsTable
                Divider().opacity(0.5)
                QualityPanel(readings: readings)
            }
        } else {
            card("Couldn't check") {
                Text(result?.reason ?? "The app couldn't measure this time.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(report.nextStep)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        accuracy
        recentResults

        if !assessment.values.isEmpty {
            NormsPanel(values: assessment.values, noDip: report.noDip)
                .padding(16)
                .glassCard(cornerRadius: 20)
        }

        Button { showScience = true } label: {
            Label("The science behind these signs", systemImage: "book.closed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 20)
    }

    /// Each reading's three values; the result uses each sign's middle one.
    private var readingsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("#").gridColumnAlignment(.leading)
                    Text("Nail")
                    Text("Fingertip")
                    Text("Thickness")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
                ForEach(Array(readings.enumerated()), id: \.offset) { index, reading in
                    GridRow {
                        Text("\(index + 1)")
                            .foregroundStyle(Theme.secondaryText)
                        Text(reading.noCuticleDip ? "≥180°" : SignKind.lovibond.formattedOrDash(reading.lovibond))
                        Text(SignKind.hyponychial.formattedOrDash(reading.hyponychial))
                        Text(SignKind.depthRatio.formattedOrDash(reading.depthRatio))
                    }
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            if readings.count >= ClubbingAssessment.readingsForSteadyResult {
                Text("The result uses the middle value of each sign.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Up to five earlier check-ups' nail angles.
    private var recentResults: some View {
        let rows = recent.prefix(5).map { session -> (id: UUID, date: Date, report: CheckupReport) in
            (session.id, session.date, session.report)
        }
        return card("Your recent results") {
            if rows.isEmpty {
                Text("Your earlier check-ups will show here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(rows, id: \.id) { row in
                    let earlier = row.report.results.first { $0.sign == sign }
                    HStack {
                        Text(row.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.subheadline)
                        Spacer()
                        Text(earlier?.valueText ?? "—")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Image(systemName: (earlier?.state ?? .couldntCheck).symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle((earlier?.state ?? .couldntCheck).color)
                            .accessibilityLabel((earlier?.state ?? .couldntCheck).label)
                    }
                }
            }
        }
    }

    // MARK: - Other signs

    /// A sign without its own layout yet: the value, state and reason.
    @ViewBuilder
    private var other: some View {
        if let result {
            VStack(spacing: 10) {
                Text(result.valueText ?? "—")
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                StatePill(state: result.state)
                if let reason = result.reason {
                    Text(reason)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .glassCard()
            accuracy
            recentResults
        }
    }

    // MARK: - Accuracy

    /// Our own test numbers for this sign (validation.json).
    @ViewBuilder
    private var accuracy: some View {
        if let validation = ValidationData.bundled[sign] {
            card("How accurate is this?") {
                ForEach(validation.lines, id: \.label) { line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.label)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Text(line.value)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let note = validation.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Our own test data, last updated \(validation.updated).")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: - Pieces

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 20)
    }
}
