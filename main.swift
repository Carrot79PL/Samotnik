// Samotnik — klasyczna gra w kulki (peg solitaire) dla macOS.
// Scena 3D (SceneKit, PBR) renderowana w natywnej rozdzielczości ekranu; plansza przechyla się w stronę kursora.

import Cocoa
import SceneKit
import SpriteKit

/// Motyw: kolory sceny, planszy i nakładki 2D.
struct Theme {
    let light: Bool
    let bg: UInt32, text: UInt32, panel: UInt32
    let lacquer: UInt32, base: UInt32, floor: UInt32
    let vignette: UInt32, vignetteAlpha: CGFloat
    let ambient: CGFloat, exposure: CGFloat
    let tint: CGFloat                    // jasność kolorowych reflektorów
    let dirt: CGFloat, dust: UInt32      // siła i barwa kurzu oraz śladów na lakierze
    let camVignette: CGFloat, bloom: CGFloat
    let key: CGFloat, studio: CGFloat, dof: Bool   // światło główne, siła studia odbić, głębia ostrości
    let ssao: CGFloat, shadowAlpha: CGFloat, shadowSoft: CGFloat, floorY: CGFloat, ambientTint: UInt32

    static let dark = Theme(light: false, bg: 0x111418, text: 0xEDEDED, panel: 0x090A0D,
                            lacquer: 0x232930, base: 0x14181D, floor: 0x0C0F12,
                            vignette: 0x000000, vignetteAlpha: 0.72, ambient: 140, exposure: -0.15,
                            tint: 220, dirt: 1, dust: 0xCFC8BC, camVignette: 0.7, bloom: 0.3, key: 850, studio: 0.9, dof: true,
                            ssao: 0.7, shadowAlpha: 0.72, shadowSoft: 9, floorY: -1.7, ambientTint: 0x99ADCC)
    // czysty, chłodny jasny motyw: prawie biel, biały lakier na jasnoszarej podstawie, bez kolorowych plam
    static let light = Theme(light: true, bg: 0xEEF0F3, text: 0x1B1F24, panel: 0xF7F8FA,
                             lacquer: 0xF2F2F0, base: 0xC3C8CF, floor: 0xE7E9EC,
                             vignette: 0x2A3038, vignetteAlpha: 0.12, ambient: 160, exposure: 0,
                             tint: 0, dirt: 0.3, dust: 0x9AA0A8, camVignette: 0, bloom: 0.04, key: 480, studio: 0.4, dof: false,
                             ssao: 0.2, shadowAlpha: 0.2, shadowSoft: 18, floorY: -0.95, ambientTint: 0xFFFFFF)
    var bgColor: NSColor { NSColor(cgColor: rgb(bg))! }
    var textColor: NSColor { NSColor(cgColor: rgb(text))! }
    var panelColor: NSColor { NSColor(cgColor: rgb(panel))! }
}

var theme = Theme.dark
var bgColor: NSColor { theme.bgColor }

func pbr(_ hex: UInt32, rough: CGFloat, metal: CGFloat = 0, clear: CGFloat = 0) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = NSColor(cgColor: rgb(hex))
    m.roughness.contents = rough
    m.metalness.contents = metal
    if clear > 0 {
        m.clearCoat.contents = clear
        m.clearCoatRoughness.contents = 0.03
    }
    return m
}

func glowMaterial(_ alpha: CGFloat = 1) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = accent.withAlphaComponent(alpha)
    m.emission.contents = accent.withAlphaComponent(alpha)
    return m
}

/// Powtarzalny generator losowy — ta sama „kula” wygląda tak samo przy każdym użyciu.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Materiał kuli z wypalonej, niepowtarzalnej powierzchni.
func marbleMaterial(_ look: Look, seed: UInt64) -> SCNMaterial {
    let sf = bake(look, seed: seed)
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = sf.diffuse
    m.roughness.contents = sf.rough
    m.metalness.contents = sf.metal
    if let e = sf.emission { m.emission.contents = e }
    if let n = sf.normal { m.normal.contents = n }
    m.setValue(NSColor(srgbRed: min(1, sf.avg.x), green: min(1, sf.avg.y), blue: min(1, sf.avg.z), alpha: 1), forKey: "avgColor")
    if sf.clear > 0 {
        m.clearCoat.contents = sf.clear
        m.clearCoatRoughness.contents = 0.02 + Double(seed % 7) * 0.01
    }
    return m
}

/// Mapa otoczenia (equirect): ciemne studio z miękkimi softboxami — daje odbicia na kulach.
func environmentImage() -> CGImage {
    makeImage(1024, 512) { ctx in
        ctx.drawLinearGradient(gradient([rgb(0x050607), rgb(0x151a20), rgb(0x2C333C)], [0, 0.55, 1]),
                               start: .zero, end: CGPoint(x: 0, y: 512), options: [])
        for (x, y, r, a) in [(300.0, 420.0, 120.0, 1.0), (760.0, 360.0, 70.0, 0.45), (520.0, 470.0, 160.0, 0.35)] {
            ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, a), rgb(0xFFFFFF, 0)], [0, 1]),
                                   startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                   endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
        }
    }
}

/// Obrys planszy jako suma zaokrąglonych pól i mostków między sąsiadami, opcjonalnie z otworami.
func boardPath(_ b: Board, pad: CGFloat, radius: CGFloat, holes: CGFloat?) -> NSBezierPath {
    let s = 0.5 + pad
    let m = CGMutablePath()
    for p in b.all {
        let x = b.x(p), y = b.y(p)
        m.addPath(CGPath(roundedRect: CGRect(x: x - s, y: y - s, width: 2 * s, height: 2 * s), cornerWidth: radius, cornerHeight: radius, transform: nil))
        if b.has(Pos(r: p.r, c: p.c + 1)) { m.addRect(CGRect(x: x, y: y - s, width: 1, height: 2 * s)) }
        if b.has(Pos(r: p.r + 1, c: p.c)) { m.addRect(CGRect(x: x - s, y: y - 1, width: 2 * s, height: 1)) }
    }
    let out = CGMutablePath()
    out.addPath(m.normalized(using: .winding))
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

// MARK: - Logo studia (Orange Carrot)

/// Części znaku z mark.svg (viewBox -80 -90 160 310): trzy pasy marchewki i liście.
func markPart(_ part: Int, height: CGFloat) -> CGImage {
    let s = height / 310
    return makeImage(Int(160 * s), Int(height)) { ctx in
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: s, y: -s)
        ctx.translateBy(x: 80, y: 90)
        func poly(_ pts: [(CGFloat, CGFloat)], _ hex: UInt32) {
            ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
            pts.dropFirst().forEach { ctx.addLine(to: CGPoint(x: $0.0, y: $0.1)) }
            ctx.closePath()
            ctx.setFillColor(rgb(hex))
            ctx.fillPath()
        }
        switch part {
        case 0: poly([(-60, 0), (60, 0), (42.29, 62), (-42.29, 62)], 0xFF9433)
        case 1: poly([(-39.71, 71), (39.71, 71), (24, 126), (-24, 126)], 0xFF7A22)
        case 2: poly([(-21.43, 135), (21.43, 135), (0, 210)], 0xF05A14)
        default:
            for (deg, y, h) in [(-28.0, -60.0, 50.0), (0, -72, 62), (28, -60, 50)] {
                ctx.saveGState()
                ctx.rotate(by: deg * .pi / 180)
                ctx.addPath(CGPath(roundedRect: CGRect(x: -6, y: y, width: 12, height: h), cornerWidth: 6, cornerHeight: 6, transform: nil))
                ctx.setFillColor(rgb(0x34C26B))
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
    }
}

func wordmarkTexture(widthPx: CGFloat) -> SKTexture? {
    guard let url = Bundle.main.url(forResource: "wordmark", withExtension: "svg"),
          let img = NSImage(contentsOf: url) else { return nil }
    var r = CGRect(x: 0, y: 0, width: widthPx, height: widthPx * 0.15)
    guard let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil) else { return nil }
    let t = SKTexture(cgImage: cg)
    t.filteringMode = .linear
    return t
}

// MARK: - HUD (nakładka 2D)

struct MenuRow { let name: String; let value: String?; let dim: Bool; var plain = false }

final class HUD: SKScene {
    var px: CGFloat = 2
    let gameLayer = SKNode(), panel = SKNode(), sign = SKNode()
    let vignette = SKSpriteNode()
    var folding = false
    let title = SKLabelNode(), info = SKLabelNode(), count = SKLabelNode(), sub = SKLabelNode(), help = SKLabelNode()
    var gameText = (count: "", sub: "", info: "", help: "")
    var redraw: (() -> Void)?
    let caption = SKLabelNode(), captionBack = SKShapeNode()
    var captionText: String?
    var intro: SKNode?
    var introDone: (() -> Void)?
    var introBuilt = CGSize.zero          // rozmiar, w jakim zbudowano intro
    let curtain = SKSpriteNode()
    var about: SKNode?
    var rows: [(y: CGFloat, mid: CGFloat?)] = []
    private var spare: [SKLabelNode] = [], used: [SKLabelNode] = []
    var rowH: CGFloat = 0, rowX: CGFloat = 0

    func setup() {
        scaleMode = .resizeFill
        backgroundColor = .clear
        title.horizontalAlignmentMode = .left; title.verticalAlignmentMode = .top
        info.horizontalAlignmentMode = .left; info.verticalAlignmentMode = .top
        count.horizontalAlignmentMode = .right; count.verticalAlignmentMode = .top
        sub.horizontalAlignmentMode = .right; sub.verticalAlignmentMode = .top
        help.horizontalAlignmentMode = .center; help.verticalAlignmentMode = .bottom
        for l in [title, info, count, sub, help] { gameLayer.addChild(l) }
        panel.zPosition = 100
        applyTheme()
        vignette.zPosition = -20
        addChild(vignette)
        [gameLayer, panel, sign].forEach(addChild)
        caption.horizontalAlignmentMode = .center
        caption.verticalAlignmentMode = .center
        let cap = SKNode()
        cap.zPosition = 150
        cap.addChild(captionBack)
        cap.addChild(caption)
        cap.name = "caption"
        addChild(cap)
        gameLayer.alpha = 0
        sign.alpha = 0
        curtain.color = Theme.dark.bgColor               // ciemna kurtyna od pierwszej klatki, aż ruszy intro
        curtain.size = CGSize(width: 10000, height: 10000)
        curtain.zPosition = 300
        addChild(curtain)
    }

    /// Winieta i tło podpisu w kolorach bieżącego motywu.
    func applyTheme() {
        vignette.texture = makeTexture(512, 512) { ctx in
            let c = CGPoint(x: 256, y: 256)
            let stops: [CGFloat] = [0, 0.45, 0.7, 0.88, 1]
            ctx.drawRadialGradient(gradient(stops.map { rgb(theme.vignette, pow($0, 2.2) * theme.vignetteAlpha) }, stops),
                                   startCenter: c, startRadius: 0, endCenter: c, endRadius: 256 * 1.42, options: [.drawsAfterEndLocation])
        }
        captionBack.fillColor = theme.panelColor.withAlphaComponent(0.82)
        captionBack.strokeColor = theme.textColor.withAlphaComponent(0.08)
        layoutSign()
        refresh()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        if let o = intro, introBuilt.height > 0 {      // logo dopasowuje się do nowego rozmiaru okna
            let k = size.height / introBuilt.height
            o.setScale(k)
            o.position = CGPoint(x: size.width / 2 - k * introBuilt.width / 2, y: size.height * 0.56 - k * introBuilt.height * 0.56)
        }
        layoutSign()
        refresh()
    }

    func text(_ l: SKLabelNode, _ s: String, size: CGFloat, font: String = "AvenirNext-UltraLight", alpha: CGFloat, kern: CGFloat = 0, color: NSColor? = nil) {
        let f = NSFont(name: font, size: size) ?? NSFont.systemFont(ofSize: size, weight: .light)
        l.attributedText = NSAttributedString(string: s, attributes: [
            .font: f, .foregroundColor: (color ?? theme.textColor).withAlphaComponent(theme.light ? min(1, alpha * 1.6) : alpha), .kern: kern])
    }

    func label(_ s: String, size: CGFloat, font: String = "AvenirNext-Regular", alpha: CGFloat, at p: CGPoint,
               align: SKLabelHorizontalAlignmentMode = .left, kern: CGFloat = 0.5, color: NSColor? = nil) -> SKLabelNode {
        let l: SKLabelNode
        if let r = spare.popLast() { l = r } else { l = SKLabelNode(); panel.addChild(l) }
        l.removeAllActions()
        l.isHidden = false
        l.alpha = 1
        l.setScale(1)
        used.append(l)
        text(l, s, size: size, font: font, alpha: alpha, kern: kern, color: color)
        l.horizontalAlignmentMode = align
        l.verticalAlignmentMode = .center
        l.position = p
        return l
    }

    var pad: CGFloat { max(44, size.height * 0.055) }

    func refresh() {
        let w = size.width, h = size.height
        guard w > 10, h > 10 else { return }
        vignette.position = CGPoint(x: w / 2, y: h / 2)
        vignette.size = size
        text(title, "SAMOTNIK", size: h * 0.024, font: "AvenirNext-Regular", alpha: 0.55, kern: h * 0.012)
        title.position = CGPoint(x: pad, y: h - pad)
        text(info, gameText.info, size: h * 0.015, font: "AvenirNext-Regular", alpha: 0.35, kern: 0.5)
        info.position = CGPoint(x: pad, y: h - pad - h * 0.04)
        text(count, gameText.count, size: h * 0.07, alpha: 0.85)
        count.position = CGPoint(x: w - pad, y: h - pad + h * 0.012)
        text(sub, gameText.sub, size: h * 0.016, font: "AvenirNext-Regular", alpha: 0.4, kern: 1)
        sub.position = CGPoint(x: w - pad, y: h - pad - h * 0.07)
        text(help, gameText.help, size: h * 0.0145, font: "AvenirNext-Regular", alpha: 0.3, kern: 0.5)
        help.position = CGPoint(x: w / 2, y: pad * 0.6)
        layoutCaption()
        redraw?()
    }

    /// Napis na dole ekranu (samouczek, podpowiedzi); nil chowa go. hide > 0 — schowaj po tylu sekundach.
    func say(_ s: String?, hide: Double = 0) {
        captionText = s
        guard let cap = childNode(withName: "caption") else { return }
        cap.removeAllActions()
        guard s != nil else { cap.run(.fadeOut(withDuration: 0.3)); return }
        layoutCaption()
        cap.alpha = 0
        var seq: [SKAction] = [.fadeIn(withDuration: 0.35)]
        if hide > 0 { seq += [.wait(forDuration: hide), .fadeOut(withDuration: 0.6)] }
        cap.run(.sequence(seq))
    }

    func layoutCaption() {
        guard let s = captionText else { return }
        let h = size.height
        text(caption, s, size: h * 0.021, font: "AvenirNext-Regular", alpha: 0.95, kern: 0.5)
        let y = pad * 0.6 + h * 0.075
        caption.position = CGPoint(x: size.width / 2, y: y)
        let f = caption.frame.insetBy(dx: -h * 0.025, dy: -h * 0.014)
        captionBack.path = CGPath(roundedRect: f, cornerWidth: f.height / 2, cornerHeight: f.height / 2, transform: nil)
    }

    /// Co pół sekundy zmienia się zwykle tylko czas — przerysowujemy wyłącznie napisy, które się zmieniły.
    func setGame(count c: String, sub s: String, info i: String, help hp: String) {
        let old = gameText
        gameText = (c, s, i, hp)
        let h = size.height
        guard h > 10 else { return }
        if old.count != c { text(count, c, size: h * 0.07, alpha: 0.85) }
        if old.sub != s { text(sub, s, size: h * 0.016, font: "AvenirNext-Regular", alpha: 0.4, kern: 1) }
        if old.info != i { text(info, i, size: h * 0.015, font: "AvenirNext-Regular", alpha: 0.35, kern: 0.5) }
        if old.help != hp { text(help, hp, size: h * 0.0145, font: "AvenirNext-Regular", alpha: 0.3, kern: 0.5) }
    }

    func showGameLayer(_ on: Bool) {
        gameLayer.removeAllActions()
        gameLayer.run(.fadeAlpha(to: on ? 1 : 0, duration: 0.4))
    }

    /// Czy punkt trafia w mały znak studia (z marginesem, żeby łatwo było kliknąć).
    func signHit(_ pt: CGPoint) -> Bool {
        guard sign.alpha > 0.1, !sign.children.isEmpty else { return false }
        return sign.calculateAccumulatedFrame().insetBy(dx: -12, dy: -12).contains(pt)
    }

    /// Karta „O grze”: nazwa, wersja, autor, studio.
    func showAbout() {
        about?.removeFromParent()
        let w = size.width, h = size.height
        let o = SKNode()
        o.zPosition = 260
        let dim = SKSpriteNode(color: theme.panelColor, size: size)
        dim.position = CGPoint(x: w / 2, y: h / 2)
        dim.alpha = 0.7
        o.addChild(dim)
        let cw = h * 0.62, ch = h * 0.56
        let card = SKShapeNode(rect: CGRect(x: -cw / 2, y: -ch / 2, width: cw, height: ch), cornerRadius: h * 0.025)
        card.fillColor = theme.light ? NSColor(white: 1, alpha: 0.96) : NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 0.96)
        card.strokeColor = theme.textColor.withAlphaComponent(0.1)
        card.position = CGPoint(x: w / 2, y: h / 2)
        o.addChild(card)
        let mh = h * 0.13, mw = mh * 160 / 310
        for i in 0..<4 {
            let s = SKSpriteNode(texture: SKTexture(cgImage: markPart(i, height: mh * px)), size: CGSize(width: mw, height: mh))
            s.position = CGPoint(x: w / 2, y: h / 2 + ch * 0.27)
            o.addChild(s)
        }
        func line(_ t: String, _ y: CGFloat, _ sz: CGFloat, _ font: String, _ a: CGFloat, color: NSColor? = nil, kern: CGFloat = 0.5) {
            let l = SKLabelNode()
            text(l, t, size: h * sz, font: font, alpha: a, kern: kern, color: color)
            l.verticalAlignmentMode = .center
            l.position = CGPoint(x: w / 2, y: h / 2 + ch * y)
            o.addChild(l)
        }
        line("SAMOTNIK", 0.02, 0.05, "AvenirNext-UltraLight", 0.95, kern: h * 0.014)
        line("wersja 1.0", -0.1, 0.019, "AvenirNext-Regular", 0.6)
        line("autor: Tomasz Marchewka", -0.2, 0.022, "AvenirNext-DemiBold", 0.9)
        line("© 2026 Orange Carrot Studio", -0.3, 0.016, "AvenirNext-Regular", 0.5)
        line("kliknij lub naciśnij Esc, aby zamknąć", -0.42, 0.013, "AvenirNext-Regular", 0.35, color: accent)
        o.alpha = 0
        o.run(.fadeIn(withDuration: 0.25))
        addChild(o)
        about = o
    }

    func hideAbout() {
        guard let o = about else { return }
        about = nil
        o.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
    }

    /// Mały znak studia w prawym dolnym rogu.
    func layoutSign() {
        sign.removeAllChildren()
        let h = size.height, mh = h * 0.045, mw = mh * 160 / 310
        var x = size.width - pad
        if let wt = wordmarkTexture(widthPx: h * 0.15 * px) {
            let ws = SKSpriteNode(texture: wt, size: CGSize(width: h * 0.15, height: h * 0.0225))
            ws.anchorPoint = CGPoint(x: 1, y: 0.5)
            ws.position = CGPoint(x: x, y: pad * 0.6 + mh * 0.35)
            if theme.light { ws.color = theme.textColor; ws.colorBlendFactor = 1 }   // biały napis studia nie zniknie na jasnym tle
            sign.addChild(ws)
            x -= h * 0.15 + mw * 0.6
        }
        for i in 0..<4 {
            let s = SKSpriteNode(texture: SKTexture(cgImage: markPart(i, height: mh * px)), size: CGSize(width: mw, height: mh))
            s.position = CGPoint(x: x - mw / 2, y: pad * 0.6 + mh * 0.35)
            sign.addChild(s)
        }
    }

    // MARK: Intro

    func playIntro(done: @escaping () -> Void) {
        introDone = done
        let w = size.width, h = size.height
        introBuilt = size
        let o = SKNode()
        o.zPosition = 200
        let mh = h * 0.3, mw = mh * 160 / 310
        let cx = w / 2, cy = h * 0.56

        let glow = makeTexture(256, 256) { ctx in
            ctx.drawRadialGradient(gradient([rgb(0xFF7A22, 0.5), rgb(0xFF7A22, 0)], [0, 1]),
                                   startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                   endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        }
        let back = SKSpriteNode(color: Theme.dark.bgColor, size: CGSize(width: w * 4, height: h * 4))  // logo zawsze na ciemnym tle
        back.position = CGPoint(x: w / 2, y: h / 2)
        back.zPosition = -1
        o.addChild(back)
        let g = SKSpriteNode(texture: glow, size: CGSize(width: mh * 1.15, height: mh * 1.15))
        g.position = CGPoint(x: cx, y: cy)
        g.alpha = 0
        g.blendMode = .add
        g.run(.fadeAlpha(to: 0.28, duration: 1.8))
        o.addChild(g)

        for i in 0..<3 {
            let s = SKSpriteNode(texture: SKTexture(cgImage: markPart(i, height: mh * px)), size: CGSize(width: mw, height: mh))
            s.position = CGPoint(x: cx, y: cy - mh * 0.12)
            s.alpha = 0
            let a = SKAction.group([.fadeIn(withDuration: 0.5), .moveTo(y: cy, duration: 0.55)]); a.timingMode = .easeOut
            s.run(.sequence([.wait(forDuration: 0.25 + Double(i) * 0.18), a]))
            o.addChild(s)
        }
        let lv = SKSpriteNode(texture: SKTexture(cgImage: markPart(3, height: mh * px)), size: CGSize(width: mw, height: mh))
        lv.anchorPoint = CGPoint(x: 0.5, y: 220.0 / 310)
        lv.position = CGPoint(x: cx, y: cy - mh / 2 + mh * 220 / 310)
        lv.yScale = 0.001
        let grow = SKAction.scaleY(to: 1.08, duration: 0.35); grow.timingMode = .easeOut
        let settle = SKAction.scaleY(to: 1, duration: 0.2); settle.timingMode = .easeInEaseOut
        lv.run(.sequence([.wait(forDuration: 0.95), grow, settle]))
        o.addChild(lv)

        let ww = min(w * 0.42, h * 0.8)
        if let wt = wordmarkTexture(widthPx: ww * px) {
            let ws = SKSpriteNode(texture: wt, size: CGSize(width: ww, height: ww * 0.15))
            ws.position = CGPoint(x: cx, y: cy - mh / 2 - h * 0.08)
            ws.alpha = 0
            ws.xScale = 0.94
            let a = SKAction.group([.fadeIn(withDuration: 0.9), .scaleX(to: 1, duration: 0.9)]); a.timingMode = .easeOut
            ws.run(.sequence([.wait(forDuration: 1.3), a]))
            o.addChild(ws)
        }
        o.run(.sequence([.wait(forDuration: 4.0), .fadeOut(withDuration: 1.1), .run { [weak self] in DispatchQueue.main.async { locked { self?.finishIntro() } } }]))
        addChild(o)
        intro = o
        curtain.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))   // intro ma własne ciemne tło
    }

    func skipIntro() {
        guard let o = intro else { return }
        o.removeAllActions()
        o.run(.sequence([.fadeOut(withDuration: 0.35), .run { [weak self] in DispatchQueue.main.async { locked { self?.finishIntro() } } }]))
    }

    private func finishIntro() {
        guard intro != nil else { return }
        intro?.removeFromParent()
        intro = nil
        sign.run(.fadeAlpha(to: 0.5, duration: 1.2))
        introDone?()
        introDone = nil
    }

    // MARK: Panele

    /// Etykiety wracają do puli (ukryte), reszta węzłów jest usuwana.
    func clearPanel() {
        redraw = nil
        rows = []
        used.forEach { $0.isHidden = true }
        spare += used
        used = []
        panel.children.filter { !($0 is SKLabelNode) }.forEach { $0.removeFromParent() }
    }

    /// Harmonijka: linie panelu składają się kolejno do środka, potem `done`.
    func fold(_ done: @escaping () -> Void) {
        guard !folding else { return }
        folding = true
        let nodes = panel.children.filter { !$0.isHidden }
        let ys = nodes.map { $0.frame.midY }
        guard let lo = ys.min(), let hi = ys.max() else { folding = false; done(); return }
        let mid = (lo + hi) / 2, span = max(1, hi - lo)
        for (n, y) in zip(nodes, ys) {
            let d = Double(abs(y - mid) / span) * 2
            let a: SKAction = n is SKLabelNode
                ? .group([.scaleY(to: 0.02, duration: 0.3), .moveBy(x: 0, y: (mid - y) * 0.9, duration: 0.34), .fadeOut(withDuration: 0.34)])
                : .fadeOut(withDuration: 0.2)
            a.timingMode = .easeIn
            n.run(.sequence([.wait(forDuration: d * 0.12), a]))     // zewnętrzne linie zwijają się ostatnie
        }
        run(.sequence([.wait(forDuration: 0.5), .run { [weak self] in
            DispatchQueue.main.async { locked { self?.folding = false; done() } }
        }]))
    }

    /// Odwrotność harmonijki: linie rozkładają się od środka na swoje miejsca.
    func unfold() {
        let nodes = panel.children.filter { !$0.isHidden }
        let ys = nodes.map { $0.position.y }
        guard let lo = ys.min(), let hi = ys.max() else { return }
        let mid = (lo + hi) / 2, span = max(1, hi - lo)
        panel.alpha = 1
        for n in nodes {
            n.removeAllActions()
            if let l = n as? SKLabelNode {
                let target = l.position
                let d = Double(abs(target.y - mid) / span) * 2
                l.position.y = mid + (target.y - mid) * 0.1
                l.yScale = 0.02
                l.alpha = 0
                let a = SKAction.group([.move(to: target, duration: 0.42), .scaleY(to: 1, duration: 0.38), .fadeIn(withDuration: 0.3)])
                a.timingMode = .easeOut
                l.run(.sequence([.wait(forDuration: 0.15 + d * 0.12), a]))
            } else {
                n.alpha = 0
                n.run(.sequence([.wait(forDuration: 0.45), .fadeIn(withDuration: 0.25)]))
            }
        }
    }

    func appear() {
        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.35))
    }

    func showMenu(_ items: [MenuRow], selected: Int, notes: [String], animated: Bool = false) {
        clearPanel()
        redraw = { [weak self] in self?.showMenu(items, selected: selected, notes: notes) }
        let h = size.height, x = size.width * 0.075
        let top = h * 0.8
        _ = label("SAMOTNIK", size: h * 0.062, font: "AvenirNext-UltraLight", alpha: 0.92, at: CGPoint(x: x - h * 0.004, y: top), kern: h * 0.02)
        _ = label("gra logiczna w kulki", size: h * 0.017, alpha: 0.38, at: CGPoint(x: x, y: top - h * 0.055), kern: h * 0.004)
        rowH = h * 0.06
        rowX = x
        for (i, it) in items.enumerated() {
            let y = top - h * 0.15 - CGFloat(i) * rowH
            let sel = i == selected
            let a: CGFloat = it.dim ? 0.3 : (sel ? 0.95 : 0.5)
            _ = label(it.name, size: h * 0.028, font: sel ? "AvenirNext-Regular" : "AvenirNext-UltraLight", alpha: a,
                      at: CGPoint(x: x + (sel ? h * 0.018 : 0), y: y), kern: 1)
            if sel {
                let bar = SKShapeNode(rect: CGRect(x: x - h * 0.004, y: y - h * 0.013, width: max(2, h * 0.0035), height: h * 0.026), cornerRadius: 1)
                bar.fillColor = accent
                bar.strokeColor = .clear
                panel.addChild(bar)
            }
            var mid: CGFloat?
            if let v = it.value {
                let l = label(it.plain ? v : "‹   \(v)   ›", size: h * 0.022, alpha: sel ? 0.9 : 0.42, at: CGPoint(x: x + h * 0.23, y: y))
                mid = l.frame.midX
            }
            rows.append((y, mid))
        }
        var y = top - h * 0.15 - CGFloat(items.count) * rowH - h * 0.01
        for (i, n) in notes.enumerated() where !n.isEmpty {
            _ = label(n, size: h * 0.0155, alpha: i == 0 ? 0.5 : 0.36, at: CGPoint(x: x, y: y), color: i == 0 ? accent : nil)
            y -= h * 0.03
        }
        _ = label("↑ ↓  wybór    ·    ← →  zmiana    ·    Enter  zatwierdź", size: h * 0.0145, alpha: 0.28,
                  at: CGPoint(x: size.width / 2, y: pad * 0.6 + h * 0.01), align: .center)
        if animated { unfold() }
    }

    /// (wiersz, kierunek): -1 / +1 dla strzałek wartości, 0 dla samej pozycji.
    func menuHit(_ pt: CGPoint) -> (Int, Int)? {
        for (i, r) in rows.enumerated() where abs(pt.y - r.y) < rowH / 2 && pt.x > rowX - 30 && pt.x < rowX + size.height * 0.75 {
            if let mid = r.mid, pt.x > rowX + size.height * 0.2 { return (i, pt.x < mid ? -1 : 1) }
            return (i, 0)
        }
        return nil
    }

    func table(_ header: [String], _ data: [[String]], xs: [CGFloat], right: Set<Int>, y0: CGFloat) -> CGFloat {
        let w = size.width, h = size.height
        var y = y0
        for (j, s) in header.enumerated() {
            _ = label(s.uppercased(), size: h * 0.014, font: "AvenirNext-DemiBold", alpha: 0.5, at: CGPoint(x: w * xs[j], y: y), align: right.contains(j) ? .right : .left, kern: 2)
        }
        y -= h * 0.045
        if data.isEmpty {
            _ = label("brak wyników — zagraj na tej planszy", size: h * 0.021, alpha: 0.6, at: CGPoint(x: w * xs[0], y: y))
            return y - h * 0.05
        }
        for (i, row) in data.enumerated() {
            if i % 2 == 0 {                                   // pasy ułatwiające czytanie wierszy
                let bar = SKShapeNode(rect: CGRect(x: w * xs[0] - h * 0.02, y: y - h * 0.022, width: w * (xs[xs.count - 1] - xs[0]) + h * 0.04, height: h * 0.044), cornerRadius: h * 0.008)
                bar.fillColor = NSColor(white: 1, alpha: 0.04)
                bar.strokeColor = .clear
                panel.addChild(bar)
            }
            for (j, s) in row.enumerated() {
                _ = label(s, size: h * 0.022, font: j == 1 || j == row.count - 1 ? "AvenirNext-DemiBold" : "AvenirNext-Regular",
                          alpha: i == 0 ? 1 : 0.85, at: CGPoint(x: w * xs[j], y: y), align: right.contains(j) ? .right : .left,
                          color: i == 0 && (j == 0 || j == row.count - 1) ? accent : nil)
            }
            y -= h * 0.046
        }
        return y
    }

    func showRecords(board: String, records: [[String]], players: [[String]], animated: Bool = false) {
        clearPanel()
        redraw = { [weak self] in self?.showRecords(board: board, records: records, players: players) }
        let w = size.width, h = size.height
        let dim = SKSpriteNode(color: theme.panelColor, size: size)
        dim.position = CGPoint(x: w / 2, y: h / 2)
        dim.alpha = 0.95                                       // prawie pełne tło: tekst nie miesza się z planszą 3D
        dim.zPosition = -1
        panel.addChild(dim)
        _ = label("Rekordy", size: h * 0.05, font: "AvenirNext-Regular", alpha: 0.95, at: CGPoint(x: w * 0.16, y: h * 0.87), kern: 2)
        _ = label("‹   \(board)   ›", size: h * 0.026, font: "AvenirNext-DemiBold", alpha: 0.9, at: CGPoint(x: w * 0.84, y: h * 0.87), align: .right)
        let xs: [CGFloat] = [0.16, 0.2, 0.42, 0.56, 0.68, 0.84]
        var y = table(["#", "Gracz", "Trudność", "Zostało", "Czas", "Punkty"], records, xs: xs, right: [5], y0: h * 0.77)
        y -= h * 0.035
        _ = label("Gracze", size: h * 0.032, font: "AvenirNext-Regular", alpha: 0.9, at: CGPoint(x: w * 0.16, y: y), kern: 1.5)
        _ = table(["", "Gracz", "Gier", "Najlepiej", "Rekord", "Punkty"], players, xs: xs, right: [5], y0: y - h * 0.055)
        _ = label("← →  plansza    ·    Esc  powrót", size: h * 0.016, alpha: 0.45, at: CGPoint(x: w / 2, y: pad * 0.6 + h * 0.01), align: .center)
        if animated { appear() }
    }

    func showEnd(_ head: String, _ lines: [String], animated: Bool) {
        clearPanel()
        redraw = { [weak self] in self?.showEnd(head, lines, animated: false) }
        let w = size.width, h = size.height
        let dim = SKSpriteNode(color: theme.panelColor, size: size)
        dim.position = CGPoint(x: w / 2, y: h / 2)
        dim.alpha = 0.6
        dim.zPosition = -1
        panel.addChild(dim)
        _ = label(head, size: h * 0.075, font: "AvenirNext-UltraLight", alpha: 0.95, at: CGPoint(x: w / 2, y: h * 0.56), align: .center, kern: 2)
        for (i, s) in lines.enumerated() {
            let hl = s.hasPrefix("+") || s.hasPrefix("Odblokowano") || s.hasPrefix("Cel osiągnięty")
            _ = label(s, size: h * 0.021, alpha: hl ? 0.85 : 0.6, at: CGPoint(x: w / 2, y: h * 0.47 - CGFloat(i) * h * 0.042), align: .center, color: hl ? accent : nil)
        }
        _ = label("kliknij lub Enter — kolejna gra    ·    Z  cofnij    ·    Esc  menu", size: h * 0.015, alpha: 0.35,
                  at: CGPoint(x: w / 2, y: h * 0.47 - CGFloat(lines.count) * h * 0.042 - h * 0.03), align: .center)
        if animated { appear() }
    }
}

// MARK: - Widok

final class GameView: SCNView {
    weak var game: Game?
    override var acceptsFirstResponder: Bool { true }
    private func loc(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
    override func mouseDown(with e: NSEvent) { locked { game?.mouseDown(loc(e)) } }
    override func mouseDragged(with e: NSEvent) { locked { game?.mouseMoved(loc(e)); game?.mouseDragged(loc(e)) } }
    override func mouseUp(with e: NSEvent) { locked { game?.mouseUp(loc(e)) } }
    override func mouseMoved(with e: NSEvent) { game?.mouseMoved(loc(e)) }      // tylko kierunek przechyłu i podświetlenie menu — bez blokady renderera
    override func keyDown(with e: NSEvent) { if locked({ game?.key(e) }) != true { super.keyDown(with: e) } }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); locked { game?.resized() } }
}

/// Przezroczysta nakładka 2D nad sceną 3D; kliknięcia przepuszcza do widoku gry pod spodem.
final class OverlayView: SKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Zmiany sceny i nakładki z wątku głównego robimy pod blokadą renderera SceneKit.
@discardableResult
func locked<T>(_ f: () -> T) -> T {
    SCNTransaction.lock()
    defer { SCNTransaction.unlock() }
    return f()
}

// MARK: - Gra 3D

final class Game: NSObject, SCNSceneRendererDelegate {
    enum Mode { case intro, menu, records, play, end, tutorial }
    enum Item { case resume, play, tutorial, board, difficulty, set, theme, player, newPlayer, records, quit }

    let audio: Audio
    let store = Store()
    let view: GameView
    let scene = SCNScene()
    let hud = HUD(size: CGSize(width: 100, height: 100))
    let cam = SCNNode()
    let root = SCNNode()
    let ring = SCNNode()
    var echoes: [Int: SCNNode] = [:]             // rozmyte odbicia kul w lakierze
    private let pairLock = NSLock()               // renderer czyta pary w swoim wątku — osobna, chroniona kopia
    private var pairs: [(SCNNode, SCNNode)] = []
    let tints = [SCNNode(), SCNNode()]
    var boardNodes: [SCNNode] = []
    var floorNode = SCNNode()
    var keyNode = SCNNode()
    var ambientNode = SCNNode()

    var mode = Mode.intro
    var paused = false
    var menuSel = 0
    var recBoard = 0

    var grid: [Pos: Int] = [:]
    var nodes: [Int: SCNNode] = [:]
    var isA: [Int: Bool] = [:]
    var looks: [Int: Int] = [:]      // który wariant powierzchni ma dana kula
    var history: [Move] = []
    var undosUsed = 0
    var elapsed: TimeInterval = 0
    var resumedAt: Date?
    var selected: Pos?
    var dragCandidate = false, dragging = false
    var grabOffset = CGPoint.zero

    var mouse = CGPoint.zero      // -1...1, ustawiane z wątku głównego
    var tilt = CGPoint.zero
    var menuSway = 0.0
    var lastTime: TimeInterval = 0

    let R: CGFloat = 0.36, holeR: CGFloat = 0.27
    lazy var restY: CGFloat = (R * R - holeR * holeR).squareRoot()
    var geoA: [SCNGeometry] = [], geoB: [SCNGeometry] = []
    let variants = 8
    var setCache: [Int: ([SCNGeometry], [SCNGeometry])] = [:]

    var naming: String?              // wpisywane imię nowego gracza
    var tutorial = false, tutorialToken = 0
    var thinking = false             // solver szuka podpowiedzi

    var randomSelected = false, generating = false
    var randomBoard: Board?

    var board: Board {
        if tutorial { return Board.all[1] }
        if randomSelected, let r = randomBoard { return r }
        return Board.all[store.s.board]
    }
    var timeLimit: Int? { diff.secondsPerMarble.map { $0 * board.marbles } }
    var goal: Int { max(diff.goal, board.target) }
    var goalText: String { goal == 1 ? "1 kulka" : "najwyżej \(goal) \(plural(goal))" }
    var diff: Difficulty { Difficulty.all[store.s.difficulty] }
    var seconds: Int { Int(elapsed + (resumedAt.map { Date().timeIntervalSince($0) } ?? 0)) }

    init(view: GameView, overlay: OverlayView, audio: Audio) {
        self.view = view
        self.audio = audio
        super.init()
        audio.musicOn = !store.s.musicOff
        if store.s.set >= MarbleSet.available { store.s.set = 0 }
        theme = store.s.lightTheme == true ? .light : .dark
        if Board.all[store.s.board].level != store.s.difficulty { store.s.board = Board.ofLevel(store.s.difficulty)[0] }
        buildScene()
        view.scene = scene
        view.pointOfView = cam
        view.delegate = self
        view.backgroundColor = bgColor
        view.antialiasingMode = .multisampling8X
        view.isJitteringEnabled = true                     // dodatkowe wygładzanie, gdy obraz stoi
        if let ml = view.layer as? CAMetalLayer, (NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) > 1 {
            ml.wantsExtendedDynamicRangeContent = true
            ml.pixelFormat = .rgba16Float
            ml.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        }
        view.preferredFramesPerSecond = 120
        view.rendersContinuously = true
        view.isPlaying = true
        view.game = self
        hud.setup()
        overlay.allowsTransparency = true
        overlay.preferredFramesPerSecond = 120
        overlay.presentScene(hud)
        resized()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.mode == .play else { return }
            self.refreshHUD()
            if let lim = self.timeLimit, self.seconds >= lim { locked { self.finish(timeout: true) } }
        }
    }

    // MARK: Scena

    func buildScene() {
        scene.background.contents = bgColor
        scene.fogColor = bgColor
        scene.fogStartDistance = 17
        scene.fogEndDistance = 38
        scene.lightingEnvironment.contents = writeStudioHDR(light: theme.light)
        scene.lightingEnvironment.intensity = theme.studio

        let c = SCNCamera()
        c.fieldOfView = 28
        c.zNear = 1; c.zFar = 90
        c.wantsHDR = true
        c.wantsExposureAdaptation = false
        c.whitePoint = 1.6
        c.exposureOffset = theme.exposure
        c.bloomIntensity = theme.bloom
        c.bloomThreshold = 1.0
        c.bloomBlurRadius = 12
        c.vignettingPower = 0.9
        c.vignettingIntensity = theme.camVignette
        c.wantsDepthOfField = theme.dof                    // bardzo delikatna głębia ostrości, ostrość na środku planszy
        c.fStop = 11
        c.apertureBladeCount = 7
        c.focalBlurSampleCount = 12
        c.screenSpaceAmbientOcclusionIntensity = theme.ssao
        c.screenSpaceAmbientOcclusionRadius = 0.25
        cam.camera = c
        scene.rootNode.addChildNode(cam)

        let key = SCNNode()
        let kl = SCNLight()
        kl.type = .directional
        kl.intensity = theme.key
        kl.color = NSColor(srgbRed: 1, green: 0.96, blue: 0.9, alpha: 1)
        kl.castsShadow = true
        kl.shadowMapSize = CGSize(width: 4096, height: 4096)
        kl.shadowSampleCount = 16
        kl.shadowRadius = theme.shadowSoft
        kl.shadowColor = NSColor(white: 0, alpha: theme.shadowAlpha)
        kl.shadowBias = 1.2
        kl.automaticallyAdjustsShadowProjection = true
        key.light = kl
        keyNode = key
        key.eulerAngles = SCNVector3(-0.8, -0.55, 0)             // niżej = dłuższe cienie
        scene.rootNode.addChildNode(key)

        let amb = ambientNode
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = theme.ambient
        amb.light!.color = NSColor(cgColor: rgb(theme.ambientTint))!
        scene.rootNode.addChildNode(amb)

        for (n, col) in zip(tints, [NSColor(srgbRed: 0.35, green: 0.75, blue: 0.78, alpha: 1), NSColor(srgbRed: 0.6, green: 0.45, blue: 0.85, alpha: 1)]) {
            let l = SCNLight()
            l.type = .spot                                      // krążące reflektory z własnymi miękkimi cieniami
            l.spotInnerAngle = 25
            l.spotOuterAngle = 80
            l.castsShadow = !theme.light                       // w jasnym motywie bez kolorowych smug cieni
            l.shadowMapSize = CGSize(width: 1024, height: 1024)
            l.shadowSampleCount = 8
            l.shadowRadius = 10
            l.shadowColor = NSColor(white: 0, alpha: 0.38)
            l.shadowBias = 2
            l.intensity = theme.tint
            l.color = col
            l.attenuationStartDistance = 2
            l.attenuationEndDistance = 11
            n.light = l
            scene.rootNode.addChildNode(n)
        }

        let floor = SCNFloor()
        floor.reflectivity = 0.04
        floor.materials = [pbr(theme.floor, rough: 0.95)]
        floorNode = SCNNode()
        let fn = floorNode
        fn.geometry = floor
        styleFloor()
        scene.rootNode.addChildNode(fn)
        scene.rootNode.addChildNode(root)

        let torus = SCNTorus(ringRadius: 0.36, pipeRadius: 0.013)
        torus.materials = [glowMaterial()]
        ring.geometry = torus
        ring.isHidden = true
        root.addChildNode(ring)

        buildBoard()
        applySet(sync: true)
        root.opacity = 0                                   // plansza pojawia się dopiero po logo
    }

    /// Plansza: górna płyta z otworami na niższej, ciemniejszej podstawie.
    func buildBoard() {
        boardNodes.forEach { $0.removeFromParentNode() }
        boardNodes = makeBoardNodes(board, seed: .random(in: 0...UInt64.max))
        boardNodes.forEach(root.addChildNode)
    }

    /// Nowe, losowe uszkodzenia przy każdej grze — liczone w tle, podmieniane, gdy gotowe.
    func rebuildBoard() {
        let b = board
        DispatchQueue.global(qos: .userInitiated).async {
            let fresh = self.makeBoardNodes(b, seed: .random(in: 0...UInt64.max))
            DispatchQueue.main.async {
                locked {
                    guard self.board.name == b.name else { return }
                    self.boardNodes.forEach { $0.removeFromParentNode() }
                    self.boardNodes = fresh
                    fresh.forEach(self.root.addChildNode)
                }
            }
        }
    }

    /// Plansza: lakierowana płyta z otworami (cienka warstwa wierzchnia z odpryskami na gładkim spodzie)
    /// na ciemnej podstawie (gładka bryła i cienka górna warstwa z odpryskami).
    func makeBoardNodes(_ b: Board, seed: UInt64) -> [SCNNode] {
        func flat(_ g: SCNGeometry, _ y: CGFloat) -> SCNNode {
            let n = SCNNode(geometry: g)
            n.eulerAngles.x = -.pi / 2
            n.position.y = y
            return n
        }
        let top = SCNShape(path: chippedBoardPath(b, pad: 0.08, radius: 0.45, holes: holeR, seed: seed), extrusionDepth: 0.05)
        top.chamferRadius = 0.008
        top.chamferMode = .front
        let plainLacquer = pbr(theme.lacquer, rough: Game.lacquerRough, clear: 0.3)      // boki i fazki: bez tekstury, wspólne dla warstw
        let lacquer = pbr(theme.lacquer, rough: Game.lacquerRough, clear: 0.3)
        lacquer.clearCoatRoughness.contents = Game.lacquerRough * 0.7                // satynowy lakier: szerokie, miękkie odbicie
        // UV przedniej ściany SCNShape obejmuje obrys planszy, więc tekstura ma jego wymiar
        let texRect = b.extent.insetBy(dx: -0.08, dy: -0.08)
        let wear = boardSurface(b, rect: texRect, base: theme.lacquer, rough: Game.lacquerRough, seed: seed)
        lacquer.diffuse.contents = wear.diffuse
        lacquer.roughness.contents = wear.rough
        lacquer.normal.contents = wear.normal
        lacquer.normal.intensity = 0.6
        // UV przedniej ściany SCNShape są rozpięte na obrysie planszy, tak jak tekstura (texRect)
        for prop in [lacquer.diffuse, lacquer.roughness, lacquer.normal] {   // ostre ślady także pod kątem, bez migotania
            prop.mipFilter = .linear
            prop.maxAnisotropy = 16
        }
        top.materials = [lacquer, plainLacquer, plainLacquer, plainLacquer, plainLacquer]
        let under = SCNShape(path: boardPath(b, pad: 0.08, radius: 0.45, holes: holeR), extrusionDepth: 0.075)
        under.materials = [plainLacquer]

        let baseMat = pbr(theme.base, rough: 0.7)
        let body = SCNShape(path: boardPath(b, pad: 0.2, radius: 0.55, holes: nil), extrusionDepth: 0.25)
        // bez fazki: zaokrąglenie wyginałoby normalne całej ściany i odcinało ją od górnej warstwy
        body.materials = [baseMat]
        let lip = SCNShape(path: chippedBoardPath(b, pad: 0.2, radius: 0.55, holes: nil, seed: seed &+ 55), extrusionDepth: 0.056)
        lip.chamferRadius = 0.008
        lip.chamferMode = .front
        lip.materials = [baseMat]
        // warstwy lekko na siebie zachodzą — bez szczelin, przez które przeciekałoby światło
        return [flat(body, -0.295), flat(lip, -0.148), flat(under, -0.0825), flat(top, -0.025)]
    }

    /// Każdy zestaw ma pulę niepowtarzalnych wariantów, wypalanych w tle i zapamiętywanych;
    /// kule dostają je losowo, z własnym obrotem i rozmiarem.
    func applySet(sync: Bool = false) {
        let idx = store.s.set
        if let c = setCache[idx] {
            geoA = c.0; geoB = c.1
            for (id, n) in nodes {
                n.childNodes.first?.geometry = geometry(id)
                echoes[id]?.geometry?.firstMaterial?.multiply.contents = geometry(id).firstMaterial?.value(forKey: "avgColor")
            }
            return
        }
        let set = MarbleSet.all[idx], count = variants
        let work: () -> ([SCNMaterial], [SCNMaterial]) = {
            let a = (0..<count).map { marbleMaterial(set.a, seed: UInt64(idx) &* 1_000_003 &+ UInt64($0) &* 7919 &+ 11) }
            let b = (0..<count).map { marbleMaterial(set.b, seed: UInt64(idx) &* 1_000_003 &+ UInt64($0) &* 7919 &+ 977) }
            return (a, b)
        }
        let finish: ([SCNMaterial], [SCNMaterial]) -> Void = { [weak self] ma, mb in
            guard let self else { return }
            let s = SCNSphere(radius: self.R)
            s.segmentCount = 72
            func geos(_ ms: [SCNMaterial]) -> [SCNGeometry] {
                ms.map { m in let g = s.copy() as! SCNGeometry; g.materials = [m]; return g }
            }
            self.setCache[idx] = (geos(ma), geos(mb))
            if self.store.s.set == idx { self.applySet() }
        }
        if sync {
            let (ma, mb) = work()
            finish(ma, mb)
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let (ma, mb) = work()
                DispatchQueue.main.async { locked { finish(ma, mb) } }
            }
        }
    }

    /// Chropowatość lakieru planszy — od niej zależy, jak bardzo rozmyte są odbicia kul.
    static let lacquerRough: CGFloat = 0.32

    /// Miękka poświata pod kulą w jej średnim kolorze: tak wygląda rozmyte odbicie w satynowym lakierze.
    /// Im bardziej chropowaty lakier, tym szersza i słabsza.
    lazy var glowTexture: CGImage = makeImage(256, 256) { ctx in
        let c = CGPoint(x: 128, y: 128)
        let stops: [CGFloat] = stride(from: 0, through: 1, by: 0.1).map { $0 }
        let cols = stops.map { CGColor(gray: 1, alpha: exp(-$0 * $0 * 4.5) * (1 - $0)) }
        ctx.drawRadialGradient(gradient(cols, stops), startCenter: c, startRadius: 0, endCenter: c, endRadius: 128, options: [])
    }

    func glowNode(_ id: Int) -> SCNNode {
        let rough = Game.lacquerRough
        let d = R * 2 * (1.25 + rough * 1.5)
        let pl = SCNPlane(width: d, height: d * 1.3)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = glowTexture
        m.multiply.contents = geometry(id).firstMaterial?.value(forKey: "avgColor") ?? NSColor.white
        m.transparencyMode = .aOne
        m.blendMode = .add
        m.writesToDepthBuffer = false
        pl.materials = [m]
        let n = SCNNode(geometry: pl)
        n.eulerAngles.x = -.pi / 2
        n.castsShadow = false
        n.renderingOrder = 1
        return n
    }

    /// Poświaty idą za kulami: przy uniesieniu słabną i rozlewają się.
    func syncEchoes() {
        let strength = 0.55 * (1 - Game.lacquerRough * 0.8)
        pairLock.lock()
        let list = pairs
        pairLock.unlock()
        for (n, g) in list {
            let h = max(0, n.position.y - restY)
            g.position = SCNVector3(n.position.x, 0.004, n.position.z + R * 0.45 + h * 0.3)
            let s = 1 + h * 0.9
            g.scale = SCNVector3(s, s, s)
            g.opacity = n.opacity * CGFloat(strength) * CGFloat(exp(-Double(h) * 2.4))
        }
    }

    func geometry(_ id: Int) -> SCNGeometry {
        let v = looks[id] ?? 0
        return isA[id] == true ? geoA[v % geoA.count] : geoB[v % geoB.count]
    }

    func resized() {
        let b = view.bounds.size
        guard b.width > 10, b.height > 10 else { return }
        hud.px = view.window?.backingScaleFactor ?? 2
        hud.size = b
        let aspect = b.width / b.height
        let d: CGFloat = 15.5 * CGFloat(board.n + 1) / 8 * max(1, 1.45 / aspect)
        let pitch: CGFloat = 0.98
        cam.position = SCNVector3(0, d * sin(pitch), d * cos(pitch))
        cam.look(at: SCNVector3(0, -0.3, 0.3))
        cam.camera?.focusDistance = d
        placeRoot(animated: false)
    }

    /// W menu plansza odsuwa się w prawo, robiąc miejsce na listę po lewej.
    func placeRoot(animated: Bool) {
        let b = view.bounds.size
        let visibleW = 2 * cam.position.y / sin(0.98) * tan(14 * .pi / 180) * b.width / max(1, b.height)
        let inMenu = mode == .menu
        let x: CGFloat = inMenu ? visibleW * 0.17 : 0
        let sc: CGFloat = inMenu ? 0.72 : 1
        root.removeAction(forKey: "place")
        if animated {
            let a = SCNAction.group([.move(to: SCNVector3(x, 0, 0), duration: 0.8), .scale(to: sc, duration: 0.8)]); a.timingMode = .easeInEaseOut
            root.runAction(a, forKey: "place")
        } else if mode != .intro {
            root.position = SCNVector3(x, 0, 0)
            root.scale = SCNVector3(sc, sc, sc)
        }
    }

    func renderer(_ r: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.1, time - lastTime)
        lastTime = time
        let k = CGFloat(1 - exp(-dt * 3.2))
        tilt.x += (mouse.x - tilt.x) * k
        tilt.y += (mouse.y - tilt.y) * k
        let swayTarget = mode == .menu || mode == .records ? 1.0 : 0.0
        menuSway += (swayTarget - menuSway) * (1 - exp(-dt * 1.5))
        let idle = CGFloat(sin(time * 0.23)) * 0.012
        let spin = CGFloat(sin(time * 0.17) * 0.22 * menuSway)
        root.eulerAngles = SCNVector3(-tilt.y * 0.11 + idle * 0.6, tilt.x * 0.05 + idle + spin, -tilt.x * 0.11)
        for (i, n) in tints.enumerated() {
            let a = time * 0.11 + Double(i) * .pi
            n.position = SCNVector3(CGFloat(cos(a)) * 5.5, 2.6, CGFloat(sin(a)) * 4)
            n.look(at: root.worldPosition)
        }
        syncEchoes()
    }

    // MARK: Geometria pól

    func local(_ p: Pos, lift: CGFloat = 0) -> SCNVector3 {
        SCNVector3(board.x(p), restY + lift, -board.y(p))
    }

    /// Punkt przecięcia promienia spod kursora z poziomą płaszczyzną planszy (w jej układzie).
    func planePoint(_ pt: CGPoint, y: CGFloat) -> CGPoint? {
        let a = root.convertPosition(view.unprojectPoint(SCNVector3(pt.x, pt.y, 0)), from: nil)
        let b = root.convertPosition(view.unprojectPoint(SCNVector3(pt.x, pt.y, 1)), from: nil)
        let dy = b.y - a.y
        guard abs(dy) > 1e-6 else { return nil }
        let t = (y - a.y) / dy
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.z + (b.z - a.z) * t)
    }

    func cellAt(_ v: CGPoint, tolerance: CGFloat = 0.48) -> Pos? {
        // v.x — kolumna, v.y — głębokość (z = wiersz) w układzie planszy
        let p = Pos(r: Int((v.y + board.cr).rounded()), c: Int((v.x + board.cc).rounded()))
        guard board.has(p), hypot(v.x - board.x(p), v.y + board.y(p)) < tolerance else { return nil }
        return p
    }

    // MARK: Logika

    func targets(from p: Pos) -> [Move] {
        guard grid[p] != nil else { return [] }
        return Pos.dirs.compactMap { d in
            let o = p + d, t = o + d
            guard board.has(t), let j = grid[o], grid[t] == nil else { return nil }
            return Move(from: p, over: o, to: t, jumped: j)
        }
    }

    var anyMoves: Bool { grid.keys.contains { !targets(from: $0).isEmpty } }

    func start() {
        root.opacity = 0
        root.position.y = -0.8
        tints.forEach { $0.light?.intensity = 0 }       // przy logo scena 3D jest ciemna — bez poświaty reflektorów
        setupMarbles(sound: false)
        hud.playIntro { [weak self] in
            guard let self else { return }
            self.root.runAction(.fadeIn(duration: 1.2))
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.5
            self.tints.forEach { $0.light?.intensity = theme.tint }
            SCNTransaction.commit()
            self.openMenu()
            if let m = ProcessInfo.processInfo.environment["SAMOTNIK_DEMO"] { self.demo(m) }
        }
    }

    /// Tryb testowy: „stress” szybko przełącza plansze i zestawy, „sets” pokazuje wszystkie zestawy naraz.
    func demo(_ m: String) {
        if m == "stress" {
            var k = 0
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] t in
                guard let self else { return t.invalidate() }
                locked {
                    k += 1
                    if let bi = self.items.firstIndex(of: .board), let si = self.items.firstIndex(of: .set) {
                        self.activate(k % 3 == 0 ? si : bi, dir: 1)
                    }
                    self.menuSel = k % self.items.count
                    self.renderMenu()
                }
                if k >= 60 { t.invalidate(); print("STRESS OK") }
            }
        } else if m == "fold" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { locked { self.activate(self.items.firstIndex(of: .play) ?? 0, dir: 0) } }
        } else if m == "verify" {
            DispatchQueue.global().async {
                var out = [String](repeating: "", count: Board.all.count)
                let lock = NSLock()
                let only = (ProcessInfo.processInfo.environment["SAMOTNIK_ONLY"] ?? "").split(separator: ",").compactMap { Int($0) }
                let ids = only.isEmpty ? Array(Board.all.indices) : only
                DispatchQueue.concurrentPerform(iterations: ids.count) { k in
                    let i = ids[k]
                    let b = Board.all[i]
                    let r = Solver.verify(b, budget: [1.5, 3, 8][b.level])
                    lock.lock()
                    out[i] = "\(i)\t\(b.level)\t\(b.marbles)\t\(b.name)\t\(r)"
                    FileHandle.standardError.write((out[i] + "\n").data(using: .utf8)!)
                    lock.unlock()
                }
                FileHandle.standardOutput.write((out.filter { !$0.isEmpty }.joined(separator: "\n") + "\n").data(using: .utf8)!)
                exit(0)
            }
        } else if m == "repair" {
            let only = (ProcessInfo.processInfo.environment["SAMOTNIK_ONLY"] ?? "").split(separator: ",").compactMap { Int($0) }
            let q = OperationQueue()
            q.maxConcurrentOperationCount = 3
            for i in only {
                q.addOperation {
                    let b = Board.all[i]
                    let r = Solver.repair(b, budget: [1.0, 2.0, 5.0][b.level], deadline: Date().addingTimeInterval(150))
                    FileHandle.standardError.write("\(i)\t\(b.name)\t\(r)\n".data(using: .utf8)!)
                }
            }
            DispatchQueue.global().async { q.waitUntilAllOperationsAreFinished(); exit(0) }
        } else if m == "goals" {
            // łatwe i normalne: czy cel poziomu jest osiągalny; trudne: najpierw 1 kulka, potem 2 — po kolei (pamięć)
            DispatchQueue.global().async {
                for (i, b) in Board.all.enumerated() {
                    let sv = Solver(b), start = sv.encode(b.all.filter { !b.empty.contains($0) })
                    var res = "?"
                    if b.level < 2 {
                        if case .found = sv.solve(start, target: 1, budget: 2) { res = "1" }
                        else if case .found = sv.solve(start, target: Difficulty.all[b.level].goal, budget: 3) { res = "goal" }
                        else { res = "FAIL" }
                    } else {
                        if case .found = sv.solve(start, target: 1, budget: 20) { res = "1" }
                        else if case .found = sv.solve(start, target: 2, budget: 15) { res = "2" }
                        else { res = "FAIL" }
                    }
                    FileHandle.standardError.write("\(i)\t\(b.level)\t\(b.name)\t\(res)\n".data(using: .utf8)!)
                }
                exit(0)
            }
        } else if m == "gen" {
            // wypisuje sprawdzone solverem losowe kształty jako rysunki ASCII: SAMOTNIK_GEN="poziom:ile,poziom:ile"
            let spec = (ProcessInfo.processInfo.environment["SAMOTNIK_GEN"] ?? "").split(separator: ",").compactMap { part -> (Int, Int)? in
                let a = part.split(separator: ":").compactMap { Int($0) }
                return a.count == 2 ? (a[0], a[1]) : nil
            }
            let q = OperationQueue()
            q.maxConcurrentOperationCount = 3
            for (level, count) in spec {
                for _ in 0..<count {
                    q.addOperation {
                        var b: Board?
                        let until = Date().addingTimeInterval(240)
                        while b == nil && Date() < until { b = Board.random(level: level) }
                        guard let b else { return }
                        let cmin = b.all.map(\.c).min()!, cmax = b.all.map(\.c).max()!
                        let art = (b.all.map(\.r).min()!...b.all.map(\.r).max()!).map { r in
                            "\"" + String((cmin...cmax).map { c -> Character in
                                let p = Pos(r: r, c: c)
                                return b.empty.contains(p) ? "o" : (b.has(p) ? "X" : ".")
                            }) + "\""
                        }.joined(separator: ", ")
                        FileHandle.standardError.write("GEN\t\(level)\t\(b.marbles)\t[\(art)]\n".data(using: .utf8)!)
                    }
                }
            }
            DispatchQueue.global().async { q.waitUntilAllOperationsAreFinished(); exit(0) }
        } else if m == "random" {
            menuSel = items.firstIndex(of: .board) ?? 0
            if let bi = items.firstIndex(of: .board) { activate(bi, dir: -1) }   // z pierwszej planszy ← przechodzi na „Losowa”
        } else if m == "hint" {
            newGame()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { locked { self.hint() } }
        } else if m == "about" {
            let f = hud.sign.calculateAccumulatedFrame()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { locked { self.mouseDown(CGPoint(x: f.midX, y: f.midY)) } }
        } else if m == "theme" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { locked { if let i = self.items.firstIndex(of: .theme) { self.activate(i, dir: 1) } } }
        } else if m == "boards" {
            var k = 0
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { t in
                locked { if let bi = self.items.firstIndex(of: .board) { self.activate(bi, dir: 1) } }
                k += 1
                if k >= 14 { t.invalidate() }
            }
        } else if m == "tutorial" {
            startTutorial()
        } else if m == "records" {
            openRecords()
        } else if m == "naming" {
            naming = "Ania"
            menuSel = items.firstIndex(of: .newPlayer) ?? 0
            renderMenu()
        } else if m == "sets" {
            let keep = store.s.set
            for i in MarbleSet.all.indices where setCache[i] == nil { store.s.set = i; applySet(sync: true) }
            store.s.set = keep
            let n = MarbleSet.all.count
            for (id, node) in nodes {
                let c = setCache[id % n]!
                node.childNodes.first?.geometry = ((id / n) % 2 == 0 ? c.0 : c.1)[id % variants]
            }
            print("SETS OK")
        }
    }

    /// Świeże ustawienie kulek na planszy (także jako podgląd w menu).
    func setupMarbles(sound: Bool) {
        root.removeAction(forKey: "end")
        deselect(settle: false)
        nodes.values.forEach { $0.removeFromParentNode() }
        echoes.values.forEach { $0.removeFromParentNode() }
        pairLock.lock(); pairs = []; pairLock.unlock()
        nodes = [:]; echoes = [:]; grid = [:]; isA = [:]; looks = [:]; history = []
        undosUsed = 0
        elapsed = 0
        resumedAt = nil
        for (id, p) in board.all.filter({ !board.empty.contains($0) }).enumerated() {
            isA[id] = (p.r + p.c) % 2 == 0
            looks[id] = Int.random(in: 0..<variants)
            let ball = SCNNode(geometry: geometry(id))
            ball.eulerAngles = SCNVector3(CGFloat.random(in: 0...(2 * .pi)), CGFloat.random(in: 0...(2 * .pi)), CGFloat.random(in: 0...(2 * .pi)))
            let sc = CGFloat.random(in: 0.985...1.015)
            ball.scale = SCNVector3(sc, sc, sc)
            ball.position.y = (sc - 1) * R
            let n = SCNNode()
            n.addChildNode(ball)
            n.position = local(p, lift: 1.6)
            n.opacity = 0
            ball.renderingOrder = 2
            root.addChildNode(n)
            nodes[id] = n
            grid[p] = id
            let e = glowNode(id)
            e.opacity = 0
            root.addChildNode(e)
            echoes[id] = e
            pairLock.lock(); pairs.append((n, e)); pairLock.unlock()
            let dist = hypot(Double(board.x(p)), Double(board.y(p)))
            let drop = SCNAction.move(to: local(p), duration: 0.55); drop.timingMode = .easeIn
            let settle = SCNAction.sequence([.move(by: SCNVector3(0, 0.06, 0), duration: 0.09), .move(by: SCNVector3(0, -0.06, 0), duration: 0.09)])
            n.runAction(.sequence([.wait(duration: 0.1 + dist * 0.08), .group([.fadeIn(duration: 0.35), drop]), settle]))
        }
        if sound {
            for (i, note) in [62.0, 66, 69, 74].enumerated() { audio.tone(note, amp: 0.05, decay: 1.6, pan: 0.3 + Double(i) * 0.13, delay: Double(i) * 0.12) }
        }
    }

    func newGame() {
        mode = .play
        paused = false
        naming = nil
        hud.clearPanel()
        hud.say(nil)
        hud.showGameLayer(true)
        placeRoot(animated: true)
        rebuildBoard()
        setupMarbles(sound: true)
        resumedAt = Date()
        updateMovable()
        refreshHUD()
    }

    func refreshHUD() {
        let undo: String
        switch diff.undos {
        case .max: undo = "   ·   Z  cofnij"
        case 0: undo = ""
        default: undo = "   ·   Z  cofnij (\(max(0, diff.undos - undosUsed)))"
        }
        let hint = diff.solverHint ? "   ·   H  podpowiedź" : ""
        let time = timeLimit.map { "zostało \(clock(max(0, $0 - seconds)))" } ?? clock(seconds)
        hud.setGame(count: "\(grid.count)",
                    sub: "\(plural(grid.count))   ·   ruch \(history.count)   ·   \(time)",
                    info: "\(board.name)   ·   \(diff.name)   ·   cel: \(goalText)   ·   \(store.player.name)",
                    help: "Esc  menu\(undo)\(hint)   ·   R  od nowa   ·   M  muzyka \(audio.musicOn ? "wł." : "wył.")   ·   F  pełny ekran")
    }

    /// Łatwy poziom: solver szuka drogi do jednej kulki z bieżącej pozycji i pokazuje pierwszy ruch.
    func hint() {
        guard mode == .play, diff.solverHint, !thinking else { return }
        thinking = true
        hud.say("Szukam drogi do jednej kulki…")
        let solver = Solver(board), start = solver.encode(grid.keys), goal = self.goal
        DispatchQueue.global(qos: .userInitiated).async {
            // najlepszy osiągalny wynik: najpierw 1 kulka, potem 2, 3… aż do celu poziomu
            var best: (Int, [(Pos, Pos, Pos)])?
            var timedOut = false
            for t in 1...max(1, goal) {
                switch solver.solve(start, target: t, budget: t == 1 ? 1.2 : 0.5) {
                case .found(let p): best = (t, p)
                case .timeout: timedOut = true
                case .impossible: break
                }
                if best != nil { break }
            }
            DispatchQueue.main.async {
                locked {
                    self.thinking = false
                    guard self.mode == .play else { return }
                    if let (t, path) = best, let (f, _, to) = path.first {
                        self.select(f)
                        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.3, pipeRadius: 0.02))
                        ring.geometry!.materials = [glowMaterial()]
                        let l = self.local(to)
                        ring.position = SCNVector3(l.x, 0.014, l.z)
                        ring.name = "hint"
                        ring.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.3, duration: 0.5), .fadeOpacity(to: 1, duration: 0.5)])))
                        self.root.addChildNode(ring)
                        let aim = t == 1 ? "do jednej kulki" : "do \(t) \(plural(t))"
                        self.hud.say("Podpowiedź: skocz zaznaczoną kulką na pulsujące pole — ta droga prowadzi \(aim).", hide: 5)
                    } else if timedOut {
                        self.hud.say("Nie znalazłem pewnej drogi w krótkim czasie — spróbuj sam.", hide: 4)
                    } else {
                        self.hud.say("Z tej pozycji nie osiągniesz już celu (\(self.goalText)) — cofnij ruch (Z).", hide: 5)
                    }
                }
            }
        }
    }

    func select(_ p: Pos) {
        deselect()
        selected = p
        if let n = nodes[grid[p]!] {
            n.removeAllActions()
            let up = SCNAction.move(to: local(p, lift: 0.3), duration: 0.18); up.timingMode = .easeOut
            n.runAction(up)
        }
        let l = local(p)
        ring.position = SCNVector3(l.x, 0.012, l.z)
        ring.isHidden = false
        ring.opacity = 0
        ring.scale = SCNVector3(0.85, 0.85, 0.85)
        ring.runAction(.group([.fadeIn(duration: 0.15), .scale(to: 1, duration: 0.15)]))
        if diff.hints || mode == .tutorial {
            for m in targets(from: p) {
                let d = SCNNode(geometry: SCNCylinder(radius: 0.11, height: 0.006))
                d.geometry!.materials = [glowMaterial()]
                let t = local(m.to)
                d.position = SCNVector3(t.x, -0.112, t.z)
                d.name = "hint"
                d.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.4, duration: 0.9), .fadeOpacity(to: 1, duration: 0.9)])))
                root.addChildNode(d)
            }
        }
        audio.tone(86, amp: 0.035, decay: 0.3, harm: 0.1)
    }

    func deselect(settle: Bool = true) {
        if settle, let s = selected, let id = grid[s], let n = nodes[id] {
            n.removeAllActions()
            let down = SCNAction.move(to: local(s), duration: 0.18); down.timingMode = .easeIn
            n.runAction(down)
        }
        selected = nil
        ring.removeAllActions()
        ring.isHidden = true
        root.childNodes(passingTest: { n, _ in n.name == "hint" }).forEach { $0.removeFromParentNode() }
    }

    /// Na łatwym poziomie delikatne pierścienie pokazują kulki, które mogą skoczyć.
    func updateMovable() {
        root.childNodes(passingTest: { n, _ in n.name == "movable" }).forEach { $0.removeFromParentNode() }
        guard diff.movable, mode == .play else { return }
        let geo = SCNTorus(ringRadius: 0.33, pipeRadius: 0.008)
        geo.materials = [glowMaterial(0.45)]
        for p in grid.keys where !targets(from: p).isEmpty {
            let n = SCNNode(geometry: geo)
            let l = local(p)
            n.position = SCNVector3(l.x, 0.01, l.z)
            n.name = "movable"
            root.addChildNode(n)
        }
    }

    func jump(_ n: SCNNode, to: SCNVector3, height: CGFloat = 0.85, duration: Double = 0.42) {
        n.removeAllActions()
        let from = n.position
        let dx = to.x - from.x, dz = to.z - from.z, d = hypot(dx, dz)
        if d > 0.5, let ball = n.childNodes.first {             // kula lekko się toczy w locie
            let roll = SCNAction.rotate(by: d / R * 0.35, around: SCNVector3(dz / d, 0, -dx / d), duration: duration)
            roll.timingMode = .easeInEaseOut
            ball.runAction(roll)
        }
        n.runAction(.customAction(duration: duration) { node, el in
            let t = min(1, Double(el) / duration)
            let e = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
            node.position = SCNVector3(from.x + (to.x - from.x) * e,
                                       from.y + (to.y - from.y) * e + height * sin(.pi * e),
                                       from.z + (to.z - from.z) * e)
        })
    }

    func perform(_ m: Move) {
        guard let id = grid[m.from], let n = nodes[id], let jn = nodes[m.jumped] else { return }
        deselect(settle: false)
        grid[m.to] = id; grid[m.from] = nil; grid[m.over] = nil
        history.append(m)
        jump(n, to: local(m.to))
        jn.removeAllActions()
        let gone = SCNAction.group([.move(by: SCNVector3(0, -0.5, 0), duration: 0.35), .fadeOut(duration: 0.35), .scale(to: 0.5, duration: 0.35)])
        gone.timingMode = .easeIn
        jn.runAction(.sequence([.wait(duration: 0.18), gone]))

        let steps: [Double] = [0, 2, 4, 7, 9, 12, 14, 16]
        let note = 62 + steps[history.count % steps.count]
        audio.tone(note + 12, amp: 0.09, decay: 1.1, harm: 0.3, pan: 0.35 + 0.3 * Double(m.to.c) / Double(board.n - 1), delay: 0.4)
        audio.play(Voice(freq: 1900, amp: 0.035, decay: 0.025, pan: 0.5, harm: 0.5, delay: 0.42))
        updateMovable()
        refreshHUD()
        if !anyMoves {
            root.runAction(.sequence([.wait(duration: 0.8), .run { [weak self] _ in DispatchQueue.main.async { locked { self?.finish() } } }]), forKey: "end")
        }
    }

    func undo() {
        guard mode == .play || mode == .end else { return }
        guard undosUsed < diff.undos, let m = history.last else { audio.tone(45, amp: 0.05, decay: 0.25, harm: 0.1); return }
        guard let id = grid[m.to], let n = nodes[id], let jn = nodes[m.jumped] else { return }
        history.removeLast()
        if diff.undos != .max { undosUsed += 1 }
        root.removeAction(forKey: "end")
        if mode == .end {
            mode = .play
            hud.clearPanel()
            resumedAt = Date()
        }
        deselect()
        grid[m.from] = id; grid[m.to] = nil; grid[m.over] = m.jumped
        jump(n, to: local(m.from))
        jn.removeAllActions()
        jn.position = local(m.over, lift: 0.5)
        jn.scale = SCNVector3(1, 1, 1)
        let back = SCNAction.group([.fadeIn(duration: 0.3), .move(to: local(m.over), duration: 0.35)]); back.timingMode = .easeOut
        jn.runAction(back)
        audio.tone(57, amp: 0.06, decay: 0.7, harm: 0.2)
        updateMovable()
        refreshHUD()
    }

    func deny(_ p: Pos) {
        guard let id = grid[p], let n = nodes[id] else { return }
        let d: CGFloat = 0.05
        n.removeAllActions()
        n.position = local(p)
        n.runAction(.sequence([.move(by: SCNVector3(-d, 0, 0), duration: 0.05), .move(by: SCNVector3(2 * d, 0, 0), duration: 0.08), .move(to: local(p), duration: 0.05)]))
        audio.tone(45, amp: 0.06, decay: 0.25, harm: 0.1)
    }

    func toggleMusic() {
        audio.musicOn.toggle()
        store.s.musicOff = !audio.musicOn
        store.save()
        if mode == .play { refreshHUD() }
    }

    func finish(timeout: Bool = false) {
        guard mode == .play, timeout || !anyMoves else { return }
        let secs = seconds
        elapsed = TimeInterval(secs)
        resumedAt = nil
        mode = .end
        root.removeAction(forKey: "end")
        deselect()
        updateMovable()
        let left = grid.count
        let perfect = left == 1 && grid.keys.contains { board.empty.contains($0) }
        let goalMet = !timeout && left <= goal
        let raw = (board.marbles - left) * 10 + (left == 1 ? 200 : 0) + (perfect ? 100 : 0)
        let score = Int(Double(raw) * diff.multiplier * (goalMet ? 1 : 0.4))

        var p = store.player
        p.points += score
        p.games += 1
        p.best = min(p.best ?? 99, left)
        store.player = p
        if !randomSelected {                      // losowe plansze nie trafiają do tabeli rekordów
            store.s.records.append(Record(player: p.name, board: store.s.board, difficulty: store.s.difficulty, left: left,
                                          seconds: secs, score: score, date: Date()))
        }
        if store.s.records.count > 500 { store.s.records.removeFirst(store.s.records.count - 500) }
        store.save()

        let notes: [Double] = goalMet ? (left == 1 ? [74, 78, 81, 86, 90] : [62, 66, 69, 74]) : [57, 60, 64]
        for (i, note) in notes.enumerated() { audio.tone(note, amp: 0.055, decay: 2, pan: 0.2 + Double(i) * 0.15, delay: Double(i) * 0.17) }

        let head: String
        if timeout { head = "Koniec czasu" }
        else if !goalMet { head = "Cel nieosiągnięty" }
        else {
            switch left {
            case 1 where perfect: head = "Mistrzostwo"
            case 1: head = "Znakomicie"
            case 2: head = "Bardzo dobrze"
            default: head = "Cel osiągnięty"
            }
        }
        var lines = ["\(remained(left))   ·   czas \(clock(secs))   ·   \(board.name), \(diff.name.lowercased())"]
        if perfect { lines[0] = "Ostatnia kulka stoi na polu startowym   ·   czas \(clock(secs))" }
        lines.append(goalMet ? "Cel osiągnięty: \(goalText)" : "Cel: \(goalText) — tym razem się nie udało (punkty ×0,4)")
        lines.append("+\(score) pkt   ·   razem \(p.points) pkt")
        hud.showEnd(head, lines, animated: true)
        refreshHUD()
    }

    // MARK: Menu i rekordy

    var items: [Item] { (paused ? [.resume] : []) + [.play, .tutorial, .difficulty, .board, .theme, .player, .newPlayer, .records, .quit] }

    func row(_ it: Item) -> MenuRow {
        switch it {
        case .resume: return MenuRow(name: "Wróć do gry", value: nil, dim: false)
        case .play: return MenuRow(name: paused ? "Nowa gra" : "Graj", value: nil, dim: false)
        case .tutorial: return MenuRow(name: "Samouczek", value: nil, dim: false)
        case .board:
            if randomSelected && generating { return MenuRow(name: "Plansza", value: "Losowa  ·  generuję…", dim: false) }
            return MenuRow(name: "Plansza", value: "\(board.name)  ·  \(board.marbles)", dim: false)
        case .difficulty: return MenuRow(name: "Trudność", value: diff.name, dim: false)
        case .set: return MenuRow(name: "Kulki", value: MarbleSet.all[store.s.set].name, dim: false)
        case .theme: return MenuRow(name: "Motyw", value: theme.light ? "Jasny" : "Ciemny", dim: false)
        case .player: return MenuRow(name: "Gracz", value: store.player.name, dim: false)
        case .newPlayer: return MenuRow(name: "Nowy gracz…", value: naming.map { $0 + "▏" }, dim: false, plain: true)
        case .records: return MenuRow(name: "Rekordy", value: nil, dim: false)
        case .quit: return MenuRow(name: "Wyjście", value: nil, dim: false)
        }
    }

    func renderMenu(animated: Bool = false) {
        menuSel = min(menuSel, items.count - 1)
        let p = store.player
        var notes: [String]
        if naming != nil {
            notes = ["Wpisz imię nowego gracza i naciśnij Enter   ·   Esc anuluje"]
        } else if items[menuSel] == .board && randomSelected {
            notes = ["Losowy kształt, sprawdzony solverem: da się zostawić jedną kulkę   ·   Enter losuje kolejny"]
        } else if items[menuSel] == .tutorial {
            notes = ["Komputer rozwiąże planszę angielską i po drodze wyjaśni zasady."]
        } else {
            notes = [diff.about]
        }
        notes.append("\(p.name)   ·   \(p.points) pkt   ·   gier \(p.games)")
        hud.showMenu(items.map(row), selected: menuSel, notes: notes, animated: animated)
    }

    func openMenu() {
        if mode == .play, let t = resumedAt { elapsed += Date().timeIntervalSince(t); resumedAt = nil; paused = true }
        if mode == .end { paused = false }
        mode = .menu
        deselect()
        updateMovable()
        hud.showGameLayer(false)
        menuSel = 0
        placeRoot(animated: true)
        renderMenu(animated: true)
    }

    func resume() {
        mode = .play
        paused = false
        hud.clearPanel()
        hud.showGameLayer(true)
        placeRoot(animated: true)
        resumedAt = Date()
        updateMovable()
        refreshHUD()
    }

    func cycle<T>(_ value: inout Int, _ all: [T], _ dir: Int) {
        value = (value + (dir == 0 ? 1 : dir) + all.count) % all.count
    }

    func activate(_ index: Int, dir: Int) {
        guard index < items.count else { return }
        menuSel = index
        let it = items[index]
        if naming != nil && it != .newPlayer { naming = nil }
        switch it {
        case .resume: if dir == 0 { hud.fold { self.resume() } }; return
        case .play: if dir == 0 && !generating { hud.fold { self.newGame() } }; return
        case .tutorial: if dir == 0 { hud.fold { self.startTutorial() } }; return
        case .board:
            // plansze bieżącego poziomu + „Losowa” (-1); Enter na losowej losuje kolejną
            let options = Board.ofLevel(store.s.difficulty) + [-1]
            let current = randomSelected ? -1 : store.s.board
            if generating { return }
            if dir == 0 && current == -1 { generateRandom(); renderMenu(); return }
            let i = options.firstIndex(of: current) ?? 0
            let next = options[(i + (dir == 0 ? 1 : dir) + options.count) % options.count]
            paused = false
            if next == -1 {
                randomSelected = true
                generateRandom()
            } else {
                randomSelected = false
                store.s.board = next
                var lb = store.s.levelBoards ?? [0, 1, 3]
                lb[store.s.difficulty] = next
                store.s.levelBoards = lb
                showBoard()
            }
        case .difficulty:
            cycle(&store.s.difficulty, Difficulty.all, dir)
            paused = false
            randomSelected = false
            let remembered = store.s.levelBoards?[store.s.difficulty]
            store.s.board = remembered.flatMap { Board.all.indices.contains($0) && Board.all[$0].level == store.s.difficulty ? $0 : nil }
                ?? Board.ofLevel(store.s.difficulty)[0]
            showBoard()
        case .set:
            return
        case .theme:
            transitionTheme(to: theme.light ? .dark : .light)
        case .player:
            cycle(&store.s.current, store.s.players, dir)
            paused = false
        case .newPlayer:
            if dir == 0 {
                if let n = naming { commitName(n) } else { naming = "" }
                renderMenu()
            }
            return
        case .records: if dir == 0 { openRecords() }; return
        case .quit: if dir == 0 { NSApp.terminate(nil) }; return
        }
        store.save()
        audio.tone(dir < 0 ? 79 : 81, amp: 0.03, decay: 0.25, harm: 0.1)
        renderMenu()
    }

    /// W jasnym motywie podłoga rysuje tylko cień planszy — pod nią widać czysty kolor tła.
    func styleFloor() {
        guard let m = floorNode.geometry?.firstMaterial else { return }
        m.lightingModel = theme.light ? .shadowOnly : .physicallyBased
        m.diffuse.contents = NSColor(cgColor: rgb(theme.floor))
        (floorNode.geometry as? SCNFloor)?.reflectivity = theme.light ? 0 : 0.04
        floorNode.position.y = theme.floorY      // w jasnym motywie bliżej planszy: cień przy niej, nie gdzieś z boku
    }

    /// Płynna zmiana motywu: obraz starej sceny przykrywa ekran i powoli się rozpuszcza nad nowym motywem,
    /// a napisy menu łagodnie pojawiają się w nowych kolorach.
    func transitionTheme(to t: Theme) {
        let old = view.snapshot()
        theme = t
        store.s.lightTheme = t.light
        let cover = SKSpriteNode(texture: SKTexture(image: old), size: hud.size)
        cover.position = CGPoint(x: hud.size.width / 2, y: hud.size.height / 2)
        cover.zPosition = -30                                // pod winietą i napisami
        hud.addChild(cover)
        applyTheme()
        let fade = SKAction.fadeOut(withDuration: 0.9)
        fade.timingMode = .easeInEaseOut
        cover.run(.sequence([.wait(forDuration: 0.05), fade, .removeFromParent()]))
        for layer in [hud.panel, hud.gameLayer] where layer.alpha > 0 {
            let a = layer.alpha
            layer.alpha = 0
            layer.run(.sequence([.wait(forDuration: 0.25), .fadeAlpha(to: a, duration: 0.55)]))
        }
    }

    /// Przełącza motyw: tło, mgła, podłoże, studio odbić, plansza i nakładka.
    func applyTheme() {
        scene.background.contents = bgColor
        scene.fogColor = bgColor
        view.backgroundColor = bgColor
        view.window?.backgroundColor = bgColor
        styleFloor()
        ambientNode.light?.intensity = theme.ambient
        tints.forEach { $0.light?.intensity = theme.tint; $0.light?.castsShadow = !theme.light }
        keyNode.light?.shadowColor = NSColor(white: 0, alpha: theme.shadowAlpha)
        keyNode.light?.shadowRadius = theme.shadowSoft
        cam.camera?.screenSpaceAmbientOcclusionIntensity = theme.ssao
        ambientNode.light?.color = NSColor(cgColor: rgb(theme.ambientTint))!
        cam.camera?.exposureOffset = theme.exposure
        cam.camera?.vignettingIntensity = theme.camVignette
        cam.camera?.bloomIntensity = theme.bloom
        cam.camera?.wantsDepthOfField = theme.dof
        keyNode.light?.intensity = theme.key
        scene.lightingEnvironment.intensity = theme.studio
        scene.lightingEnvironment.contents = writeStudioHDR(light: theme.light)
        buildBoard()
        hud.applyTheme()
    }

    func showBoard() {
        buildBoard()
        resized()
        setupMarbles(sound: false)
    }

    /// Losuje planszę dla bieżącego poziomu w tle (sprawdzoną solverem) i pokazuje ją w menu.
    func generateRandom() {
        guard !generating else { return }
        generating = true
        let level = store.s.difficulty
        DispatchQueue.global(qos: .userInitiated).async {
            let b = Board.random(level: level)
            DispatchQueue.main.async {
                locked {
                    self.generating = false
                    guard self.randomSelected, self.store.s.difficulty == level else { return }
                    if let b {
                        self.randomBoard = b
                        if self.mode == .menu { self.showBoard() }
                    } else {
                        self.randomSelected = self.randomBoard != nil
                    }
                    if self.mode == .menu { self.renderMenu() }
                }
            }
        }
    }

    func commitName(_ raw: String) {
        naming = nil
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let i = store.s.players.firstIndex(where: { $0.name == name }) {
            store.s.current = i
        } else {
            store.s.players.append(Player(name: name))
            store.s.current = store.s.players.count - 1
        }
        paused = false
        store.save()
        audio.tone(81, amp: 0.04, decay: 0.4, harm: 0.1)
        menuSel = items.firstIndex(of: .player) ?? 0
    }

    /// Wpisywanie imienia bezpośrednio w menu.
    func typeName(_ e: NSEvent) {
        guard var n = naming else { return }
        switch e.keyCode {
        case 36, 76: commitName(n); renderMenu(); return
        case 53: naming = nil; renderMenu(); return
        case 51: if !n.isEmpty { n.removeLast() }
        default:
            let ok = (e.characters ?? "").filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
            n += ok
            n = String(n.prefix(16))
        }
        naming = n
        renderMenu()
    }

    // MARK: Samouczek

    static let tips: [Int: String] = [
        0: "Kulką przeskakujesz sąsiednią kulkę i lądujesz na wolnym polu tuż za nią.",
        1: "Przeskoczona kulka znika z planszy.",
        3: "Skacze się tylko w poziomie i w pionie — nigdy na skos.",
        7: "Planuj z wyprzedzeniem: samotna kulka przy brzegu łatwo zostaje bez ruchu.",
        14: "Opłaca się czyścić planszę fragmentami, blok po bloku.",
        24: "Cel: zostawić jedną kulkę — najlepiej na polu, które na starcie było puste.",
    ]

    func startTutorial() {
        mode = .tutorial
        tutorial = true
        paused = false
        naming = nil
        hud.clearPanel()
        hud.showGameLayer(false)
        buildBoard()
        resized()
        setupMarbles(sound: true)
        placeRoot(animated: true)
        hud.say("Samouczek: komputer gra sam. Kliknij lub naciśnij dowolny klawisz, aby wyjść.")
        tutorialToken += 1
        let token = tutorialToken
        let solver = Solver(board), start = solver.encode(grid.keys)
        DispatchQueue.global(qos: .userInitiated).async {
            var plan: [(Pos, Pos, Pos)] = []
            if case .found(let p) = solver.solve(start, budget: 8) { plan = p }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { locked { self.tutorialStep(plan, 0, token) } }
        }
    }

    func tutorialStep(_ plan: [(Pos, Pos, Pos)], _ i: Int, _ token: Int) {
        guard tutorialToken == token, mode == .tutorial else { return }
        if let t = Game.tips[i] { hud.say(t) }
        guard i < plan.count else {
            hud.say(grid.count == 1 ? "Gotowe — została jedna kulka. Kliknij, aby wrócić do menu."
                                    : "Koniec pokazu. Kliknij, aby wrócić do menu.")
            return
        }
        let (f, o, t) = plan[i]
        let pause = Game.tips[i] != nil ? 1.6 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
            locked {
                guard self.tutorialToken == token, self.mode == .tutorial else { return }
                self.select(f)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    locked {
                        guard self.tutorialToken == token, self.mode == .tutorial, let j = self.grid[o] else { return }
                        self.perform(Move(from: f, over: o, to: t, jumped: j))
                        self.tutorialStep(plan, i + 1, token)
                    }
                }
            }
        }
    }

    func endTutorial() {
        tutorialToken += 1
        tutorial = false
        hud.say(nil)
        buildBoard()
        resized()
        setupMarbles(sound: false)
        openMenu()
    }

    func openRecords() {
        mode = .records
        recBoard = store.s.board
        renderRecords(animated: true)
    }

    func renderRecords(animated: Bool = false) {
        let recs = store.top(board: recBoard).enumerated().map { i, r in
            ["\(i + 1).", r.player, Difficulty.all[r.difficulty].name, "\(r.left) \(plural(r.left))", clock(r.seconds), "\(r.score)"]
        }
        let ps = store.s.players.sorted { $0.points > $1.points }.prefix(6).map { p -> [String] in
            let top = store.s.records.filter { $0.player == p.name }.map(\.score).max()
            return ["", p.name, "\(p.games)", p.best.map { "\($0) \(plural($0))" } ?? "—", top.map { "\($0)" } ?? "—", "\(p.points)"]
        }
        hud.showRecords(board: Board.all[recBoard].name, records: recs, players: Array(ps), animated: animated)
    }

    // MARK: Wejście

    func mouseMoved(_ pt: CGPoint) {
        let b = view.bounds.size
        mouse = CGPoint(x: max(-1, min(1, pt.x / b.width * 2 - 1)), y: max(-1, min(1, pt.y / b.height * 2 - 1)))
        if mode == .menu, !dragging, let (i, _) = hud.menuHit(pt), i != menuSel {
            menuSel = i
            renderMenu()
        }
    }

    func mouseDown(_ pt: CGPoint) {
        if hud.about != nil { hud.hideAbout(); return }
        if mode != .intro, hud.signHit(pt) { hud.showAbout(); return }
        switch mode {
        case .intro: hud.skipIntro(); return
        case .menu: if !hud.folding, let (i, d) = hud.menuHit(pt) { activate(i, dir: d) }; return
        case .records:
            if pt.y > hud.size.height * 0.8 {
                recBoard = (recBoard + (pt.x > hud.size.width / 2 ? 1 : -1) + Board.all.count) % Board.all.count
                renderRecords()
            } else { openMenu() }
            return
        case .end: newGame(); return
        case .tutorial: endTutorial(); return
        case .play: break
        }
        dragging = false
        dragCandidate = false
        guard let v = planePoint(pt, y: restY), let p = cellAt(v) else { deselect(); return }
        if let s = selected, let m = targets(from: s).first(where: { $0.to == p }) { perform(m); return }
        if grid[p] != nil {
            if targets(from: p).isEmpty { deselect(); deny(p); return }
            if selected != p { select(p) }
            dragCandidate = true
            if let g = planePoint(pt, y: restY + 0.3) {
                let l = local(p)
                grabOffset = CGPoint(x: l.x - g.x, y: l.z - g.y)
            }
        } else {
            deselect()
        }
    }

    func mouseDragged(_ pt: CGPoint) {
        guard mode == .play, dragCandidate, let s = selected, let id = grid[s], let n = nodes[id],
              let g = planePoint(pt, y: restY + 0.3) else { return }
        let x = g.x + grabOffset.x, z = g.y + grabOffset.y
        let l = local(s)
        if !dragging && hypot(x - l.x, z - l.z) > 0.06 { dragging = true }
        if dragging {
            n.removeAllActions()
            n.position = SCNVector3(x, restY + 0.3, z)
        }
    }

    func mouseUp(_ pt: CGPoint) {
        defer { dragging = false; dragCandidate = false }
        guard mode == .play, dragging, let s = selected, let id = grid[s], let n = nodes[id] else { return }
        if let p = cellAt(CGPoint(x: n.position.x, y: n.position.z), tolerance: 0.62),
           let m = targets(from: s).first(where: { $0.to == p }) {
            perform(m)
        } else {
            jump(n, to: local(s, lift: 0.3), height: 0.15, duration: 0.25)
        }
    }

    func key(_ e: NSEvent) -> Bool {
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        let enter = e.keyCode == 36 || e.keyCode == 76 || ch == " "
        let esc = e.keyCode == 53
        if hud.about != nil { if e.keyCode == 53 || e.keyCode == 36 { hud.hideAbout() }; return true }
        if mode == .menu, hud.folding { return true }
        if mode == .menu, naming != nil { typeName(e); return true }
        if ch == "m" { toggleMusic(); return true }
        if ch == "f" { view.window?.toggleFullScreen(nil); return true }
        switch mode {
        case .intro: hud.skipIntro()
        case .tutorial: endTutorial()
        case .menu:
            switch e.keyCode {
            case 126: menuSel = (menuSel - 1 + items.count) % items.count; renderMenu()
            case 125: menuSel = (menuSel + 1) % items.count; renderMenu()
            case 123: activate(menuSel, dir: -1)
            case 124: activate(menuSel, dir: 1)
            default:
                if enter { activate(menuSel, dir: 0) } else if esc, paused { resume() } else { return false }
            }
        case .records:
            switch e.keyCode {
            case 123: recBoard = (recBoard - 1 + Board.all.count) % Board.all.count; renderRecords()
            case 124: recBoard = (recBoard + 1) % Board.all.count; renderRecords()
            default: if esc || enter { openMenu() } else { return false }
            }
        case .end:
            if enter || ch == "r" || ch == "n" { newGame() } else if esc { openMenu() } else if ch == "z" || ch == "u" { undo() } else { return false }
        case .play:
            switch ch {
            case "z", "u", "\u{7f}": undo()
            case "r", "n": newGame()
            case "h": hint()
            default: if esc { if selected != nil { deselect() } else { openMenu() } } else { return false }
            }
        }
        return true
    }
}

// MARK: - Aplikacja

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var game: Game!
    var fullScreenObserver: NSObjectProtocol?
    let audio = Audio()

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()

        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let rect = NSRect(x: 0, y: 0, width: vf.width * 0.8, height: vf.height * 0.85)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Samotnik"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = bgColor
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 820, height: 560)
        window.acceptsMouseMovedEvents = true

        let container = NSView(frame: rect)
        let view = GameView(frame: rect, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        let overlay = OverlayView(frame: rect)
        for v in [view, overlay] as [NSView] {
            v.autoresizingMask = [.width, .height]
            container.addSubview(v)
        }
        window.contentView = container
        game = Game(view: view, overlay: overlay, audio: audio)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification, object: window, queue: .main) { [weak self] _ in
            locked { self?.game.resized() }
        }
        // intro rusza dopiero, gdy okno ma docelowy rozmiar (po wejściu w pełny ekran) — logo od razu we właściwej skali
        var started = false
        let begin = { [weak self] in
            guard let self, !started else { return }
            started = true
            locked { self.game.resized(); self.game.start() }
        }
        if CommandLine.arguments.contains("--window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { begin() }
        } else {
            fullScreenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { begin() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.window.toggleFullScreen(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { begin() }      // na wypadek, gdyby pełny ekran się nie włączył
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ukryj Samotnika", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Zakończ Samotnika", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let gameItem = NSMenuItem(); main.addItem(gameItem)
        let menu = NSMenu(title: "Gra")
        menu.addItem(withTitle: "Menu", action: #selector(showMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Cofnij ruch", action: #selector(undo), keyEquivalent: "z").target = self
        menu.addItem(withTitle: "Muzyka wł./wył.", action: #selector(toggleMusic), keyEquivalent: "m").target = self
        menu.addItem(.separator())
        let fs = menu.addItem(withTitle: "Pełny ekran", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        gameItem.submenu = menu
        NSApp.mainMenu = main
    }

    @objc func showMenu() { locked { if game.mode != .intro { game.openMenu() } } }
    @objc func undo() { locked { game.undo() } }
    @objc func toggleMusic() { locked { game.toggleMusic() } }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
