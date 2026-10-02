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
//  Uses the most natural English voice installed on the phone (Premium,
//  then Enhanced, then the default) at a softer volume. Premium voices are
//  free downloads in Settings > Accessibility > Spoken Content > Voices.
//  The phone's own voices speaking live are fine for a released app;
//  recorded clips of Apple's voices are not (personal use only).
//

@preconcurrency import AVFoundation

final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastPhrase: String?
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

    /// Speaks the cue for the current advice if it's new and enough time
    /// has passed.
    func update(_ direction: GuidanceDirection?) {
        guard let direction, let phrase = Self.phrase(for: direction) else { return }
        let now = Date()
        let gap = direction == .noFingerDetected ? reminderGap : minGap
        guard now.timeIntervalSince(lastSpokenAt) >= gap,
              phrase != lastPhrase || direction == .noFingerDetected else { return }
        speak(phrase)
    }

    /// Speaks right away, cutting off anything in progress.
    func speak(_ phrase: String) {
        prepareAudio()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voice
        utterance.volume = volume
        // Natural voices sound best near their own pace; the basic ones a
        // touch quicker, as before.
        let natural = (voice?.quality ?? .default) != .default
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (natural ? 1.0 : 1.05)
        synthesizer.speak(utterance)
        lastPhrase = phrase
        lastSpokenAt = Date()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
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

    /// The most natural English voice on this phone: Premium, then Enhanced,
    /// preferring the phone's own region (US, UK, ...). Skips novelty and
    /// Personal Voice voices. nil = the system default, as before.
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

    static func phrase(for direction: GuidanceDirection) -> String? {
        switch direction {
        case .noFingerDetected: return "Hold your index finger up, side on, inside the frame."
        case .moveCloser: return "Move closer."
        case .moveBack: return "Move back."
        case .moveLeft: return "Move left."
        case .moveRight: return "Move right."
        case .moveUp: return "Move up."
        case .moveHandDown: return "Move down."
        case .straighten: return "Straighten your finger."
        case .turnToSide: return "Turn your finger fully sideways."
        case .looksGood: return "Hold still."
        }
    }
}
