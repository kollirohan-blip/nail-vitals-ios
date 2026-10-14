//
//  SchamrothView.swift
//  NailVitals
//
//  Schamroth window test (beta): a photo of the backs of both index
//  fingertips pressed together, nail to nail, and whether the small gap
//  between the nail beds (the window) shows. Taken three ways: on a stand
//  with a spoken 3-2-1 timer, by someone else, or from Photos. The app
//  proposes the gap it finds (SchamrothFinder) and the user confirms it,
//  or taps the gap themselves. The photo stays on screen only: nothing is
//  saved.
//

import PhotosUI
import SwiftUI

struct SchamrothView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .start
    @State private var photo: UIImage?
    @State private var found: SchamrothFinder.Result?
    /// The gap on screen: the app's proposal or the user's tap.
    @State private var gap: SchamrothWindow?
    @State private var tapNote: String?
    @State private var cameraMode: SchamrothCameraView.Mode?
    @State private var pickerItem: PhotosPickerItem?
    @State private var loadError: String?

    enum Stage: Equatable {
        case start, analyzing, review
        case done(windowSeen: Bool)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .start:
                    ScrollView { start.padding(.horizontal, 20).padding(.vertical, 8) }
                case .analyzing:
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Looking for the window…").font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .review:
                    review
                case .done(let seen):
                    ScrollView { done(seen).padding(.horizontal, 20).padding(.vertical, 8) }
                }
            }
            .background(AppBackground())
            .navigationTitle("Schamroth window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                if stage != .start {
                    ToolbarItem(placement: .topBarTrailing) { Button("New photo") { reset() } }
                }
            }
        }
        .fullScreenCover(item: $cameraMode) { mode in
            SchamrothCameraView(mode: mode) { image in
                cameraMode = nil
                use(image)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    use(image)
                } else {
                    loadError = "Couldn't open that photo. Try another one."
                }
                pickerItem = nil
            }
        }
    }

    // MARK: - Before a photo

    private var start: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("BETA · EXPERIMENTAL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                Text("Looks for the small gap between your nails")
                    .font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Press the backs of your two index fingertips together, nail to nail. Normally a small diamond-shaped gap, the window, shows between the nails near the cuticles. In clubbing it disappears (Schamroth, 1976).")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                SchamrothPoseDrawing()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .glassCard(cornerRadius: 24)

            VStack(alignment: .leading, spacing: 12) {
                tip("hand.point.up.left", "Bend both index fingers at the last joint and press the nails flat together. Point them up.")
                tip("camera.viewfinder", "Photograph them from the side, close, so the nails are big in the photo.")
                tip("rectangle.portrait", "Hold them in front of a plain, light wall, in good light.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .glassCard(cornerRadius: 24)

            Button { cameraMode = .timer } label: {
                Label("Use the timer (phone on a stand)", systemImage: "timer")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.action)
            Button { cameraMode = .helper } label: {
                Label("Someone else takes it", systemImage: "camera.fill")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .tint(.primary)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .tint(.primary)
            if let loadError {
                Text(loadError).font(.system(size: 13)).foregroundStyle(Theme.attention)
            }
            Text("The photo stays on this screen. Nothing is saved or sent.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.6))
            SafetyNote()
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .frame(width: 26)
                .foregroundStyle(Color.primary.opacity(0.8))
            Text(text)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Checking the gap

    private var review: some View {
        VStack(spacing: 0) {
            if let photo {
                GeometryReader { geo in
                    let map = Fit(image: photo.size, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: photo)
                            .resizable()
                            .frame(width: map.size.width, height: map.size.height)
                            .offset(x: map.origin.x, y: map.origin.y)
                        if let gap {
                            Path { p in
                                guard let first = gap.outline.first else { return }
                                p.move(to: map.view(first))
                                for q in gap.outline.dropFirst() { p.addLine(to: map.view(q)) }
                                p.closeSubpath()
                            }
                            .stroke(Theme.aligned, lineWidth: 3)
                            .shadow(color: Theme.aligned.opacity(0.8), radius: 6)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .contentShape(.rect)
                    .onTapGesture { location in tapped(map.image(location)) }
                }
            }
            reviewPanel
                .padding(16)
        }
    }

    private var reviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if gap != nil {
                Text("Is the outlined gap the window between your nails?")
                    .font(.system(size: 17, weight: .semibold))
                HStack(spacing: 10) {
                    Button("Not the window") { gap = nil; tapNote = "Tap the window on the photo if you can see one." }
                        .buttonStyle(GhostButtonStyle())
                    Button("Yes, that's it") { finish(windowSeen: true) }
                        .buttonStyle(GlowButtonStyle(color: Theme.action))
                }
            } else {
                Text("No window found automatically")
                    .font(.system(size: 17, weight: .semibold))
                Text(tapNote ?? (found.map { $0.indexFingers.count < 2 } == true
                                 ? "The app couldn't find both index fingers in this photo. If you can see a small gap between your nails, tap it. Otherwise retake the photo."
                                 : "If you can see a small gap between your nails, tap it on the photo."))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                Button("There's no gap") { finish(windowSeen: false) }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    // MARK: - Result

    private func done(_ seen: Bool) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("BETA · EXPERIMENTAL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                HStack(spacing: 10) {
                    Circle().fill(seen ? Theme.aligned : Theme.adjusting).frame(width: 12, height: 12)
                    Text(seen ? "Window seen" : "No window seen")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(seen ? Theme.aligned : Theme.adjusting)
                }
                Text(seen
                     ? "A small gap between the nail beds is the usual finding (Schamroth, 1976)."
                     : "In clubbing the window disappears (Schamroth, 1976). It also closes if the fingertips aren't pressed nail to nail at the last joint, or if the photo isn't taken from the side. Try again; if it stays closed, mention it to your doctor along with your clubbing scan.")
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
                if seen, let gap, let thickness = found?.fingerWidth {
                    Text(String(format: "The window is about %.0f%% of your fingertip's thickness long.", gap.length / thickness * 100))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                Text("This check is experimental and hasn't been tested on enough people to know how often it's right.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .glassCard(cornerRadius: 24)
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Button("Done") { dismiss() }
                .buttonStyle(GlowButtonStyle(color: Theme.action))
            SafetyNote()
        }
    }

    // MARK: - Actions

    private func use(_ image: UIImage) {
        let prepared = NailCheckView.prepared(image, maxSide: 2400)
        photo = prepared
        gap = nil
        tapNote = nil
        stage = .analyzing
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.pixelBuffer(prepared).map { SchamrothFinder.find(in: $0) }
            DispatchQueue.main.async {
                found = result
                gap = result?.window
                stage = .review
            }
        }
    }

    private func tapped(_ point: CGPoint) {
        guard let photo, let cg = photo.cgImage, let rgba = RGBAImage(cg) else { return }
        let reach = (found?.fingerWidth ?? min(photo.size.width, photo.size.height) * 0.1) * 1.5
        if let traced = SchamrothFinder.traceTapped(rgba, at: point, reach: reach) {
            gap = traced
            tapNote = nil
        } else {
            gap = nil
            tapNote = "That spot isn't a closed gap. Tap inside the gap between your nails, or tap \"There's no gap\"."
        }
    }

    private func finish(windowSeen: Bool) {
        withAnimation(.easeInOut(duration: 0.3)) { stage = .done(windowSeen: windowSeen) }
    }

    private func reset() {
        photo = nil
        found = nil
        gap = nil
        tapNote = nil
        stage = .start
    }

    static func pixelBuffer(_ image: UIImage) -> CVPixelBuffer? {
        guard let cg = image.cgImage else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, cg.width, cg.height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
        guard let buffer else { return nil }
        CIContext().render(CIImage(cgImage: cg), to: buffer)
        return buffer
    }
}

/// The photo fitted into a frame: image pixels to screen points and back.
private struct Fit {
    let scale: CGFloat
    let origin: CGPoint
    let size: CGSize

    init(image: CGSize, in frame: CGSize) {
        scale = min(frame.width / max(image.width, 1), frame.height / max(image.height, 1))
        size = CGSize(width: image.width * scale, height: image.height * scale)
        origin = CGPoint(x: (frame.width - size.width) / 2, y: (frame.height - size.height) / 2)
    }

    func view(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    func image(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }
}

/// Two fingertips pressed nail to nail, with the window between them.
struct SchamrothPoseDrawing: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 300, size.height / 200)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width / 2 + (x - 150) * s, y: y * s) }
            for mirror in [false, true] {
                func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { mirror ? p(300 - x, y) : p(x, y) }
                var finger = Path()
                finger.move(to: q(60, 200)); finger.addLine(to: q(60, 80))
                finger.addQuadCurve(to: q(118, 22), control: q(62, 26))
                // The inner edge touches the other finger above and below the window.
                finger.addQuadCurve(to: q(150, 52), control: q(147, 20))
                finger.addLine(to: q(150, 70)); finger.addLine(to: q(141, 95)); finger.addLine(to: q(150, 120))
                finger.addLine(to: q(150, 200)); finger.closeSubpath()
                ctx.fill(finger, with: .color(.primary.opacity(0.18)))
                ctx.stroke(finger, with: .color(.primary.opacity(0.7)), lineWidth: 2)
            }
            var window = Path()
            window.move(to: p(150, 70)); window.addLine(to: p(141, 95)); window.addLine(to: p(150, 120))
            window.addLine(to: p(159, 95)); window.closeSubpath()
            ctx.stroke(window, with: .color(Theme.aligned), lineWidth: 2.5)
        }
        .accessibilityLabel("Two fingertips pressed nail to nail with a small diamond-shaped gap between them")
    }
}

/// The camera for the window test: a shutter for someone else to press, or
/// a spoken 3-2-1 timer with the phone on a stand. No automatic shutter.
struct SchamrothCameraView: View {
    enum Mode: String, Identifiable {
        case timer, helper
        var id: String { rawValue }
    }

    let mode: Mode
    let onPhoto: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraManager()
    @State private var voice = VoiceCoach()
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.permissionGranted {
                CameraPreviewView(session: camera.session).ignoresSafeArea()
            } else if camera.permissionDenied {
                Text("Camera access is off. Turn it on in Settings → Nail Vitals → Camera.")
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(32)
            }
            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .contentTransition(.numericText())
            }
            VStack {
                HStack {
                    Button { cancel(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.horizontal, 20)
                Spacer()
                Text(mode == .timer
                     ? "Stand the phone up, fingertips nail to nail, side on, in the frame. Tap Start: the photo is taken after 3, 2, 1."
                     : "Fingertips nail to nail, side on, close to the camera. Tap the button.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 20)
                Button(action: shoot) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.85), lineWidth: 4)
                        if mode == .timer {
                            Text(countdown == nil ? "Start" : "Stop")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                        } else {
                            Circle().fill(Color.white).padding(8)
                        }
                    }
                    .frame(width: 78, height: 78)
                }
                .accessibilityLabel(mode == .timer ? (countdown == nil ? "Start the timer" : "Stop the timer") : "Take the photo")
                .padding(.vertical, 24)
            }
        }
        .onAppear {
            camera.autoCaptureAllowed = false
            camera.checkPermissionAndStart()
        }
        .onDisappear {
            cancel()
            camera.stop()
        }
        .onChange(of: camera.capturedPixelBuffer != nil) { _, has in
            guard has, let buffer = camera.capturedPixelBuffer else { return }
            let ci = CIImage(cvPixelBuffer: buffer)
            if let cg = CIContext().createCGImage(ci, from: ci.extent) {
                onPhoto(UIImage(cgImage: cg))
            }
            camera.resetCapture()
        }
    }

    private func shoot() {
        guard mode == .timer else { camera.capturePhoto(); return }
        if countdownTask != nil { cancel(); return }
        countdownTask = Task {
            for n in [3, 2, 1] {
                withAnimation { countdown = n }
                voice.speak("\(n)")
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            countdown = nil
            countdownTask = nil
            // No buzz here: a buzz while the photo is taken can blur it.
            camera.capturePhoto()
        }
    }

    private func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        voice.stop()
    }
}
