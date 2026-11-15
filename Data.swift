// Samotnik — plansze, zestawy kulek, gracze, rekordy i zapis stanu.

import Foundation

// MARK: - Plansze

struct Board {
    let name: String
    let level: Int                       // 0 łatwy, 1 normalny, 2 trudny
    let n: Int
    let cells: Set<Pos>
    let empty: Set<Pos>
    let all: [Pos]
    let cc: CGFloat, cr: CGFloat         // środek zajętego obszaru (kolumna, wiersz) — także dla plansz asymetrycznych
    let extent: CGRect                   // obrys pól w układzie planszy (x w prawo, y w górę)
    /// Współrzędne środka pola w układzie planszy: x w prawo, y w górę, środek obszaru w (0, 0).
    func x(_ p: Pos) -> CGFloat { CGFloat(p.c) - cc }
    func y(_ p: Pos) -> CGFloat { cr - CGFloat(p.r) }
    var marbles: Int { cells.count - empty.count }
    /// Najmniej kulek, jakie solver potrafi zostawić z pozycji startowej (zwykle 1; większe tylko dla nielicznych plansz).
    var target: Int { Board.targets[name] ?? 1 }
    static var targets: [String: Int] = ["Wielka gwiazda": 2]
    func has(_ p: Pos) -> Bool { cells.contains(p) }

    init(name: String, level: Int, cells list: [Pos], empty: [Pos]) {
        self.name = name
        self.level = level
        all = list.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
        cells = Set(all)
        self.empty = Set(empty)
        let rs = all.map(\.r), cs = all.map(\.c)
        n = max(rs.max()! - rs.min()!, cs.max()! - cs.min()!) + 1
        cc = CGFloat(cs.min()! + cs.max()!) / 2
        cr = CGFloat(rs.min()! + rs.max()!) / 2
        let w = CGFloat(cs.max()! - cs.min()! + 1), h = CGFloat(rs.max()! - rs.min()! + 1)
        extent = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    }

    init(_ name: String, level: Int, n: Int, empty: [Pos], _ inside: (Int, Int) -> Bool) {
        self.init(name: name, level: level,
                  cells: (0..<n).flatMap { r in (0..<n).map { Pos(r: r, c: $0) } }.filter { inside($0.r, $0.c) }, empty: empty)
    }

    /// Plansza z rysunku: X — kulka, o — pole puste na starcie, kropka lub spacja — brak pola.
    init(_ name: String, level: Int, _ art: [String]) {
        var cells: [Pos] = [], empty: [Pos] = []
        for (r, line) in art.enumerated() {
            for (c, ch) in line.enumerated() {
                if ch == "X" || ch == "o" { cells.append(Pos(r: r, c: c)) }
                if ch == "o" { empty.append(Pos(r: r, c: c)) }
            }
        }
        self.init(name: name, level: level, cells: cells, empty: empty)
    }

    static func ofLevel(_ l: Int) -> [Int] { all.indices.filter { all[$0].level == l } }

    // Kolejność ma znaczenie tylko dla rekordów (indeksy) — nowe plansze zawsze dopisujemy na końcu.
    static let all: [Board] = [
        Board("Mały krzyż", level: 0, n: 5, empty: [Pos(r: 2, c: 2)]) { r, c in (1...3).contains(r) || (1...3).contains(c) },
        Board("Angielska", level: 1, n: 7, empty: [Pos(r: 3, c: 3)]) { r, c in (2...4).contains(r) || (2...4).contains(c) },
        Board("Europejska", level: 1, n: 7, empty: [Pos(r: 3, c: 2)]) { r, c in
            (2...4).contains(r) || (2...4).contains(c) || ((1...5).contains(r) && (1...5).contains(c))
        },
        Board("Bastion", level: 2, [".XXXXXXX.", "XXXXXXXXX", "XXXXoXXXX", "XXXXXXXXX", "..XXXXX..", "..XXXXX.."]),
        Board("Wiegleb", level: 2, n: 9, empty: [Pos(r: 4, c: 4)]) { r, c in (3...5).contains(r) || (3...5).contains(c) },
        Board("Asymetryczna", level: 1, n: 8, empty: [Pos(r: 3, c: 3)]) { r, c in (2...4).contains(c) || (2...4).contains(r) },
        Board("Kwadrat 5×5", level: 0, n: 5, empty: [Pos(r: 1, c: 2)]) { _, _ in true },
        Board("Kwadrat 6×6", level: 1, n: 6, empty: [Pos(r: 1, c: 1)]) { _, _ in true },
        Board("Szeroki krzyż", level: 2, n: 8, empty: [Pos(r: 2, c: 3)]) { r, c in (2...5).contains(r) || (2...5).contains(c) },
        Board("Litera L", level: 1, n: 7, empty: [Pos(r: 5, c: 1)]) { r, c in c <= 2 || r >= 4 },
        Board("Litera T", level: 1, n: 7, empty: [Pos(r: 3, c: 3)]) { r, c in r <= 2 || (2...4).contains(c) },
        Board("Schody", level: 0, [".XX....", "XXXX...", "XXXXX..", ".XXXoX.", "..XXXXX", "...XXXX", "....XXX"]),
        Board("Strzała", level: 0, n: 9, empty: [Pos(r: 3, c: 4)]) { r, c in (r <= 3 && abs(c - 4) <= r) || ((4...6).contains(r) && (3...5).contains(c)) },
        Board("Serce", level: 0, [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXoXX.", "..XXX..", "...X..."]),
        Board("Wyspa", level: 1, [".XXXX.", "XXXXXX", "XXoXXX", "XXXXXX", "..XX..", "..XX.."]),
        Board("Klepsydra", level: 1, n: 7, empty: [Pos(r: 3, c: 3)]) { r, c in abs(c - 3) <= max(1, abs(r - 3)) },
        Board("Błyskawica", level: 1, n: 8, empty: [Pos(r: 3, c: 4)]) { r, c in
            (r <= 2 && c <= 4) || ((3...4).contains(r) && (2...6).contains(c)) || (r >= 5 && c >= 3)
        },
        Board("Wiatrak", level: 0, n: 7, empty: [Pos(r: 2, c: 3)]) { r, c in
            ((2...4).contains(r) && (2...4).contains(c)) || (r <= 1 && (3...4).contains(c)) || ((3...4).contains(r) && c >= 5)
                || (r >= 5 && (2...3).contains(c)) || ((2...3).contains(r) && c <= 1)
        },

        // — łatwe —
        Board("Prostokąt 3×4", level: 0, ["XoXX", "XXXX", "XXXX"]),
        Board("Prostokąt 3×5", level: 0, ["XXoXX", "XXXXX", "XXXXX"]),
        Board("Kwadrat 4×4", level: 0, ["XoXX", "XXXX", "XXXX", "XXXX"]),
        Board("Prostokąt 4×5", level: 0, ["XXXXX", "XXoXX", "XXXXX", "XXXXX"]),
        Board("Kropla", level: 0, ["XXX..", "XXX..", "..oXX", "..XXX", "..XXX"]),
        Board("Litera U", level: 0, ["XX.XX", "XX.XX", "XXoXX", "XXXXX"]),
        Board("Litera H", level: 0, ["XX.XX", "XX.XX", "XoXXX", "XX.XX", "XX.XX"]),
        Board("Litera Z", level: 0, ["XXoX..", "XXXX..", "..XX..", "..XXXX", "..XXXX"]),
        Board("Łódka", level: 0, [".XXoXX.", "XXXXXXX", ".XXXXX."]),
        Board("Trapez", level: 0, ["..oXX..", ".XXXXX.", ".XXXXX."]),
        Board("Krzyżyk", level: 0, ["..XX..", "..oX..", "XXXXXX", "XXXXXX", "..XX..", "..XX.."]),
        Board("Mała tarcza", level: 0, [".XXX.", "XXoXX", "XXXXX", ".XXX.", "..X.."]),
        Board("Domek", level: 0, ["..X..", "..X..", "XXXXX", "XXoXX", "XXXXX"]),
        Board("Grzybek", level: 0, [".XXXX.", "XXoXXX", "XXXXXX", "..XX..", "..XX.."]),
        Board("Zatoka", level: 1, [".XXXXX", ".XXXXX", "XXoXXX", "XXXXXX", "XXXXXX"]),
        Board("Litera C", level: 1, ["XXXXXX", "XXXXXX", "XX....", "XX....", "XXXoXX", "XXXXXX"]),
        Board("Litera O", level: 1, ["XXXXXX", "XXXXXX", "XX..XX", "XX..XX", "XXXoXX", "XXXXXX"]),
        Board("Przesmyk", level: 1, ["....XXX", "....XXX", "....XXX", "XXoXXXX", "XXXX...", "XXXX...", "XXXX..."]),
        Board("Półwysep", level: 1, ["..XXXX.", "..XXXX.", "..XoXXX", "....XXX", "...XXXX", "XXXXX..", "XXXXX..", "XXXX..."]),
        Board("Gwiazda", level: 1, ["...X...", "..XXX..", "XXXXXXX", ".XXoXX.", "XXXXXXX", "..XXX..", "...X..."]),
        Board("Zamek", level: 1, ["X.X.X.X", "XXXoXXX", "XXXXXXX", "XXXXXXX", "XX...XX"]),
        Board("Most", level: 1, ["XXXXXXXX", "XXXXXXXX", "XXXoXXXX", "XX....XX", "XX....XX"]),
        Board("Laguna", level: 1, ["..XX..", "..XX..", "..XX..", "..oX..", "XXXXXX", "XXXXXX", "XXXXXX"]),
        Board("Okulary", level: 1, [".XXX.XXX.", "XXXXoXXXX", "XXXXXXXXX", ".XXX.XXX."]),
        Board("Tarcza", level: 1, ["XXXXXXX", "XXXXXXX", "XXXoXXX", ".XXXXX.", ".XXXXX.", "..XXX..", "...X..."]),

        // — trudne —
        Board("Koło", level: 2, ["..XXXX..", ".XXXXXX.", "XXXXXXXX", "XXXXXXXX", "XXXoXXXX", "XXXXXXXX", ".XXXXXX.", "..XXXX.."]),
        Board("Kwadrat 7×7", level: 2, ["XXXXXXX", "XXXXXXX", "XXXoXXX", "XXXXXXX", "XXXXXXX", "XXXXXXX", "XXXXXXX"]),
        Board("Cytadela", level: 2, ["..XXXXX..", "XXXXXXXXX", "XXXXoXXXX", "XXXXXXXXX", "XXXXXXXXX"]),
        Board("Prostokąt 6×8", level: 2, ["XXXXXXXX", "XXXXXXXX", "XXXoXXXX", "XXXXXXXX", "XXXXXXXX", "XXXXXXXX"]),
        Board("Archipelag", level: 2, ["XXXXXXXXX", "XXXXXXXXX", "XXXXoXXXX", "XXXXXXXXX", "..XX.XX..", "..XX.XX.."]),
        Board("Gruby krzyż", level: 2, ["...XXXX..", "...XXXX..", "...XXXX..", "XXXXXXXXX", "XXXoXXXXX", "XXXXXXXXX", "XXXXXXXXX", "...XXXX..", "...XXXX.."]),
        Board("Monolit", level: 2, ["XXXXX", "XXXXX", "XXXXX", "XXoXX", "XXXXX", "XXXXX", "XXXXX", "XXXXX"]),
        Board("Wielka gwiazda", level: 2, ["....X....", "...XXX...", "..XXXXX..", "XXXXXXXXX", ".XXoXXXX.", "XXXXXXXXX", "..XXXXX..", "...XXX...", "....X...."]),
        Board("Twierdza", level: 2, ["X.X.X.X.X", "XXXXXXXXX", "XXXXoXXXX", "XXXXXXXXX", "XXXXXXXXX", "XXX...XXX"]),
        Board("Labirynt", level: 2, ["XXXXXXX..", "XXXXXXX..", "...XoXXXX", "...XXXXXX", "...XXXXX.", "...XXXXX.", "...XXXXX."]),
        Board("Delta", level: 2, ["XXXXXXXXX", "XXXXXXXXX", "XXXXoXXXX", "XXXXXXXXX", "XXXXXXXXX"]),
        Board("Kaskada", level: 2, [".XXXXX.", "XXXXXX.", "XXXXXXX", "XXXoXXX", "XXXXXXX", "XXXXX..", ".XXX...", ".XXX..."]),
        Board("Mozaika", level: 2, ["XXX...XXX", "XXX...XXX", ".XXXoXXX.", ".XXXXXXX.", "..XXXXX..", "..XXXXX..", "..XXXXX.."]),
        Board("Atol", level: 2, ["XX...XX", "XX...XX", "XX...XX", "XXXXXXX", "XXXoXXX", "XXXXXXX", "XXXXXXX"]),
        Board("Wielka tarcza", level: 2, ["XXXXXXXXX", "XXXXXXXXX", "XXXXXXXXX", ".XXXXXXX.", ".XXoXXXX.", "..XXXXX..", "...XXX...", "....X...."]),
        Board("Wielka błyskawica", level: 2, ["XXXXXX....", "XXXXXX....", "XXXXXX....", "..XXXXXX..", "..XXoXXX..", "....XXXXXX", "....XXXXXX", "....XXXXXX"]),
        Board("Fiord", level: 2, ["XXXX.....", "XXXXXXXXX", "XXXoXXXXX", "XXXXXXXXX", "XXXXXXXXX", "....XXX.."]),
    ]
}

extension String {
    /// Pomocnicze wcięcie rysunku planszy.
    func withPad(_ k: Int) -> String { String(repeating: ".", count: k) + self + String(repeating: ".", count: k) }
}

// MARK: - Trudność

struct Difficulty {
    let name: String, about: String
    let multiplier: Double
    let goal: Int               // ile kulek najwyżej może zostać, żeby cel był osiągnięty
    let undos: Int              // Int.max = bez limitu
    let hints: Bool             // cele po wybraniu kulki
    let movable: Bool           // podświetlenie kulek, które mogą skoczyć
    let solverHint: Bool        // klawisz H: podpowiedź prawdziwego ruchu z solvera
    let secondsPerMarble: Int?  // limit czasu: tyle sekund na każdą kulkę startową

    static let all = [
        Difficulty(name: "Łatwy", about: "cel: najwyżej 4 kulki  ·  podświetlone ruchy  ·  H podpowiada ruch  ·  cofanie bez limitu  ·  punkty ×1",
                   multiplier: 1, goal: 4, undos: .max, hints: true, movable: true, solverHint: true, secondsPerMarble: nil),
        Difficulty(name: "Normalny", about: "cel: najwyżej 2 kulki  ·  cele po wybraniu kulki  ·  3 cofnięcia  ·  punkty ×1,5",
                   multiplier: 1.5, goal: 2, undos: 3, hints: true, movable: false, solverHint: false, secondsPerMarble: nil),
        Difficulty(name: "Trudny", about: "cel: 1 kulka  ·  limit czasu (6 s na kulkę)  ·  bez podpowiedzi i cofania  ·  punkty ×2",
                   multiplier: 2, goal: 1, undos: 0, hints: false, movable: false, solverHint: false, secondsPerMarble: 6),
    ]
}

// MARK: - Zestawy kulek

/// Marmur: żyłki z zaburzonej sinusoidy wzdłuż losowego kierunku.
func veins(_ p: V3, _ v: Variant, sharp: Double) -> Double {
    let t = fbm(p * 2.2 + v.o, 5)
    let main = pow(1 - abs(sin((dot(p, v.axis) * 3.1 + t * 7.5) * .pi)), sharp)
    let fine = pow(1 - abs(sin((dot(p, v.side) * 5.3 + fbm(p * 4 + v.o2, 4) * 9) * .pi)), sharp * 2.2) * 0.45
    return min(1, main + fine)
}

func wood(_ p: V3, _ v: Variant, light: V3, dark: V3) -> Texel {
    let along = dot(p, v.axis)
    let radial = simd_length_compat(p - v.axis * along + v.side * 0.35)
    let rings = fract(radial * 7 + fbm(p * 2.5 + v.o, 4) * 0.9 + along * 0.4)
    let ring = smooth(0.0, 0.25, rings) * (1 - smooth(0.55, 1.0, rings))
    let grain = noise(V3(dot(p, v.side) * 70, dot(p, cross3(v.axis, v.side)) * 70, along * 3) + v.o2)
    let c = mix(dark, light, ring * 0.75 + 0.25) * (0.88 + grain * 0.2)
    return Texel(c: c, rough: 0.42 + grain * 0.15, h: ring * 0.4 + grain * 0.6)
}

func cross3(_ a: V3, _ b: V3) -> V3 { V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }

/// Kąt wokół osi wzoru, 0…2π.
func around(_ p: V3, _ v: Variant) -> Double {
    let q = cross3(v.axis, v.side)
    return atan2(dot(p, q), dot(p, v.side)) + .pi
}

let billiard: [UInt32] = [0xF2C230, 0x1F4FB8, 0xC8262E, 0x5B2A86, 0xEE7A22, 0x1E7A45, 0x7A1E22]
let pastel: [UInt32] = [0xE9785F, 0x3FA7A0, 0xE2B43C, 0x6C7FD8]
let swirls: [UInt32] = [0x2E7FD0, 0x2FA968, 0xD8402C, 0xE8B92A, 0x8A4FD0]

struct MarbleSet {
    /// Na razie w grze jest tylko podstawowy zestaw; pozostałe czekają w kodzie.
    static let available = 1

    let name: String
    let a: Look, b: Look
    let cost: Int       // punkty potrzebne do odblokowania

    static let all: [MarbleSet] = [
        MarbleSet(name: "Klasyczne",
                  a: Look(clear: 1) { p, v in Texel(c: col(0xDCD8D0) * (0.96 + fbm(p * 3 + v.o) * 0.08), rough: 0.26) },
                  b: Look(clear: 1) { p, v in Texel(c: mix(col(0x07080A), col(0x1C2026), fbm(p * 2 + v.o) * 0.6), rough: 0.12) },
                  cost: 0),
        MarbleSet(name: "Marmur",
                  a: Look(clear: 1) { p, v in Texel(c: mix(col(0xEDEBE6), col(0x6E7177), veins(p, v, sharp: 7) * 0.85), rough: 0.18) },
                  b: Look(clear: 1) { p, v in Texel(c: mix(col(0x0B0B0D), col(0xD9D5CC), veins(p, v, sharp: 12)), rough: 0.14) },
                  cost: 0),
        MarbleSet(name: "Drewno",
                  a: Look(clear: 0.5, bump: 0.6) { p, v in wood(p, v, light: col(0xE2C496), dark: col(0xB3864F)) },
                  b: Look(clear: 0.5, bump: 0.6) { p, v in wood(p, v, light: col(0x7A5232), dark: col(0x2E1B0F)) },
                  cost: 0),
        MarbleSet(name: "Kocie oko",
                  a: Look(clear: 1) { p, v in
                      let a = around(p, v), lat = dot(p, v.axis)
                      let vane = abs(sin(a * 2 + lat * 3 + fbm(p * 2 + v.o, 3) * 2.5))
                      let s = 1 - smooth(0.12, 0.3, vane)
                      return Texel(c: mix(col(0xD9E4EA), col(v.pick(swirls)), s * smooth(0.95, 0.6, abs(lat))), rough: 0.04)
                  },
                  b: Look(clear: 1) { p, v in
                      let a = around(p, v), lat = dot(p, v.axis)
                      let vane = abs(sin(a * 3 - lat * 4 + fbm(p * 2 + v.o, 3) * 3))
                      let s = 1 - smooth(0.1, 0.25, vane)
                      return Texel(c: mix(col(0x1D2229), col(v.pick([0xE0812B, 0x37B5A5, 0xB66BE0])), s * smooth(0.95, 0.5, abs(lat))), rough: 0.04)
                  },
                  cost: 500),
        MarbleSet(name: "Bilard",
                  a: Look(clear: 1) { p, v in
                      let band = abs(dot(p, v.axis)) < 0.42
                      let dotSpot = dot(p, v.side) > 0.93
                      let c = dotSpot ? col(0xF4F1EA) : (band ? col(v.pick(billiard)) : col(0xF4F1EA))
                      return Texel(c: c, rough: 0.1)
                  },
                  b: Look(clear: 1) { p, v in
                      let d = dot(p, v.axis)
                      let c = d > 0.93 ? col(0xF4F1EA) : col(v.pick(billiard))
                      return Texel(c: d > 0.975 && d < 0.985 ? col(0x111111) : c, rough: 0.1)
                  },
                  cost: 1200),
        MarbleSet(name: "Planety",
                  a: Look(bump: 0.35) { p, v in
                      let lat = dot(p, v.axis)
                      let t = fbm(p * 3 + v.o, 5)
                      let b = sin(lat * 15 + t * 4) * 0.5 + 0.5
                      var c = mix(mix(col(0x8A5A3A), col(0xC89F6E), b), col(0xEADBC0), smooth(0.55, 0.9, sin(lat * 7 + t * 2) * 0.5 + 0.5))
                      let spot = simd_length_compat(p - (v.side * 0.85 + v.axis * -0.35))
                      c = mix(c, col(0xB5533A), smooth(0.24, 0.12, spot + (t - 0.5) * 0.1))
                      return Texel(c: c, rough: 0.6, h: t)
                  },
                  b: Look { p, v in
                      let lat = dot(p, v.axis)
                      let t = fbm(p * 2.5 + v.o, 5)
                      let c = mix(col(0x234E96), col(0x5D95D2), sin(lat * 9 + t * 3) * 0.5 + 0.5)
                      return Texel(c: mix(c, col(0xE6F0FA), smooth(0.8, 0.95, noise(V3(lat * 30, t * 4, 0) + v.o2)) * 0.7), rough: 0.55)
                  },
                  cost: 2000),
        MarbleSet(name: "Chrom i miedź",
                  a: Look { p, v in Texel(c: col(0xD3D6DB), rough: 0.03 + fbm(p * 6 + v.o, 3) * 0.05, metal: 1) },
                  b: Look(bump: 1.6) { p, v in
                      let n = fbm(p * 3 + v.o, 5)
                      let patina = smooth(0.58, 0.7, n)
                      let hammer = worley(p * 9 + v.o2).0
                      return Texel(c: mix(col(0xC27A4C) * (0.9 + hammer * 0.2), col(0x4E9C8C), patina),
                                   rough: mix(0.22 + hammer * 0.18, 0.85, patina), metal: 1 - patina, h: hammer * hammer + patina * 0.15)
                  },
                  cost: 3000),
        MarbleSet(name: "Opal",
                  a: Look(clear: 1) { p, v in
                      let h = fbm(p * 2.5 + v.o, 4) * 2.2
                      let fleck = smooth(0.6, 0.75, noise(p * 14 + v.o2))
                      return Texel(c: mix(hue(h, sat: 0.28, val: 0.95), hue(h + 0.3, sat: 0.7, val: 1), fleck), rough: 0.08)
                  },
                  b: Look(clear: 1, emits: true) { p, v in
                      let h = fbm(p * 3 + v.o, 4) * 3
                      let fleck = smooth(0.58, 0.72, noise(p * 11 + v.o2))
                      let f = hue(h, sat: 0.9, val: 0.85)
                      return Texel(c: mix(col(0x0E1216), f, fleck), rough: 0.06, e: f * fleck * 0.18)
                  },
                  cost: 4200),
        MarbleSet(name: "Kropki",
                  a: Look(clear: 0.6, bump: 0.5) { p, v in
                      let d = worley(p * 3.2 + v.o).0
                      return Texel(c: d < 0.27 ? col(v.pick(pastel)) : col(0xF2EFE8), rough: 0.35, h: smooth(0.3, 0.24, d))
                  },
                  b: Look(clear: 0.6) { p, v in
                      let d = worley(p * 4 + v.o).0
                      return Texel(c: d < 0.22 ? col(0xF2EFE8) : col(0x1C2A4A), rough: 0.35)
                  },
                  cost: 5600),
        MarbleSet(name: "Lawa i popiół",
                  a: Look(emits: true, bump: 1.4) { p, v in
                      let (f1, f2) = worley(p * 3 + v.o)
                      let crack = 1 - smooth(0.02, 0.1, f2 - f1)
                      let heat = 0.6 + fbm(p * 4 + v.o2, 3) * 0.8
                      let rock = mix(col(0x161110), col(0x3A2C26), fbm(p * 6 + v.o, 4))
                      return Texel(c: mix(rock, col(0xFF6A1A), crack * 0.6), rough: 0.85,
                                   e: mix(col(0xFF4A08), col(0xFFC24A), crack * 0.5) * crack * heat, h: (1 - crack) * (0.6 + fbm(p * 9 + v.o2, 3) * 0.4))
                  },
                  b: Look(emits: true, bump: 0.8) { p, v in
                      let ember = smooth(0.82, 0.9, noise(p * 26 + v.o2))
                      let g = fbm(p * 5 + v.o, 4)
                      return Texel(c: col(0x6E6A66) * (0.75 + g * 0.4), rough: 0.95, e: col(0xFF5A10) * ember * 0.9, h: g + noise(p * 30 + v.o) * 0.3)
                  },
                  cost: 7200),
        MarbleSet(name: "Kosmos",
                  a: Look(clear: 1, clean: true, emits: true) { p, v in
                      let n1 = fbm(p * 2 + v.o, 5), n2 = fbm(p * 2.6 + v.o2, 5)
                      var c = mix(col(0x05060F), col(0x3A1E6E), smooth(0.45, 0.75, n1))
                      c = mix(c, col(0x1E5C9E), smooth(0.55, 0.8, n2) * 0.8)
                      let star = smooth(0.86, 0.93, noise(p * 95 + v.o))
                      return Texel(c: c + V3(repeating: star), rough: 0.05, e: c * 0.35 + V3(repeating: star * 1.2))
                  },
                  b: Look(clean: true, emits: true, bump: 1.0) { p, v in
                      let g = worley(p * 9 + v.o).0
                      let spot = smooth(0.7, 0.8, fbm(p * 2 + v.o2, 4))
                      let e = mix(col(0xFF5A00), col(0xFFD27A), 1 - g) * (1 - spot * 0.75)
                      return Texel(c: col(0xFF8A20), rough: 0.6, e: e, h: 1 - g)
                  },
                  cost: 9000),
        MarbleSet(name: "Neon",
                  a: Look(clear: 1, clean: true, emits: true) { p, v in
                      let lat = dot(p, v.axis) + fbm(p * 2 + v.o, 3) * 0.08
                      let ring = 1 - smooth(0.02, 0.07, abs(fract(lat * 3 + 0.5) - 0.5))
                      return Texel(c: mix(col(0x0A0C10), col(0x2FD8C8), ring), rough: 0.08, e: col(0x2FD8C8) * ring * 1.3)
                  },
                  b: Look(clear: 1, clean: true, emits: true) { p, v in
                      let lat = dot(p, v.axis), a = around(p, v) / (2 * .pi)
                      let l1 = 1 - smooth(0.02, 0.06, abs(fract(lat * 2.5) - 0.5))
                      let l2 = 1 - smooth(0.012, 0.04, abs(fract(a * 6) - 0.5)) * smooth(0.98, 0.85, abs(lat))
                      let g = max(l1, l2)
                      return Texel(c: mix(col(0x0A0C10), col(0xD83CB8), g), rough: 0.08, e: col(0xD83CB8) * g * 1.3)
                  },
                  cost: 11000),
        MarbleSet(name: "Złoto i platyna",
                  a: Look(bump: 0.25) { p, v in
                      let brush = noise(V3(dot(p, v.side) * 3, dot(p, cross3(v.axis, v.side)) * 3, dot(p, v.axis) * 160) + v.o)
                      return Texel(c: col(0xE0B44C) * (0.94 + brush * 0.1), rough: 0.18 + brush * 0.2, metal: 1, h: brush)
                  },
                  b: Look(bump: 1.8) { p, v in
                      let d = worley(p * 10 + v.o).0
                      return Texel(c: col(0xE5E4E2), rough: 0.06 + d * 0.22, metal: 1, h: d * d)
                  },
                  cost: 13500),
    ]
}

// MARK: - Gracze, rekordy, zapis

struct Player: Codable {
    var name: String
    var points = 0
    var games = 0
    var best: Int? = nil     // najmniej pozostawionych kulek
}

struct Record: Codable {
    var player: String
    var board: Int
    var difficulty: Int
    var left: Int
    var seconds: Int
    var score: Int
    var date: Date
}

struct Save: Codable {
    var players: [Player] = []
    var current = 0
    var board = 1
    var difficulty = 1
    var set = 0
    var records: [Record] = []
    var musicOff = false
    var levelBoards: [Int]? = nil    // ostatnio wybrana plansza na każdym poziomie trudności
    var lightTheme: Bool? = nil
}

final class Store {
    var s = Save()
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Samotnik")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("zapis.json")
        if let d = try? Data(contentsOf: url), let v = try? JSONDecoder().decode(Save.self, from: d) { s = v }
        if s.players.isEmpty {
            let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
            s.players = [Player(name: first.isEmpty ? "Gracz 1" : first)]
        }
        s.current = min(s.current, s.players.count - 1)
        s.board = min(s.board, Board.all.count - 1)
        s.set = min(s.set, MarbleSet.all.count - 1)
    }

    var player: Player {
        get { s.players[s.current] }
        set { s.players[s.current] = newValue }
    }

    func unlocked(_ set: Int) -> Bool { player.points >= MarbleSet.all[set].cost }
    var unlockedCount: Int { MarbleSet.all.indices.filter(unlocked).count }
    var nextLocked: MarbleSet? { MarbleSet.all.filter { $0.cost > player.points }.min { $0.cost < $1.cost } }

    func top(board: Int, limit: Int = 8) -> [Record] {
        s.records.filter { $0.board == board }
            .sorted { ($0.score, -$0.left, -$0.seconds) > ($1.score, -$1.left, -$1.seconds) }
            .prefix(limit).map { $0 }
    }

    func save() {
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: url, options: .atomic) }
    }
}

func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
