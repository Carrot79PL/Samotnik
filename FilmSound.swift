import AVFoundation

/// Oprawa dźwiękowa wersji filmowej (synteza na żywo):
/// pióro (szelest + ziarno papieru + stuknięcie stalówki), szum pomieszczenia, ambientowy akord,
/// przelot kamery (whoosh), niski akcent przy odsłonięciu, „plum” kleksa, połysk przy przejeździe światła.
final class TMIFilmSound {
    let engine = AVAudioEngine()
    /// [0] głośność pióra, [1] prędkość 0…1, [2] koniec pisania (s), [3] wyciszenie 0…1, [4] licznik przyłożeń, [5] pan -1…1, [6] reset zegara, [7] długość intra
    let p = UnsafeMutablePointer<Float>.allocate(capacity: 8)
    private var running = false
    init() {
        for i in 0..<8 { p[i] = 0 }; p[3] = 1
        let sr: Float = 48000
        let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 2)!
        let P = p
        var seed: UInt32 = 0x9E3779B9
        var clk: Float = 0, gain: Float = 0, spd: Float = 0, pan: Float = 0, outG: Float = 1
        var hp1: Float = 0, hpx: Float = 0, b1l: Float = 0, b1b: Float = 0, b2l: Float = 0, b2b: Float = 0
        var imp: Float = 0, body1: Float = 0, body2: Float = 0, tick: Float = 0, lastTouch: Float = 0
        var room: Float = 0, room2: Float = 0
        var ph = [Float](repeating: 0, count: 8)
        var padL: Float = 0, padR: Float = 0
        var wl: Float = 0, wb: Float = 0, boomPh: Float = 0, plopPh: Float = 0
        var rvL = [Float](repeating: 0, count: 2399), rvR = [Float](repeating: 0, count: 3119), ri = 0, rj = 0
        let notes: [Float] = [73.42, 110.0, 146.83, 220.0, 277.18, 369.99, 440.0, 554.37]   // D2 A2 D3 A3 C#4 F#4 A4 C#5 (Dmaj7/9)
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) * 2 - 1 }
        func ss(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
        let node = AVAudioSourceNode(format: fmt) { _, _, frames, abl in
            let ab = UnsafeMutableAudioBufferListPointer(abl)
            let L = UnsafeMutableBufferPointer<Float>(ab[0]), R = UnsafeMutableBufferPointer<Float>(ab[1])
            if P[6] > 0 { clk = 0; P[6] = 0; boomPh = 0; plopPh = 0 }
            let we = P[2], dur = P[7]
            for i in 0..<Int(frames) {
                clk += 1 / sr
                let n = rnd()
                gain += (P[0] - gain) * 0.0012; spd += (P[1] - spd) * 0.002; pan += (P[5] - pan) * 0.0005; outG += (P[3] - outG) * 0.0008
                // --- pióro: syk papieru (górne pasmo) ---
                hp1 = 0.96 * (hp1 + n - hpx); hpx = n
                let f1 = 2 * sinf(.pi * (3800 + 2600 * spd) / sr)
                b1l += f1 * b1b; let h1 = hp1 - b1l - 0.9 * b1b; b1b += f1 * h1
                // --- ziarno włókien: drobne impulsy, częstsze przy szybszym ruchu ---
                if Float(seed & 0xFFFF) / 65535 < (180 + 900 * spd) / sr { imp = (0.4 + 0.6 * abs(rnd())) }
                imp *= 0.82
                let f2 = 2 * sinf(.pi * (1700 + 900 * spd) / sr)
                b2l += f2 * b2b; let h2 = imp * (0.6 + 0.4 * n) - b2l - 0.35 * b2b; b2b += f2 * h2
                // --- rezonans blatu, stuknięcie przy przyłożeniu stalówki ---
                if P[4] != lastTouch { lastTouch = P[4]; tick = 1 }
                tick *= 0.9935
                body1 += (b2b * 0.3 + tick * n * 0.5 - body1) * 0.03; body2 += (body1 - body2) * 0.03
                let penS = (b1b * 0.22 * (0.4 + spd) + b2b * 0.55 + body2 * 1.2) * gain + tick * tick * (0.5 * b2b + 0.08 * sinf(clk * 2 * .pi * 2100))
                // --- szum pomieszczenia ---
                room += (n - room) * 0.02; room2 += (room - room2) * 0.05
                let roomS = room2 * 0.035
                // --- ambientowy akord: wchodzi powoli, rośnie przy odjeździe kamery ---
                let padA = 0.018 * ss(0.3, 4.0, clk) + 0.05 * ss(we + 0.4, we + 3.2, clk)
                var pl: Float = 0, pr: Float = 0
                for k in 0..<8 { let fr = notes[k] * (1 + 0.0009 * Float(k % 3 - 1))
                    ph[k] += fr / sr; if ph[k] > 1 { ph[k] -= 1 }
                    let x = sinf(ph[k] * 2 * .pi), x2 = sinf(ph[k] * 4 * .pi) * 0.18
                    let trem = 0.75 + 0.25 * sinf(clk * (0.13 + 0.04 * Float(k)) * 2 * .pi + Float(k))
                    let w = (k < 2 ? 0.9 : (k > 5 ? ss(we + 1.0, we + 3.5, clk) * 0.8 : 0.7)) * trem
                    let pk = Float(k) / 7
                    pl += (x + x2) * w * (1 - pk * 0.6); pr += (x + x2) * w * (0.4 + pk * 0.6) }
                padL += (pl - padL) * 0.25; padR += (pr - padR) * 0.25
                // --- przelot kamery: szum z rosnącym filtrem ---
                let wk = ss(we + 0.5, we + 1.6, clk) * (1 - ss(we + 2.2, we + 3.6, clk))
                let fw = 2 * sinf(.pi * (300 + 2600 * ss(we + 0.5, we + 3.4, clk)) / sr)
                wl += fw * wb; let wh = n - wl - 1.1 * wb; wb += fw * wh
                let whoosh = wb * wk * 0.10
                // --- niski akcent przy odsłonięciu logo ---
                let bt = clk - (we + 2.4); var boom: Float = 0
                if bt > 0 && bt < 4 { boomPh += (46 + 20 * expf(-bt * 6)) / sr; boom = sinf(boomPh * 2 * .pi) * expf(-bt * 1.3) * ss(0, 0.04, bt) * 0.22 }
                // --- „plum” kleksa ---
                let pt = clk - (we + 1.92); var plop: Float = 0
                if pt > 0 && pt < 0.5 { plopPh += (240 + 700 * expf(-pt * 28)) / sr; plop = sinf(plopPh * 2 * .pi) * expf(-pt * 16) * 0.045 + n * expf(-pt * 90) * 0.012 }
                // --- połysk przy przejeździe światła ---
                let st = clk - (we + 2.8); var shim: Float = 0
                if st > 0 && st < 2.5 { let e = sinf(.pi * min(st / 1.6, 1)) * expf(-max(st - 1.6, 0) * 3)
                    shim = (sinf(clk * 2 * .pi * 1760) + sinf(clk * 2 * .pi * 2217.5) * 0.7 + sinf(clk * 2 * .pi * 2637) * 0.5) * e * 0.012 * (0.6 + 0.4 * sinf(clk * 37)) }
                // --- miks + prosty pogłos ---
                let endFade = 1 - ss(dur - 1.2, dur - 0.05, clk)
                let dryL = roomS + padL * padA + whoosh * 0.8 + boom + plop * 0.9 + shim
                let dryR = roomS * 0.9 + padR * padA + whoosh + boom + plop + shim * 0.8
                let eL = rvL[ri], eR = rvR[rj]
                rvL[ri] = dryR * 0.35 + eL * 0.55; rvR[rj] = dryL * 0.35 + eR * 0.55
                ri = (ri + 1) % rvL.count; rj = (rj + 1) % rvR.count
                let g = outG * endFade * 0.9
                L[i] = tanhf((dryL + eL * 0.5) * g * 1.2); R[i] = tanhf((dryR + eR * 0.5) * g * 1.2)
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.9
    }
    func start(writeEnd: Float, duration: Float) { p[2] = writeEnd; p[7] = duration; p[6] = 1; p[3] = 1; if !running { try? engine.start(); running = true } }
    func stop() { p[0] = 0; if running { engine.pause(); running = false } }
}
