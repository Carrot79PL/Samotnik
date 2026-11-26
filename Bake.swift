import Cocoa
import simd

/// „Wypiekanie” logo: rasteryzacja ścieżek SVG (CoreGraphics) + mapa czasu pisania.
/// Dla każdego piksela atramentu liczymy odległość geodezyjną wzdłuż kreski od początku litery,
/// więc atrament „płynie” po krzywych: litera po literze, na końcu podkreślenie, potem STUDIO.
struct LogoBake {
    let w: Int, h: Int
    var alpha: [UInt8]          // pokrycie atramentu
    var tau: [Float]            // moment odsłonięcia 0…1 (2 = brak atramentu)
    var ids: [UInt8]            // id komponentu (litery) na piksel, 255 = brak
    var compStart: [Float]      // znormalizowany start pisania komponentu 0…1
    var soft: Float             // szerokość miękkiej krawędzi w jednostkach tau
    var tipBins: [SIMD3<Float>] // (x,y,aktywne) w pikselach logo, indeks = tau * (n-1)
    var rg: [UInt8] = []        // R: rozmyte pokrycie (do pogrubiania/ścieniania), G: „nacisk” 0…1 (wolniej = grubiej)
}

private func tmiParsePath(_ d: String, scale s: CGFloat, ox: CGFloat, oy: CGFloat) -> CGPath {
    var nums: [CGFloat] = [], buf = "", cmd: Character = "M"
    let path = CGMutablePath()
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s + ox, y: y * s + oy) }
    func need(_ c: Character) -> Int { c == "C" ? 6 : (c == "M" || c == "L") ? 2 : 0 }
    func flush() {
        if !buf.isEmpty { nums.append(CGFloat(Double(buf) ?? 0)); buf = "" }
        let n = need(cmd)
        if n > 0 && nums.count == n {
            switch cmd {
            case "M": path.move(to: P(nums[0], nums[1])); cmd = "L"
            case "L": path.addLine(to: P(nums[0], nums[1]))
            default: path.addCurve(to: P(nums[4], nums[5]), control1: P(nums[0], nums[1]), control2: P(nums[2], nums[3]))
            }
            nums.removeAll(keepingCapacity: true)
        }
    }
    for ch in d {
        if ch.isLetter { flush(); cmd = ch; nums.removeAll(); if ch == "Z" || ch == "z" { path.closeSubpath() } }
        else if ch == "-" { if !buf.isEmpty && buf.last != "e" { flush() }; buf.append(ch) }
        else if ch == "." { if buf.contains(".") { flush() }; buf.append(ch) }
        else if ch == " " || ch == "," || ch == "\n" { flush() }
        else { buf.append(ch) }
    }
    flush()
    return path
}

private func tmiRaster(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: w * h)
    data.withUnsafeMutableBytes { p in
        let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
        ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
        draw(ctx)
    }
    return data
}

private func tmiBoxBlur(_ src: [Float], _ w: Int, _ h: Int, _ r: Int, passes: Int) -> [Float] {
    var a = src, b = [Float](repeating: 0, count: w * h)
    for _ in 0..<passes {
        for y in 0..<h { // poziomo
            var acc: Float = 0; let row = y * w
            for x in -r...r { acc += a[row + min(max(x, 0), w - 1)] }
            for x in 0..<w { b[row + x] = acc / Float(2 * r + 1)
                acc += a[row + min(x + r + 1, w - 1)] - a[row + max(x - r, 0)] }
        }
        for x in 0..<w { // pionowo
            var acc: Float = 0
            for y in -r...r { acc += b[min(max(y, 0), h - 1) * w + x] }
            for y in 0..<h { a[y * w + x] = acc / Float(2 * r + 1)
                acc += b[min(y + r + 1, h - 1) * w + x] - b[max(y - r, 0) * w + x] }
        }
    }
    return a
}

private func tmiGaussBlur(_ src: [Float], _ w: Int, _ h: Int, sigma: Float) -> [Float] {
    let R = Int(ceil(sigma * 3)); var k = [Float](repeating: 0, count: 2 * R + 1); var sum: Float = 0
    for i in -R...R { let v = expf(-Float(i * i) / (2 * sigma * sigma)); k[i + R] = v; sum += v }
    for i in 0..<k.count { k[i] /= sum }
    var tmp = [Float](repeating: 0, count: w * h), out = tmp
    for y in 0..<h { let row = y * w
        for x in 0..<w { var acc: Float = 0
            let lo = max(-R, -x), hi = min(R, w - 1 - x)
            for i in lo...hi { acc += src[row + x + i] * k[i + R] }
            tmp[row + x] = acc } }
    for x in 0..<w { for y in 0..<h { var acc: Float = 0
        let lo = max(-R, -y), hi = min(R, h - 1 - y)
        for i in lo...hi { acc += tmp[(y + i) * w + x] * k[i + R] }
        out[y * w + x] = acc } }
    return out
}

private struct TMIMinHeap {
    var d: [Float] = [], v: [Int32] = []
    var isEmpty: Bool { d.isEmpty }
    mutating func push(_ dist: Float, _ val: Int32) {
        d.append(dist); v.append(val); var c = d.count - 1
        while c > 0 { let p = (c - 1) >> 1; if d[p] <= d[c] { break }; d.swapAt(p, c); v.swapAt(p, c); c = p }
    }
    mutating func pop() -> (Float, Int32) {
        let top = (d[0], v[0]); let ld = d.removeLast(), lv = v.removeLast()
        if !d.isEmpty { d[0] = ld; v[0] = lv; var c = 0
            while true { let a = 2 * c + 1, b = a + 1; var m = c
                if a < d.count && d[a] < d[m] { m = a }; if b < d.count && d[b] < d[m] { m = b }
                if m == c { break }; d.swapAt(m, c); v.swapAt(m, c); c = m } }
        return top
    }
}

func bakeLogo(width W: Int = 3200) -> LogoBake {
    let H = Int((Double(W) * tmVBH / tmVBW).rounded())
    let s = CGFloat(W) / CGFloat(tmVBW)
    // CoreGraphics: y w górę → odwróć, żeby wiersz 0 = góra obrazu
    let flip = { (c: CGContext) in c.translateBy(x: 0, y: CGFloat(H)); c.scaleBy(x: 1, y: -1) }
    let sigP = tmSigPaths.map { tmiParsePath($0, scale: s, ox: 0, oy: 0) }
    let stuP = tmStudioPaths.map { tmiParsePath($0, scale: s, ox: 0, oy: 0) }
    let lw = CGFloat(tmStrokeW) * s

    func fillSig(_ i: Int) -> (CGContext) -> Void { { c in flip(c); c.addPath(sigP[i]); c.setFillColor(gray: 0, alpha: 1); c.fillPath(using: .evenOdd) } }
    func strokeStu(_ i: Int) -> (CGContext) -> Void { { c in flip(c); c.addPath(stuP[i]); c.setStrokeColor(gray: 0, alpha: 1); c.setLineWidth(lw); c.setLineCap(.round); c.setLineJoin(.round); c.strokePath() } }

    var drawers: [(CGContext) -> Void] = []
    for i in 0..<sigP.count { drawers.append(fillSig(i)) }
    for i in 0..<stuP.count { drawers.append(strokeStu(i)) }
    let nSig = sigP.count
    let N = W * H
    // pokrycie całości + właściciel piksela (komponent o największym pokryciu)
    var alpha = [UInt8](repeating: 0, count: N), owner = [Int8](repeating: -1, count: N), best = [UInt8](repeating: 0, count: N)
    for (i, dr) in drawers.enumerated() {
        let a = tmiRaster(W, H, dr)
        for j in 0..<N where a[j] > 0 {
            if a[j] > alpha[j] { alpha[j] = a[j] }
            // skrzyżowania: litera wygrywa z podkreśleniem (inaczej przecinałoby kreskę litery na pół)
            if owner[j] < 0 || (i > 0 && owner[j] == 0 && a[j] >= 64) || (i > 0 && a[j] > best[j] && owner[j] != 0) { best[j] = a[j]; owner[j] = Int8(i) }
        }
    }
    // ===== Ścieżka pióra jak prawdziwa ręka: szkielet kreski → jedno ciągłe przejście =====
    let nb: [(Int, Int, Float)] = [(1,0,1),(-1,0,1),(0,1,1),(0,-1,1),(1,1,1.414),(1,-1,1.414),(-1,1,1.414),(-1,-1,1.414)]
    var lists = [[Int32]](repeating: [], count: drawers.count)
    for j in 0..<N where owner[j] >= 0 { lists[Int(owner[j])].append(Int32(j)) }
    struct Comp { var id: Int; var minX: Int; var len: Float; var kind: Int; var s: Float = 0; var d: Float = 0 }
    struct PenPt { var x: Float; var y: Float; var t: Float; var mode: Int; var slow: Float = 0 }   // mode 0 pisze, 1 cofa po tuszu, 2 przylot po oderwaniu
    let F = 4, w2 = (W + F - 1) / F, h2 = (H + F - 1) / F
    var comps: [Comp] = [], paths: [Int: [PenPt]] = [:]
    let nb8 = [(1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)]
    for i in 0..<drawers.count where !lists[i].isEmpty {
        let kind = i >= nSig ? 2 : (i == 0 ? 1 : 0)
        var cntL = [UInt16](repeating: 0, count: w2 * h2)
        var bx0 = w2, by0 = h2, bx1 = 0, by1 = 0, minX = W
        for jv in lists[i] { let j = Int(jv), x = j % W, y = j / W; minX = min(minX, x)
            if alpha[j] > 110 { let k = (y / F) * w2 + x / F; cntL[k] += 1; bx0 = min(bx0, x / F); by0 = min(by0, y / F); bx1 = max(bx1, x / F); by1 = max(by1, y / F) } }
        if bx1 < bx0 { continue }
        bx0 = max(bx0 - 1, 1); by0 = max(by0 - 1, 1); bx1 = min(bx1 + 1, w2 - 2); by1 = min(by1 + 1, h2 - 2)
        var m = [UInt8](repeating: 0, count: w2 * h2)
        for k in 0..<(w2 * h2) where cntL[k] >= UInt16(F * F / 2) { m[k] = 1 }
        // Zhang–Suen
        var changed = true
        while changed { changed = false
            for pass in 0..<2 { var del: [Int] = []
                for y in by0...by1 { for x in bx0...bx1 { let j = y * w2 + x; if m[j] == 0 { continue }
                    let p = [m[j - w2], m[j - w2 + 1], m[j + 1], m[j + w2 + 1], m[j + w2], m[j + w2 - 1], m[j - 1], m[j - w2 - 1]].map { Int($0) }
                    let B = p.reduce(0, +); if B < 2 || B > 6 { continue }
                    var A = 0; for k in 0..<8 where p[k] == 0 && p[(k + 1) % 8] == 1 { A += 1 }
                    if A != 1 { continue }
                    if pass == 0 { if p[0] * p[2] * p[4] != 0 || p[2] * p[4] * p[6] != 0 { continue } }
                    else { if p[0] * p[2] * p[6] != 0 || p[0] * p[4] * p[6] != 0 { continue } }
                    del.append(j) } }
                for j in del { m[j] = 0 }; if !del.isEmpty { changed = true } } }
        func deg(_ j: Int) -> Int { var c = 0; for (dx, dy) in nb8 where m[j + dy * w2 + dx] == 1 { c += 1 }; return c }
        // przycinanie krótkich ostróg
        for y in by0...by1 { for x in bx0...bx1 { let j0 = y * w2 + x; if m[j0] == 0 || deg(j0) != 1 { continue }
            var run = [j0], cur = j0, prev = -1, ok = false
            while run.count <= 4 { var nx = -1; var cnt = 0
                for (dx, dy) in nb8 { let n = cur + dy * w2 + dx; if m[n] == 1 && n != prev && !run.contains(n) { nx = n; cnt += 1 } }
                if cnt != 1 { ok = cnt >= 2; break }
                if deg(nx) >= 3 { ok = true; break }
                prev = cur; cur = nx; run.append(nx) }
            if ok && run.count <= 4 { for r in run { m[r] = 0 } } } }
        var sk: [Int] = []
        for y in by0...by1 { for x in bx0...bx1 where m[y * w2 + x] == 1 { sk.append(y * w2 + x) } }
        if sk.isEmpty { continue }
        var vis = [Bool](repeating: false, count: w2 * h2)
        func P(_ j: Int) -> SIMD2<Float> { SIMD2(Float(j % w2), Float(j / w2)) }
        let ends = sk.filter { deg($0) == 1 }
        var cur = sk.min { P($0).x != P($1).x ? P($0).x < P($1).x : P($0).y > P($1).y }!; _ = ends
        var pts = [PenPt(x: P(cur).x, y: P(cur).y, t: 0, mode: 0)], tl: Float = 0
        vis[cur] = true; var remaining = sk.count - 1
        var dir = SIMD2<Float>(1, 0)
        func isNb(_ a: Int, _ b: Int) -> Bool { abs(a % w2 - b % w2) <= 1 && abs(a / w2 - b / w2) <= 1 }
        while remaining > 0 {
            var bestN = -1, bestS: Float = -9
            var cands: [Int] = []
            for (dx, dy) in nb8 { let n = cur + dy * w2 + dx; if m[n] == 1 && !vis[n] { cands.append(n) } }
            for n in cands {
                // czy gałąź to ślepa odnoga (np. szczyt litery M)? – zalej ją bez przechodzenia przez bieżący punkt
                var seen: Set<Int> = [n, cur], st = [n], size = 0; var sx: Float = 0
                while let c = st.popLast(), size < 160 { size += 1; sx += P(c).x
                    for (ex, ey) in nb8 { let q = c + ey * w2 + ex; if m[q] == 1 && !vis[q] && !seen.contains(q) && !(cands.contains(q) && q != n) { seen.insert(q); st.append(q) } } }
                let dead = size < 90
                let d = simd_normalize(P(n) - P(cur))
                let lean = (sx / Float(max(size, 1)) - P(cur).x) * 0.06   // najpierw to, co bardziej na lewo
                let sc = simd_dot(d, dir) * 0.6 + (dead ? 10.0 - Float(size) * 0.01 : 0) - lean
                if sc > bestS { bestS = sc; bestN = n } }
            if bestN >= 0 {
                for (dx, dy) in nb8 { let q = bestN + dy * w2 + dx; if m[q] == 1 && !vis[q] && q != bestN && isNb(q, cur) {
                    var leads = false; for (ex, ey) in nb8 { let r = q + ey * w2 + ex; if m[r] == 1 && !vis[r] && r != cur && r != bestN && !isNb(r, cur) && !isNb(r, bestN) { leads = true } }
                    if !leads { vis[q] = true; remaining -= 1 } } }
                let d = P(bestN) - P(cur); tl += simd_length(d) * Float(F)
                dir = simd_normalize(dir * 0.4 + simd_normalize(d) * 0.6)
                vis[bestN] = true; remaining -= 1; cur = bestN
                pts.append(PenPt(x: P(cur).x, y: P(cur).y, t: tl, mode: 0)); continue }
            // ślepy koniec: wróć po szkielecie do najbliższego nienapisanego miejsca (pióro sunie po tuszu)
            var par = [Int: Int](), q = [cur], qi = 0, found = -1; par[cur] = cur
            while qi < q.count && found < 0 { let c = q[qi]; qi += 1
                for (dx, dy) in nb8 { let n = c + dy * w2 + dx; if m[n] == 1 && par[n] == nil { par[n] = c; if !vis[n] { found = n; break }; q.append(n) } } }
            if found >= 0 && q.count < 3000 {
                var back: [Int] = []; var c = par[found]!; while c != cur { back.append(c); c = par[c]! }
                for c in back.reversed() { let d = P(c) - P(cur); tl += simd_length(d) * Float(F) / 3; cur = c; dir = simd_normalize(d); pts.append(PenPt(x: P(c).x, y: P(c).y, t: tl, mode: 1)) }
                continue }
            // oderwanie pióra: najbliższy nienapisany fragment
            let pc = P(cur); var nn = -1, nd: Float = 1e9
            for j in sk where !vis[j] { let d = simd_length(P(j) - pc); if d < nd { nd = d; nn = j } }
            if nn < 0 { break }
            let short = nd < 30
            tl += short ? nd * Float(F) : 40 + nd * Float(F) * 0.25
            cur = nn; vis[cur] = true; remaining -= 1; dir = simd_normalize(P(cur) - pc)
            pts.append(PenPt(x: P(cur).x, y: P(cur).y, t: tl, mode: short ? 0 : 2))
        }
        // tempo ręki: wolniej w ciasnych łukach oraz na początku i końcu kreski (nacisk), szybciej na prostych
        let np = pts.count
        if np > 2 {
            var sl = [Float](repeating: 0, count: np)
            var runStart = 0
            for k in 0..<np {
                if pts[k].mode != 0 { runStart = k + 1; continue }
                let a = max(k - 4, 0), c = min(k + 4, np - 1)
                let d1 = SIMD2(pts[k].x - pts[a].x, pts[k].y - pts[a].y), d2 = SIMD2(pts[c].x - pts[k].x, pts[c].y - pts[k].y)
                var curv: Float = 0
                if simd_length(d1) > 0.5 && simd_length(d2) > 0.5 { curv = 1 - simd_dot(simd_normalize(d1), simd_normalize(d2)) }
                var runEnd = k; while runEnd + 1 < np && pts[runEnd + 1].mode == 0 { runEnd += 1; if runEnd - k > 8 { break } }
                let edge = max(0, 1 - Float(min(k - runStart, runEnd - k + (runEnd - k > 8 ? 99 : 0))) / 7)
                let cv = max(0, min(1, (curv - 0.05) / 0.6))
                sl[k] = min(1, cv * cv * (3 - 2 * cv) + 0.7 * edge) }
            var sm = sl
            for k in 0..<np { var s: Float = 0, n: Float = 0; for o in -3...3 { let q = k + o; if q >= 0 && q < np { s += sl[q]; n += 1 } }; sm[k] = s / n }
            var tt: Float = 0
            for k in 0..<np { pts[k].slow = sm[k]
                if k == 0 { pts[k].t = 0; continue }
                let seg = simd_length(SIMD2(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y)) * Float(F)
                switch pts[k].mode { case 1: tt += seg / 3; case 2: tt += 40 + seg * 0.25; default: tt += seg / (1 - 0.55 * sm[k]) }
                pts[k].t = tt }
            tl = tt }
        comps.append(Comp(id: i, minX: minX, len: max(tl, 1), kind: kind)); paths[i] = pts
    }
    let order = comps.sorted { a, b in a.kind != b.kind ? a.kind < b.kind : (a.kind == 2 ? a.id < b.id : a.minX < b.minX) }
    let gap = 26 * Float(W) / 1100
    var tot: Float = 0
    var timed: [Int: Comp] = [:]
    for (oi, c0) in order.enumerated() { var c = c0
        let speed: Float = c.kind == 1 ? 1.7 : (c.kind == 2 ? 1.35 : 1)
        c.s = tot; c.d = c.len / speed
        tot += c.d + (c.kind == 2 ? gap * 0.5 : gap)
        if oi + 1 < order.count && order[oi + 1].kind != c.kind { tot += gap * 7 }   // spokojny przelot pióra do podkreślenia / STUDIO
        timed[c.id] = c
    }
    tot -= gap * 0.5
    // tau pikseli: etykieta najbliższego (geodezyjnie) punktu ścieżki, w którym pióro pierwszy raz tam pisało
    var tau = [Float](repeating: 2, count: N)
    var slowP = [Float](repeating: 0, count: N)
    var dist = [Float](repeating: -1, count: N)
    var heap = TMIMinHeap()
    for (id, c) in timed { guard let pts = paths[id] else { continue }
        let speed: Float = c.kind == 1 ? 1.7 : (c.kind == 2 ? 1.35 : 1)
        for p in pts where p.mode != 1 {
            let x = Int(p.x) * F + F / 2, y = Int(p.y) * F + F / 2; if x >= W || y >= H { continue }
            let j = y * W + x; if Int(owner[j]) != id { continue }
            let lab = (c.s + p.t / speed) / tot
            if dist[j] < 0 || lab < tau[j] { dist[j] = 0; tau[j] = lab; slowP[j] = p.slow; heap.push(0, Int32(j)) } } }
    while !heap.isEmpty {
        let (d, jv) = heap.pop(); let j = Int(jv); if d > dist[j] { continue }
        let jx = j % W, jy = j / W, oj = owner[j]
        for (dx, dy, wgt) in nb { let nx = jx + dx, ny = jy + dy; if nx < 0 || ny < 0 || nx >= W || ny >= H { continue }
            let n = ny * W + nx; if owner[n] != oj { continue }
            let nd = d + wgt; if dist[n] < 0 || nd < dist[n] { dist[n] = nd; tau[n] = tau[j]; slowP[n] = slowP[j]; heap.push(nd, Int32(n)) } } }
    for j in 0..<N where owner[j] >= 0 && tau[j] >= 2 { if let c = timed[Int(owner[j])] { tau[j] = (c.s + c.d) / tot } }
    for _ in 0..<3 {
        var t2 = tau
        for y in 1..<(H - 1) { for x in 1..<(W - 1) { let j = y * W + x; if tau[j] >= 2 {
            var mn: Float = 2
            for (dx, dy, _) in nb { mn = min(mn, tau[(y + dy) * W + x + dx]) }
            if mn < 2 { t2[j] = mn } } } }
        tau = t2
    }
    // oś czasu pióra (pozycja w pikselach logo, wygładzona) → kosze tau
    var tline: [(Float, SIMD2<Float>, Bool)] = []   // (czas 0…1, pozycja, na papierze od poprzedniego punktu)
    for c0 in order { let c = timed[c0.id]!; guard let pts = paths[c.id] else { continue }
        let speed: Float = c.kind == 1 ? 1.7 : (c.kind == 2 ? 1.35 : 1)
        for (k, p) in pts.enumerated() {
            var acc = SIMD2<Float>(0, 0), n: Float = 0
            for o in -3...3 { let kk = k + o; if kk < 0 || kk >= pts.count { continue }
                if (o > 0 && (k + 1...kk).contains { pts[$0].mode == 2 }) || (o < 0 && (kk + 1...k).contains { pts[$0].mode == 2 }) { continue }
                acc += SIMD2(pts[kk].x, pts[kk].y); n += 1 }
            let pos = (acc / n) * Float(F) + Float(F) / 2
            tline.append(((c.s + p.t / speed) / tot, pos, k > 0 && p.mode != 2)) } }
    let B = 4096
    var tips = [SIMD3<Float>](repeating: .zero, count: B)
    var si = 0
    for bI in 0..<B { let T = Float(bI) / Float(B - 1)
        while si + 1 < tline.count && tline[si + 1].0 < T { si += 1 }
        if tline.isEmpty { break }
        if si + 1 >= tline.count || T <= tline[0].0 { let e = T <= tline[0].0 ? tline[0] : tline[tline.count - 1]; tips[bI] = SIMD3(e.1.x, e.1.y, 1); continue }
        let a0 = tline[si], a1 = tline[si + 1]; let f = max(0, min(1, (T - a0.0) / max(a1.0 - a0.0, 1e-7)))
        let pos = a0.1 + (a1.1 - a0.1) * f
        tips[bI] = SIMD3(pos.x, pos.y, a1.2 ? 1 : 0) }
    if let dp = ProcessInfo.processInfo.environment["TM_DUMP"] {
        var out = "W,\(W),\(H),\(tot)\n"; for t in tips { out += "\(t.x),\(t.y),\(t.z)\n" }
        for c in order { out += "C,\(c.id),\(c.kind),\(c.s),\(c.d),\(paths[c.id]?.count ?? 0)\n" }
        try? out.write(toFile: dp, atomically: true, encoding: .utf8)
        var am = [UInt8](repeating: 0, count: N); for j in 0..<N where tau[j] < 2 { am[j] = UInt8(min(255, tau[j] * 255)) }
        try? Data(am).write(to: URL(fileURLWithPath: dp + ".tau"))
    }
    var ids = [UInt8](repeating: 255, count: N)
    for j in 0..<N where owner[j] >= 0 { ids[j] = UInt8(owner[j]) }
    for _ in 0..<8 {
        var i2 = ids
        for y in 1..<(H - 1) { for x in 1..<(W - 1) { let j = y * W + x; if ids[j] == 255 {
            for (dx, dy, _) in nb { let v = ids[(y + dy) * W + x + dx]; if v != 255 { i2[j] = v; break } } } } }
        ids = i2
    }
    var compStart = [Float](repeating: 0, count: drawers.count)
    for (id, c) in timed { compStart[id] = c.s / tot }
    // tekstura RG: rozmyte pokrycie + nacisk (rozlany na sąsiadów, żeby krawędzie też go miały)
    let blurA = tmiGaussBlur(alpha.map { Float($0) / 255 }, W, H, sigma: 6 * Float(W) / 4096)
    let blurS = tmiGaussBlur(slowP, W, H, sigma: 6 * Float(W) / 4096), blurM = tmiGaussBlur(alpha.map { $0 > 0 ? 1 : 0 }, W, H, sigma: 6 * Float(W) / 4096)
    var rg = [UInt8](repeating: 255, count: N * 4)
    for j in 0..<N { rg[j * 4] = UInt8(max(0, min(255, blurA[j] * 255))); rg[j * 4 + 1] = UInt8(max(0, min(255, blurS[j] / max(blurM[j], 1e-3) * 255))); rg[j * 4 + 2] = alpha[j] }
    var lb = LogoBake(w: W, h: H, alpha: alpha, tau: tau, ids: ids, compStart: compStart, soft: 15 * Float(W) / 2400 / tot, tipBins: tips)
    lb.rg = rg
    return lb
}
