import Cocoa
import SceneKit
import SpriteKit

// MARK: - Intro studia BLUEROOT w 3D (wzór: Bilard) – niebieskie tło, odbicie pod obiektami, podpis pisany piórem i napis STUDIO.
// Zamiast bili: kulki (Samotnik) albo klocki (Klocki) spadają, zderzają się i zamieniają w znak BLUEROOT.

enum Intro3DKind { case marbles, blocks }

fileprivate let i3Bg: UInt32 = 0x111418
fileprivate let i3sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
fileprivate func i3rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: i3sRGB, components: [CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, a])!
}
fileprivate func i3c(_ h: UInt32, _ a: CGFloat = 1) -> NSColor { NSColor(cgColor: i3rgb(h, a))! }
fileprivate func i3img(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: i3sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}
fileprivate func i3grad(_ c: [CGColor], _ l: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: i3sRGB, colors: c as CFArray, locations: l)! }

final class Intro3DView: SCNView, SCNSceneRendererDelegate {
    var onDone: (() -> Void)?
    var finished = false
    var duration = 12.0
    var kind: Intro3DKind = .marbles
    static var marbleMaker: ((Int, Bool) -> SCNMaterial)?      // Samotnik: prawdziwe kulki z gry
    var realNodes: [SCNNode] = [], mirrorNodes: [SCNNode] = []

    convenience init(frame: NSRect, kind: Intro3DKind) { self.init(frame: frame, options: nil); self.kind = kind }

    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with e: NSEvent) { finish() }
    func finish() {
        guard !finished else { return }
        finished = true
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.6; self.animator().alphaValue = 0 }) { [weak self] in
            self?.isPlaying = false
            self?.removeFromSuperview()
            self?.onDone?()
        }
    }

    // zwierciadlana kopia: obiekt w pozycji rzeczywistej → (x, -1-y, z) (podłoga na y = -0.5)
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        for (r, m) in zip(realNodes, mirrorNodes) { let p = r.presentation; m.position = p.position; m.orientation = p.orientation; m.scale = p.scale; m.isHidden = p.isHidden }
    }

    /// Znak BLUEROOT (3 pasy + 3 liście) na przezroczystym tle: 600×1430 px, 5 px na jednostkę
    static func markImage(blue: Bool) -> CGImage {
        let pal: [UInt32] = blue ? [0x5AAEFF, 0x3A8DF5, 0x1F66DB] : [0xFF9433, 0xFF7A22, 0xF05A14]
        let bands: [[(CGFloat, CGFloat)]] = [[(-60, 0), (60, 0), (42.29, 62), (-42.29, 62)],
                                             [(-39.71, 71), (39.71, 71), (24, 126), (-24, 126)],
                                             [(-21.43, 135), (21.43, 135), (0, 210)]]
        let leaves: [(CGFloat, CGFloat, CGFloat)] = [(-28, -60, 50), (0, -72, 62), (28, -60, 50)]
        return i3img(600, 1430) { ctx in
            let m = CGAffineTransform(a: 5, b: 0, c: 0, d: -5, tx: 300, ty: 1060)
            ctx.setFillColor(i3rgb(0x34C26B))
            for (d, y, h) in leaves {
                var tr = CGAffineTransform(rotationAngle: d * .pi / 180).concatenating(m)
                ctx.addPath(CGPath(roundedRect: CGRect(x: -6, y: y, width: 12, height: h), cornerWidth: 6, cornerHeight: 6, transform: &tr))
            }
            ctx.fillPath()
            for (i, b) in bands.enumerated() {
                let p = CGMutablePath(); p.addLines(between: b.map { CGPoint(x: $0.0, y: $0.1) }, transform: m); p.closeSubpath()
                ctx.setFillColor(i3rgb(pal[i])); ctx.addPath(p); ctx.fillPath()
            }
        }
    }

    static func envImage() -> CGImage {
        i3img(1024, 512) { ctx in
            ctx.drawLinearGradient(i3grad([i3rgb(0x1B2A44), i3rgb(0x3A5A8C), i3rgb(0x0A0E18)], [0, 0.5, 1]), start: CGPoint(x: 0, y: 512), end: .zero, options: [])
            ctx.drawRadialGradient(i3grad([i3rgb(0xFFFFFF, 0.95), i3rgb(0xFFFFFF, 0)], [0, 1]), startCenter: CGPoint(x: 330, y: 400), startRadius: 0, endCenter: CGPoint(x: 330, y: 400), endRadius: 140, options: [])
            ctx.drawRadialGradient(i3grad([i3rgb(0x7FB8FF, 0.8), i3rgb(0x7FB8FF, 0)], [0, 1]), startCenter: CGPoint(x: 760, y: 330), startRadius: 0, endCenter: CGPoint(x: 760, y: 330), endRadius: 120, options: [])
        }
    }

    func glossy(_ hex: UInt32, mirror: Bool) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = i3c(hex); m.roughness.contents = 0.16; m.metalness.contents = 0.0
        m.clearCoat.contents = 0.6; m.clearCoatRoughness.contents = 0.05
        if mirror { m.cullMode = .front }
        return m
    }

    // MARK: Budowa sceny
    func build() {
        let env = ProcessInfo.processInfo.environment
        duration = 4.3 + 5.2 + 0.15 + 0.8 + 1.6
        let dur = duration
        backgroundColor = i3c(i3Bg)
        antialiasingMode = .multisampling4X
        allowsCameraControl = false
        isPlaying = true; rendersContinuously = true; preferredFramesPerSecond = 60
        delegate = self
        let sc = SCNScene()
        sc.background.contents = i3c(i3Bg)
        sc.lightingEnvironment.contents = Self.envImage(); sc.lightingEnvironment.intensity = 0.9
        sc.physicsWorld.gravity = SCNVector3(0, -14, 0)
        scene = sc

        let cam = SCNCamera()
        cam.fieldOfView = 24; cam.zNear = 0.5; cam.zFar = 60
        cam.wantsHDR = false
        let cn = SCNNode(); cn.camera = cam
        let dist: CGFloat = 9.0
        cn.position = SCNVector3(0, 0.15, dist)
        let aim = SCNNode(); aim.position = SCNVector3(0, -0.40, 0); sc.rootNode.addChildNode(aim)
        cn.constraints = [SCNLookAtConstraint(target: aim)]
        sc.rootNode.addChildNode(cn); pointOfView = cn

        func radial(_ rgbc: UInt32, _ a: CGFloat) -> CGImage {
            let n = 1024
            let cr = Double((rgbc >> 16) & 255) / 255, cg = Double((rgbc >> 8) & 255) / 255, cb = Double(rgbc & 255) / 255
            var buf = [UInt8](repeating: 0, count: n * n * 4)
            var seed: UInt64 = 0x9E3779B97F4A7C15
            for y in 0..<n { for x in 0..<n {
                let dx = (Double(x) + 0.5) / Double(n) * 2 - 1, dy = (Double(y) + 0.5) / Double(n) * 2 - 1
                let r = min(1, (dx * dx + dy * dy).squareRoot())
                let f = pow(1 - r, 2.2)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let noise = (Double(seed >> 40) / Double(1 << 24) - 0.5) * 3.0 / 255
                let al = max(0, min(1, Double(a) * f + (f > 0 ? noise : 0)))
                let i = (y * n + x) * 4
                buf[i] = UInt8(cr * al * 255); buf[i + 1] = UInt8(cg * al * 255); buf[i + 2] = UInt8(cb * al * 255); buf[i + 3] = UInt8(al * 255)
            } }
            let prov = CGDataProvider(data: Data(buf) as CFData)!
            return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        }
        let glowP = SCNPlane(width: 7, height: 7); let gm = SCNMaterial(); gm.lightingModel = .constant; gm.diffuse.contents = radial(0x2E86FF, 0.10); gm.blendMode = .add; gm.writesToDepthBuffer = false
        glowP.materials = [gm]; let glowN = SCNNode(geometry: glowP); glowN.position = SCNVector3(0, 0, -2.5); glowN.renderingOrder = -2; sc.rootNode.addChildNode(glowN)
        let shP = SCNPlane(width: kind == .marbles ? 5.8 : 3.4, height: 1.1); let shm = SCNMaterial(); shm.lightingModel = .constant; shm.diffuse.contents = radial(0x000000, 0.65); shm.blendMode = .alpha; shm.writesToDepthBuffer = false
        shP.materials = [shm]; let shN = SCNNode(geometry: shP); shN.eulerAngles.x = -.pi / 2; shN.position = SCNVector3(0, -0.499, 0.05); shN.renderingOrder = -1

        // światła jak w Bilardzie
        let key = SCNLight(); key.type = .spot; key.intensity = kind == .marbles ? 800 : 1700; key.temperature = 6200
        key.spotInnerAngle = 25; key.spotOuterAngle = 70; key.castsShadow = false
        let kn = SCNNode(); kn.light = key; kn.position = SCNVector3(-2.5, 5.0, 4.5)
        kn.constraints = [SCNLookAtConstraint(target: sc.rootNode)]
        sc.rootNode.addChildNode(kn)
        let amb = SCNLight(); amb.type = .ambient; amb.color = i3c(0x2A3342); amb.intensity = 500
        let an = SCNNode(); an.light = amb; sc.rootNode.addChildNode(an)
        let fill = SCNLight(); fill.type = .omni; fill.intensity = 300; fill.color = i3c(0x4DA3FF)
        let fnode = SCNNode(); fnode.light = fill; fnode.position = SCNVector3(3.5, 1.5, 2.5); sc.rootNode.addChildNode(fnode)

        let holder = SCNNode(); sc.rootNode.addChildNode(holder); holder.addChildNode(shN)
        let reflN = SCNNode()                                   // odbicie: rozmyte i przyciemnione, jak pod bilą
        if let bf = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 34.0]),
           let dim = CIFilter(name: "CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.22, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.22, z: 0, w: 0),
                                                                    "inputBVector": CIVector(x: 0, y: 0, z: 0.22, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.22)]) { reflN.filters = [bf, dim] }
        let mirrorRoot = SCNNode(); mirrorRoot.position = SCNVector3(0, -1.0, 0); mirrorRoot.scale = SCNVector3(1, -1, 1)
        reflN.addChildNode(mirrorRoot); holder.addChildNode(reflN)

        // podłoga i ściany tylko dla fizyki (niewidoczne)
        func wall(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            let n = SCNNode(); n.position = SCNVector3(x, y, 0)
            n.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: SCNBox(width: w, height: h, length: 2, chamferRadius: 0), options: nil))
            n.physicsBody?.restitution = kind == .marbles ? 0.6 : 0.25; n.physicsBody?.friction = 0.5
            holder.addChildNode(n)
        }
        wall(0, -1.0, 14, 1.0); wall(-1.55, 0, 0.4, 14); wall(1.55, 0, 0.4, 14)

        // spadające obiekty
        let pile = SCNNode(), pileM = SCNNode(); holder.addChildNode(pile); mirrorRoot.addChildNode(pileM)
        func drop(_ real: SCNNode, _ mir: SCNNode, _ shape: SCNPhysicsShape, at p: CGPoint, angle: CGFloat, spin: CGFloat, vx: CGFloat, bounce: CGFloat) {
            real.position = SCNVector3(p.x, p.y, 0); real.eulerAngles.z = angle
            let b = SCNPhysicsBody(type: .dynamic, shape: shape)
            b.mass = 1; b.restitution = bounce; b.friction = 0.45; b.rollingFriction = 0.08; b.damping = 0.05; b.angularDamping = 0.25
            b.velocityFactor = SCNVector3(1, 1, 0); b.angularVelocityFactor = SCNVector3(0, 0, 1)
            real.physicsBody = b
            b.velocity = SCNVector3(vx, 0, 0); b.angularVelocity = SCNVector4(0, 0, 1, spin)
            pile.addChildNode(real); pileM.addChildNode(mir)
            realNodes.append(real); mirrorNodes.append(mir)
        }
        if kind == .marbles {
            // jak w grze: biało-czarne kulki wpadają na rząd pól, a potem jedna przeskakuje drugą i ją zbija
            let rad: CGFloat = 0.28, d: CGFloat = 0.62, fy = -0.5 + rad
            func sx(_ k: Int) -> CGFloat { CGFloat(k - 4) * d }
            // (pole, biała?)
            let init_: [(Int, Bool)] = [(0, true), (1, false), (3, true), (4, false), (7, false), (8, true)]
            var nodes: [Int: SCNNode] = [:]
            for (n, (slot, white)) in init_.enumerated() {
                let base = Self.marbleMaker?(n, white)
                func make(_ mirror: Bool) -> SCNNode {
                    let sph = SCNSphere(radius: rad); sph.segmentCount = 64
                    if let bm = base { let m = bm.copy() as! SCNMaterial; if mirror { m.cullMode = .front }; sph.materials = [m] }
                    else { sph.materials = [glossy(white ? 0xDCD8D0 : 0x15171B, mirror: mirror)] }
                    return SCNNode(geometry: sph)
                }
                let real = make(false), mir = make(true)
                real.position = SCNVector3(sx(slot), 2.6 + CGFloat(n) * 0.35, 0)
                pile.addChildNode(real); pileM.addChildNode(mir)
                realNodes.append(real); mirrorNodes.append(mir); nodes[slot] = real
                let delay = 0.1 + Double(n) * 0.11
                real.runAction(.sequence([.wait(duration: delay), .customAction(duration: 0.55) { node, t in
                    let p = CGFloat(t) / 0.55
                    let y0 = 2.6 + CGFloat(n) * 0.35
                    let e = p < 0.72 ? (p / 0.72) * (p / 0.72) : 1
                    var y = y0 + (fy - y0) * e
                    if p >= 0.72 { let q = (p - 0.72) / 0.28; y = fy + 0.16 * sin(q * .pi) }   // jedno małe odbicie
                    node.position = SCNVector3(sx(slot), y, 0)
                }]))
            }
            // skoki: (z pola, nad polem, na pole, początek)
            let jumps: [(Int, Int, Int, Double)] = [(0, 1, 2, 1.05), (3, 4, 5, 1.45), (8, 7, 6, 1.85)]
            for (from, over, to, t0) in jumps {
                guard let mover = nodes[from], let victim = nodes[over] else { continue }
                mover.runAction(.sequence([.wait(duration: t0), .customAction(duration: 0.36) { node, t in
                    let p = CGFloat(t) / 0.36
                    let e = p * p * (3 - 2 * p)
                    node.position = SCNVector3(sx(from) + (sx(to) - sx(from)) * e, fy + 0.55 * sin(p * .pi), 0)
                }]))
                victim.runAction(.sequence([.wait(duration: t0 + 0.16), .group([
                    .customAction(duration: 0.3) { node, t in
                        let p = CGFloat(t) / 0.3
                        node.position = SCNVector3(sx(over) + 0.2 * p * (sx(over) > 0 ? 1 : -1), fy + 0.6 * p - 0.5 * p * p, 0)
                        node.scale = SCNVector3(1 - p, 1 - p, 1 - p)
                    }]), .hide()]))
            }
        } else {
            let cell: CGFloat = 0.2
            let specs: [(UInt32, [(CGFloat, CGFloat)])] = [
                (0x4DD0E1, [(0, 0), (1, 0), (2, 0), (3, 0)]), (0xFFD54F, [(0, 0), (1, 0), (0, 1), (1, 1)]),
                (0xB36AE2, [(0, 0), (1, 0), (2, 0), (1, 1)]), (0xFF9433, [(0, 0), (1, 0), (2, 0), (2, 1)]), (0x34C26B, [(1, 0), (2, 0), (0, 1), (1, 1)])]
            let start: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [(-0.9, 2.7, 0.4, 2.0, 0.3), (0.6, 3.4, -0.3, -2.5, -0.4), (-0.2, 4.2, 1.2, 1.5, 0.2), (0.9, 5.0, 0.7, -1.8, -0.6), (-0.7, 5.9, -0.5, 2.2, 0.5)]
            for (i, sp) in specs.enumerated() {
                let cx = sp.1.map { $0.0 }.reduce(0, +) / 4, cy = sp.1.map { $0.1 }.reduce(0, +) / 4
                let offs = sp.1.map { CGPoint(x: ($0.0 - cx) * cell, y: ($0.1 - cy) * cell) }
                func make(_ mirror: Bool) -> SCNNode {
                    let n = SCNNode(); let mat = glossy(sp.0, mirror: mirror)
                    for o in offs { let b = SCNBox(width: cell * 0.96, height: cell * 0.96, length: cell * 0.96, chamferRadius: 0.025); b.materials = [mat]
                        let bn = SCNNode(geometry: b); bn.position = SCNVector3(o.x, o.y, 0); n.addChildNode(bn) }
                    return n
                }
                let shape = SCNPhysicsShape(shapes: offs.map { _ in SCNPhysicsShape(geometry: SCNBox(width: cell, height: cell, length: cell, chamferRadius: 0), options: nil) },
                                            transforms: offs.map { NSValue(scnMatrix4: SCNMatrix4MakeTranslation($0.x, $0.y, 0)) })
                drop(make(false), make(true), shape, at: CGPoint(x: start[i].0, y: start[i].1), angle: start[i].2, spin: start[i].3, vx: start[i].4, bounce: 0.25)
            }
        }

        // znak BLUEROOT: najpierw pomarańczowy (po zderzeniu), potem niebieski; stoi na „podłodze”, z odbiciem
        func markPlane(_ blue: Bool, mirror: Bool) -> SCNNode {
            let p = SCNPlane(width: 1.45 * 600 / 1430, height: 1.45)
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = Self.markImage(blue: blue); m.diffuse.mipFilter = .linear
            m.blendMode = .alpha; m.writesToDepthBuffer = false; m.isDoubleSided = true; m.transparency = 0
            p.materials = [m]
            let n = SCNNode(geometry: p); n.position = SCNVector3(0, -0.5 + 0.725, 0.1); n.renderingOrder = 6
            return n
        }
        let orN = markPlane(false, mirror: false), blN = markPlane(true, mirror: false)
        let orM = markPlane(false, mirror: true), blM = markPlane(true, mirror: true)
        holder.addChildNode(orN); holder.addChildNode(blN); mirrorRoot.addChildNode(orM); mirrorRoot.addChildNode(blM)
        func fade(_ n: SCNNode, from a: CGFloat, to b: CGFloat, at t: Double, over d: Double) {
            n.runAction(.sequence([.wait(duration: t), .customAction(duration: d) { node, e in node.geometry?.firstMaterial?.transparency = a + (b - a) * CGFloat(e) / CGFloat(d) }]))
        }
        for n in [orN, orM] { fade(n, from: 0, to: 1, at: 2.45, over: 0.7); fade(n, from: 1, to: 0, at: 3.7, over: 0.9) }
        for n in [blN, blM] { fade(n, from: 0, to: 1, at: 3.7, over: 0.9) }
        for n in [pile, pileM] { n.runAction(.sequence([.wait(duration: 2.45), .customAction(duration: 0.55) { node, e in node.opacity = 1 - CGFloat(e) / 0.55 }, .hide()])) }
        // błysk przy zmianie koloru
        let flP = SCNPlane(width: 4, height: 4); let flm = SCNMaterial(); flm.lightingModel = .constant; flm.diffuse.contents = radial(0xBEDCFF, 0.55); flm.blendMode = .add; flm.writesToDepthBuffer = false; flm.transparency = 0
        flP.materials = [flm]; let flN = SCNNode(geometry: flP); flN.position = SCNVector3(0, 0.2, 0.3); flN.renderingOrder = 8; holder.addChildNode(flN)
        flN.runAction(.sequence([.wait(duration: 3.5), .customAction(duration: 1.0) { _, t in flm.transparency = sin(CGFloat(t) * .pi) }]))
        // powolny najazd kamery
        cn.runAction(.customAction(duration: dur) { node, t in
            let p = CGFloat(t) / CGFloat(dur)
            node.position = SCNVector3(0, 0.15, dist - 0.55 * p)
        })
        holder.runAction(.sequence([.wait(duration: dur), .run { [weak self] _ in DispatchQueue.main.async { self?.finish() } }]))

        // podpis (animowana linia pióra) + napis STUDIO: warstwa SpriteKit nad sceną
        let ov2 = SKScene(size: bounds.size); ov2.scaleMode = .resizeFill; ov2.backgroundColor = .clear
        let w = bounds.width, h = bounds.height
        let sw = min(w, h * 16 / 9), sh = sw * 9 / 16
        let rect = CGRect(x: (w - sw) / 2, y: (h - sh) / 2, width: sw, height: sh)
        let px = window?.backingScaleFactor ?? 2
        let writeStart = 4.3, writeDur = 5.2
        let studioAt = writeStart + writeDur + 0.15
        // gdy wchodzi STUDIO: tło (bila i jej odbicie) rozmywa się – płytka głębia ostrości
        cam.wantsDepthOfField = true; cam.wantsHDR = true; cam.bloomIntensity = 0; cam.screenSpaceAmbientOcclusionIntensity = 0; cam.wantsExposureAdaptation = false; cam.fStop = 64; cam.focusDistance = dist; cam.focalBlurSampleCount = 64
        cn.runAction(.sequence([.wait(duration: studioAt - 0.2), .customAction(duration: 1.6) { _, t in
            let p = CGFloat(t) / 1.6; let e = p * p * (3 - 2 * p)
            cam.focusDistance = dist - 7.0 * e
            cam.fStop = 64 - 63.8 * e
        }]), forKey: "dof")
        if let sigURL = Bundle.main.url(forResource: "podpis_sig", withExtension: "png"),
           let stuURL = Bundle.main.url(forResource: "podpis_studio", withExtension: "png"),
           let sigImg = NSImage(contentsOf: sigURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let sigW = sw * 0.56, sigH = sigW * CGFloat(sigImg.height) / CGFloat(sigImg.width)
            let center = CGPoint(x: rect.midX, y: rect.maxY - sh * CGFloat(Double(env["BILARD_INTRO_Y"] ?? "") ?? 0.60))
            // kolejność pisania: mapa czasu (16 bit w R,G) – piksel pojawia się, gdy pióro dojdzie do jego miejsca na linii
            guard let tmURL = Bundle.main.url(forResource: "podpis_time", withExtension: "png"),
                  let tmImg = NSImage(contentsOf: tmURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let penURL = Bundle.main.url(forResource: "podpis_pen", withExtension: "json"),
                  let pj = (try? Data(contentsOf: penURL)).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any],
                  let track = pj["tip"] as? [[Double]], !track.isEmpty else { return }
            let tmTex = SKTexture(cgImage: tmImg); tmTex.filteringMode = .nearest
            // warianty efektów: BILARD_INTRO_FX = A (kometa), B (złoty pył), C (neon), D (gwiazdki)
            let fx = (env["BILARD_INTRO_FX"] ?? "B").uppercased()
            let cfg: (wetT: String, wetG: String, wetLen: String, flash: String, halo: String, hc: String, col: UInt32, col2: UInt32, foil: String, m1: String, m2: String)
            switch fx {
            case "B": cfg = ("1.0, 0.80, 0.42", "0.30, 0.20, 0.04", "0.06", "1.0, 0.85, 0.5", "1.0", "mix(vec3(1.0,0.55,0.12), vec3(1.0,0.85,0.4), v_tex_coord.x)", 0xFFD98A, 0xFFB347, "1.0", "0.62, 0.42, 0.10", "1.0, 0.86, 0.45")
            case "C": cfg = ("0.35, 1.0, 0.95", "0.05, 0.35, 0.40", "0.12", "0.9, 0.4, 1.0", "1.0", "mix(vec3(0.1,0.9,1.0), vec3(0.85,0.3,1.0), v_tex_coord.x)", 0x6CF6FF, 0xE070FF, "0.0", "1.0, 1.0, 1.0", "1.0, 1.0, 1.0")
            case "D": cfg = ("1.0, 0.95, 0.85", "0.25, 0.22, 0.12", "0.05", "1.0, 1.0, 0.9", "1.0", "vec3(1.0,0.93,0.75)", 0xFFF3C8, 0xBEDCFF, "1.0", "0.45, 0.52, 0.62", "0.98, 0.99, 1.0")
            default:  cfg = ("0.50, 0.76, 1.0", "0.10, 0.22, 0.45", "0.09", "0.55, 0.78, 1.0", "1.0", "mix(vec3(0.25,0.55,1.0), vec3(0.6,0.85,1.0), v_tex_coord.x)", 0xBEDCFF, 0x78AAFF, "0.0", "1.0, 1.0, 1.0", "1.0, 1.0, 1.0")
            }
            let uT = SKUniform(name: "u_t", float: 0), uS = SKUniform(name: "u_s", float: -2), uH = SKUniform(name: "u_h", float: 0), uF = SKUniform(name: "u_f", float: Float(cfg.foil) ?? 0)
            let shader = SKShader(source: """
                void main() {
                    vec4 c = texture2D(u_texture, v_tex_coord);
                    vec4 tm = texture2D(u_order, v_tex_coord);
                    float raw = tm.r * 255.0 * 256.0 + tm.g * 255.0;
                    float t = (raw - 500.0) / 65000.0;
                    float a = (raw < 1.0) ? 0.0 : 1.0 - smoothstep(u_t - 0.006, u_t, t);
                    float wet = clamp(1.0 - (u_t - t) / \(cfg.wetLen), 0.0, 1.0);          // świeży tusz świeci
                    vec3 rgb = c.rgb * mix(vec3(1.0), vec3(\(cfg.wetT)), wet) + c.a * wet * vec3(\(cfg.wetG));
                    float d = v_tex_coord.x - u_s + 0.16 * (v_tex_coord.y - 0.5);  // pochylony błysk po skończeniu podpisu
                    rgb += c.a * exp(-d * d * 420.0) * vec3(\(cfg.flash)) * 0.9;
                    if (u_f > 0.0) {                                                // metaliczna folia: gradient + fazowane krawędzie + refleks
                        vec2 px = vec2(3.0 / 2400.0, 3.0 / 880.0);
                        float gx = texture2D(u_texture, v_tex_coord + vec2(px.x, 0.0)).a - texture2D(u_texture, v_tex_coord - vec2(px.x, 0.0)).a;
                        float gy = texture2D(u_texture, v_tex_coord + vec2(0.0, px.y)).a - texture2D(u_texture, v_tex_coord - vec2(0.0, px.y)).a;
                        vec3 n = normalize(vec3(-gx * 1.4, gy * 1.4, 0.55));
                        float g = v_tex_coord.y;
                        vec3 metal = mix(vec3(\(cfg.m2)), vec3(\(cfg.m1)), smoothstep(0.1, 0.75, g));
                        metal *= 0.82 + 0.18 * sin(g * 26.0 + v_tex_coord.x * 5.0);
                        float spec = pow(clamp(dot(n, normalize(vec3(0.45, 0.55, 0.7))), 0.0, 1.0), 5.0);
                        metal += spec * 0.55 + pow(clamp(dot(n, normalize(vec3(-0.5, -0.4, 0.75))), 0.0, 1.0), 8.0) * 0.25;
                        rgb = mix(c.a * metal, rgb, wet);
                    }
                    vec4 outc = vec4(rgb, c.a) * a;
                    if (u_h > 0.0) {                                                // neonowa poświata wokół liter
                        float h = 0.0;
                        for (int i = 0; i < 8; i++) {
                            float an = float(i) * 0.7854;
                            vec2 dir = vec2(cos(an) / 2400.0, sin(an) / 880.0);
                            vec2 u1 = v_tex_coord + dir * 12.0, u2 = v_tex_coord + dir * 34.0;
                            vec4 t1 = texture2D(u_order, u1), t2 = texture2D(u_order, u2);
                            float r1 = (t1.r * 255.0 * 256.0 + t1.g * 255.0 - 500.0) / 65000.0, r2 = (t2.r * 255.0 * 256.0 + t2.g * 255.0 - 500.0) / 65000.0;
                            float v1 = (t1.r + t1.g < 0.001) ? 0.0 : 1.0 - smoothstep(u_t - 0.006, u_t, r1);
                            float v2 = (t2.r + t2.g < 0.001) ? 0.0 : 1.0 - smoothstep(u_t - 0.006, u_t, r2);
                            h += texture2D(u_texture, u1).a * v1 + texture2D(u_texture, u2).a * v2 * 0.6;
                        }
                        h = clamp(h / 5.0, 0.0, 1.0) * u_h;
                        vec3 hc = \(cfg.hc);
                        outc += vec4(hc * h * 1.5, h * 0.9);
                    }
                    gl_FragColor = outc;
                }
                """, uniforms: [uT, uS, uH, uF, SKUniform(name: "u_order", texture: tmTex)])
            let sprite = SKSpriteNode(texture: SKTexture(cgImage: sigImg), size: CGSize(width: sigW, height: sigH))
            sprite.shader = shader; sprite.position = center
            ov2.addChild(sprite)
            // odbicie w szklanej tafli pod podpisem
            let maskTex = SKTexture(cgImage: i3img(8, 128) { c in
                c.drawLinearGradient(i3grad([i3rgb(0xFFFFFF, 0.15), i3rgb(0xFFFFFF, 0)], [0, 1]), start: CGPoint(x: 0, y: 128), end: CGPoint(x: 0, y: 0), options: [])
            })
            let reflCrop = SKCropNode()
            let reflMask = SKSpriteNode(texture: maskTex, size: CGSize(width: sigW, height: sigH)); let mirrorY = center.y + sigH / 2 - 0.80 * sigH     // lustro tuż pod podkreśleniem (jak pod bilą)
            reflMask.position = CGPoint(x: center.x, y: mirrorY - sigH * 0.5)
            reflCrop.maskNode = reflMask
            let refl = SKSpriteNode(texture: SKTexture(cgImage: sigImg), size: CGSize(width: sigW, height: sigH))
            refl.shader = shader; refl.yScale = -1; refl.position = CGPoint(x: center.x, y: 2 * mirrorY - center.y)
            reflCrop.addChild(refl)
            let blurN = SKEffectNode(); blurN.shouldEnableEffects = true; blurN.shouldRasterize = false
            blurN.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 12 * px])
            blurN.alpha = 0.55; blurN.addChild(reflCrop); ov2.addChild(blurN)
            let glowTex = SKTexture(cgImage: i3img(128, 128) { c in
                c.drawRadialGradient(i3grad([i3rgb(cfg.col, 0.95), i3rgb(cfg.col2, 0)], [0, 1]), startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                     endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
            })
            // gwiazdka 4-ramienna (flara)
            let starTex = SKTexture(cgImage: i3img(128, 128) { c in
                let g = i3grad([i3rgb(0xFFFFFF, 0), i3rgb(0xFFFFFF, 1), i3rgb(0xFFFFFF, 0)], [0, 0.5, 1])
                for vertical in [false, true] {
                    c.saveGState()
                    if vertical { c.translateBy(x: 128, y: 0); c.rotate(by: .pi / 2) }
                    c.clip(to: CGRect(x: 0, y: 61, width: 128, height: 6))
                    c.drawLinearGradient(g, start: CGPoint(x: 0, y: 64), end: CGPoint(x: 128, y: 64), options: [])
                    c.restoreGState()
                }
                c.drawRadialGradient(i3grad([i3rgb(0xFFFFFF, 0.9), i3rgb(0xFFFFFF, 0)], [0, 1]), startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                     endCenter: CGPoint(x: 64, y: 64), endRadius: 22, options: [])
            })
            let glow = SKSpriteNode(texture: glowTex, size: CGSize(width: sh * 0.15, height: sh * 0.15)); glow.alpha = 0; glow.blendMode = .add
            ov2.addChild(glow)
            let flare = SKSpriteNode(texture: starTex, size: CGSize(width: sh * 0.26, height: sh * 0.26)); flare.alpha = 0; flare.blendMode = .add
            flare.color = i3c(cfg.col); flare.colorBlendFactor = 0.6
            ov2.addChild(flare)
            // pozioma smuga anamorficzna
            let streak = SKSpriteNode(texture: glowTex, size: CGSize(width: sh * 0.9, height: sh * 0.022)); streak.alpha = 0; streak.blendMode = .add
            streak.color = i3c(cfg.col); streak.colorBlendFactor = 0.5; ov2.addChild(streak)
            let sparks = SKEmitterNode()
            sparks.particleTexture = glowTex; sparks.particleBirthRate = 0
            sparks.particleColor = i3c(cfg.col); sparks.particleColorBlendFactor = 1
            sparks.particleBlendMode = .add; sparks.targetNode = ov2
            var sparkRate: CGFloat = 140
            switch fx {
            case "B":   // złoty pył opadający
                sparkRate = 260; sparks.particleLifetime = 1.4; sparks.particleLifetimeRange = 0.4
                sparks.particleSpeed = 20; sparks.particleSpeedRange = 16; sparks.emissionAngle = -.pi / 2; sparks.emissionAngleRange = .pi * 0.9
                sparks.yAcceleration = -70; sparks.particleScale = 0.12; sparks.particleScaleRange = 0.08; sparks.particleScaleSpeed = -0.05
                sparks.particleAlpha = 0.9; sparks.particleAlphaSpeed = -0.8; sparks.particlePositionRange = CGVector(dx: 6, dy: 6)
            case "C":   // neonowe iskry
                sparkRate = 380; sparks.particleLifetime = 0.8; sparks.particleLifetimeRange = 0.2
                sparks.particleSpeed = 44; sparks.particleSpeedRange = 30; sparks.emissionAngleRange = .pi * 2
                sparks.particleScale = 0.12; sparks.particleScaleRange = 0.06; sparks.particleScaleSpeed = -0.08
                sparks.particleAlpha = 0.9; sparks.particleAlphaSpeed = -1.5; sparks.particlePositionRange = CGVector(dx: 3, dy: 3)
                sparks.particleColorSequence = SKKeyframeSequence(keyframeValues: [i3c(0x6CF6FF), i3c(0xE070FF)], times: [0, 1])
                sparks.particleColorBlendFactor = 1
            case "D":   // gwiazdki zostające na literach
                sparkRate = 70; sparks.particleTexture = starTex; sparks.particleLifetime = 0.8; sparks.particleLifetimeRange = 0.3
                sparks.particleSpeed = 6; sparks.particleSpeedRange = 8; sparks.emissionAngleRange = .pi * 2
                sparks.particleScale = 0.28; sparks.particleScaleRange = 0.16; sparks.particleScaleSpeed = -0.2
                sparks.particleRotationRange = .pi; sparks.particleRotationSpeed = 2.5
                sparks.particleAlpha = 0.95; sparks.particleAlphaSpeed = -1.2; sparks.particlePositionRange = CGVector(dx: 10, dy: 10)
            default:    // A – kometa z długim ogonem
                sparkRate = 700; sparks.particleLifetime = 1.4; sparks.particleLifetimeRange = 0.3
                sparks.particleSpeed = 4; sparks.particleSpeedRange = 6; sparks.emissionAngleRange = .pi * 2
                sparks.particleScale = 0.16; sparks.particleScaleRange = 0.03; sparks.particleScaleSpeed = -0.1
                sparks.particleAlpha = 0.8; sparks.particleAlphaSpeed = -1.0; sparks.particlePositionRange = CGVector(dx: 1, dy: 1)
            }
            ov2.addChild(sparks)
            // migotanie gwiazdek po skończeniu podpisu (A, B, D) – w losowych punktach linii pióra
            if fx != "C" {
                let n = fx == "D" ? 26 : 16
                for _ in 0..<n {
                    let tp = track[Int.random(in: 0..<track.count)]
                    let st = SKSpriteNode(texture: starTex, size: CGSize(width: sh * CGFloat.random(in: 0.025...0.07), height: sh * CGFloat.random(in: 0.025...0.07)))
                    st.position = CGPoint(x: center.x - sigW / 2 + CGFloat(tp[0]) * sigW, y: center.y + sigH / 2 - CGFloat(tp[1]) * sigH)
                    st.alpha = 0; st.blendMode = .add; st.zRotation = CGFloat.random(in: -0.3...0.3); st.color = i3c(cfg.col); st.colorBlendFactor = 0.5
                    st.run(.sequence([.wait(forDuration: writeStart + writeDur + Double.random(in: 0.0...1.5)),
                                      .group([.sequence([.fadeAlpha(to: 1, duration: 0.12), .fadeOut(withDuration: 0.5)]),
                                              .sequence([.scale(to: 1.4, duration: 0.15), .scale(to: 0.2, duration: 0.5)])]), .removeFromParent()]))
                    ov2.addChild(st)
                }
            }
            // finał: fontanna iskier jadąca z błyskiem, fale uderzeniowe i rozbłysk
            let fountain = SKEmitterNode()
            fountain.particleTexture = glowTex; fountain.particleBirthRate = 0; fountain.targetNode = ov2
            fountain.particleLifetime = 1.0; fountain.particleLifetimeRange = 0.4; fountain.particleSpeed = 150; fountain.particleSpeedRange = 90
            fountain.emissionAngle = .pi / 2; fountain.emissionAngleRange = .pi * 0.8; fountain.yAcceleration = -160
            fountain.particleScale = 0.14; fountain.particleScaleRange = 0.08; fountain.particleScaleSpeed = -0.1
            fountain.particleAlpha = 1; fountain.particleAlphaSpeed = -0.9; fountain.particleColor = i3c(cfg.col); fountain.particleColorBlendFactor = 1
            fountain.particleBlendMode = .add; fountain.position = CGPoint(x: -9999, y: -9999); ov2.addChild(fountain)
            let flashN = SKSpriteNode(color: i3c(cfg.col), size: CGSize(width: sw * 2, height: sh * 2)); flashN.alpha = 0; flashN.blendMode = .add
            flashN.position = CGPoint(x: rect.midX, y: rect.midY); ov2.addChild(flashN)
            for k in 0..<3 {
                let ring = SKShapeNode(circleOfRadius: sh * 0.05); ring.strokeColor = i3c(k == 1 ? cfg.col2 : cfg.col); ring.lineWidth = 2; ring.fillColor = NSColor.clear
                ring.blendMode = SKBlendMode.add; ring.alpha = 0; ring.position = center; ov2.addChild(ring)
                let big = CGFloat(sw / (sh * 0.1) * 0.45)
                let pop = SKAction.sequence([SKAction.fadeAlpha(to: 0.45, duration: 0.05), SKAction.fadeOut(withDuration: 0.9)])
                let grow = SKAction.scale(to: big, duration: 1.0)
                ring.run(SKAction.sequence([SKAction.wait(forDuration: writeStart + writeDur + 0.05 + Double(k) * 0.18), SKAction.group([pop, grow])]))
            }
            flashN.run(.sequence([.wait(forDuration: writeStart + writeDur), .fadeAlpha(to: 0.22, duration: 0.08), .fadeOut(withDuration: 0.7)]))
            sprite.run(.customAction(withDuration: dur) { _, e in
                let t = Double(e) - writeStart
                guard t >= 0 else { uT.floatValue = -1; return }
                let p = min(1, t / writeDur)
                uT.floatValue = Float(p >= 1 ? 1.1 : p)
                glow.alpha = (p > 0 && p < 1) ? 1 : 0
                flare.alpha = (p > 0 && p < 1) ? CGFloat(0.75 + 0.25 * sin(t * 40)) : 0
                flare.zRotation = CGFloat(t * 2.0); streak.alpha = flare.alpha * 0.8
                sparks.particleBirthRate = (p > 0 && p < 1) ? sparkRate : 0
                uS.floatValue = Float(-0.2 + max(0, t - writeDur) / 1.3 * 1.5)
                uH.floatValue = Float(min(1, p * 4) * (p >= 1 ? 0.28 + 0.07 * sin((t - writeDur) * 4) + 0.7 * max(0, 1 - (t - writeDur) / 1.0) : 1))
                let q = (t - writeDur) / 1.3
                if q > 0 && q < 1 {
                    fountain.particleBirthRate = 500
                    fountain.position = CGPoint(x: center.x - sigW / 2 + CGFloat(-0.2 + q * 1.5) * sigW, y: center.y - sigH * 0.1)
                } else { fountain.particleBirthRate = 0 }
                if p < 1 {
                    sparks.position = glow.position
                    let i = min(track.count - 1, Int(p * Double(track.count - 1)))
                    glow.position = CGPoint(x: center.x - sigW / 2 + CGFloat(track[i][0]) * sigW, y: center.y + sigH / 2 - CGFloat(track[i][1]) * sigH)
                    flare.position = glow.position; streak.position = glow.position
                }
            })
            if let st = NSImage(contentsOf: stuURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let studio = SKSpriteNode(texture: SKTexture(cgImage: st), size: CGSize(width: sigW, height: sigH))
                studio.position = center; studio.alpha = 0
                studio.run(.sequence([.wait(forDuration: studioAt), .fadeIn(withDuration: 0.8)]))
                ov2.addChild(studio)
            }
        }
        overlaySKScene = ov2
    }
}
