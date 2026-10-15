import AVFoundation
import Foundation
import MPMCore

/// Four short synthesized tones (sound.js, DESIGN §10): tick, start, time's up, stop.
final class Tones {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [SoundKind: AVAudioPCMBuffer] = [:]
    private var reconfigured: NSObjectProtocol?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // The output changed: the engine stopped itself; drop what was queued so the next tone starts clean.
        reconfigured = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.player.stop()
        }
        buffers[.tick] = make([(1320, 0, 0.06)])
        buffers[.start] = make([(523, 0, 0.14), (784, 0.11, 0.18)])
        buffers[.timeup] = make([(880, 0, 0.16), (659, 0.17, 0.22)])
        buffers[.stop] = make([(196, 0, 0.34)])
    }

    /// Sine notes: (frequency, start offset, length), each with a quick attack and an exponential fade.
    private func make(_ notes: [(Double, Double, Double)]) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = notes.map { $0.1 + $0.2 + 0.03 }.max() ?? 0.1
        let frames = AVAudioFrameCount(total * rate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        for i in 0..<Int(frames) { data[i] = 0 }
        for (freq, at, len) in notes {
            let start = Int(at * rate), n = Int(len * rate)
            let attack = 0.012 * rate
            for j in 0..<n where start + j < Int(frames) {
                let t = Double(j) / rate
                let env: Double = Double(j) < attack ? Double(j) / attack : pow(0.0001 / 1.0, (Double(j) - attack) / (Double(n) - attack))
                data[start + j] += Float(0.07 * env * sin(2 * .pi * freq * t))
            }
        }
        return buf
    }

    func play(_ kind: SoundKind, muted: Bool) {
        guard !muted, let buf = buffers[kind] else { return }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
