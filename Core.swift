// Samotnik — wspólne elementy: kolory, rysowanie, dźwięk i model planszy.

import Cocoa
import SpriteKit
import AVFoundation
import os

// MARK: - Kolory i pomocnicze

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let accent = NSColor(srgbRed: 0.49, green: 0.72, blue: 0.70, alpha: 1)

func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)!
}

func makeImage(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

func makeTexture(_ w: CGFloat, _ h: CGFloat, _ draw: (CGContext) -> Void) -> SKTexture {
    let t = SKTexture(cgImage: makeImage(Int(w.rounded(.up)), Int(h.rounded(.up)), draw))
    t.filteringMode = .linear
    return t
}

func drawMarble(_ ctx: CGContext, d: CGFloat, white: Bool, at o: CGPoint = .zero) {
    ctx.saveGState()
    ctx.translateBy(x: o.x, y: o.y)
    ctx.addEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
    ctx.clip()
    let body = white
        ? [rgb(0xFBFAF7), rgb(0xE7E4DE), rgb(0xBDB9B2), rgb(0x86827C)]
        : [rgb(0x5C6470), rgb(0x2B3038), rgb(0x15181C), rgb(0x07080A)]
    ctx.drawRadialGradient(gradient(body, [0, 0.35, 0.78, 1]),
                           startCenter: CGPoint(x: d * 0.36, y: d * 0.66), startRadius: 0,
                           endCenter: CGPoint(x: d * 0.5, y: d * 0.5), endRadius: d * 0.62,
                           options: [.drawsAfterEndLocation])
    // odbite światło od dołu (półksiężyc)
    let rim = white ? rgb(0xFFFFFF, 0.30) : rgb(0x8FA6C4, 0.38)
    ctx.drawRadialGradient(gradient([rgb(0, 0), rim], [0, 1]),
                           startCenter: CGPoint(x: d * 0.45, y: d * 0.57), startRadius: d * 0.40,
                           endCenter: CGPoint(x: d * 0.5, y: d * 0.5), endRadius: d * 0.5, options: [])
    // odblask
    let spec: CGFloat = white ? 0.95 : 0.55
    ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, spec), rgb(0xFFFFFF, 0)], [0, 1]),
                           startCenter: CGPoint(x: d * 0.35, y: d * 0.70), startRadius: 0,
                           endCenter: CGPoint(x: d * 0.35, y: d * 0.70), endRadius: d * 0.17, options: [])
    ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, spec), rgb(0xFFFFFF, 0)], [0, 1]),
                           startCenter: CGPoint(x: d * 0.33, y: d * 0.72), startRadius: 0,
                           endCenter: CGPoint(x: d * 0.33, y: d * 0.72), endRadius: d * 0.05, options: [])
    ctx.restoreGState()
}

func plural(_ n: Int) -> String {
    if n == 1 { return "kulka" }
    let m10 = n % 10, m100 = n % 100
    return (2...4).contains(m10) && !(12...14).contains(m100) ? "kulki" : "kulek"
}

func remained(_ n: Int) -> String {
    if n == 1 { return "Została 1 kulka" }
    let m10 = n % 10, m100 = n % 100
    let verb = (2...4).contains(m10) && !(12...14).contains(m100) ? "Zostały" : "Zostało"
    return "\(verb) \(n) \(plural(n))"
}

func midi(_ n: Double) -> Double { 440 * pow(2, (n - 69) / 12) }

// MARK: - Dźwięk

struct Voice {
    var freq = 0.0, amp = 0.0, decay = 1.0, pan = 0.5, harm = 0.0, delay = 0.0
    var music = false
    var start = 0.0, active = false
}

final class Audio {
    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var source: AVAudioSourceNode?
    private let pending = OSAllocatedUnfairLock<[Voice]>(initialState: [])

    var musicOn = true
    var musicFade = 0.00003         // tempo narastania i wyciszania muzyki
    var musicLevel = 1.0
    private var t = 0.0, dt = 1.0 / 48000
    private var voices = [Voice](repeating: Voice(), count: 32)
    private var nextChime = 4.0
    private var musicGain = 0.0

    // Dmaj9 → Bm7 → Gmaj7 → Aadd9, niski rejestr
    private let chords: [[Double]] = [[50, 57, 61, 64, 66], [47, 54, 57, 61, 62], [43, 50, 54, 57, 59], [45, 52, 57, 59, 61]]
        .map { $0.map(midi) }
    let pentatonic: [Double] = [74, 76, 78, 81, 83, 86, 88]

    init() {
        let outRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let sr = outRate > 0 ? outRate : 48000
        dt = 1 / sr
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let src = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frames, abl in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            let l = bufs[0].mData!.assumingMemoryBound(to: Float.self)
            let r = bufs.count > 1 ? bufs[1].mData!.assumingMemoryBound(to: Float.self) : l
            self.render(Int(frames), l, r)
            return noErr
        }
        source = src
        engine.attach(src)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 48
        engine.connect(src, to: reverb, format: fmt)
        engine.connect(reverb, to: engine.mainMixerNode, format: fmt)
        try? engine.start()
    }

    func play(_ v: Voice) { pending.withLock { $0.append(v) } }

    func tone(_ note: Double, amp: Double, decay: Double, harm: Double = 0.25, pan: Double = 0.5, delay: Double = 0) {
        play(Voice(freq: midi(note), amp: amp, decay: decay, pan: pan, harm: harm, delay: delay))
    }

    private func add(_ v: Voice) {
        var v = v
        v.start = t + v.delay
        v.active = true
        let slot = voices.firstIndex { !$0.active } ?? 0
        voices[slot] = v
    }

    private func render(_ frames: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>) {
        let incoming = pending.withLock { v -> [Voice] in let p = v; v.removeAll(); return p }
        for v in incoming { add(v) }
        let target = musicOn ? musicLevel : 0.0
        let fade = musicFade
        let twoPi = 2 * Double.pi
        let seg = 12.0

        for i in 0..<frames {
            musicGain += (target - musicGain) * fade
            var L = 0.0, R = 0.0

            if musicGain > 0.0005 {
                // dwa nakładające się akordy, płynne przenikanie (sin² + cos² = 1)
                let k = Int(t / seg)
                for c in max(0, k - 1)...k {
                    let e = sin(Double.pi * (t - Double(c) * seg) / (2 * seg))
                    let env = e * e * musicGain
                    let chord = chords[c % chords.count]
                    for (j, f) in chord.enumerated() {
                        let jd = Double(j)
                        let trem = 0.7 + 0.3 * sin(twoPi * (0.04 + 0.013 * jd) * t + jd * 1.7)
                        let s = sin(twoPi * f * t) + 0.55 * sin(twoPi * f * 1.0032 * t + 0.6) + 0.1 * sin(twoPi * 2 * f * t)
                        let a = s * env * trem * 0.022
                        let pan = 0.2 + 0.6 * jd / Double(chord.count - 1)
                        L += a * (1 - pan); R += a * pan
                    }
                }
                if t >= nextChime {
                    let n = pentatonic[Int.random(in: 0..<pentatonic.count)] - (Bool.random() ? 12 : 0)
                    add(Voice(freq: midi(n), amp: 0.035, decay: 2.4, pan: .random(in: 0.15...0.85), harm: 0.15, music: true))
                    nextChime = t + .random(in: 2.5...7)
                }
            }

            for v in 0..<voices.count where voices[v].active {
                let vo = voices[v]
                let age = t - vo.start
                if age < 0 { continue }
                let env = exp(-age / vo.decay) * min(1, age * 250)
                if age > 0.05 && env < 0.0003 { voices[v].active = false; continue }
                var s = sin(twoPi * vo.freq * age) + vo.harm * sin(twoPi * 2.003 * vo.freq * age) * exp(-age * 4)
                s *= env * vo.amp * (vo.music ? musicGain : 1)
                L += s * (1 - vo.pan); R += s * vo.pan
            }

            t += dt
            l[i] = Float(tanh(L * 1.2))
            r[i] = Float(tanh(R * 1.2))
        }
    }
}

// MARK: - Model

struct Pos: Hashable, Codable {
    let r: Int, c: Int
    static func + (a: Pos, b: Pos) -> Pos { Pos(r: a.r + b.r, c: a.c + b.c) }
    static let dirs = [Pos(r: 0, c: 1), Pos(r: 1, c: 0), Pos(r: 0, c: -1), Pos(r: -1, c: 0)]
}

struct Move { let from: Pos, over: Pos, to: Pos, jumped: Int }

