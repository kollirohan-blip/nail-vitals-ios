//
//  ReportCardView.swift
//  NailVitals
//
//  One check-up as a report card. It answers "is this good or bad?" first
//  (the banner), then lists every sign that was checked, grouped by Shape,
//  Colour, Circulation and Extra, then says what to do next. Each sign row
//  opens that sign's detail page. The caller adds the safety line and its
//  own buttons underneath.
//
//  The order follows what people look for in a test result: the result,
//  what it means, what to do next, then the details (one tap away).
//

import SwiftUI

/// So a sign can drive a sheet or a navigation push.
extension NailSign: Identifiable {
    var id: String { rawValue }
}

struct ReportCardView: View {
    /// The check-up's side readings, oldest first.
    let readings: [FingerSigns]
    /// Results for the signs other than clubbing.
    var extra: [SignResult] = []
    let hand: MeasuredHand
    let date: Date
    /// Right after a scan: the banner, then each sign, appear one by one.
    var animated = false
    let onOpen: (NailSign) -> Void

    /// How many parts are showing (banner = 1, then one per sign, then
    /// the next step).
    @State private var revealed = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var report: CheckupReport { CheckupReport(readings: readings, extra: extra) }
    /// Everything shows at once unless this is the animated reveal.
    private var shown: Int { animated && !reduceMotion ? revealed : .max }

    var body: some View {
        let report = self.report
        VStack(alignment: .leading, spacing: 16) {
            Text("\(Self.dayText(date)) · \(hand.label) index finger")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            StateBanner(state: report.overall, title: report.headline, detail: bannerDetail(report))
                .reveal(1, of: shown)

            if readings.count < ClubbingAssessment.readingsForSteadyResult, report.measuredCount > 0 {
                Text(steadierHint)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(SignGroup.allCases, id: \.self) { group in
                let results = report.results(in: group)
                if !results.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(results) { result in
                                signRow(result, report)
                                    .reveal(2 + (report.results.firstIndex(of: result) ?? 0), of: shown)
                            }
                        }
                        .glassCard(cornerRadius: 20)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What to do next")
                    .font(.headline)
                Text(report.nextStep)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassCard(cornerRadius: 20)
            .reveal(2 + report.results.count, of: shown)
        }
        .onAppear { startReveal(parts: 2 + report.results.count) }
    }

    // MARK: - Rows

    /// A sign: its name, value and state. Clubbing also lists its three
    /// measured signs.
    private func signRow(_ result: SignResult, _ report: CheckupReport) -> some View {
        Button { onOpen(result.sign) } label: {
            VStack(alignment: .leading, spacing: 10) {
                // One line when it fits; otherwise the value and state go
                // under the name (long state names, very large text).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        rowTitle(result)
                        Spacer(minLength: 8)
                        rowValue(result)
                        StatePill(state: result.state)
                        chevron
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            rowTitle(result)
                            Spacer(minLength: 8)
                            chevron
                        }
                        HStack(spacing: 8) {
                            rowValue(result)
                            StatePill(state: result.state)
                        }
                    }
                }
                if result.state == .couldntCheck, let reason = result.reason {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if result.sign == .clubbing, result.state != .couldntCheck {
                    VStack(spacing: 6) {
                        ForEach(SignKind.allCases, id: \.self) { kind in
                            clubbingLine(kind, report)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the details")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
    }

    private func rowTitle(_ result: SignResult) -> some View {
        Text(result.sign.title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func rowValue(_ result: SignResult) -> some View {
        if let text = result.valueText {
            Text(text)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    /// One of the three clubbing signs: its state icon, name, value and
    /// published limit.
    private func clubbingLine(_ kind: SignKind, _ report: CheckupReport) -> some View {
        let value = report.assessment.values[kind]
        let state = value.map { SignState(kind.status(of: $0)) } ?? .couldntCheck
        let shown = kind == .lovibond && report.noDip ? "≥180°" : kind.formattedOrDash(value)
        let name = HStack(spacing: 8) {
            Image(systemName: state.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(state.color)
            Text(kind.plainName)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        let numbers = HStack(spacing: 8) {
            Text(shown)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text("limit \(kind.formattedThreshold)")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                name
                Spacer(minLength: 6)
                numbers
            }
            VStack(alignment: .leading, spacing: 2) {
                name
                numbers.padding(.leading, 26)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.plainName): \(value == nil ? "not measured" : shown), \(state.label). Limit \(kind.formattedThreshold).")
    }

    // MARK: - Wording

    /// The banner's second line: what the result means when one sign was
    /// checked, a count when there were several.
    private func bannerDetail(_ report: CheckupReport) -> String {
        if report.measuredCount == 0 {
            return report.results.first?.reason ?? "The app couldn't measure this time."
        }
        if report.results.count == 1 {
            return ResultView.verdictDetail(report.assessment,
                                            steady: readings.count >= ClubbingAssessment.readingsForSteadyResult,
                                            noDip: report.noDip)
        }
        let checked = "\(report.measuredCount) of \(report.results.count) signs checked"
        switch report.overall {
        case .typical: return checked + " · all in the typical range"
        case .measureAgain: return checked + " · at least one is close to its limit"
        case .worthDiscussing: return checked + " · at least one is past its limit"
        case .couldntCheck: return checked
        }
    }

    private var steadierHint: String {
        let remaining = ClubbingAssessment.readingsForSteadyResult - readings.count
        return "For a steadier result, measure \(remaining) more time\(remaining == 1 ? "" : "s"). The app will use the middle values."
    }

    /// "Today · 7:42 PM", "Yesterday · 7:42 PM", "Oct 5 · 2:34 PM".
    static func dayText(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today · \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday · \(time)"
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(time)"
    }

    // MARK: - Reveal

    private func startReveal(parts: Int) {
        guard animated, !reduceMotion else { return }
        for step in 1...parts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(step - 1) * 0.18) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { revealed = max(revealed, step) }
            }
        }
    }
}

private extension View {
    /// Hidden until the report card's reveal reaches `step`.
    func reveal(_ step: Int, of revealed: Int) -> some View {
        opacity(revealed >= step ? 1 : 0)
            .offset(y: revealed >= step ? 0 : 8)
    }
}
