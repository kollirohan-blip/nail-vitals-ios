//
//  AboutMeasurementsView.swift
//  NailVitals
//
//  What the three signs are, their published cut-offs and sources, how the
//  app combines them, and why a doctor is still the next step. Opened from
//  the result screen, and the Learn tab's "The science" page.
//

import SwiftUI

struct AboutMeasurementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AboutMeasurementsContent()
                .navigationTitle("About these measurements")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// The page itself, also pushed from the Learn tab.
struct AboutMeasurementsContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("From one side photo of your index finger, the app measures three signs that doctors use to check for finger clubbing.")
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.85))

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

                section("Schamroth window test (beta)") {
                    bullet("With the backs of the two index fingertips pressed together, nail to nail, a small diamond-shaped gap normally shows between the nail beds. In clubbing it disappears. Dr. Leo Schamroth described it from his own fingers in 1976.")
                    bullet("The app looks for background showing through between the two fingers and asks you to confirm the gap it found, or to tap it yourself. It is experimental and hasn't been tested on enough people to know how often it's right.")
                }

                section("Percentiles and the Nail Vitals Index") {
                    bullet("Percentile: the share of healthy fingers in a published study with a lower value. The nail angle is compared with Bentley's silhouettes of children and young adults (168.3°, SD 3.6), the fingertip angle with Husarik's 123 healthy people (178.9°, SD 4.7). This assumes their values follow a bell curve.")
                    bullet("The thickness ratio has no percentile: we couldn't check a published healthy average and spread for it, so it is only compared with its 1.0 cut-off.")
                    bullet("Nail Vitals Index: the average of how many standard deviations the two angles sit from those healthy averages. 0 is average. It describes where your finger sits; it has no cut-off of its own and the result above doesn't use it.")
                    bullet("On a handful of photos, the app's nail angle differed from points placed by hand by about 3°. A study with more people placing the points is checking whether that difference is real.")
                }

                section("Why a doctor, not just the app") {
                    Text("Clubbing is a sign, not a disease. It can go along with lung, heart, liver or digestive conditions, and some people are born with it and are healthy. Only a doctor can find out what it means for you. The app gives a steady, repeatable measurement you can bring to that conversation.")
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.85))
                }

                section("Limits") {
                    bullet("Photo measurements shift by a few degrees if the finger is turned, bent or blurry. The app checks for these and asks for a retake.")
                    bullet("Scanned again on another day, the result usually lands within about ±3° (nail angle), ±4° (fingertip angle) and ±0.06 (ratio). Measured over \(Repeatability.sessions) repeat sessions of one person so far.")
                    bullet("This app has only been checked on a small number of people so far.")
                }

                section("Why sources give different numbers") {
                    bullet("Lovibond's 1938 description, judged by eye at the bedside, put a normal nail angle near 160° and clubbing above 180°.")
                    bullet("Measured on silhouettes, healthy fingers averaged 168° (Bentley 1976). A 2001 JAMA review found that people without clubbing don't go above 176°. The app uses these measured values.")
                    bullet("Between a typical value and the limit there is no sharp line, so the app shows a \"close to the limit\" zone 3° either side of it, and needs 2 of the 3 signs to agree before it suggests talking to a doctor.")
                    bullet("The limits were set by measuring fingers directly. Whether they hold exactly for a phone photo is what the app's own tests check; see \"How accurate is this?\" on your result.")
                }

                section("Sources") {
                    ForEach(Source.all, id: \.url) { item in
                        if let url = URL(string: item.url) {
                            Link(destination: url) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(item.citation)
                                        .font(.footnote)
                                        .multilineTextAlignment(.leading)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                        }
                    }
                    source("Schamroth L. Personal experience. S Afr Med J. 1976;50(9):297–300.")
                }

                SafetyNote()
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(AppBackground())
    }

    private func sign(_ kind: SignKind, what: String, healthy: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.plainName)
                        .font(.body.weight(.semibold))
                        .foregroundColor(Theme.text)
                    Text(kind.title)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("cut-off \(kind.formattedThreshold)")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary.opacity(0.7))
            }
            Text(what)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.85))
            Text(healthy)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground(cornerRadius: 16)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundColor(Theme.text)
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Color.primary.opacity(0.6)).frame(width: 5, height: 5)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.85))
        }
    }

    private func source(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
    }
}

#Preview {
    AboutMeasurementsView()
}
