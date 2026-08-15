//
//  ResultView.swift
//  NailVitals
//
//  Shows the measured Lovibond angle after capture. MUST include the
//  "screening aid, not a diagnosis" framing every time -- this is a
//  legal and ethical requirement stated in the project spec, not
//  optional copy.
//
//  STATUS: stub -- fill in once AngleAnalyzer produces real results.
//

import SwiftUI

struct ResultView: View {
    // FIXED: this used to say "AngleMeasurement", a type that no
    // longer exists -- AngleAnalyzer.swift was rewritten to use
    // LovibondCandidate/LovibondResult instead, and this file didn't
    // get updated to match at the time, causing a build error.
    let candidate: LovibondCandidate

    var body: some View {
        VStack(spacing: 16) {
            Text("\(candidate.angleDegrees, specifier: "%.1f")°")
                .font(.system(size: 48, weight: .bold))

            Text("This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // TODO: save-to-history action, reference range context.
            // Reference data from the Python prototype (post-bugfix,
            // verified against synthetic ground truth): 115.5-130.3
            // degrees observed across 5 repeated real trials on a
            // healthy control finger -- lower than the textbook
            // ~160-180 degree reference, still under investigation
            // (see project notes on the semi-automatic confirmation
            // step this depends on).
        }
        .padding()
    }
}

