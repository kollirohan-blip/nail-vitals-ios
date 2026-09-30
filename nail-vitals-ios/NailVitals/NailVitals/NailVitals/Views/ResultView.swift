//
//  ResultView.swift
//  NailVitals
//
//  Shows the measured Lovibond angle after capture. MUST include the
//  "screening aid, not a diagnosis" framing every time -- this is a
//  legal and ethical requirement stated in the project spec, not
//  optional copy.
//
//  With 3 or more readings in a session, the middle value is the headline:
//  single readings of the same finger vary by a few degrees with pose.
//

import SwiftUI

struct ResultView: View {
    let candidate: LovibondCandidate
    /// Every plausible reading this session, including this one.
    let sessionReadings: [Double]

    private static let readingsForSteadyResult = 3

    private var headline: Double {
        sessionReadings.count >= Self.readingsForSteadyResult ? median(sessionReadings) : candidate.angleDegrees
    }

    var body: some View {
        VStack(spacing: 16) {
            if AngleAnalyzer.plausibleRange.contains(candidate.angleDegrees) {
                if sessionReadings.count >= Self.readingsForSteadyResult {
                    Text("Middle of \(sessionReadings.count) readings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text("\(headline, specifier: "%.1f")°")
                    .font(.system(size: 48, weight: .bold))

                interpretation

                if sessionReadings.count > 1 {
                    Text("This session: " + sessionReadings.map { String(format: "%.1f°", $0) }.joined(separator: ", "))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                if sessionReadings.count < Self.readingsForSteadyResult {
                    Text("For a steadier result, measure \(Self.readingsForSteadyResult - sessionReadings.count) more time\(Self.readingsForSteadyResult - sessionReadings.count == 1 ? "" : "s"). The app will use the middle value.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Couldn't get a reliable measurement")
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Please retake the photo with your finger turned sideways.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
            }

            Text("This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding()
    }

    /// Reference context around the widely cited 180° threshold (Lovibond:
    /// normal fingers measure well below 180°; clubbing reaches or exceeds
    /// it). Readings shift a few degrees between photos, so values just
    /// under 180° ask for a re-measure rather than reading as clear.
    private var interpretation: some View {
        let (title, detail): (String, String)
        switch headline {
        case ..<175:
            (title, detail) = ("Typical range", "Healthy fingers measure below 180°.")
        case ..<180:
            (title, detail) = ("Close to 180°", "Readings this close to 180° can shift by a few degrees. Measure again to confirm.")
        default:
            (title, detail) = ("At or above 180°", "This is the range where clubbing is considered. Worth mentioning to a doctor, along with any symptoms you've noticed.")
        }
        return VStack(spacing: 6) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(detail)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
        }
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
