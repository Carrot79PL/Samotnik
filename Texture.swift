// Samotnik — proceduralne powierzchnie kul: szum 3D liczony na sferze (bez szwów i ściśnięć przy biegunach).

import Foundation
import CoreGraphics

typealias V3 = SIMD3<Double>

func col(_ hex: UInt32) -> V3 {
    V3(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)) / 255
}
func mix(_ a: V3, _ b: V3, _ t: Double) -> V3 { a + (b - a) * t }
func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = max(0, min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
}
func fract(_ x: Double) -> Double { x - x.rounded(.down) }

/// Barwa z koła barw (h 0…1), do opali i neonów.
func hue(_ h: Double, sat: Double, val: Double) -> V3 {
    let k = V3(5, 3, 1)
    var out = V3.zero
    for i in 0..<3 {
        let n = fract((k[i] / 6) + h) * 6
        out[i] = val - val * sat * max(0, min(min(n, 4 - n), 1))
    }
    return out
}

@inline(__always) func hash3(_ x: Int, _ y: Int, _ z: Int, _ s: UInt64 = 0) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 73856093 ^ y &* 19349663 ^ z &* 83492791)) &+ s &* 0x9E3779B97F4A7C15
    h = (h ^ (h >> 33)) &* 0xFF51AFD7ED558CCD
    h = (h ^ (h >> 33)) &* 0xC4CEB9FE1A85EC53
    h ^= h >> 33
    return Double(h & 0xFFFFFF) / Double(0xFFFFFF)
}

/// Szum wartości 3D, wynik 0…1.
func noise(_ p: V3) -> Double {
    let fx = p.x.rounded(.down), fy = p.y.rounded(.down), fz = p.z.rounded(.down)
    let ix = Int(fx), iy = Int(fy), iz = Int(fz)
    let tx = p.x - fx, ty = p.y - fy, tz = p.z - fz
    let u = tx * tx * (3 - 2 * tx), v = ty * ty * (3 - 2 * ty), w = tz * tz * (3 - 2 * tz)
    func c(_ a: Int, _ b: Int, _ d: Int) -> Double { hash3(ix + a, iy + b, iz + d) }
    let x00 = mix(c(0, 0, 0), c(1, 0, 0), u), x10 = mix(c(0, 1, 0), c(1, 1, 0), u)
    let x01 = mix(c(0, 0, 1), c(1, 0, 1), u), x11 = mix(c(0, 1, 1), c(1, 1, 1), u)
    return mix(mix(x00, x10, v), mix(x01, x11, v), w)
}

func fbm(_ p: V3, _ oct: Int = 4) -> Double {
    var sum = 0.0, amp = 0.5, q = p, norm = 0.0
    for _ in 0..<oct {
        sum += noise(q) * amp
        norm += amp
        amp *= 0.5
        q = q * 2.03 + V3(17.1, 5.3, 11.7)
    }
    return sum / norm
}

/// Szum komórkowy: odległość do najbliższego (F1) i drugiego (F2) punktu.
func worley(_ p: V3) -> (Double, Double) {
    let ix = Int(p.x.rounded(.down)), iy = Int(p.y.rounded(.down)), iz = Int(p.z.rounded(.down))
    var f1 = 9.0, f2 = 9.0
    for a in -1...1 { for b in -1...1 { for c in -1...1 {
        let cx = ix + a, cy = iy + b, cz = iz + c
        let fp = V3(Double(cx) + hash3(cx, cy, cz, 1), Double(cy) + hash3(cx, cy, cz, 2), Double(cz) + hash3(cx, cy, cz, 3))
        let d = simd_length_compat(fp - p)
        if d < f1 { f2 = f1; f1 = d } else if d < f2 { f2 = d }
    } } }
    return (f1, f2)
}

@inline(__always) func simd_length_compat(_ v: V3) -> Double { (v * v).sum().squareRoot() }
@inline(__always) func dot(_ a: V3, _ b: V3) -> Double { (a * b).sum() }

/// Losowe cechy jednej kuli: przesunięcie szumu, osie wzoru, liczby do wyboru kolorów.
struct Variant {
    let o: V3, o2: V3
    let axis: V3, side: V3
    let r: [Double]
    let tint: Double

    init(_ g: inout SplitMix) {
        func unit(_ g: inout SplitMix) -> V3 {
            let z = Double.random(in: -1...1, using: &g), t = Double.random(in: 0...(2 * .pi), using: &g)
            let s = (1 - z * z).squareRoot()
            return V3(s * cos(t), s * sin(t), z)
        }
        o = V3(.random(in: 0...100, using: &g), .random(in: 0...100, using: &g), .random(in: 0...100, using: &g))
        o2 = V3(.random(in: 0...100, using: &g), .random(in: 0...100, using: &g), .random(in: 0...100, using: &g))
        axis = unit(&g)
        let t = unit(&g)
        let sd = t - axis * dot(t, axis)
        side = sd / max(1e-6, simd_length_compat(sd))
        r = (0..<8).map { _ in Double.random(in: 0...1, using: &g) }
        tint = .random(in: -0.04...0.04, using: &g)
    }
    func pick<T>(_ a: [T], _ i: Int = 0) -> T { a[min(a.count - 1, Int(r[i] * Double(a.count)))] }
}

struct Texel {
    var c: V3
    var rough: Double
    var metal = 0.0
    var e = V3.zero
    var h = 0.0                 // wysokość reliefu (0…1), z niej powstaje normal mapa
}

/// Wygląd jednej strony zestawu: funkcja powierzchni + stałe materiału.
struct Look {
    var clear = 0.0
    var clean = false           // bez brudu (np. świecące)
    var emits = false
    var bump = 0.0              // siła reliefu; 0 = gładka powierzchnia
    var shade: (V3, Variant) -> Texel
}

struct Surface { let diffuse: CGImage, rough: CGImage, metal: CGImage, emission: CGImage?, normal: CGImage?, clear: Double, avg: V3 }

/// Mapy danych (chropowatość, metaliczność, normalne) są liniowe — inaczej SceneKit „zlinearyzuje” je jak kolor.
func image(_ bytes: [UInt8], _ w: Int, _ h: Int, gray: Bool, linear: Bool = false) -> CGImage {
    let cs = gray ? CGColorSpace(name: CGColorSpace.linearGray)!
                  : CGColorSpace(name: linear ? CGColorSpace.linearSRGB : CGColorSpace.sRGB)!
    let prov = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: gray ? 8 : 32, bytesPerRow: gray ? w : w * 4,
                   space: cs, bitmapInfo: CGBitmapInfo(rawValue: gray ? 0 : CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

/// Wypala teksturę equirect: każdy piksel to punkt na sferze, na którym liczymy wzór i ślady użytkowania.
func bake(_ look: Look, seed: UInt64, w: Int = 512, h: Int = 256) -> Surface {
    var g = SplitMix(state: seed)
    let v = Variant(&g)
    var dif = [UInt8](repeating: 255, count: w * h * 4)
    var rgh = [UInt8](repeating: 0, count: w * h)
    var met = [UInt8](repeating: 0, count: w * h)
    var emi = [UInt8](repeating: 255, count: w * h * 4)
    var hgt = [Double](repeating: 0, count: w * h)
    var rowSum = [V3](repeating: .zero, count: h)       // średni kolor (z emisją) — barwa odbicia kuli na planszy
    func b(_ x: Double) -> UInt8 { UInt8(max(0, min(255, (x * 255).rounded()))) }

    dif.withUnsafeMutableBufferPointer { dp in
    rgh.withUnsafeMutableBufferPointer { rp in
    met.withUnsafeMutableBufferPointer { mp in
    emi.withUnsafeMutableBufferPointer { ep in
    hgt.withUnsafeMutableBufferPointer { hp in
    rowSum.withUnsafeMutableBufferPointer { sp in
        let dP = dp.baseAddress!, rP = rp.baseAddress!, mP = mp.baseAddress!, eP = ep.baseAddress!, hP = hp.baseAddress!, sP = sp.baseAddress!
        DispatchQueue.concurrentPerform(iterations: h) { y in
            let th = .pi * (Double(y) + 0.5) / Double(h)
            for x in 0..<w {
                let ph = 2 * .pi * (Double(x) + 0.5) / Double(w)
                let p = V3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
                var t = look.shade(p, v)
                t.c *= 1 + v.tint
                if !look.clean {                                   // brud, kurz, smugi
                    // miękkie, rozmyte zabrudzenia zamiast drobnych kropek
                    let dirt = smooth(0.6, 0.9, fbm(p * 9 + v.o2, 3)) * 0.5
                    let lum = dot(t.c, V3(0.3, 0.59, 0.11))
                    t.c = lum > 0.4 ? t.c * (1 - dirt * 0.09) : t.c + V3(repeating: dirt * 0.03)
                    t.rough = min(1, t.rough + smooth(0.62, 0.9, fbm(p * 3 + v.o2, 3)) * 0.3)
                }
                let i = y * w + x
                dP[i * 4] = b(t.c.x); dP[i * 4 + 1] = b(t.c.y); dP[i * 4 + 2] = b(t.c.z)
                rP[i] = b(t.rough)
                mP[i] = b(t.metal)
                eP[i * 4] = b(t.e.x); eP[i * 4 + 1] = b(t.e.y); eP[i * 4 + 2] = b(t.e.z)
                hP[i] = t.h
                sP[y] += (t.c + t.e) * sin(th)
            }
        }
    } } } } } }

    // normal mapa z różnic wysokości; w poziomie poprawka na zwężanie się południków przy biegunach
    var normal: CGImage?
    if look.bump > 0 {
        var nrm = [UInt8](repeating: 255, count: w * h * 4)
        let k = look.bump * Double(h) / 40
        for y in 0..<h {
            let sn = max(0.08, sin(.pi * (Double(y) + 0.5) / Double(h)))
            for x in 0..<w {
                let l = hgt[y * w + (x + w - 1) % w], r = hgt[y * w + (x + 1) % w]
                let u = hgt[max(0, y - 1) * w + x], d = hgt[min(h - 1, y + 1) * w + x]
                var n = V3(-(r - l) * k / sn, (d - u) * k, 1)
                n /= simd_length_compat(n)
                let i = (y * w + x) * 4
                nrm[i] = b(n.x * 0.5 + 0.5); nrm[i + 1] = b(n.y * 0.5 + 0.5); nrm[i + 2] = b(n.z * 0.5 + 0.5)
            }
        }
        normal = image(nrm, w, h, gray: false, linear: true)
    }
    return Surface(diffuse: image(dif, w, h, gray: false), rough: image(rgh, w, h, gray: true),
                   metal: image(met, w, h, gray: true),
                   emission: look.emits ? image(emi, w, h, gray: false) : nil, normal: normal, clear: look.clear,
                   avg: rowSum.reduce(.zero, +) / (Double(w) * Double(h) * 2 / .pi))
}

// MARK: - Środowisko HDR

/// Studio w zakresie HDR (equirect, wartości liniowe > 1): softbox nad planszą, pionowe lampy po bokach,
/// ciepłe okno i chłodne panele. Zapisane jako Radiance .hdr, żeby SceneKit dostał pełny zakres jasności.
func writeStudioHDR(light: Bool = false) -> URL {
    let w = 1024, h = 512
    var px = [V3](repeating: .zero, count: w * h)
    func box(_ lon: Double, _ lat: Double, _ c: Double, _ d: Double, halfW: Double, halfH: Double, soft: Double) -> Double {
        var dl = abs(lon - c); dl = min(dl, 2 * .pi - dl)
        return smooth(halfW + soft, halfW, dl) * smooth(halfH + soft, halfH, abs(lat - d))
    }
    DispatchQueue.concurrentPerform(iterations: h) { y in
        let lat = .pi / 2 - .pi * (Double(y) + 0.5) / Double(h)          // +π/2 góra
        for x in 0..<w {
            let lon = 2 * .pi * (Double(x) + 0.5) / Double(w)
            let up = max(0, sin(lat))
            var c = light ? mix(V3(0.52, 0.54, 0.57), V3(0.90, 0.91, 0.93), up)           // jasne, neutralne studio
                          : mix(V3(0.010, 0.011, 0.013), V3(0.05, 0.055, 0.065), up)         // ciemne studio
            c += V3(0.02, 0.022, 0.025) * smooth(-0.25, 0, lat) * smooth(0.2, 0, lat)  // jaśniejszy horyzont
            let zen = .pi / 2 - lat                                                         // odległość kątowa od zenitu
            c += V3(2.6, 2.55, 2.5) * smooth(0.9, 0.3, zen)                                   // duży, miękki softbox nad głową
            c += V3(7, 7.2, 7.6) * box(lon, lat, 0.0, 0.25, halfW: 0.05, halfH: 0.55, soft: 0.05)   // pionowe lampy
            c += V3(7, 7.2, 7.6) * box(lon, lat, 3.3, 0.25, halfW: 0.05, halfH: 0.55, soft: 0.05)
            c += V3(4.5, 2.6, 1.2) * box(lon, lat, 4.6, 0.3, halfW: 0.28, halfH: 0.2, soft: 0.1)    // ciepłe okno
            c += V3(0.25, 0.9, 0.95) * box(lon, lat, 2.2, 0.1, halfW: 0.35, halfH: 0.3, soft: 0.3)  // chłodne panele
            c += V3(0.7, 0.35, 1.1) * box(lon, lat, 5.6, 0.1, halfW: 0.3, halfH: 0.3, soft: 0.3)
            px[y * w + x] = c
        }
    }
    var out = Data("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y \(h) +X \(w)\n".utf8)
    out.reserveCapacity(w * h * 4 + 64)
    for c in px {                                            // RGBE bez kompresji
        let m = max(c.x, c.y, c.z)
        if m < 1e-32 { out.append(contentsOf: [0, 0, 0, 0]); continue }
        let e = Int((log2(m)).rounded(.down)) + 1
        let sc = 256 / pow(2, Double(e))
        out.append(contentsOf: [UInt8(min(255, c.x * sc)), UInt8(min(255, c.y * sc)), UInt8(min(255, c.z * sc)), UInt8(e + 128)])
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(light ? "samotnik-studio-jasne.hdr" : "samotnik-studio.hdr")
    try? out.write(to: url)
    return url
}
