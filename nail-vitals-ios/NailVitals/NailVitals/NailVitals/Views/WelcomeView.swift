//
//  WelcomeView.swift
//  NailVitals
//
//  First launch, three screens and no forms: what the app does and
//  doesn't do (with one acknowledgement), what happens to your photos, and
//  which finger to measure. No account, no setup: the next tap after this
//  is the first assessment. How to hold the finger is taught where it's
//  needed, on the camera screen (IntroView).
//

import SwiftUI

struct WelcomeView: View {
    let onDone: () -> Void

    @State private var page = 0
    @State private var understood = false
    @AppStorage("measuredHand") private var hand: MeasuredHand = .right

    private let pages = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                what.tag(0)
                privacy.tag(1)
                finger.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(0..<pages, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.accent : Color.primary.opacity(0.2))
                        .frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            .animation(.easeOut(duration: 0.25), value: page)
            .accessibilityHidden(true)

            Button(page < pages - 1 ? "Continue" : "Get started") {
                if page < pages - 1 {
                    withAnimation(.easeOut(duration: 0.3)) { page += 1 }
                } else {
                    onDone()
                }
            }
            .buttonStyle(.primaryAction)
            .disabled(!understood)
            .opacity(understood ? 1 : 0.45)
            .padding(.horizontal, 24)
            .padding(.top, Spacing.component)
            .padding(.bottom, Spacing.component)
        }
        .background(AppBackground())
        .interactiveDismissDisabled()
    }

    private func screen<Art: View, Body: View>(_ title: String, @ViewBuilder art: () -> Art,
                                               @ViewBuilder body: () -> Body) -> some View {
        ScrollView {
            VStack(spacing: Spacing.component) {
                art()
                    .frame(height: 200)
                    .padding(.top, Spacing.section)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                body()
            }
            .padding(.horizontal, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // 1. What it does, and the one thing to acknowledge.
    private var what: some View {
        screen("Measure what's usually judged by eye") {
            ResultGauge(angle: 167, uncertainty: 3)
                .frame(width: 280, height: 170)
        } body: {
            Text("Nail Vitals measures the shape of your fingertip from three side photos and tells you whether the signs of finger clubbing are in the typical range.")
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // The whole card is the control: a large target, easy to hit.
            Button { understood.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: understood ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(understood ? Theme.accent : Theme.secondaryText)
                    Text("I understand this is a screening aid, not a diagnosis. Only a doctor can say what a result means.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Spacing.normal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .glassCard(cornerRadius: 20)
            }
            .buttonStyle(.pressableCard)
            .accessibilityAddTraits(understood ? [.isSelected] : [])
            .accessibilityHint("Required to continue")
        }
    }

    // 2. Where the photos go.
    private var privacy: some View {
        screen("Your photos stay on this phone") {
            Image(systemName: "lock.iphone")
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(Theme.accent)
        } body: {
            VStack(alignment: .leading, spacing: Spacing.normal) {
                point("iphone", "Measured on this phone", "Your photos are measured here and aren't kept.")
                point("number", "Only numbers are saved", "The app keeps the measurements, never the pictures.")
                point("bubble.left.and.text.bubble.right", "Ask is optional", "If you ask a question, your numbers and the question go to an AI service. A photo never does.")
            }
            .padding(Spacing.normal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 20)
        }
    }

    // 3. Which finger.
    private var finger: some View {
        screen("Which finger will you measure?") {
            ZStack {
                FingerProfileShape()
                    .stroke(Theme.text, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                LovibondAngleMark()
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            .frame(width: 100, height: 180)
        } body: {
            Picker("Finger", selection: $hand) {
                ForEach(MeasuredHand.allCases, id: \.self) { Text("\($0.label) index").tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Use the same index finger each time, so your results can be compared. The camera will guide you: point it straight up, side-on, and the photo takes itself.")
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
