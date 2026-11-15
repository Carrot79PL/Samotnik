// Samotnik — solver: przeszukiwanie w głąb z pamięcią przegranych pozycji (plansza jako maska bitowa).
// Służy do podpowiedzi na łatwym poziomie i do samouczka.

import Foundation

final class Solver {
    enum Result { case found([(Pos, Pos, Pos)]), impossible, timeout }

    let cells: [Pos]
    private var index: [Pos: Int] = [:]
    private var moves: [(f: UInt64, o: UInt64, t: UInt64, fi: Int, oi: Int, ti: Int)] = []

    init(_ b: Board) {
        cells = b.all
        for (i, p) in cells.enumerated() { index[p] = i }
        for p in cells {
            for d in Pos.dirs {
                let o = p + d, t = o + d
                guard let fi = index[p], let oi = index[o], let ti = index[t] else { continue }
                moves.append((1 << UInt64(fi), 1 << UInt64(oi), 1 << UInt64(ti), fi, oi, ti))
            }
        }
        // najpierw ruchy z brzegów ku środkowi — rozwiązania znajdują się wtedy dużo szybciej
        let cx = b.cc, cy = b.cr
        func far(_ i: Int) -> CGFloat { abs(CGFloat(cells[i].c) - cx) + abs(CGFloat(cells[i].r) - cy) }
        moves.sort { far($0.fi) - far($0.ti) > far($1.fi) - far($1.ti) || (far($0.fi) - far($0.ti) == far($1.fi) - far($1.ti) && far($0.fi) > far($1.fi)) }
    }

    /// Sprawdza planszę: czy z jej pola startowego da się zostawić jedną kulkę; jeśli nie, szuka innego pola startowego.
    static func verify(_ b: Board, budget: TimeInterval) -> String {
        let sv = Solver(b)
        func tryHole(_ h: Pos) -> Result { sv.solve(sv.encode(b.all.filter { $0 != h }), budget: budget) }
        let start = b.empty.first!
        if case .found = tryHole(start) { return "OK" }
        let near = b.all.filter { $0 != start }.sorted {
            abs(CGFloat($0.c) - b.cc) + abs(CGFloat($0.r) - b.cr) < abs(CGFloat($1.c) - b.cc) + abs(CGFloat($1.r) - b.cr)
        }
        let deadline = Date().addingTimeInterval(budget * 12)
        for h in near.prefix(ProcessInfo.processInfo.environment["SAMOTNIK_ALL"] != nil ? 64 : 8) where Date() < deadline {
            if case .found = tryHole(h) { return "ALT \(h.r),\(h.c)" }
        }
        return "FAIL"
    }

    func encode<S: Sequence>(_ ps: S) -> UInt64 where S.Element == Pos {
        ps.reduce(0) { $0 | (1 << UInt64(index[$1]!)) }
    }

    /// Szuka ciągu ruchów kończącego się co najwyżej `target` kulkami, w limicie czasu.
    func solve(_ start: UInt64, target: Int = 1, budget: TimeInterval) -> Result {
        var failed = Set<UInt64>()
        var path: [Int] = []
        let deadline = Date().addingTimeInterval(budget)
        var visited = 0, out = false
        func dfs(_ s: UInt64, _ n: Int) -> Bool {
            if n <= target { return true }
            if failed.contains(s) { return false }
            visited += 1
            if visited & 4095 == 0 && (Date() > deadline || failed.count > 3_000_000) { out = true }   // limit czasu i pamięci
            if out { return false }
            for (k, m) in moves.enumerated() where s & m.f != 0 && s & m.o != 0 && s & m.t == 0 {
                path.append(k)
                if dfs((s & ~(m.f | m.o)) | m.t, n - 1) { return true }
                path.removeLast()
                if out { return false }
            }
            failed.insert(s)
            return false
        }
        if dfs(start, start.nonzeroBitCount) {
            return .found(path.map { (cells[moves[$0].fi], cells[moves[$0].oi], cells[moves[$0].ti]) })
        }
        return out ? .timeout : .impossible
    }
}

// MARK: - Losowe plansze

extension Board {
    /// Losowa plansza dla poziomu: spójny kształt z prostokątów (szer. ≥ 2, czasem symetryczny) i pole startowe,
    /// z którego solver znajduje drogę do jednej kulki. nil, gdy w limicie czasu nic się nie udało.
    static func random(level: Int) -> Board? {
        var g = SplitMix(state: .random(in: 0...UInt64.max))
        let range = [14...24, 26...38, 40...50][level]
        let grid = [7, 8, 9][level]
        let budget = [0.6, 1.5, 3.0][level]
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            var set = Set<Pos>()
            let mirror = Bool.random(using: &g)
            while set.count < range.lowerBound {
                let w = Int.random(in: 2...(3 + level), using: &g), h = Int.random(in: 2...(3 + level), using: &g)
                let r0 = Int.random(in: 0...(grid - h), using: &g), c0 = Int.random(in: 0...(grid - w), using: &g)
                for r in r0..<(r0 + h) {
                    for c in c0..<(c0 + w) {
                        set.insert(Pos(r: r, c: c))
                        if mirror { set.insert(Pos(r: r, c: grid - 1 - c)) }
                    }
                }
            }
            guard range.contains(set.count), connected(set) else { continue }
            // bez nudnych prostokątów: kształt wypełnia najwyżej 80% swojego obrysu
            let rs = set.map(\.r), cs = set.map(\.c)
            let box = (rs.max()! - rs.min()! + 1) * (cs.max()! - cs.min()! + 1)
            guard Double(set.count) / Double(box) <= 0.8 else { continue }
            let shape = Board(name: "Losowa", level: level, cells: Array(set), empty: [set.first!])
            let sv = Solver(shape)
            let holes = shape.all.sorted {
                abs(CGFloat($0.c) - shape.cc) + abs(CGFloat($0.r) - shape.cr) < abs(CGFloat($1.c) - shape.cc) + abs(CGFloat($1.r) - shape.cr)
            }
            for h in holes.prefix(4) {
                if case .found = sv.solve(sv.encode(shape.all.filter { $0 != h }), budget: budget) {
                    return Board(name: "Losowa", level: level, cells: Array(set), empty: [h])
                }
            }
        }
        return nil
    }

    static func connected(_ s: Set<Pos>) -> Bool {
        guard let first = s.first else { return false }
        var seen: Set<Pos> = [first], queue = [first]
        while let p = queue.popLast() {
            for d in Pos.dirs where s.contains(p + d) && !seen.contains(p + d) {
                seen.insert(p + d)
                queue.append(p + d)
            }
        }
        return seen.count == s.count
    }
}

// MARK: - Naprawa plansz (narzędzie deweloperskie)

extension Solver {
    /// Pierwsze pole startowe (od środka), z którego da się zostawić jedną kulkę.
    static func solvableHole(_ b: Board, budget: TimeInterval, tries: Int) -> Pos? {
        let sv = Solver(b)
        let near = b.all.sorted {
            abs(CGFloat($0.c) - b.cc) + abs(CGFloat($0.r) - b.cr) < abs(CGFloat($1.c) - b.cc) + abs(CGFloat($1.r) - b.cr)
        }
        for h in near.prefix(tries) {
            if case .found = sv.solve(sv.encode(b.all.filter { $0 != h }), budget: budget) { return h }
        }
        return nil
    }

    /// Usuwa pola brzegowe (najpierw parami, symetrycznie), aż kształt stanie się rozwiązywalny; zwraca rysunek ASCII.
    static func repair(_ b: Board, budget: TimeInterval, deadline: Date) -> String {
        let cmin = b.all.map(\.c).min()!, cmax = b.all.map(\.c).max()!
        let rmin = b.all.map(\.r).min()!, rmax = b.all.map(\.r).max()!
        func art(_ cells: Set<Pos>, _ hole: Pos) -> String {
            (rmin...rmax).map { r in
                "\"" + String((cmin...cmax).map { c -> Character in
                    let p = Pos(r: r, c: c)
                    return p == hole ? "o" : (cells.contains(p) ? "X" : ".")
                }) + "\""
            }.joined(separator: ", ")
        }
        if let h = solvableHole(b, budget: budget, tries: 64) { return "HOLE " + art(b.cells, h) }
        let edge = b.all.filter { p in Pos.dirs.contains { !b.has(p + $0) } }
        var candidates: [[Pos]] = []
        for p in edge {
            let m = Pos(r: p.r, c: cmin + cmax - p.c)
            candidates.append(m != p && b.has(m) ? [p, m] : [p])
        }
        for p in edge { candidates.append([p]) }
        for cut in candidates where Date() < deadline {
            var cells = b.cells
            cut.forEach { cells.remove($0) }
            guard Board.connected(cells) else { continue }
            let t = Board(name: b.name, level: b.level, cells: Array(cells), empty: [cells.first!])
            if let h = solvableHole(t, budget: budget, tries: 6) { return "CUT " + art(cells, h) }
        }
        return "FAIL"
    }
}
