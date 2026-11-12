//
//  CheckupReport.swift
//  NailVitals
//
//  One check-up as the report card shows it: a result per enabled sign and
//  one overall state. Clubbing is worked out from the side readings
//  (ClubbingAssessment); results for the other signs are passed in as they
//  were measured. The overall state is the most serious one among the
//  signs that were measured: a sign the app couldn't check never counts
//  as a problem.
//
//  Plain logic only, so Tools/signs-harness can test it.
//

import Foundation

nonisolated struct CheckupReport {
    static let clubbingAnalyzerVersion = 1

    /// Enabled signs only, in NailSign.allCases order.
    let results: [SignResult]
    /// The three clubbing signs behind the clubbing result.
    let assessment: ClubbingAssessment
    /// Most readings found no cuticle dip: the profile counts as 180 or more.
    let noDip: Bool

    /// - Parameters:
    ///   - readings: the check-up's side readings, oldest first.
    ///   - extra: results for the other signs, as measured.
    ///   - enabled: the signs to show (SignAvailability).
    init(readings: [FingerSigns], extra: [SignResult] = [], enabled: Set<NailSign> = SignAvailability.enabled) {
        let assessment = ClubbingAssessment(readings: readings)
        let noDip = readings.filter(\.noCuticleDip).count * 2 > readings.count
        self.assessment = assessment
        self.noDip = noDip

        var results: [SignResult] = []
        for sign in NailSign.allCases where enabled.contains(sign) {
            if sign == .clubbing {
                results.append(Self.clubbing(assessment, noDip: noDip))
            } else if let stored = extra.first(where: { $0.sign == sign }) {
                results.append(stored)
            }
        }
        self.results = results
    }

    private static func clubbing(_ assessment: ClubbingAssessment, noDip: Bool) -> SignResult {
        guard !assessment.values.isEmpty else {
            return SignResult(sign: .clubbing, state: .couldntCheck, value: nil, valueText: nil,
                              reason: "The app couldn't measure your finger in these photos.",
                              analyzerVersion: clubbingAnalyzerVersion)
        }
        let profile = assessment.values[.lovibond]
        let text = noDip ? "≥180°" : profile.map(SignKind.lovibond.formatted)
        return SignResult(sign: .clubbing, state: SignState(assessment.verdict), value: profile, valueText: text,
                          reason: nil, analyzerVersion: clubbingAnalyzerVersion)
    }

    /// The most serious state among the measured signs; "couldn't check"
    /// when nothing was measured.
    var overall: SignState {
        results.map(\.state).filter { $0 != .couldntCheck }.max { $0.severity < $1.severity } ?? .couldntCheck
    }

    var measuredCount: Int { results.filter { $0.state != .couldntCheck }.count }

    func results(in group: SignGroup) -> [SignResult] {
        results.filter { $0.sign.group == group }
    }

    /// The banner's answer to "is this good or bad?".
    var headline: String {
        switch overall {
        case .typical: return "Nothing stood out today"
        case .measureAgain: return "Measure again"
        case .worthDiscussing: return "Worth discussing with a doctor"
        case .couldntCheck: return "Couldn't check this time"
        }
    }

    /// What to do next, in plain words.
    var nextStep: String {
        switch overall {
        case .typical:
            return "Nothing to do now. Check again in a few weeks to build your trend."
        case .measureAgain:
            return "Measure again in good light, with your finger straight. If it reads the same on another day, mention it at your next checkup."
        case .worthDiscussing:
            return "Show this result to a doctor. Only a doctor can say what it means. Mention any symptoms you've noticed."
        case .couldntCheck:
            return "Try again in good light, in front of a plain background that's much lighter or darker than your skin."
        }
    }
}
