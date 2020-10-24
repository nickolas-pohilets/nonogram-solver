//
//  main.swift
//  nonogram-solver
//
//  Created by Nickolas Pokhylets on 21/10/2020.
//

import Foundation

struct Problem: Decodable {
    var width: Int { vertical.count }
    var height: Int { horizontal.count }
    var vertical: [[Int]]
    var horizontal: [[Int]]

    public enum CodingKeys: String, CodingKey {
        case vertical = "v"
        case horizontal = "h"
    }

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}

struct Bitmap: Hashable, CustomStringConvertible {
    private typealias Word = UInt64
    private var data: Word

    static let maxSize = MemoryLayout<Word>.size * 8
    static let empty = Bitmap(data: 0)

    private init(data: Word) {
        self.data = data
    }

    public init(ones: Range<Int>) {
        self.data = ((1 << ones.count) - 1) << ones.lowerBound
    }

    var isEmpty: Bool { data == 0 }

    var description: String {
        return self.describe(count: nil)
    }

    func describe(count: Int?) -> String {
        if isEmpty {
            return "0"
        }
        var result = ""
        var x = data
        var k = 0
        while x != 0 || (k < (count ?? 1)) {
            result += "\(x & 1)"
            x >>= 1
            k += 1
        }
        return result
    }

    subscript(_ i: Int) -> Bool {
        get {
            let mask: UInt64 = (1 << i)
            return data & mask != 0
        }
        set {
            let mask: UInt64 = (1 << i)
            if newValue {
                data |= mask
            } else {
                data &= ~mask
            }
        }
    }

    static func |=(lhs: inout Bitmap, rhs: Bitmap) {
        lhs.data |= rhs.data
    }

    static func &=(lhs: inout Bitmap, rhs: Bitmap) {
        lhs.data &= rhs.data
    }

    static prefix func ~(arg: Bitmap) -> Bitmap {
        Bitmap(data: ~arg.data)
    }

    static func ^(lhs: Bitmap, rhs: Bitmap) -> Bitmap {
        Bitmap(data: lhs.data ^ rhs.data)
    }

    static func &(lhs: Bitmap, rhs: Bitmap) -> Bitmap {
        Bitmap(data: lhs.data & rhs.data)
    }

    static func |(lhs: Bitmap, rhs: Bitmap) -> Bitmap {
        Bitmap(data: lhs.data | rhs.data)
    }
}

struct SolvedRow {
    var zeros: Bitmap
    var ones: Bitmap
}

enum SolvingError: Error {
    case noSolution
}

struct Axis {
    var size: Int { combinations.count }
    var combinations: [[Bitmap]]
    var solved: [SolvedRow]
    var dirty: Bitmap

    init(groups: [[Int]], otherSize: Int) {
        combinations = groups.map {
            generateCombinations(size: otherSize, groups: $0)
        }
        solved = Array(repeating: SolvedRow(zeros: .empty, ones: .empty), count: groups.count)
        dirty = .empty
        for i in 0..<groups.count {
            dirty[i] = true
        }
    }

    var isSolved: Bool {
        return combinations.allSatisfy { $0.count == 1 }
    }

    mutating func process(other: inout Axis) throws -> Bool {
        var result: Bool = false
        for (i, combs) in combinations.enumerated() {
            assert(!combs.isEmpty)
            if !dirty[i] { continue }

            // Filter out combinations which are known to be impossible
            var filteredCombs = combs
            let s = solved[i]
            filteredCombs.removeAll {
                (s.ones & $0) != s.ones || (s.zeros & ~$0) != s.zeros
            }
            if filteredCombs.isEmpty {
                throw SolvingError.noSolution
            }
            combinations[i] = filteredCombs

            // Compute cell which are common for all the remaining combinations
            var ones = Bitmap(ones: 0..<other.size)
            var zeros = Bitmap(ones: 0..<other.size)
            for c in filteredCombs {
                ones &= c
                zeros &= ~c
            }
            assert((ones & zeros).isEmpty)

            // Update solution
            if update(index: i, plane: \.ones, value: ones, other: &other) { result = true }
            if update(index: i, plane: \.zeros, value: zeros, other: &other) { result = true }
        }
        dirty = .empty
        return result
    }

    mutating func update(index i: Int, plane: WritableKeyPath<SolvedRow, Bitmap>, value: Bitmap, other: inout Axis) -> Bool {
        let changed = solved[i][keyPath: plane] ^ value
        if changed.isEmpty { return false }
        assert(solved[i][keyPath: plane] & value == solved[i][keyPath: plane])
        solved[i][keyPath: plane] = value
        other.dirty |= changed

        for j in 0..<other.size {
            if changed[j] {
                other.solved[j][keyPath: plane][i] = value[j]
            }
        }

        return true
    }
}

class Solutions {
    var solutions: [State] = []
}

struct Cell: Hashable {
    var row: Int
    var col: Int
}

struct State: CustomStringConvertible {
    var problem: Problem
    var vertical: Axis
    var horizontal: Axis
    var path: [String]

    init(problem: Problem) {
        self.problem = problem
        self.vertical = Axis(groups: problem.vertical, otherSize: problem.horizontal.count)
        self.horizontal = Axis(groups: problem.horizontal, otherSize: problem.vertical.count)
        self.path = ["root"]
    }

    var isSolved: Bool {
        return vertical.isSolved && horizontal.isSolved
    }

    mutating func solve(solutions: Solutions) throws {
        while true {
            try self.simplify()
            if self.isSolved {
                solutions.solutions.append(self)
                return
            }

            let unsolvedCells = self.getUnsolvedCells()
            let random = unsolvedCells.randomElement()!
            let assumption = Bool.random()

            var copy = self
            copy.assume(cell: random, value: assumption)
            do {
                try copy.solve(solutions: solutions)
            }
            catch SolvingError.noSolution {
                // We managed to disprove hypothesis and we learned something from that.
                self.assume(cell: random, value: !assumption)
                continue
            }

            // Check if have multiple solutions
            self.assume(cell: random, value: !assumption)
            do {
                try self.solve(solutions: solutions)
            } catch SolvingError.noSolution {
                // copy has a solution, ignore this branch
                return
            }
        }
    }

    mutating func simplify() throws {
        var k = 0
        while true {
            let vProgressed = try vertical.process(other: &horizontal)
            let hProgressed = try horizontal.process(other: &vertical)
            if !(vProgressed || hProgressed) {
                break
            }
            k += 1
            print("After step \(path.joined(separator: "/")) [\(k)]:")
            print(self.description)
        }
    }

    func getUnsolvedCells() -> [Cell] {
        var result: [Cell] = []
        for (i, row) in horizontal.solved.enumerated() {
            for j in 0..<problem.width {
                if row.ones[j] == row.zeros[j] {
                    result.append(Cell(row: i, col: j))
                }
            }
        }
        return result
    }

    mutating func assume(cell: Cell, value: Bool) {
        let key: WritableKeyPath<SolvedRow, Bitmap> = value ? \.ones : \.zeros
        horizontal.solved[cell.row][keyPath: key][cell.col] = true
        horizontal.dirty[cell.row] = true
        vertical.solved[cell.col][keyPath: key][cell.row] = true
        vertical.dirty[cell.col] = true
        path.append("(\(cell.row),\(cell.col)) = \(value ? 1 : 0)")
    }

    var description: String {
        var result: String = ""
        for (i, row) in horizontal.solved.enumerated() {
            if i > 0 && i % 5 == 0 {
                for j in 0..<problem.width {
                    if j > 0 && j % 5 == 0 {
                        result += "╋"
                    }
                    result += "━"
                }
                result += "\n"
            }
            for j in 0..<problem.width {
                if j > 0 && j % 5 == 0 {
                    result += "┃"
                }
                if row.ones[j] {
                    assert(!row.zeros[j])
                    result += "1"
                } else if row.zeros[j] {
                    result += "0"
                } else {
                    result += " "
                }
            }
            result += "\n"
        }
        return result
    }
}

func generateCombinations(size: Int, groups: [Int]) -> [Bitmap] {
    let total = groups.reduce(0) { $0 + $1 } + groups.count - 1
    let volatility = size - total
    assert(volatility >= 0)
    var result: [Bitmap] = []
    generateCombinations(result: &result, current: .empty, from: 0, volatility: volatility, groups: groups[...])
    return result
}

func generateCombinations(result: inout [Bitmap], current: Bitmap, from pos: Int, volatility: Int, groups: ArraySlice<Int>) {
    guard let n = groups.first else {
        result.append(current)
        return
    }
    for i in 0...volatility {
        var bitmap = current
        for j in 0..<n {
            bitmap[pos + i + j] = true
        }
        generateCombinations(result: &result, current: bitmap, from: pos + i + n + 1, volatility: volatility - i, groups: groups.dropFirst())
    }
}

func main(args: [String]) {
    for path in args.dropFirst() {
        do {
            let p = try Problem(path: path)
            var s = State(problem: p)
            let solutions = Solutions()
            try s.solve(solutions: solutions)
            print("Solved: \(solutions.solutions.count) solutions")
            for s in solutions.solutions {
                print(s.description)
            }
        }
        catch SolvingError.noSolution {
            print("No solution")
            exit(1)
        }
        catch let error {
            print(error)
        }
    }
}

main(args: ProcessInfo.processInfo.arguments)
