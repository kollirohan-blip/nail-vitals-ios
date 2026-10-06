//
//  NailCheckView.swift
//  NailVitals
//
//  Nail color check (beta): a photo of the nails from above, and for each
//  nail the user marks, whether it is pale with a darker band at the tip --
//  the pattern of Terry's nails (narrow band; Holzberg & Walker 1984) and
//  half-and-half nails (about half the nail; Lindsay 1967). The user taps
//  the nail's base and where its pink ends; NailColorAnalyzer reads the
//  color in between. The photo stays on screen only: nothing is saved.
//

import PhotosUI
import SwiftUI

/// One nail marked on the photo, in image pixels.
struct MarkedNail: Identifiable {
    let id = UUID()
    var start: CGPoint
    var end: CGPoint
    var pattern = NailColorAnalyzer.NailPattern(kind: .unclear)
}

struct NailCheckView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var photo: UIImage?
    @State private var pixels: RGBAImage?
    @State private var nails: [MarkedNail] = []
    /// The first tap of a new nail, waiting for the second.
    @State private var pendingStart: CGPoint?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var loadError: String?

    // Zoom and pan of the photo.
    @State private var zoom: CGFloat = 1
    @State private var zoomAtStart: CGFloat?
    @State private var pan: CGSize = .zero
    @State private var panAtStart: CGSize?
    /// The dot being dragged (nail index, end dot?), for the magnifier.
    @State private var dragging: (index: Int, end: Bool)?

    private static let maxNails = 6

    var body: some View {
        NavigationStack {
            Group {
                if let photo {
                    marking(photo)
                } else {
                    ScrollView { start.padding(.horizontal, 20).padding(.vertical, 8) }
                }
            }
            .background(AppBackground())
            .navigationTitle("Nail color check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if photo != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New photo") { reset() }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in use(image) }
                .ignoresSafeArea()
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
                Text("Looks for a pale nail with a darker band at the tip")
                    .font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Doctors call this Terry's nails when the band is narrow, and half-and-half nails when it covers about half the nail.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .glassCard(cornerRadius: 24)

            VStack(alignment: .leading, spacing: 12) {
                tip("hand.raised.fingers.spread", "Rest your hand flat, back of the hand up.")
                tip("camera.viewfinder", "Photograph the nails from straight above, close enough that they're big.")
                tip("sun.max", "Daylight or a bright room. No flash, no nail polish.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .glassCard(cornerRadius: 24)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label("Take a photo", systemImage: "camera.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.action)
            }
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

    // MARK: - Marking nails

    private func marking(_ photo: UIImage) -> some View {
        VStack(spacing: 0) {
            Text(instruction)
                .font(.system(size: 15, weight: .medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .animation(nil, value: instruction)
            canvas(photo)
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .clipShape(.rect(cornerRadius: 20))
                .padding(.horizontal, 12)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(nails.enumerated()), id: \.element.id) { index, nail in
                        nailRow(index, nail)
                    }
                    if !nails.isEmpty { summary }
                    SafetyNote()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    private var instruction: String {
        if pendingStart != nil { return "Now tap where the pink ends, just before the white tip." }
        if nails.isEmpty { return "Tap the base of a nail, where it meets the skin. Pinch to zoom." }
        if nails.count >= Self.maxNails { return "Drag the dots to adjust." }
        return "Drag the dots to adjust, or tap another nail's base to add it."
    }

    private func mapping(_ photo: UIImage, in size: CGSize) -> PhotoMapping {
        let fit = min(size.width / photo.size.width, size.height / photo.size.height)
        let scale = fit * zoom
        return PhotoMapping(scale: scale, origin: CGPoint(x: (size.width - photo.size.width * scale) / 2 + pan.width,
                                                     y: (size.height - photo.size.height * scale) / 2 + pan.height))
    }

    private func canvas(_ photo: UIImage) -> some View {
        GeometryReader { geo in
            let map = mapping(photo, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.85)
                // Positioned rather than offset, so a zoomed photo doesn't
                // grow the canvas and shift everything drawn on it.
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: photo.size.width * map.scale, height: photo.size.height * map.scale)
                    .position(x: map.origin.x + photo.size.width * map.scale / 2,
                              y: map.origin.y + photo.size.height * map.scale / 2)
                ForEach(Array(nails.enumerated()), id: \.element.id) { index, nail in
                    NailLine(nail: nail, map: map, number: index + 1)
                    handle(index: index, end: false, at: map.view(nail.start), map: map)
                    handle(index: index, end: true, at: map.view(nail.end), map: map)
                }
                if let pendingStart {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black, lineWidth: 1.5))
                        .frame(width: 11, height: 11)
                        .position(map.view(pendingStart))
                }
                if let dragging, dragging.index < nails.count {
                    let point = dragging.end ? nails[dragging.index].end : nails[dragging.index].start
                    Magnifier(photo: photo, point: point, scale: map.scale * 3)
                        .position(x: point.x * map.scale + map.origin.x < geo.size.width / 2 ? geo.size.width - 70 : 70, y: 70)
                }
                if zoom > 1.01 {
                    Button {
                        withAnimation(.snappy) { zoom = 1; pan = .zero }
                    } label: {
                        Text("1×").font(.system(size: 13, weight: .semibold)).frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .position(x: geo.size.width - 30, y: geo.size.height - 30)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(.rect)
            .gesture(SpatialTapGesture().onEnded { tapped(map.image($0.location), photo: photo) })
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if zoomAtStart == nil { zoomAtStart = zoom; panAtStart = pan }
                        let from = zoomAtStart ?? 1, next = min(8, max(1, from * value.magnification))
                        // Keep the part of the photo under the fingers in place.
                        let fit = min(geo.size.width / photo.size.width, geo.size.height / photo.size.height)
                        let start = panAtStart ?? .zero
                        let x0 = (geo.size.width - photo.size.width * fit * from) / 2 + start.width
                        let y0 = (geo.size.height - photo.size.height * fit * from) / 2 + start.height
                        let anchor = value.startLocation, ratio = next / from
                        pan = CGSize(width: anchor.x - (anchor.x - x0) * ratio - (geo.size.width - photo.size.width * fit * next) / 2,
                                     height: anchor.y - (anchor.y - y0) * ratio - (geo.size.height - photo.size.height * fit * next) / 2)
                        zoom = next
                    }
                    .onEnded { _ in
                        zoomAtStart = nil
                        panAtStart = nil
                        if zoom <= 1.01 { zoom = 1; pan = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard dragging == nil, zoomAtStart == nil, zoom > 1.01 else { return }
                        if panAtStart == nil { panAtStart = pan }
                        pan = CGSize(width: panAtStart!.width + value.translation.width,
                                     height: panAtStart!.height + value.translation.height)
                    }
                    .onEnded { _ in if zoomAtStart == nil { panAtStart = nil } }
            )
        }
    }

    private func handle(index: Int, end: Bool, at point: CGPoint, map: PhotoMapping) -> some View {
        Circle()
            .fill(end ? Color(red: 1, green: 0.45, blue: 0.6) : .white)
            .overlay(Circle().stroke(.black.opacity(0.8), lineWidth: 1.5))
            .frame(width: 11, height: 11)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
            .position(point)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard index < nails.count else { return }
                        dragging = (index, end)
                        let p = map.image(value.location)
                        if end { nails[index].end = p } else { nails[index].start = p }
                        analyze(index)
                    }
                    .onEnded { _ in dragging = nil }
            )
            .accessibilityLabel(end ? "End of nail \(index + 1)" : "Base of nail \(index + 1)")
    }

    private func nailRow(_ index: Int, _ nail: MarkedNail) -> some View {
        let reading = Self.reading(nail.pattern)
        return HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(nail.pattern.kind == .paleWithBand ? Theme.attention : .primary)
                Text(reading.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(role: .destructive) {
                nails.remove(at: index)
            } label: {
                Image(systemName: "trash").font(.system(size: 14))
            }
            .foregroundStyle(Color.primary.opacity(0.5))
            .accessibilityLabel("Remove nail \(index + 1)")
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    static func reading(_ pattern: NailColorAnalyzer.NailPattern) -> (title: String, detail: String) {
        let share = pattern.bandShare.map { "\(Int(($0 * 100).rounded()))%" } ?? ""
        switch pattern.kind {
        case .paleWithBand:
            let narrow = (pattern.bandShare ?? 0) < NailColorAnalyzer.narrowBandShare
            return ("Pale, with a band at the tip",
                    "The band is \(share) of the nail: " + (narrow ? "narrow, like Terry's nails." : "toward half, like half-and-half nails."))
        case .usual:
            return ("Usual color", "Pink, pale only at the base (the half-moon).")
        case .even:
            return ("Even color", "No band at the tip.")
        case .unclear:
            return ("Unclear", "The color changes unevenly. Check the dots, or retake in even light.")
        }
    }

    private var summary: some View {
        let flagged = nails.filter { $0.pattern.kind == .paleWithBand }.count
        return VStack(alignment: .leading, spacing: 10) {
            if flagged > 0 {
                Text("Pattern seen on \(flagged) of \(nails.count) nail\(nails.count == 1 ? "" : "s")")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.attention)
                Text("Terry's-type nails have been linked with liver cirrhosis, heart failure and adult-onset diabetes, and also appear with normal ageing. Half-and-half nails are seen in 20–50% of people with chronic kidney disease.")
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No band pattern on \(nails.count) nail\(nails.count == 1 ? "" : "s")")
                    .font(.system(size: 18, weight: .semibold))
            }
            Text("Nail color in a photo depends on the light, the camera and skin tone. This check is experimental and hasn't been tested on enough people to know how often it's right.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    // MARK: - Actions

    private func use(_ image: UIImage) {
        let upright = Self.prepared(image)
        guard let cg = upright.cgImage, let rgba = RGBAImage(cg) else {
            loadError = "Couldn't open that photo. Try another one."
            return
        }
        loadError = nil
        photo = upright
        pixels = rgba
        nails = []
        pendingStart = nil
        zoom = 1
        pan = .zero
    }

    private func reset() {
        photo = nil
        pixels = nil
        nails = []
        pendingStart = nil
    }

    private func tapped(_ point: CGPoint, photo: UIImage) {
        guard point.x >= 0, point.y >= 0, point.x < photo.size.width, point.y < photo.size.height else { return }
        if let start = pendingStart {
            pendingStart = nil
            guard hypot(point.x - start.x, point.y - start.y) > 8 else { return }
            nails.append(MarkedNail(start: start, end: point))
            analyze(nails.count - 1)
        } else if nails.count < Self.maxNails {
            pendingStart = point
        }
    }

    private func analyze(_ index: Int) {
        guard let pixels, index < nails.count else { return }
        let samples = NailColorAnalyzer.nailProfile(pixels, from: nails[index].start, to: nails[index].end)
        nails[index].pattern = NailColorAnalyzer.pattern(samples)
    }

    /// The photo upright, in sRGB, at most 2048 px on its longer side.
    static func prepared(_ image: UIImage, maxSide: CGFloat = 2048) -> UIImage {
        let shrink = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * shrink).rounded(), height: (image.size.height * shrink).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Image pixels to screen points and back, for the current zoom and pan.
private struct PhotoMapping {
    let scale: CGFloat
    let origin: CGPoint
    func view(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    func image(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }
}

/// A marked nail: white over the pale part, pink over the band, gray dashes
/// over the free edge past the pink (left out of the reading).
private struct NailLine: View {
    let nail: MarkedNail
    let map: PhotoMapping
    let number: Int

    var body: some View {
        let a = map.view(nail.start), b = map.view(nail.end)
        let at = { (t: Double) in CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        let pattern = nail.pattern
        ZStack {
            if let split = pattern.split, let pinkEnd = pattern.pinkEnd,
               pattern.kind == .paleWithBand || pattern.kind == .usual {
                segment(at(0), at(split), .white)
                segment(at(split), at(pinkEnd), Color(red: 1, green: 0.45, blue: 0.6))
                segment(at(pinkEnd), at(1), .gray, dashed: true)
            } else {
                segment(a, b, .white.opacity(0.8), dashed: pattern.kind == .unclear)
            }
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(.white, in: Circle())
                .position(behind(a, from: b))
        }
        .allowsHitTesting(false)
    }

    /// 22 points past `a`, away from `b`: where the nail's number goes.
    private func behind(_ a: CGPoint, from b: CGPoint) -> CGPoint {
        let length = max(1, hypot(b.x - a.x, b.y - a.y))
        return CGPoint(x: a.x - (b.x - a.x) / length * 22, y: a.y - (b.y - a.y) / length * 22)
    }

    private func segment(_ p: CGPoint, _ q: CGPoint, _ color: Color, dashed: Bool = false) -> some View {
        Path { path in path.move(to: p); path.addLine(to: q) }
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: dashed ? [4, 5] : []))
            .shadow(color: .black.opacity(0.6), radius: 1.5)
    }
}

/// The photo around the dragged dot, enlarged, so the finger doesn't hide it.
private struct Magnifier: View {
    let photo: UIImage
    /// The dot, in image pixels.
    let point: CGPoint
    /// Screen points per image pixel inside the magnifier.
    let scale: CGFloat
    private let size: CGFloat = 110

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: photo)
                .resizable()
                .frame(width: photo.size.width * scale, height: photo.size.height * scale)
                .offset(x: size / 2 - point.x * scale, y: size / 2 - point.y * scale)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(.white, lineWidth: 3)
            Image(systemName: "plus").font(.system(size: 18, weight: .light)).foregroundStyle(.white)
        }
        .shadow(radius: 6)
        .allowsHitTesting(false)
    }
}

/// The system camera, for one still photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
