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
    let measurement: AngleMeasurement

    var body: some View {
        VStack(spacing: 16) {
            Text("\(measurement.angleDegrees, specifier: "%.1f")°")
                .font(.system(size: 48, weight: .bold))

            Text("This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // TODO: save-to-history action, reference range context
            // (~160-180 deg typical, informed by the 6-photo validation
            // batch from the Python prototype: 130.7-161.1 deg range
            // observed across repeated real trials on a healthy
            // control finger)
        }
        .padding()
    }
}
