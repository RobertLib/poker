import AVFoundation
import Foundation

// MARK: - Sound Effects

nonisolated enum SoundEffect: CaseIterable, Sendable {
    case shuffle      // new hand
    case deal         // card dealt
    case flip         // card revealed
    case chipsSmall   // bet / call
    case chipsBig     // pot won
    case check        // knuckle knock
    case fold         // soft swish
    case allIn        // dramatic hit
    case yourTurn     // gentle ding
    case win          // arpeggio up
    case lose         // sad descend
    case levelUp      // blinds increased
    case victory      // game won fanfare
}

/// Fully procedural sound engine — every effect is synthesized on first use,
/// so the game ships with zero audio assets.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private let engine = AVAudioEngine()
    private var playerPool: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private let sampleRate: Double = 44_100
    private var started = false
    /// Kept so the graph can be rebuilt after the hardware changes underneath
    /// it; see `wireUp`.
    private var format: AVAudioFormat?

    private init() {}

    func prepare() {
        guard !started else { return }
        started = true

        activateSession()

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        self.format = format
        for _ in 0..<8 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            playerPool.append(node)
        }
        wireUp(format)

        // Plugging in headphones — or unplugging them, or a call ending — hands
        // the engine a different output and tears its connections to the mixer
        // down on the way. It does not put them back, and it does not restart:
        // without this the table simply goes quiet for the rest of the session,
        // and `play`'s own `engine.start()` cannot help because the graph it
        // would start is no longer connected to anything.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil) { [weak self] _ in
                Task { @MainActor in self?.rebuildGraph() }
            }

        // A phone call or Siri is the other way the audio goes away, and it is
        // not the same failure: the system deactivates the *session* underneath
        // a graph that is still wired up correctly. `.ended` is the only cue the
        // app gets to take it back, and `play`'s `engine.start()` cannot stand
        // in for it — starting an engine over a deactivated session is silence.
        // Reactivating is safe whether or not `.shouldResume` is set, because
        // nothing here starts playing: the category is `.ambient` with
        // `.mixWithOthers`, so it takes no audio away from whatever interrupted.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw.flatMap(AVAudioSession.InterruptionType.init) == .ended else { return }
                Task { @MainActor in self?.rebuildGraph() }
            }

        // Building five seconds of audio is a few hundred thousand sine
        // evaluations — far too much to do while the table is appearing. The
        // waveforms are computed off the main actor and installed as they land;
        // until then `play` simply finds no buffer and stays quiet.
        let rate = sampleRate
        Task.detached(priority: .userInitiated) {
            let waveforms = SoundSynth.renderAll(sampleRate: rate)
            await MainActor.run { [weak self] in
                self?.install(waveforms, format: format)
            }
        }
    }

    private func activateSession() {
        // `.ambient` so the ring/silent switch still silences the game and
        // whatever the player already had on keeps playing.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Connects every player node to the mixer and starts the engine. Safe to
    /// call again on a graph that is already wired — `connect` replaces the
    /// existing connection rather than adding a second one.
    private func wireUp(_ format: AVAudioFormat) {
        for node in playerPool {
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = 0.85
        try? engine.start()
    }

    /// Recovers from an output change or an ended interruption. The synthesized
    /// buffers survive both — they are plain 44.1 kHz mono and the mixer
    /// converts — so only the connections and the session need putting back.
    /// Doing both either way is deliberate: each half is a no-op on the failure
    /// that did not need it, and that is cheaper than telling them apart.
    private func rebuildGraph() {
        guard started, let format else { return }
        activateSession()
        wireUp(format)
    }

    private func install(_ waveforms: [SoundEffect: [Float]], format: AVAudioFormat) {
        for (effect, samples) in waveforms {
            guard !samples.isEmpty,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData else { continue }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                channel[0].update(from: source.baseAddress!, count: samples.count)
            }
            buffers[effect] = buffer
        }
    }

    func play(_ effect: SoundEffect) {
        guard SettingsStore.shared.soundEnabled, started else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning, let buffer = buffers[effect] else { return }

        let node = playerPool[nextPlayer]
        nextPlayer = (nextPlayer + 1) % playerPool.count
        node.stop()
        node.scheduleBuffer(buffer, at: nil)
        node.play()
    }

}

// MARK: - Synthesis

/// Pure waveform maths, deliberately free of any actor so it can run off the
/// main thread while the game is starting.
nonisolated struct SoundSynth {

    let sampleRate: Double

    static func renderAll(sampleRate: Double) -> [SoundEffect: [Float]] {
        let synth = SoundSynth(sampleRate: sampleRate)
        return SoundEffect.allCases.reduce(into: [:]) { result, effect in
            result[effect] = synth.samples(for: effect)
        }
    }

    /// One effect's waveform, soft-clipped exactly once.
    ///
    /// The clip belongs here rather than in `mix` because several effects mix a
    /// mix — `.allIn` layers `clinks`, which layers its own tones — and clipping
    /// per mix squashed those twice, costing them 0.85 of their level for each
    /// nesting level and flattening the transients that make a chip sound like a
    /// chip.
    func samples(for effect: SoundEffect) -> [Float] {
        softClip(rawSamples(for: effect))
    }

    private func rawSamples(for effect: SoundEffect) -> [Float] {
        let samples: [Float]
        switch effect {
        case .shuffle:
            samples = mix(
                noiseBurst(duration: 0.28, attack: 0.02, decay: 4.5, gain: 0.16, brightness: 0.55),
                delay(noiseBurst(duration: 0.22, attack: 0.015, decay: 5.5, gain: 0.13, brightness: 0.6), by: 0.10))
        case .deal:
            samples = noiseBurst(duration: 0.09, attack: 0.004, decay: 26, gain: 0.22, brightness: 0.8)
        case .flip:
            samples = mix(
                noiseBurst(duration: 0.045, attack: 0.002, decay: 60, gain: 0.18, brightness: 0.9),
                tone(frequency: 1350, duration: 0.05, decay: 55, gain: 0.06))
        case .chipsSmall:
            samples = clinks(count: 3, baseGain: 0.16)
        case .chipsBig:
            samples = clinks(count: 7, baseGain: 0.18)
        case .check:
            samples = mix(
                tone(frequency: 155, duration: 0.09, decay: 30, gain: 0.55),
                noiseBurst(duration: 0.02, attack: 0.001, decay: 90, gain: 0.12, brightness: 0.4))
        case .fold:
            samples = noiseBurst(duration: 0.12, attack: 0.015, decay: 18, gain: 0.10, brightness: 0.35)
        case .allIn:
            samples = mix(
                tone(frequency: 110, duration: 0.4, decay: 7, gain: 0.5),
                tone(frequency: 220, duration: 0.35, decay: 8, gain: 0.25),
                delay(clinks(count: 8, baseGain: 0.14), by: 0.06))
        case .yourTurn:
            samples = mix(
                tone(frequency: 880, duration: 0.25, decay: 11, gain: 0.12),
                tone(frequency: 1760, duration: 0.2, decay: 14, gain: 0.05))
        case .win:
            samples = arpeggio(frequencies: [523.25, 659.25, 783.99], noteLength: 0.11, gain: 0.20)
        case .lose:
            samples = arpeggio(frequencies: [392, 311.1], noteLength: 0.22, gain: 0.16)
        case .levelUp:
            samples = arpeggio(frequencies: [587.3, 880], noteLength: 0.14, gain: 0.15)
        case .victory:
            samples = arpeggio(frequencies: [523.25, 659.25, 783.99, 1046.5, 1318.5],
                               noteLength: 0.15, gain: 0.22)
        }

        return samples
    }

    // MARK: Building blocks

    func tone(frequency: Double, duration: Double, decay: Double, gain: Double,
                      harmonics: [Double] = [1.0, 0.28, 0.12]) -> [Float] {
        let count = Int(duration * sampleRate)
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = exp(-decay * t) * min(t / 0.004, 1)
            var value = 0.0
            for (index, amplitude) in harmonics.enumerated() {
                value += amplitude * sin(2 * .pi * frequency * Double(index + 1) * t)
            }
            result[i] = Float(value * envelope * gain)
        }
        return result
    }

    func noiseBurst(duration: Double, attack: Double, decay: Double,
                            gain: Double, brightness: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        var result = [Float](repeating: 0, count: count)
        var rng = SplitMix64(seed: 0xBADC0FFEE)
        var previous: Double = 0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = min(t / max(attack, 0.0001), 1) * exp(-decay * t)
            let white = Double(rng.next() % 20001) / 10000.0 - 1.0
            // One-pole filter: brightness 1 = white noise, 0 = heavily lowpassed.
            previous = brightness * white + (1 - brightness) * previous
            result[i] = Float(previous * envelope * gain)
        }
        return result
    }

    func clinks(count: Int, baseGain: Double) -> [Float] {
        var rng = SplitMix64(seed: 0xC115C115)
        var layers: [[Float]] = []
        for i in 0..<count {
            let frequency = 2900.0 + Double(rng.next() % 1600)
            let clink = mix(
                tone(frequency: frequency, duration: 0.06, decay: 70, gain: baseGain,
                     harmonics: [1.0, 0.42, 0.2, 0.1]),
                tone(frequency: frequency * 1.503, duration: 0.05, decay: 85, gain: baseGain * 0.4))
            layers.append(delay(clink, by: Double(i) * 0.035 + Double(rng.next() % 12) / 1000))
        }
        return mix(layers)
    }

    func arpeggio(frequencies: [Double], noteLength: Double, gain: Double) -> [Float] {
        var layers: [[Float]] = []
        for (i, frequency) in frequencies.enumerated() {
            let note = tone(frequency: frequency, duration: noteLength * 3.2, decay: 5.5, gain: gain,
                            harmonics: [1.0, 0.18, 0.06])
            layers.append(delay(note, by: Double(i) * noteLength))
        }
        return mix(layers)
    }

    // MARK: Combinators

    func delay(_ samples: [Float], by seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate)) + samples
    }

    func mix(_ layers: [Float]...) -> [Float] {
        mix(layers)
    }

    /// Sums layers, longest wins. Deliberately does *not* clip — see `samples(for:)`.
    func mix(_ layers: [[Float]]) -> [Float] {
        let length = layers.map(\.count).max() ?? 0
        var result = [Float](repeating: 0, count: length)
        for layer in layers {
            for (i, sample) in layer.enumerated() { result[i] += sample }
        }
        return result
    }

    /// Bounds the waveform to ±0.85 with a soft knee, so a busy layering
    /// distorts gracefully rather than wrapping around.
    func softClip(_ samples: [Float]) -> [Float] {
        samples.map { Float(tanh(Double($0) * 1.2)) * 0.85 }
    }
}

// MARK: - Haptics

#if canImport(UIKit)
import UIKit

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()

    /// Spins the Taptic Engine up ahead of feedback the app can see coming, so
    /// the first tap is not the late one — a cold generator answers a few
    /// milliseconds behind a warm one, which is exactly long enough to read as
    /// the button having missed the touch.
    ///
    /// Called where something is about to be tapped rather than once at launch:
    /// the prepared state lapses after a second or two on its own, so priming
    /// early would have gone cold again by the time it mattered. All four are
    /// primed together because the anticipated event is a *screen* — the menu,
    /// the table, your turn — and each of those mixes several of them.
    static func prepare() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        light.prepare()
        medium.prepare()
        heavy.prepare()
        notify.prepare()
    }

    static func tap() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        light.impactOccurred(intensity: 0.7)
    }

    static func chips() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        medium.impactOccurred(intensity: 0.8)
    }

    static func heavyHit() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        heavy.impactOccurred()
    }

    static func success() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        notify.notificationOccurred(.success)
    }

    static func warning() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        notify.notificationOccurred(.warning)
    }
}
#endif
