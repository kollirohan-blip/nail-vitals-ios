//
//  ReportCardView.swift
//  NailVitals
//
//  One assessment as a report card. It answers "is this good or bad?"
//  first (the banner), then lists each sign that was checked with one
//  number, its state and how many measurement checks passed, then gives
//  one main thing to do next, chosen by the result. Each sign row opens
//  that sign's page, where the detail lives. The caller adds the safety
//  line and its secondary buttons underneath.
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
    /// The assessment's side readings, oldest first.
    let readings: [FingerSigns]
    /// Results for the signs other than clubbing.
    var extra: [SignResult] = []
    let hand: MeasuredHand
    let date: Date
    /// Right after a scan: the banner, then each sign, appear one by one,
    /// with the result's buzz; the reminder set for this assessment is cleared.
    var animated = false
    /// Offer the next assessment's reminder (the newest assessment only).
    var offersReminder = false
    /// Starts a new assessment; nil where the screen has its own button.
    var onAssessAgain: (() -> Void)? = nil
    /// Shares this assessment with a doctor; nil before it's saved.
    var onShare: (() -> Void)? = nil
    let onOpen: (NailSign) -> Void

    /// How many parts are showing (banner = 1, then one per sign, then
    /// the next step).
    @State private var revealed = 0
    /// The buzz and the reminder clean-up happen once.
    @State private var announced = false
    @ObservedObject private var reminder = CheckupReminder.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var report: CheckupReport { CheckupReport(readings: readings, extra: extra) }
    /// Everything shows at once unless this is the animated reveal.
    private var shown: Int { animated && !reduceMotion ? revealed : .max }

    var body: some View {
        let report = self.report
        VStack(alignment: .leading, spacing: Spacing.normal) {
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
                    VStack(alignment: .leading, spacing: Spacing.tight) {
                        SectionLabel(group.title)
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

            VStack(alignment: .leading, spacing: 10) {
                Text("What to do next")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(report.nextStep)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                nextAction(report)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.normal)
            .glassCard(cornerRadius: 20)
            .reveal(2 + report.results.count, of: shown)
        }
        .onAppear {
            startReveal(parts: 2 + report.results.count)
            guard animated, !announced else { return }
            announced = true
            // A new assessment is done: its reminder has served its purpose.
            reminder.cancel()
            let overall = report.overall
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Haptics.result(overall) }
        }
    }

    // MARK: - Rows

    /// A sign: its name, one number, its state, and how many measurement
    /// checks passed. The detail is on the sign's page.
    private func signRow(_ result: SignResult, _ report: CheckupReport) -> some View {
        Button { onOpen(result.sign) } label: {
            VStack(alignment: .leading, spacing: 6) {
                // One line when it fits; otherwise the value and state go
                // under the name (long state names, very large text).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        rowTitle(result)
                        Spacer(minLength: 8)
                        rowValue(result, report)
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
                            rowValue(result, report)
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
                    Label(clubbingCaption, systemImage: "checkmark.seal")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.normal)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.pressableCard)
        .accessibilityHint("Opens the details")
    }

    /// "3 signs · 5 of 5 checks passed"
    private var clubbingCaption: String {
        ["3 signs", CheckSummary(readings: readings).badge].compactMap { $0 }.joined(separator: " · ")
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
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The sign's one number; the nail angle carries its day-to-day range.
    @ViewBuilder
    private func rowValue(_ result: SignResult, _ report: CheckupReport) -> some View {
        let text: String? = result.sign == .clubbing && !report.noDip
            ? result.value.map(SignKind.lovibond.withUncertainty) ?? result.valueText
            : result.valueText
        if let text {
            Text(text)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
        }
    }

    // MARK: - The one next action

    @ViewBuilder
    private func nextAction(_ report: CheckupReport) -> some View {
        switch NextAction(after: report.overall) {
        case .remind(let days):
            if offersReminder { reminderControls(days: days, primary: true) }
        case .assessAgain:
            if let onAssessAgain {
                Button("Assess again", action: onAssessAgain)
                    .buttonStyle(.primaryAction)
            }
            if offersReminder, let days = ReminderPlan.days(after: report.overall) {
                reminderControls(days: days, primary: false)
            }
        case .shareWithDoctor:
            if let onShare {
                Button(action: onShare) {
                    VStack(spacing: 2) {
                        Text("Share with your doctor")
                        Text("FHIR health-record file")
                            .font(.caption)
                    }
                }
                .buttonStyle(.primaryAction)
            }
        }
    }

    /// The opt-in reminder: a button, or the date it's set for.
    @ViewBuilder
    private func reminderControls(days: Int, primary: Bool) -> some View {
        if let date = reminder.scheduledDate {
            ViewThatFits(in: .horizontal) {
                HStack {
                    reminderSet(date)
                    Spacer(minLength: 8)
                    cancelReminder
                }
                VStack(alignment: .leading, spacing: 4) {
                    reminderSet(date)
                    cancelReminder
                }
            }
        } else if primary {
            Button { reminder.schedule(days: days) } label: {
                Label(ReminderPlan.buttonTitle(days: days), systemImage: "bell")
            }
            .buttonStyle(.primaryAction)
        } else {
            Button { reminder.schedule(days: days) } label: {
                Label(ReminderPlan.buttonTitle(days: days), systemImage: "bell")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        if reminder.permissionDenied {
            Text("Notifications are off for Nail Vitals. Turn them on in Settings.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reminderSet(_ date: Date) -> some View {
        Label("Reminder set for \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))",
              systemImage: "bell.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cancelReminder: some View {
        Button("Cancel") { reminder.cancel() }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
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
                withAnimation(.easeOut(duration: 0.6)) { revealed = max(revealed, step) }
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
