//
//  LabelingView.swift
//  NailVitals
//
//  Label mode: a person places the seven HumanLabel points on a saved
//  photo, one at a time, with a magnifier. Blind on purpose -- no app
//  markers, no outline snapping, no numbers -- so the labels are an
//  independent check of the app. The view zooms to the finger using the
//  saved joint positions (framing only; nothing is drawn from them).
//

import SwiftUI

struct LabelingView: View {
    let folder: URL
    let labeler: String

    @Environment(\.dismiss) private var dismiss
    @State private var photo: UIImage?
    @State private var focus: CGRect?          // finger region, full-photo pixels
    @State private var showWholePhoto = false
    @State private var points: [HumanLabel.Point: CGPoint] = [:]  // full-photo pixels
    @State private var step = 0
    @State private var dragging: HumanLabel.Point?
    @State private var grabOffset = CGSize.zero
    @State private var saveError: String?
    @State private var shownImage: Shown?

    private let steps = HumanLabel.Point.allCases
    private let loupeSize: CGFloat = 150
    private let loupeZoom: CGFloat = 3

    private var current: HumanLabel.Point { steps[min(step, steps.count - 1)] }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let shown = shownImage {
                    Image(uiImage: shown.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(drag(viewSize: geo.size))
                    guides(viewSize: geo.size)
                    ForEach(steps.filter { points[$0] != nil }, id: \.self) { p in
                        dot(p, viewSize: geo.size)
                    }
                } else {
                    ProgressView().tint(.white)
                }

                VStack {
                    if let p = dragging, let point = points[p] {
                        loupe(center: point, viewSize: geo.size).padding(.top, 12)
                    } else {
                        instruction.padding(.top, 12)
                    }
                    Spacer()
                    controls.padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("\(step + 1) of \(steps.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(showWholePhoto ? "Zoom to finger" : "Whole photo") {
                    showWholePhoto.toggle()
                    shownImage = makeShown()
                }
                .disabled(focus == nil)
            }
        }
        .task { await load() }
    }

    // MARK: - Pieces

    private var instruction: some View {
        Text(current.instruction)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(14)
            .glassPanel(cornerRadius: 16)
            .padding(.horizontal, 16)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let saveError {
                Text(saveError).font(.system(size: 13)).foregroundColor(Theme.attention)
            }
            Text(points[current] == nil ? "Tap the photo to place \(current.shortName.lowercased()). Drag to adjust." : "Drag any point to adjust it.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
            HStack(spacing: 12) {
                Button("Back") { step -= 1 }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(step == 0)
                if step < steps.count - 1 {
                    Button("Next") { step += 1 }
                        .buttonStyle(GlowButtonStyle(color: Theme.searching))
                        .disabled(points[current] == nil)
                } else {
                    Button("Save", action: save)
                        .buttonStyle(GlowButtonStyle())
                        .disabled(points.count < steps.count)
                }
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 22)
        .padding(.horizontal, 16)
    }

    private func color(_ p: HumanLabel.Point) -> Color {
        switch p {
        case .cuticle: return .pink
        case .nail: return .yellow
        case .skin: return .cyan
        case .crease: return Theme.aligned
        case .freeEdge: return .orange
        case .cuticleAcross, .creaseAcross: return .white
        }
    }

    private func dot(_ p: HumanLabel.Point, viewSize: CGSize) -> some View {
        let isCurrent = p == current
        return ZStack {
            Circle()
                .fill(color(p))
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                .frame(width: isCurrent ? 12 : 9, height: isCurrent ? 12 : 9)
            Text(p.shortName)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color(p))
                .shadow(color: .black, radius: 2)
                .fixedSize()
                .offset(y: -14)
        }
        .position(toView(points[p]!, viewSize))
        .allowsHitTesting(false)
    }

    /// Thin lines between the labeler's own points, to show what they
    /// outline. No values are shown.
    private func guides(viewSize: CGSize) -> some View {
        Path { path in
            func line(_ ids: [HumanLabel.Point]) {
                let ps = ids.compactMap { points[$0] }.map { toView($0, viewSize) }
                guard ps.count == ids.count else { return }
                path.addLines(ps)
            }
            line([.freeEdge, .nail, .cuticle, .skin, .crease])
            line([.cuticle, .cuticleAcross])
            line([.crease, .creaseAcross])
        }
        .stroke(Color.white.opacity(0.7), lineWidth: 1)
        .allowsHitTesting(false)
    }

    private func loupe(center: CGPoint, viewSize: CGSize) -> some View {
        let scale = fit(viewSize).scale * loupeZoom
        let origin = shownImage?.origin ?? .zero
        return ZStack(alignment: .topLeading) {
            if let shown = shownImage {
                Image(uiImage: shown.image)
                    .resizable()
                    .frame(width: shown.image.size.width * scale, height: shown.image.size.height * scale)
                    .offset(x: loupeSize / 2 - (center.x - origin.x) * scale, y: loupeSize / 2 - (center.y - origin.y) * scale)
            }
            Path { path in
                path.move(to: CGPoint(x: loupeSize / 2, y: loupeSize / 2 - 12))
                path.addLine(to: CGPoint(x: loupeSize / 2, y: loupeSize / 2 + 12))
                path.move(to: CGPoint(x: loupeSize / 2 - 12, y: loupeSize / 2))
                path.addLine(to: CGPoint(x: loupeSize / 2 + 12, y: loupeSize / 2))
            }
            .stroke(Color.white, lineWidth: 1)
        }
        .frame(width: loupeSize, height: loupeSize, alignment: .topLeading)
        .clipped()
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 3))
        .shadow(radius: 6)
    }

    // MARK: - Touch

    /// A touch near a placed point drags that point; anywhere else places
    /// (or moves) the current step's point. The finger's offset from the
    /// point is kept so the finger doesn't cover it.
    private func drag(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil {
                    let near = points.filter { $0.key != current }
                        .map { ($0.key, toView($0.value, viewSize)) }
                        .filter { hypot($0.1.x - value.startLocation.x, $0.1.y - value.startLocation.y) < 24 }
                        .min { hypot($0.1.x - value.startLocation.x, $0.1.y - value.startLocation.y)
                            < hypot($1.1.x - value.startLocation.x, $1.1.y - value.startLocation.y) }
                    if let (p, at) = near {
                        dragging = p
                        grabOffset = CGSize(width: at.x - value.startLocation.x, height: at.y - value.startLocation.y)
                    } else {
                        dragging = current
                        if let at = points[current].map({ toView($0, viewSize) }),
                           hypot(at.x - value.startLocation.x, at.y - value.startLocation.y) < 40 {
                            grabOffset = CGSize(width: at.x - value.startLocation.x, height: at.y - value.startLocation.y)
                        } else {
                            grabOffset = .zero
                        }
                    }
                }
                guard let p = dragging else { return }
                let target = CGPoint(x: value.location.x + grabOffset.width, y: value.location.y + grabOffset.height)
                points[p] = toImage(target, viewSize)
                saveError = nil
            }
            .onEnded { _ in dragging = nil }
    }

    // MARK: - Load and save

    private struct Shown {
        let image: UIImage
        let origin: CGPoint  // where the shown image sits in the full photo
    }

    /// The photo as displayed: cropped to the finger unless the whole
    /// photo was asked for. Made once per change, not on every redraw.
    private func makeShown() -> Shown? {
        guard let photo else { return nil }
        guard !showWholePhoto, let focus, let cg = photo.cgImage?.cropping(to: focus.integral) else {
            return Shown(image: photo, origin: .zero)
        }
        return Shown(image: UIImage(cgImage: cg), origin: focus.integral.origin)
    }

    private func load() async {
        let folder = self.folder, labeler = self.labeler
        let loaded = await Task.detached(priority: .userInitiated) { () -> (UIImage?, CGRect?, HumanLabel?) in
            let image = UIImage(contentsOfFile: folder.appendingPathComponent("photo.jpg").path)
            var focus: CGRect?
            if let image,
               let data = try? Data(contentsOf: folder.appendingPathComponent("capture.json")),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tip = json["indexTip"] as? [String: Double], let dip = json["indexDIP"] as? [String: Double],
               let tx = tip["x"], let ty = tip["y"], let dx = dip["x"], let dy = dip["y"] {
                // A box about three tip-to-DIP lengths across, centered
                // between the two joints.
                let length = max(hypot(dx - tx, dy - ty), 50)
                let side = length * 3
                let box = CGRect(x: (tx + dx) / 2 - side / 2, y: (ty + dy) / 2 - side / 2, width: side, height: side)
                let clipped = box.intersection(CGRect(origin: .zero, size: image.size))
                focus = clipped.width > 50 && clipped.height > 50 ? clipped : nil
            }
            return (image, focus, HumanLabelStore.load(in: folder, labeler: labeler))
        }.value
        photo = loaded.0
        focus = loaded.1
        shownImage = makeShown()
        if let existing = loaded.2 {
            for p in steps { if let point = existing.point(p) { points[p] = point } }
        }
    }

    private func save() {
        let label = HumanLabel(labeler: labeler, points: points)
        do {
            try HumanLabelStore.save(label, in: folder)
            dismiss()
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    // MARK: - Coordinates (full photo <-> view)

    private func fit(_ viewSize: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        guard let s = shownImage?.image.size, s.width > 0, s.height > 0 else { return (1, .zero) }
        let scale = min(viewSize.width / s.width, viewSize.height / s.height)
        return (scale, CGPoint(x: (viewSize.width - s.width * scale) / 2, y: (viewSize.height - s.height * scale) / 2))
    }

    private func toView(_ p: CGPoint, _ viewSize: CGSize) -> CGPoint {
        let t = fit(viewSize), o = shownImage?.origin ?? .zero
        return CGPoint(x: (p.x - o.x) * t.scale + t.offset.x, y: (p.y - o.y) * t.scale + t.offset.y)
    }

    private func toImage(_ p: CGPoint, _ viewSize: CGSize) -> CGPoint {
        let t = fit(viewSize), o = shownImage?.origin ?? .zero
        return CGPoint(x: (p.x - t.offset.x) / t.scale + o.x, y: (p.y - t.offset.y) / t.scale + o.y)
    }
}
