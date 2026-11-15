// Samotnik — ślady użytkowania planszy: odpryski krawędzi, wytarcia, odciski, rysy, wgniecenia.
// Ziarno losowania zależy od planszy, więc każda ma swój stały „charakter”, jak prawdziwy przedmiot.

import Cocoa

/// Obrys planszy (jak boardPath) z wyszczerbionymi rogami i drobnymi ubytkami na krawędziach.
func chippedBoardPath(_ b: Board, pad: CGFloat, radius: CGFloat, holes: CGFloat?, seed: UInt64) -> NSBezierPath {
    var g = SplitMix(state: seed)
    var outline = boardPath(b, pad: pad, radius: radius, holes: nil).cgPath
    let s = 0.5 + pad
    func chip(at c: CGPoint, size: CGFloat) {
        let n = Int.random(in: 5...8, using: &g)
        let rot = CGFloat.random(in: 0...(2 * .pi), using: &g)
        let p = CGMutablePath()
        for i in 0..<n {
            let a = rot + CGFloat(i) / CGFloat(n) * 2 * .pi
            let r = size * .random(in: 0.45...1, using: &g)
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * .random(in: 0.6...1, using: &g))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        outline = outline.subtracting(p)
    }
    let inset = radius * (1 - 1 / 2.squareRoot())
    for p in b.all {
        let x = b.x(p), y = b.y(p)
        for (dc, dr) in [(1, 1), (1, -1), (-1, 1), (-1, -1)] {
            // wypukły róg obrysu: brak sąsiadów w obu kierunkach
            guard !b.has(Pos(r: p.r, c: p.c + dc)), !b.has(Pos(r: p.r + dr, c: p.c)) else { continue }
            guard Double.random(in: 0...1, using: &g) < 0.6 else { continue }
            let cx = x + CGFloat(dc) * (s - inset), cy = y - CGFloat(dr) * (s - inset)
            chip(at: CGPoint(x: cx, y: cy), size: .random(in: 0.06...0.15, using: &g))
        }
        for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !b.has(Pos(r: p.r + dr, c: p.c + dc)) {
            guard Double.random(in: 0...1, using: &g) < 0.2 else { continue }
            let along = CGFloat.random(in: -0.35...0.35, using: &g)
            let cx = x + CGFloat(dc) * s + (dr != 0 ? along : 0)
            let cy = y - CGFloat(dr) * s + (dc != 0 ? along : 0)
            chip(at: CGPoint(x: cx, y: cy), size: .random(in: 0.03...0.08, using: &g))
        }
    }
    let out = CGMutablePath()
    out.addPath(outline)
    if let hr = holes {
        for p in b.all {
            out.addEllipse(in: CGRect(x: b.x(p) - hr, y: b.y(p) - hr, width: 2 * hr, height: 2 * hr))
        }
    }
    let bz = NSBezierPath(cgPath: out)
    bz.windingRule = .evenOdd
    bz.flatness = 0.003
    return bz
}

struct BoardSurface { let diffuse: CGImage, rough: CGImage, normal: CGImage }

/// Tekstury lakieru w układzie planszy; `rect` to obszar, który UV ściany SCNShape rozciąga na całą teksturę.
func boardSurface(_ b: Board, rect: CGRect, base: UInt32, rough: CGFloat, seed: UInt64, px: Int = 2048) -> BoardSurface {
    var g = SplitMix(state: seed)
    func ctx(gray: Bool) -> CGContext {
        let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: gray ? px : px * 4,
                          space: gray ? CGColorSpace(name: CGColorSpace.linearGray)! : sRGB,
                          bitmapInfo: gray ? 0 : CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.scaleBy(x: CGFloat(px) / rect.width, y: CGFloat(px) / rect.height)
        c.translateBy(x: -rect.minX, y: -rect.minY)
        return c
    }
    let dif = ctx(gray: false), rgh = ctx(gray: true), hgt = ctx(gray: true)
    let full = rect
    dif.setFillColor(rgb(base)); dif.fill(full)
    rgh.setFillColor(CGColor(gray: rough, alpha: 1)); rgh.fill(full)
    hgt.setFillColor(CGColor(gray: 0.5, alpha: 1)); hgt.fill(full)
    func R(_ a: CGFloat, _ b: CGFloat) -> CGFloat { .random(in: a...b, using: &g) }
    func pt() -> CGPoint { CGPoint(x: R(rect.minX, rect.maxX), y: R(rect.minY, rect.maxY)) }
    func blob(_ c: CGContext, _ at: CGPoint, _ r: CGFloat, _ col: CGColor) {
        c.drawRadialGradient(gradient([col, col.copy(alpha: 0)!], [0, 1]), startCenter: at, startRadius: 0, endCenter: at, endRadius: r, options: [])
    }

    // przebarwienia lakieru
    for _ in 0..<26 { blob(dif, pt(), R(0.4, 1.6), rgb(Bool.random(using: &g) ? 0xFFFFFF : 0x000000, R(0.025, 0.07) * theme.dirt)) }

    // wytarcia wokół otworów: lakier głównie matowieje, nieregularnie, najmocniej w stronę sąsiednich pól
    for p in b.all {
        let c = CGPoint(x: b.x(p), y: b.y(p))
        let wear = R(0.3, 1)
        for _ in 0..<Int.random(in: 8...16, using: &g) {
            // kąt przyciągany do jednej z czterech osi ruchu
            let axis = CGFloat(Int.random(in: 0..<4, using: &g)) * .pi / 2
            let a = axis + R(-0.6, 0.6) * R(0.3, 1)
            let r = R(0.28, 0.36)
            let at = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            let size = R(0.025, 0.07)
            blob(rgh, at, size, CGColor(gray: 1, alpha: R(0.05, 0.16) * wear))
            blob(dif, at, size, rgb(theme.light ? theme.dust : 0xFFFFFF, R(0.006, 0.016) * wear * theme.dirt))
        }
        for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where b.has(Pos(r: p.r + dr, c: p.c + dc)) {
            guard Double.random(in: 0...1, using: &g) < 0.6 else { continue }
            // smuga między polami, którędy przesuwa się kula
            let m = CGPoint(x: c.x + CGFloat(dc) * 0.5, y: c.y - CGFloat(dr) * 0.5)
            rgh.saveGState()
            rgh.translateBy(x: m.x, y: m.y)
            rgh.scaleBy(x: dc != 0 ? 2.2 : 1, y: dr != 0 ? 2.2 : 1)
            blob(rgh, CGPoint(x: R(-0.02, 0.02), y: R(-0.02, 0.02)), R(0.06, 0.1), CGColor(gray: 1, alpha: R(0.04, 0.1) * wear))
            rgh.restoreGState()
        }
    }

    // przetarte krawędzie i kurz przy brzegach: nieregularne plamy wzdłuż zewnętrznych boków pól
    let edge = boardPath(b, pad: 0.08, radius: 0.45, holes: nil).cgPath
    let s0: CGFloat = 0.5 + 0.08
    for p in b.all {
        let c = CGPoint(x: b.x(p), y: b.y(p))
        for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !b.has(Pos(r: p.r + dr, c: p.c + dc)) {
            for _ in 0..<Int.random(in: 2...5, using: &g) {
                let along = R(-0.5, 0.5), inward = R(0.02, 0.14)
                let at = CGPoint(x: c.x + CGFloat(dc) * (s0 - inward) + (dr != 0 ? along : 0),
                                 y: c.y - CGFloat(dr) * (s0 - inward) + (dc != 0 ? along : 0))
                let r = R(0.04, 0.16)
                dif.saveGState(); dif.addPath(edge); dif.clip()
                blob(dif, at, r, rgb(theme.dust, theme.dirt * R(0.01, 0.035)))
                dif.restoreGState()
                blob(rgh, at, r, CGColor(gray: 1, alpha: R(0.05, 0.15)))
            }
        }
    }

    // odciski palców: koncentryczne listewki, widoczne w połysku
    for _ in 0..<Int.random(in: 4...7, using: &g) {
        let c = pt(), rot = R(0, .pi), ridges = Int.random(in: 9...15, using: &g)
        rgh.saveGState()
        rgh.translateBy(x: c.x, y: c.y); rgh.rotate(by: rot); rgh.scaleBy(x: 1, y: R(1.25, 1.5))
        rgh.setLineWidth(0.006)
        for i in 1...ridges {
            let r = CGFloat(i) * 0.011
            rgh.setStrokeColor(CGColor(gray: 1, alpha: 0.35 * (1 - CGFloat(i) / CGFloat(ridges + 2))))
            rgh.addArc(center: .zero, radius: r, startAngle: R(0, 1), endAngle: R(4.6, 6.2), clockwise: false)
            rgh.strokePath()
        }
        rgh.restoreGState()
    }

    // smugi i osad
    for _ in 0..<10 { blob(rgh, pt(), R(0.2, 0.7), CGColor(gray: 1, alpha: R(0.1, 0.25))) }

    // mikrorysy: grupki krótkich, prostych, równoległych śladów (jak po przesuwaniu przedmiotu) — tylko w połysku
    rgh.setLineCap(.round); hgt.setLineCap(.round)
    for _ in 0..<Int.random(in: 10...18, using: &g) {
        let c = pt(), ang = R(0, .pi)
        let dir = CGPoint(x: cos(ang), y: sin(ang)), nrm = CGPoint(x: -sin(ang), y: cos(ang))
        let spread = R(0.05, 0.2)
        for _ in 0..<Int.random(in: 4...12, using: &g) {
            let off = R(-spread, spread), shift = R(-0.08, 0.08), len = R(0.03, 0.16)
            let a = CGPoint(x: c.x + nrm.x * off + dir.x * shift, y: c.y + nrm.y * off + dir.y * shift)
            let e = CGPoint(x: a.x + dir.x * len, y: a.y + dir.y * len)
            rgh.setStrokeColor(CGColor(gray: 1, alpha: R(0.06, 0.18))); rgh.setLineWidth(R(0.0015, 0.0035))
            rgh.move(to: a); rgh.addLine(to: e); rgh.strokePath()
            hgt.setStrokeColor(CGColor(gray: 0.35, alpha: R(0.05, 0.15))); hgt.setLineWidth(0.0025)
            hgt.move(to: a); hgt.addLine(to: e); hgt.strokePath()
        }
    }

    // wgniecenia
    for _ in 0..<Int.random(in: 8...16, using: &g) { blob(hgt, pt(), R(0.03, 0.09), CGColor(gray: 0, alpha: R(0.3, 0.6))) }

    // kurz: miękki nalot gęstszy przy krawędziach i w miejscach, gdzie się zbiera, plus bardzo drobny pył
    for _ in 0..<14 {
        let at = pt(), r = R(0.3, 1.1)
        blob(dif, at, r, rgb(theme.dust, theme.dirt * R(0.01, 0.025)))
        blob(rgh, at, r, CGColor(gray: 1, alpha: R(0.05, 0.12)))
    }
    for _ in 0..<5000 {
        let c = pt()
        guard noise(V3(Double(c.x) * 1.7, Double(c.y) * 1.7, 3.1)) > 0.55 else { continue }   // pył w skupiskach
        let r = R(0.0012, 0.0026)
        dif.setFillColor(rgb(theme.dust, theme.dirt * R(0.03, 0.1)))
        dif.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    // ziarno + normal mapa z wysokości
    let dp = dif.data!.assumingMemoryBound(to: UInt8.self)
    let hp = hgt.data!.assumingMemoryBound(to: UInt8.self)
    let hRow = hgt.bytesPerRow, dRow = dif.bytesPerRow
    var nrm = [UInt8](repeating: 255, count: px * px * 4)
    nrm.withUnsafeMutableBufferPointer { np in
        let nP = np.baseAddress!
        DispatchQueue.concurrentPerform(iterations: px) { y in
            for x in 0..<px {
                let gr = Int(hash3(x, y, 7) * 6) - 3
                let di = y * dRow + x * 4
                for c in 0..<3 { dp[di + c] = UInt8(max(0, min(255, Int(dp[di + c]) + gr))) }
                let l = Double(hp[y * hRow + max(0, x - 1)]), r = Double(hp[y * hRow + min(px - 1, x + 1)])
                let u = Double(hp[max(0, y - 1) * hRow + x]), d = Double(hp[min(px - 1, y + 1) * hRow + x])
                var n = V3(-(r - l) / 255 * 6, (d - u) / 255 * 6, 1)
                n /= simd_length_compat(n)
                let i = (y * px + x) * 4
                nP[i] = UInt8((n.x * 0.5 + 0.5) * 255); nP[i + 1] = UInt8((n.y * 0.5 + 0.5) * 255); nP[i + 2] = UInt8((n.z * 0.5 + 0.5) * 255)
            }
        }
    }
    return BoardSurface(diffuse: dif.makeImage()!, rough: rgh.makeImage()!, normal: image(nrm, px, px, gray: false, linear: true))
}
