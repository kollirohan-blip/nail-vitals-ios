//
//  SignDetailView.swift
//  NailVitals
//
//  One sign's page, opened from the report card. In order: the value with
//  its day-to-day range and its state, what it means, each of the three
//  signs on its own number line, why the app thinks so (the checks, with
//  their numbers one tap away), how accurate the measurement is (our own
//  test data), your earlier results, where you sit among healthy fingers,
//  and the sources. Photos aren't kept, so the proof is the numbers and
//  checks of each reading.
//

import SwiftUI

struct SignDetailView: View {
    let sign: NailSign
    /// The assessment's side readings, oldest first.
    let readings: [FingerSigns]
    /// Results for the signs other than clubbing.
    var extra: [SignResult] = []
    /// Earlier assessments, newest first, for "Your recent results".
    var recent: [ScanSession] = []

    @State private var shownAngle = ResultGauge.minAngle
    @State private var showScience = false
    @State private var showClinical = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var report: CheckupReport {
        CheckupReport(readings: readings, extra: extra, enabled: SignAvailability.enabled.union([sign]))
    }
    private var result: SignResult? { report.results.first { $0.sign == sign } }

    var body: some View {
        let report = self.report
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.normal) {
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
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showScience) { AboutMeasurementsView() }
    }

    // MARK: - Clubbing

    @ViewBuilder
    private func clubbing(_ report: CheckupReport) -> some View {
        let assessment = report.assessment
        let steady = readings.count >= ClubbingAssessment.readingsForSteadyResult
        if let result, result.state != .couldntCheck, let angle = assessment.values[.lovibond] ?? assessment.values.values.first {
            headline(result, report, steady: steady)
                .onAppear {
                    guard !reduceMotion else { shownAngle = angle; return }
                    withAnimation(.easeOut(duration: 0.7)) { shownAngle = angle }
                }

            card("What it means") {
                Text(ResultView.verdictDetail(assessment, steady: steady, noDip: report.noDip))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            card("Your three signs") {
                ForEach(Array(SignKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().opacity(0.5) }
                    RangeBar(kind: kind, value: assessment.values[kind],
                             valueText: kind == .lovibond && report.noDip ? "≥180°" : nil,
                             readings: readings.compactMap { r in
                                 kind == .lovibond && r.noCuticleDip ? nil : kind.value(in: r)
                             })
                }
                Text("Small dots are your \(readings.count) reading\(readings.count == 1 ? "" : "s"); the large dot is the value used. The result needs 2 of the 3 signs to agree.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                QualityPanel(readings: readings)
                Divider().opacity(0.5)
                clinicalDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.normal)
            .glassCard(cornerRadius: 20)
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
                .padding(Spacing.normal)
                .glassCard(cornerRadius: 20)
        }

        sources

        Button { showScience = true } label: {
            Label("The science behind these signs", systemImage: "book.closed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.pressableCard)
        .glassCard(cornerRadius: 20)
    }

    /// The dial, the value with its day-to-day range, the state and the
    /// checks badge.
    private func headline(_ result: SignResult, _ report: CheckupReport, steady: Bool) -> some View {
        let assessment = report.assessment
        let profile = assessment.values[.lovibond]
        let range = Repeatability.range95[.lovibond] ?? 0
        return VStack(spacing: 10) {
            if profile != nil {
                ResultGauge(angle: shownAngle, uncertainty: report.noDip ? 0 : range)
                    .frame(width: 280, height: 170)
                    .accessibilityHidden(true)
                ZoneLegend()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(result.valueText ?? "—")
                    .heroNumber()
                if profile != nil, !report.noDip {
                    Text(String(format: "± %.0f°", range))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(profile.map { report.noDip ? "Nail angle 180 degrees or more" : "Nail angle \(SignKind.lovibond.withUncertainty($0))" } ?? "Not measured")
            Text(report.noDip ? "No cuticle dip: Lovibond's sign" : "Nail angle (profile / Lovibond)" + (steady ? " · middle of \(readings.count) readings" : ""))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            StatePill(state: result.state)
            if let badge = CheckSummary(readings: readings).badge {
                Label(badge, systemImage: "checkmark.seal")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            if profile != nil, !report.noDip {
                Text("± is how far a scan of the same finger usually moves from day to day in our repeat tests. A phone photo isn't exact to a tenth of a degree.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassCard()
    }

    /// Each reading's numbers, behind one tap.
    private var clinicalDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showClinical.toggle() }
            } label: {
                HStack {
                    Text("Clinical details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: showClinical ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(showClinical ? "Hides each reading's numbers" : "Shows each reading's numbers")
            if showClinical {
                readingsTable
                if let spread = QualityPanel.spreadText(readings) {
                    Text(spread)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(QualityPanel.repeatText)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Photos aren't kept: these numbers are what the result is built from.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Each reading's three values, the one used marked.
    private var readingsTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("Reading").gridColumnAlignment(.leading)
                Text("Nail")
                Text("Fingertip")
                Text("Ratio")
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
            if readings.count >= ClubbingAssessment.readingsForSteadyResult {
                Divider()
                GridRow {
                    Text("Used").gridColumnAlignment(.leading)
                    Text(report.noDip ? "≥180°" : SignKind.lovibond.formattedOrDash(report.assessment.values[.lovibond]))
                    Text(SignKind.hyponychial.formattedOrDash(report.assessment.values[.hyponychial]))
                    Text(SignKind.depthRatio.formattedOrDash(report.assessment.values[.depthRatio]))
                }
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// Up to five earlier assessments' nail angles.
    private var recentResults: some View {
        let rows = recent.prefix(5).map { session -> (id: UUID, date: Date, report: CheckupReport) in
            (session.id, session.date, session.report)
        }
        return card("Your recent results") {
            if rows.isEmpty {
                Text("Your earlier assessments will show here.")
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
                Text("Differences of a few degrees between days are normal: they come from how the finger was held.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The studies behind the limits and averages, each one tap away.
    private var sources: some View {
        card("Sources") {
            ForEach(Source.all, id: \.url) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(source.short)
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Theme.accent)
                            Text(source.finding)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityLabel("\(source.short): \(source.finding) Opens the study.")
                }
            }
            Text("The limits come from studies that measured fingers directly. Whether they hold exactly for a phone photo is what our own tests check.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Other signs

    /// A sign without its own layout yet: the value, state and reason.
    @ViewBuilder
    private var other: some View {
        if let result {
            VStack(spacing: 10) {
                Text(result.valueText ?? "—")
                    .heroNumber()
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
        .padding(Spacing.normal)
        .glassCard(cornerRadius: 20)
    }
}
