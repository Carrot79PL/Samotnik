import AVFoundation

/// Proceduralny dźwięk pisania piórem: szum filtrowany pasmowo, którego głośność i jasność
/// zależą od prędkości czubka pióra; drobne „zahaczenia” o papier dają fakturę.
final class TMIPenSound {
    private let engine = AVAudioEngine()
    private let p = UnsafeMutablePointer<Float>.allocate(capacity: 2)   // [0]=cel głośności, [1]=prędkość 0…1
    private var running = false
    init() {
        p[0] = 0; p[1] = 0
        var gain: Float = 0, lp1: Float = 0, lp2: Float = 0, bp: Float = 0, low: Float = 0
        var seed: UInt32 = 0x1234567, ph: Float = 0, grain: Float = 1, grainT: Float = 1
        let sr: Float = 44100
        let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 1)!
        let params = p
        let node = AVAudioSourceNode(format: fmt) { _, _, frames, abl in
            let buf = UnsafeMutableBufferPointer<Float>(UnsafeMutableAudioBufferListPointer(abl)[0])
            for i in 0..<Int(frames) {
                seed = seed &* 1664525 &+ 1013904223
                let n = Float(seed >> 8) / Float(1 << 24) * 2 - 1
                // wygładzanie parametrów
                gain += (params[0] - gain) * 0.0009
                lp1 += (params[1] - lp1) * 0.0015
                // faktura: wolno zmienna „ziarnistość” papieru
                ph += 1 / sr; if ph > 0.011 { ph = 0; grainT = 0.45 + Float((seed >> 5) & 1023) / 1023 * 0.75 }
                grain += (grainT - grain) * 0.02
                // filtr pasmowy (SVF), środek 2,2–5,5 kHz zależnie od prędkości
                let f = 2 * sinf(Float.pi * (2200 + 3300 * lp1) / sr)
                low += f * bp; let high = n - low - 0.55 * bp; bp += f * high
                lp2 += (bp - lp2) * 0.6
                buf[i] = lp2 * gain * grain * 0.9
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.8
    }
    func start() { if !running { try? engine.start(); running = true } }
    func stop() { p[0] = 0; if running { engine.pause(); running = false } }
    /// active 0…1 (czy pióro pisze), speed 0…1
    func update(active: Float, speed: Float) { p[0] = active * (0.12 + 0.30 * speed); p[1] = speed }
}
