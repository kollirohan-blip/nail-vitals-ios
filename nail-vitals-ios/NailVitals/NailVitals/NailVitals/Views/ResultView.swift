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
            if AngleAnalyzer.plausibleRange.contains(candidate.angleDegrees) {
                Text("\(candidate.angleDegrees, specifier: "%.1f")°")
                    .font(.system(size: 48, weight: .bold))
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
                .padding(.horizontal, 24)

            // The Python prototype's 115-130 deg "healthy finger" readings
            // came from its cuticle search landing on the fingertip curve
            // (reproduced on synthetic fingers; fixed in AngleAnalyzer).
        }
        .padding()
    }
}

