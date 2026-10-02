//
//  VoiceCoach.swift
//  NailVitals
//
//  Short spoken cues while framing, so nobody has to read the screen with
//  a finger held up: "Move closer", "Turn your finger fully sideways", "Hold
//  still", "Got it". Speaks only when the advice changes, at most one cue
//  every 2.5 seconds (the "hold your finger up" reminder every 6), and can be
//  muted from the camera screen's menu.
//
//  Each cue plays a recording of a real voice when the app has one
//  (Voice/voice-<cue>.m4a, recorded by the team), and otherwise falls back
//  to the most natural voice installed on the phone (Premium, then
//  Enhanced). Recordings of Apple's Mac voices can't ship in the app (their
//  license is personal use only), so every clip must be the team's own.
//

@preconcurrency import AVFoundation

final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    /// Everything the coach says.
    enum Cue: String, CaseIterable {
        case noFinger = "no-finger"
        case moveCloser = "move-closer"
        case moveBack = "move-back"
        case moveLeft = "move-left"
        case moveRight = "move-right"
        case moveUp = "move-up"
        case moveDown = "move-down"
        case straighten = "straighten"
        case turnSideways = "turn-sideways"
        case holdStill = "hold-still"
        case gotIt = "got-it"

        var phrase: String {
            switch self {
            case .noFinger: return "Hold your index finger up, side on, inside the frame."
            case .moveCloser: return "Move closer."
            case .moveBack: return "Move back."
            case .moveLeft: return "Move left."
            case .moveRight: return "Move right."
            case .moveUp: return "Move up."
            case .moveDown: return "Move down."
            case .straighten: return "Straighten your finger."
            case .turnSideways: return "Turn your finger fully sideways."
            case .holdStill: return "Hold still."
            case .gotIt: return "Got it."
            }
        }

        init?(_ direction: GuidanceDirection) {
            switch direction {
            case .noFingerDetected: self = .noFinger
            case .moveCloser: self = .moveCloser
            case .moveBack: self = .moveBack
            case .moveLeft: self = .moveLeft
            case .moveRight: self = .moveRight
            case .moveUp: self = .moveUp
            case .moveHandDown: self = .moveDown
            case .straighten: self = .straighten
            case .turnToSide: self = .turnSideways
            case .looksGood: self = .holdStill
            }
        }

        /// The team's recording of this cue, if the app has one.
        var clipURL: URL? {
            Bundle.main.url(forResource: "voice-\(rawValue)", withExtension: "m4a")
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var lastCue: Cue?
    private var lastSpokenAt = Date.distantPast
    private var categorySet = false
    private lazy var voice = Self.bestVoice()

    /// Relative to the phone's volume: quieter than full so cues don't jump out.
    private let volume: Float = 0.6

    private let minGap: TimeInterval = 2.5
    private let reminderGap: TimeInterval = 6

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Says the cue for the current advice if it's new and enough time
    /// has passed.
    func update(_ direction: GuidanceDirection?) {
        guard let direction, let cue = Cue(direction) else { return }
        let gap = cue == .noFinger ? reminderGap : minGap
        guard Date().timeIntervalSince(lastSpokenAt) >= gap, cue != lastCue || cue == .noFinger else { return }
        say(cue)
    }

    /// Says the cue right away, cutting off anything in progress.
    func say(_ cue: Cue) {
        stop()
        prepareAudio()
        if let url = cue.clipURL, let clip = try? AVAudioPlayer(contentsOf: url) {
            clip.delegate = self
            clip.volume = volume
            clip.play()
            player = clip
        } else {
            let utterance = AVSpeechUtterance(string: cue.phrase)
            utterance.voice = voice
            utterance.volume = volume
            // Natural voices sound best near their own pace; the basic ones
            // a touch quicker.
            let natural = (voice?.quality ?? .default) != .default
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (natural ? 1.0 : 1.05)
            synthesizer.speak(utterance)
        }
        lastCue = cue
        lastSpokenAt = Date()
    }

    func stop() {
        player?.stop()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// Plays over other audio briefly (ducking it), even with the ringer
    /// switch on silent, since the cues are the point of turning this on.
    private func prepareAudio() {
        if !categorySet {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            categorySet = true
        }
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
    }

    /// After each cue, other audio (music, a video) comes back to full volume.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// The most natural English voice on this phone: Premium, then Enhanced,
    /// preferring the phone's own region (US, UK, ...). Skips novelty and
    /// Personal Voice voices. nil = the system default.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let region = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en")
                && !$0.voiceTraits.contains(.isNoveltyVoice)
                && !$0.voiceTraits.contains(.isPersonalVoice)
                && $0.quality != .default
        }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            (v.quality == .premium ? 2 : 1) * 10 + (v.language == region ? 1 : 0)
        }
        return candidates.max { rank($0) < rank($1) }
    }
}
