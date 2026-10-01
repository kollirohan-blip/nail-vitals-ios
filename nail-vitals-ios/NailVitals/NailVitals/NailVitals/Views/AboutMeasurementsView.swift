//
//  AboutMeasurementsView.swift
//  NailVitals
//
//  What the three signs are, their published cut-offs and sources, how the
//  app combines them, and why a doctor is still the next step. Opened from
//  the result screen.
//

import SwiftUI

struct AboutMeasurementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("From one side photo of your index finger, the app measures three signs that doctors use to check for finger clubbing.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.85))

                    sign(.lovibond,
                         what: "Lovibond's angle: where the nail leaves the skin fold at the cuticle.",
                         healthy: "Healthy fingers averaged 168° (SD 3.6) in a silhouette study of the right index finger; people without clubbing don't go above 176°.")
                    sign(.hyponychial,
                         what: "The angle at the cuticle between a line back to the skin crease over the last joint and a line out to the skin under the nail's free edge. It uses long lines, so it is steadier than the profile angle.",
                         healthy: "Healthy fingers averaged 178.9° (SD 4.7) in 123 people photographed from the side; none of 171 healthy people in earlier studies went above 192°.")
                    sign(.depthRatio,
                         what: "How thick the finger is at the base of the nail, divided by how thick it is at the last knuckle.",
                         healthy: "Healthy fingers are below 1.0: thinner at the nail than at the joint.")

                    section("How the result is decided") {
                        bullet("Two or more signs above their cut-off: worth discussing with a doctor.")
                        bullet("One sign above its cut-off, or two signs close to theirs: measure again. One sign alone can come from a slightly turned finger.")
                        bullet("One sign just under its cut-off on its own shows amber but counts as typical: single photos of healthy fingers often land there.")
                        bullet("Otherwise: typical range.")
                        bullet("After 3 readings, the app uses the middle value of each sign, since single photos vary by a few degrees.")
                        bullet("No dip at the cuticle means Lovibond's angle is gone (180° or more), which counts as that sign. The other two signs are then measured where the cuticle usually sits, about halfway from the fingertip to the last joint. A finger turned toward the camera can also hide the dip, so the app asks you to retake if your hand looks turned.")
                    }

                    section("Why a doctor, not just the app") {
                        Text("Clubbing is a sign, not a disease. It can go along with lung, heart, liver or digestive conditions, and some people are born with it and are healthy. Only a doctor can find out what it means for you. The app gives a steady, repeatable measurement you can bring to that conversation.")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.85))
                    }

                    section("Limits") {
                        bullet("Photo measurements shift by a few degrees if the finger is turned, bent or blurry.")
                        bullet("This app has only been checked on a small number of people so far.")
                    }

                    section("Sources") {
                        source("Myers KA, Farquhar DR. The rational clinical examination: does this patient have clubbing? JAMA. 2001;286(3):341–347.")
                        source("Husarik D, Vavricka SR, Mark M, Schaffner A, Walter RB. Assessment of digital clubbing in medical inpatients by digital photography and computerised analysis. Swiss Med Wkly. 2002;132:132–138.")
                        source("Bentley D, Moore A, Shwachman H. Finger clubbing: a quantitative survey by analysis of the shadowgraph. Lancet. 1976;2:164–167.")
                        source("Regan GM, Tagg B, Thomson ML. Subjective assessment and objective measurement of finger clubbing. Lancet. 1967;1:530–532.")
                    }

                    Text("This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("About these measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.searching)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sign(_ kind: SignKind, what: String, healthy: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("cut-off \(kind.formattedThreshold)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.searching)
            }
            Text(what)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.85))
            Text(healthy)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Theme.searching).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private func source(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
    }
}

#Preview {
    AboutMeasurementsView()
}
