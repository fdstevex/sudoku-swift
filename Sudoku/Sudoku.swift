//
// Swift port of Sudoku program
// Original author: Ronald L. Rivest
//
// This version by Steve Tibbett on 2020-05-22.
//
// This program is "public domain": you may copy, modify, run,
// publish, distribute, embed, and/or use this program in any way
// whatsoever without prior permission and/or giving me any
// credit or payment whatsoever.

import Foundation
import GameKit

enum SudokuError : Error {
    case unsolvable
    case puzzleFileFormatInvalid
    case encodingError
}

let usage_string = """
 Usage: sudoku.py <processing_options> <source_options>

    <processing_options> may include one or more of:
        (note that printing out puzzle always happens)
        -f         to save this puzzle (only useful with -g option)
                   filename is random number seed used to generate puzzle
                   (puzzle is saved in format suitable for reading in later,
                   in the "puzzles" subdirectory, as a ".txt" file)
        -s         to solve the puzzle, and print out solution (if possible)
                   and indicate whether there are no solutions, whether
                   there is a unique solution, or whether there are multiple
                   solutions.  If a solution exists, one will be printed.
                   (Solving puzzle is optional, so as not to spoil fun for puzzle
                   you only want rated.)
        -d         to turn on "debug printing"
                   This will explain in detail how a particular
                   puzzle can be solved, step by step, with reasons for
                   each step, or how a puzzle was generated.
        -r         to rate the puzzle's difficulty
                   by solving it 20 times
                   and returning the median "score" (measured as
                     moves_made + 10*guesses_made + 50*guess_depth
                   a somewhat arbitrary measure).
                   A score equal to the number of unfilled squares means
                   that the puzzle requires no backtracking to solve.
        If no processing options are given, defaults to -s -r (solve and rate).
        Processing options don't really need to be first; they may be
        anywhere in argument list, but are treated as if they were first.

    <source_options> specifies one or more puzzles:
        -gxxx      to generate a puzzle
                   using arbitrary length string xxx as random number seed
                   This allows you to regenerate the same
                   puzzle again easily later.
        -g         to generate a random puzzle
                   This uses clock as random number seed.
        -i         to read puzzle from standard input
        filename   to read puzzle from file with given filename
                   from the "puzzles" subdirectory (.txt file)

        Some "automation" you may find convenient:
        The -gxxx and filename options may include, at the end,
        a "+r" extension, where r is a decimal integer > 0 which
        specifies how many extra similar generations or filenames
        to process.  This is like a macro which expands by counting:
           -gabc+3   is the same as saying -gabc -gabc1 -gabc2 -gabc3
           ttt+5     is the same as saying ttt ttt1 ttt2 ttt3 ttt5 ttt5
           -g+6      is the same as saying -g -g -g -g -g -g -g
        If you have a directory of puzzles, with filenames indicating page
        numbers, say, as in page1 page2 ... page100, you can solve them all
        by specifying page1+99 .

 Each puzzle input file represents "empty" by ".", otherwise uses 1--9.
 If a line contains a sharp sign (#), the # and all following characters
 on that line are ignored.  Characters other than . or 1-9, including blanks,
 are also ignored.  Here is an example input file:
     # page 1 of puzzle book
     5.7...3..
     ...2...5.
     2.3.9.1..
     .2.75.8..
     .9...4.6.
     1...8....
     3..5....1
     .....3...
     4....19.5
 At the moment, only 9x9 puzzles are supported.
 All puzzles are read/saved in the "puzzles" subdirectory of the current directory.

 Examples:
     sudoku.py -g             # generate, solve, and rate a random puzzle
     sudoku.py -g -f          # generate a random puzzle and save it
     suodku.py -g -s          # generate a random puzzle and solve it
     sudoku.py -g -r          # generate a random puzzle and rate it
     sudoku.py -ga12          # generate and print random puzzle with seed a12
     sudoku.py -ga12 -s -r    # solve and rate random puzzle generated from seed a12
     sudoku.py -r pa pb       # rate puzzles in files "pa" and "pb"
     sudoku.py -s pa pb       # solve puzzles in files "pa" and "pb"
     sudoku.py pa -d -s       # solve and detail reasoning for solving puzzle "pa"
     sudoku.py -s pa1+3       # solve puzzles pa1 pa2 pa3 pa4
     sudoku.py -g+10          # generate, rate, and solve 10 puzzles
 """

/**
 n is the size of the square and the number of digits in the sudoku alphabet
 a block has nr rows and nc columns, where nr*nc = n
 row indices are in [0,...,<n]
 col indices are in [0,...,<n]
 blk indices are in [0,...,<n] (across rows first, then down)
 values are in [0,...,<n] or UNDEFINED (0)
 */

// Some global constants

let UNDEFINED = 0                // undefined value represented by 0
let rating_times = 20            // number of times to solve puzzle to get rating
let sudoku_alphabet = ".123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
var debug_print = false
var random_source = GKLinearCongruentialRandomSource(seed: UInt64(arc4random()))

// Reference type array
class PossibilitiesArray {
    init(values: [Int]) {
        self.values = values
    }
    
    var values: [Int]
}

extension Character {
    func asUInt8() -> UInt8 {
        return self.utf8.first!
    }
}

extension UInt8 {
    func toChar() -> Character {
        return Character(UnicodeScalar(self))
    }
}

extension String {
    func index(from: Int) -> Index {
        return self.index(startIndex, offsetBy: from)
    }

    func substring(from: Int) -> String {
        let fromIndex = index(from: from)
        return String(self[fromIndex...])
    }

    func substring(to: Int) -> String {
        let toIndex = index(from: to)
        return String(self[..<toIndex])
    }

    func substring(with r: Range<Int>) -> String {
        let startIndex = index(from: r.lowerBound)
        let endIndex = index(from: r.upperBound)
        return String(self[startIndex..<endIndex])
    }
}

// Implements a sudoku position in the grid, i.e. an individual square.
class Pos {
    // row index 0<=r<n
    var r: Int
    // col index 0<=c<n
    var c: Int

    // Construct/initialize position in row r and col c, 1<=r,c<=n.

    // will contain pointer to row object (group)
    var row: Group?
    // will contain pointer to col object (group)
    var col: Group?
    // will contain pointer to blk object (group)
    var blk: Group?
    // will contain [row,col,blk]
    var grps = [Group]()
    
    // DYNAMIC attributes that change as puzzle is worked on.
    // These two attributes are the ONLY values in this program
    // that are dynamic in this sense, so they are the only values
    // that need to be saved/restored for backtracking.
    var val = UNDEFINED

    // TODO should be sized based on the game size
    var possibilities = PossibilitiesArray(values: (1...n).map { $0 })

    init(r: Int, c: Int) {
        self.r = r
        self.c = c
    }
}

enum GroupType {
    case row
    case col
    case blk
}

// Implements a group (i.e. row, col, or block);
// a set of n positions constrained to have each value exactly once.
class Group {
    // gt = "row","col", or "blk", respectively (group_type)
    var group_type: GroupType
    // i = 1 to n, inclusive, giving index of group within group_type
    var index: Int
    
    // positions in this group,
    // to be filled in later cross-linking
    var posns = [Pos]()

    // Construct and initialize a group.
    init(gt: GroupType, i: Int) {
        self.group_type = gt
        self.index = i
    }
}

/**
 # Some global variables
 #
 # T is (n+1)x(n+1) array (0-th col and 0-th row unused)
 # T[i][j] is Pos for row i, column j
 #
 # sudoku_alphabet[i] is the printed version of the i-th symbol
 #
 # rows = list of all rows
 # cols = list of all cols
 # blks = list of all blocks
 # grps = list of all groups (rows, cols, or blocks)
 # posns = list of all positions
*/

// initialize(n) -- set up for table of size n with nr x nc blocks
// TODO put this in some sort of game state object
var n = 9
var nr = 3
var nc = 3

// assert n >= 1
// assert nr >= 1
// assert nc >= 1
// assert n == nr * nc

var posns = [Pos]()
var rows = [Group]()
var cols = [Group]()
var blks = [Group]()
var grps = [Group]()
var T = [[Pos]]()

func initialize(n: Int, nr: Int, nc: Int) {
    rows = [Group]()
    cols = [Group]()
    blks = [Group]()
    grps = [Group]()
    T = [[Pos]]()
    
    // create all positions
    // array of posns T is actualy (n+1) x (n+1)
    posns = [Pos]()
    
    for r in 0..<n {
        var row = [Pos]()
        
        for c in 0..<n {
            let p = Pos(r:r,c:c)
            row.append(p)
            posns.append(p)
        }

        T.append(row)
    }
    
    // create all groups
    for i in 0..<n {
        rows.append(Group(gt:.row, i:i))
        cols.append(Group(gt:.col, i:i))
        blks.append(Group(gt:.blk, i:i))
    }
    
    grps = rows + cols + blks
    
    // now cross-link positions and groups
    for row in rows {
        let r = row.index
        
        for col in cols {
            let c = col.index
            
            let p = T[r][c]
            
            // link pos p to groups containing it
            p.row = row
            p.col = col
            
            // TODO check indexes
            let blockNum = (r/nr)*nr + (c)/nc
            let blk = blks[blockNum]
            p.blk = blk
            p.grps = [row, col, blk]

            // and reverse
            row.posns.append(p)
            col.posns.append(p)
            blk.posns.append(p)
        }
    }
}

func puzzle_string() -> String {
    let print_block_lines = true
    var str = ""

    for r in 0..<n {
        var line = ""
        for c in 0..<n {
            let val = T[r][c].val
            line = line + " " + sudoku_alphabet.substring(with: val..<(val+1)) + " "
            if print_block_lines && c<(n-1) && c%nc == 2 {
                line = line + "|"
            }
        }
        str = str + "\(line)\n"
        if print_block_lines && r<(n-1) && r%nr == 2 {
            // TODO - (3*n+n/nc-1) chars
            str = str + "------------------------------\n"
        }
    }
    return str
}

// Print out the current puzzle configuration, nicely.
func print_puzzle() {
    print(puzzle_string())
}

/**
 Set position at row r col c to have value v.
 Value v may be UNDEFINED (0) or in [1,...,n].
 */
func set_pos(r: Int, c: Int, v: Int) throws {
    assert(0<=r && r<n)
    assert(0<=c && c<n)
    assert(0<=v && v<=n)

    let p = T[r][c]
    p.val = v

    // if not setting p to UNDEFINED,
    // set p's possibility list to just [v]
    // and remove v from possibilities for other positions q in same groups g as p

    if v == UNDEFINED {
        return
    }
    
    p.possibilities = PossibilitiesArray(values:[v])
    
    for g in p.grps {
        for q in g.posns {
            if p !== q && q.possibilities.values.contains(v) {
                q.possibilities = PossibilitiesArray(values:q.possibilities.values.filter { $0 != v })
            }

            // print "remove", q.r, q.c, v, "due to", p.r, p.c, v
            // CHECK FOR UNSOLVABILITY:
            if q.possibilities.values.count == 0 {
                if debug_print {
                    print("UNSOLVABLE!")
                }
                throw SudokuError.unsolvable
            }
        }
    }
}

/**
 Return input string x with all characters not in alphabet removed.
*/
 func trim(x: String, alphabet: String) -> String {
    var s = ""
    for a in x {
        if alphabet.contains(a) {
            s = s + String(a)
        }
    }
    return s
}

/**
 s is an array of strings, one per row.
 */
func initialize_from_rows(s: [String]) {
    initialize(n: 9, nr: 3, nc: 3)
    // eliminate comments
    var sv = s.map { (str:String)->String in
        let sub = String(str.split(separator:"#").first ?? "")
        return trim(x:sub, alphabet:sudoku_alphabet)
    }
    sv = sv.filter { !$0.isEmpty }
    if sv.count != n {
        print("Input does not have \(n) rows")
        print(sv)
        fatalError()
    }
    
    for r in 0..<n {
        var row = s[r]
        for c in 0..<n {
            while row.count > 0 && !sudoku_alphabet.contains(row.first!) {
                row = String(row.dropFirst())
            }
            assert(row.count > 0)
            let val = sudoku_alphabet.firstIndex(of: row.first!)!
            let index = sudoku_alphabet.distance(from: sudoku_alphabet.startIndex, to: val)
            try! set_pos(r:r, c:c, v:index)
            row = String(row.dropFirst())
        }
    }
}

/**
 Input s is a string defining input sudoku puzzle.
 Each line describes one row using digits 1--9 and "." for empty
 */
func initialize_from_string(s: String) {
    let rows = s.split(separator:"\n").map { String($0) }
    initialize_from_rows(s:rows)
}

/**
 Input puzzle from file.
 Leading and trailing blanks on each line are ignored.
 Comment lines whose first nonblank is a sharp are ignored.
 Example file:
     # page 1 of puzzle book
     5.7...3..
     ...2...5.
     2.3.9.1..
     .2.75.8..
     .9...4.6.
     1...8....
     3..5....1
     .....3...
     4....19.5
 Assumes puzzle is in directory "puzzles".
 */
func initialize_from_file(_ puzzle_filename: String) throws {
    // First remove any illegal characters from filename
    let filename_alphabet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_+!."))
    let filename = puzzle_filename.trimmingCharacters(in: filename_alphabet.inverted)
    assert(!filename.isEmpty)

    let url = URL(fileURLWithPath: ".").appendingPathComponent(filename)
    let puzzle_data = try Data(contentsOf: url)
    
    guard let str = String(data: puzzle_data, encoding: .utf8) else {
        throw SudokuError.puzzleFileFormatInvalid
    }
    
    let lines = str.components(separatedBy: "\n")
    initialize_from_rows(s:lines)
}

/**
 Write current puzzle to the specified file,
 with header_string on first line, commented out.
*/
func write_to_file(puzzle_filename: String,header_string: String) throws {
    
    let baseURL = URL(fileURLWithPath: "./puzzles/")
    try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
    
    let filedata = "# \(header_string)\n" + puzzle_string()
    guard let data = filedata.data(using: .utf8) else {
        throw SudokuError.encodingError
    }
    let url = baseURL.appendingPathComponent(puzzle_filename)
    try data.write(to: url)
    
    print("Wrote puzzle to \(url.path)")
}

/**
    Return current state of puzzle solving;
     that is, return list of triples:  p, p's value, p's possibilities

 */
func save_state() -> [(Pos, Int, PossibilitiesArray)] {
    return posns.map { p in
        (p, p.val, PossibilitiesArray(values:p.possibilities.values))
    }
}

/**
 Restore puzzle state to old_state.
 */
func restore_state(_ old_state: [(Pos, Int, PossibilitiesArray)]) {
    old_state.forEach {
        (p, p_val, p_possibilities) in
        p.val = p_val
        p.possibilities = p_possibilities
    }
}

/**
 Return the number of unfilled (undefined) positions.
 */
func number_of_undefined_posns() -> Int {
    var count = 0
    posns.forEach {
        if $0.val == UNDEFINED {
            count = count + 1
        }
    }
    return count
}

/**
 Compute possible values for each position.
 These are based ONLY on excluding values already
 established within the same group (row, col, or blk).
 This is a "recompute from scratch" operation.
 */
func compute_possibilities() throws {
    for p in posns {
        if p.val == UNDEFINED {
            p.possibilities = PossibilitiesArray(values: (1...n).map { $0 })
            for g in p.grps {
                for q in g.posns {
                    if p.possibilities.values.contains(q.val) {
                        p.possibilities = PossibilitiesArray(values: p.possibilities.values)
                        p.possibilities.values = p.possibilities.values.filter { $0 != q.val }
                        // CHECK FOR UNSOLVABILITY:
                        if p.possibilities.values.isEmpty {
                            if debug_print {
                                print("UNSOLVABLE!")
                            }
                            throw SudokuError.unsolvable
                        }
                    }
                }
            }
        }
        else {
            p.possibilities = PossibilitiesArray(values:[p.val])
        }
    }

}

/**
 Strategy 1:
 If a position has only one possibility, choose it.
 Returns True if something was forced, else returns False
 Stops after forcing the first forcable position.
 */
func S1() throws -> Bool {
    for p in posns {
        if p.val == UNDEFINED && p.possibilities.values.count == 1 {
            try set_pos(r:p.r, c:p.c, v:p.possibilities.values[0])
            if debug_print {
                print("")
                print("S1 Row \(p.r) Col \(p.c) can only have a \(p.possibilities.values[0])")
                print_puzzle()
            }
            return true
        }
    }
    
    return false
}

/**
 Strategy 2:
 If for some group there is a value that can only go in
 one place in that group, then chose it.
 Returns True if something was forced, else returns False
 */
func S2() throws -> Bool {
    for g in grps {
        for val in (1...n) {
            let cango = g.posns.filter {
                $0.val == UNDEFINED && $0.possibilities.values.contains(val)
            }
            if cango.count == 1 {
                let p = cango[0]
                try set_pos(r:p.r,c:p.c,v:val)
                if debug_print {
                    print("")
                    print("S2 In \(g.group_type),\(g.index), \(val) must go in row \(p.r) col \(p.c)")
                    print_puzzle()
                }
                return true
            }
        }
    }
    return false
}

/**
 Strategy 3:
 If for some group g1 there is a value whose only possibilities
 within g1 also lie in some other group g2, then that val may not
 go in positions in g2 that lie outside of g1.
 Returns True if something was changed, else returns False
 */
func S3() -> Bool {
    return false
/**
 ### BASED ON PROFILING STUDIES, IT SEEMS THAT
 ### S3 IS NOT WORTH ALL THE TIME IT TAKES... SO S3 IS DISABLED.
 ### OMIT PREVIOUS LINE TO RESTORE S3 TO FUNCTIONING.

     for g1 in grps:
         for val in range(1,n+1):
             cango = [p for p in g1.posns if p.val == UNDEFINED and val in p.possibilities]
             if len(cango)>1:
                 for g2 in cango[0].grps:
                     g2OK = True
                     for pos in cango:
                         if g2 not in pos.grps:
                             g2OK = False
                     if g2OK:
                         # now val can go several places within g1
                         # but those places are all within g2 as well
                         # so remove val from places within g2 outside of g1
                         for pos in g2.posns:
                             if not g1 in pos.grps and val in pos.possibilities:
                                 pos.possibilities = pos.possibilities[:]
                                 pos.possibilities.remove(val)
                                 if debug_print:
                                     print
                                     print "S3","row",pos.r,"col",pos.c, "may not be",val
                                     print "because in",g1.group_type,g1.index
                                     print "all possibilities for",val, "lie within",g2.group_type,g2.index
                                     print_puzzle()
                                 something_changed = True
                                 # CHECK FOR UNSOLVABILITY HERE:
                                 if len(pos.possibilities)==0:
                                     if debug_print:
                                         print "UNSOLVABLE!"
                                     raise "UNSOLVABLE"
     return something_changed

     */
}

/**
 Strategy 4:
 If for some group there are two positions that have the
 exact same two possible values, then those values can not go
 other places within that group
 Returns True if something was changed, else returns False
 */
func S4() throws -> Bool {
    var something_changed = false

    for g in grps {
        for p in g.posns {
            if p.possibilities.values.count == 2 {
                for q in g.posns {
                    if q !== p && q.possibilities === p.possibilities {
                        for val in p.possibilities.values {
                            for pos in g.posns {
                                if pos !== p && pos.possibilities.values.contains(val) {
                                    pos.possibilities = PossibilitiesArray(values: pos.possibilities.values.filter { $0 != val })
                                    
                                    if debug_print {
                                        print("S4 row \(pos.r) col \(pos.c) may not be \(val)")
                                        print(" because in \(g.group_type) \(g.index)")
                                        print(" positions at row \(p.r) col \(p.c) and row \(q.r) col \(q.c)")
                                        print(" have the same possibilities: \(p.possibilities)")
                                        print_puzzle()
                                    }
                                    something_changed = true
                                    // CHECK FOR UNSOLVABILITY HERE
                                    if pos.possibilities.values.isEmpty {
                                        if debug_print {
                                            print("UNSOLVABLE!")
                                        }
                                        throw SudokuError.unsolvable
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return something_changed
}

/**
 Find a forced move and make it. (at most one move made)
 Return True if a forced move was found, else return False.
 Strategies S1 and S2 make forced moves;
 strategies S3 and S4 are only used if necessary,
    to update possibilities; they don't actually make a move,
    but facilitate S1 and S2's operations.
 All these strategies return True if they make progress.
 */
func make_forced_move() throws -> Bool {
    var keep_going = true
    while keep_going {
        if try S1() || S2() {
            return true
        }
        keep_going = try S3() || S4()
    }
    
    return false
}

/**
 Solve currently established puzzle.
 return list of length 0,...,numwanted giving up to numwanted solutions found
 (typically numwanted will be 1 or 2)
 depth is recursion (guess) depth level so far;
 initial top-level call supplies depth = 0
 solns gives solutions found so far in other parts of search tree
 */
var moves_made = 0
var guesses_made = 0
var guess_depth = 0

func solve(numwanted: Int, depth: Int = 0, solns solnsIn: [[(Pos, Int, PossibilitiesArray)]]) throws -> [[(Pos, Int, PossibilitiesArray)]] {
    var solns = solnsIn
    
    assert(solns.count < numwanted)

    if depth == 0 {
        // initial call
        moves_made = 0
        guesses_made = 0
        guess_depth = 0
    }

    guess_depth = max(depth, guess_depth)

    // first solve puzzle if possible using only forced moves
    while try make_forced_move() {
        moves_made += 1
    }

    if number_of_undefined_posns() == 0 {
        if debug_print {
            print("Puzzle solved. Solution:")
            print_puzzle()
        }
        solns.append(save_state())
        return solns
    }

    if debug_print {
        print("\(depth) Puzzle only partially solved. Current configuration:")
        print_puzzle()
    }

    /**
     guess and recurse; find a random position p with fewest possibilities
     Note that we are sorting triples with p.r and p.c rather than
     pairs with just p, so that sort always returns same answer for same input
     (otherwise sort order may depend on internal memory layout, etc.)
     */
    var L = (posns.filter { $0.possibilities.values.count > 1 }).map { ($0.possibilities.values.count, $0.r, $0.c) }
    L.sort { (a, b) -> Bool in
        // the Python code just calls sort, which I'm assuming does something like this.
        if (a.0 != b.0) { return a.0 < b.0 }
        if (a.1 != b.1) { return a.1 < b.1 }
        return a.2 < b.2
    }

    let numpos = L[0].0
    L = L.filter { $0.0 == numpos }
    L = shuffle(L:L)

    let r = L[0].1
    let c = L[0].2
    let p = T[r][c]

    // guess and recurse
    let state = save_state()

    for val in shuffle(L:p.possibilities.values) {
        if debug_print {
            print("\(depth) TRYING by guessing \(val) (from \(p.possibilities.values)) for row \(p.r) column \(p.c)")
        }
        try set_pos(r:p.r,c:p.c,v:val)
        moves_made += 1
        guesses_made += 1
        do {
            solns = try solve(numwanted: numwanted, depth: depth+1, solns: solns)
            if solns.count == numwanted {
                return solns
            }
        } catch {
            
        }
        
        restore_state(state)

        if debug_print {
            print("\(depth) FINISHED guessing \(val) (from \(p.possibilities.values)) for row \(p.r) column \(p.c)")
        }
    }

    return solns
}

/**
 Return a random permutation of a copy of the list L.
 */
func shuffle<T>(L: [T]) -> [T] {
    return random_source.arrayByShufflingObjects(in: L) as! [T]
}

/*
 # Some puzzles from books that have been solved with this program:
 # Pocket Sudoku (ps): ps1, ps13, ps50, ps76, ps101, ps127, ps147, ps148
 # The Ultimate Sudoku Challenge (tusc): tusc23, tusc88, tusc90, tusc190
 # The Book of Sudoku, No 2 (bos2p): bos2p132, bos2p21
*/

/**
 "Simplify" puzzle by removing assignments to positions
 if this preserves the unique puzzle solution.
 (The puzzle is "simpler" only in that it is now less filled in;
 it is probably harder to solve.)
 */
 func simplify_puzzle() {
    for p in posns {
        guard p.val != UNDEFINED else {
            continue
        }
        
        let state = save_state()
        let val = p.val
        try! set_pos(r: p.r, c: p.c, v: UNDEFINED)
        try! compute_possibilities()
        let solns = [[(Pos, Int, PossibilitiesArray)]]()
        let nsolns = try! solve(numwanted:2, depth: 0, solns: solns).count
        if nsolns == 1 {
            if debug_print {
                print("Removing: \(p.r),\(p.c),\(val) OK:")
            }
        }
        restore_state(state)
        if nsolns == 1 {
            try! set_pos(r:p.r,c:p.c,v:UNDEFINED)
            try! compute_possibilities()
            if debug_print {
                print("Simplified puzzle:")
                print_puzzle()
            }
        }
    }
 }

/**
 Make up a sudoku puzzle.
 */

func generate_puzzle() {
    initialize_from_string(s: String(repeating: ".........\n", count: 9))
    var nsolns = 0

    // pick and fill in random positions that have more than one possibility
    while true {
        let state = save_state()

        guard let p = shuffle(L:posns).first else {
            continue
        }
        if p.possibilities.values.count <= 1 {
            continue
        }
        
        if debug_print {
            print("working on position \(p.r),\(p.c)")
            print("p.possibilities = \(p.possibilities)")
            print_puzzle()
        }
        
        for v in shuffle(L:p.possibilities.values) {
            restore_state(state)
            do {
                try set_pos(r:p.r,c:p.c,v:v)
                if debug_print {
                    print("Setting: row \(p.r), col \(p.c), val \(v)")
                    print_puzzle()
                }
                let solns = [[(Pos, Int, PossibilitiesArray)]]()
                nsolns = try solve(numwanted:2, depth: 0, solns: solns).count
                if debug_print {
                    print("Setting: \(p.r),\(p.c),\(v) --> \(nsolns) solutions")
                }
            } catch {
                if debug_print {
                    print("this puzzle state is unsolvable... exception raised.")
                }
                nsolns = 0
            }
            
            if nsolns == 0 {
                // this value of v didn't work out; keep looking...
                continue
            } else if nsolns == 1 {
                if debug_print {
                    print("Here is puzzle:")
                }
                restore_state(state)
                try! set_pos(r:p.r,c:p.c,v:v)
                simplify_puzzle()
                if debug_print {
                    print("Final (simplified) puzzle:")
                    print_puzzle()
                }
                return
                
            } else {
                // more than one solution exists;
                // set v at p and keep going with next p
                restore_state(state)
                try! set_pos(r:p.r,c:p.c,v:v)
                break
            }
        }
    }
}

// Compute a score for a puzzle, based on parameters from solving it.
func score(moves_made: Int,guesses_made: Int,guess_depth: Int) -> Int {
    return moves_made + 10*guesses_made + 50 * guess_depth
}

/**
 Here input s is a string of the form tu+r or tu or just t
 where
    t is a possibly empty string not ending in a digit
    u is a maximal length (possibly zero length) string of digits
    r is a (possibly zero length) string of decimal digits
 Return (t,int(u),int(r))  (string, int, int)
 if u or r is missing then a zero value is return for those components.
 Example: "x3y4+5" returns ("x3y",4,5)
 */
func parse_arg(_ s: String) -> (String, Int, String) {
    var t = ""
    var u = ""
    var r = ""
    let tu_r = s.split(separator:"+")
    if tu_r.isEmpty {
        return ("", 0, "")
    }
    let tu = tu_r[0]
    if tu_r.count>1 {
        r = String(tu_r[1])
    }
    let intr = Int(r) ?? 0
    
    for c in tu {
        let ch = String(c)
        u = u + ch
        if !c.isNumber {
             t = t + u
             u = ""
        }
    }
     return (String(t),Int("0"+u) ?? 0,String(intr))
}

func main(args: [String]) {
    guard args.count > 0 else {
        print(usage_string)
        return
    }

    // first collect processing options, wherever they are
    var processing_options_specified = false
    var solve_puzzle = false
    var rate_puzzle = false
    var save_puzzle = false
    debug_print = false
    
    for arg in args {
        if arg.hasPrefix("-d") {
            debug_print = true
        } else if arg.hasPrefix("-s") {
            solve_puzzle = true
            processing_options_specified = true
        } else if arg.hasPrefix("-r") {
            rate_puzzle = true
            processing_options_specified = true
        } else if arg.hasPrefix("-f") {
            save_puzzle = true
            processing_options_specified = true
        }
    }
    
    if processing_options_specified {
        solve_puzzle = true
        rate_puzzle = true
    }

    // now process each puzzle specified
    
    // file header line for file output option
    var header_string = ""
    var filename = "filename"
    
    var arglist = Array<String>(args)
    while !arglist.isEmpty {
        let arg = arglist.first!
        arglist.remove(at: 0)
        if arg.hasPrefix("-") && !arg.hasPrefix("-g") && !arg.hasPrefix("-i") {
            // processing options have already been handled; skip here
            continue
        }
        
        // blank line on output starts each puzzle
        print("")

        var seed_string = ""
        
        var state = save_state()
        
        if arg.hasPrefix("-g") {
            // -gxxx+yy set seeds to xxx and generates yy additional puzzles
            // e.g. -gxx5+3 ==> uses seeds   xx5 xx6 xx7 xx8
            // e.g. -gxx+4 ==> uses seeds    xx xx1 xx2 xx3 xx4

            var (t,u,r) = parse_arg(String(arg.dropFirst(2)))
            
            if t == "" && u == 0 {
                t = "\(arc4random())"
            }
            if u>0 {
                seed_string = "\(t)\(u)"
            } else {
                seed_string = t
            }
            
            let seed = UInt64(abs(seed_string.hash))
            random_source = GKLinearCongruentialRandomSource(seed: seed)
            generate_puzzle()
            filename = seed_string

            let header_string = "Puzzle generated from seed '\(seed_string)' :"
            
            print(header_string)
            print_puzzle()
            state = save_state()
            
            // now prepare for iteration, by stuffing new arg at front of
            // arglist that parses to (t,u+1,r-1)
            
            if let r = Int(r), r > 0 {
                let new_arg = "-g\(t)\(u+1)+\(r-1)"
                arglist.append(new_arg)
            }
        } else if arg == "-i" {
            print("Enter puzzle, followed by a blank line:")
            var s = ""
            while true {
                guard let line = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces) else {
                    break
                }
                if line.count == 0 {
                    break
                }
                s = s + line + "\n"
            }
            initialize_from_string(s:s)
            state = save_state()
            filename = "I\(arc4random())"
            header_string = "Puzzle read from input:"
            print(header_string)
            print_puzzle()
        } else {
             // abc+2 generates abc abc1 abc2
             let (t,u,r) = parse_arg(arg)
            
            if t == "" && u == 0 {
                print("argument \(arg) illegal; ignored")
            }
            if u>0 {
                filename = "\(t)\(u)"
            } else {
                filename = arg
            }
            
            do {
                try initialize_from_file(filename)
            } catch {
                print("Error with \(arg): \(error)")
                continue
            }
            
            header_string = "Puzzle read from file: \(filename)"
            print(header_string)
            print_puzzle()
            
            state = save_state()
            
            // now prepare for iteration, by stuffing new arg at front of
            // arglist that parses to (t,u+1,r-1)
            // e.g. abc3+7 generates filename abc3 and puts abc4+6 at front of arglist
            if Int(r) ?? 0>0 {
                let new_arg = "\(t)\(u+1)(r-1)"
                var new_arglist = [new_arg]
                new_arglist.append(contentsOf: arglist)
                arglist = new_arglist
            }
        }
        
        if solve_puzzle {
            // ask for up to 2 solns, to check for uniqueness
            var solns = [[(Pos, Int, PossibilitiesArray)]]()
            solns = try! solve(numwanted:2, depth: 0, solns: solns)
            if solns.isEmpty {
                 print("NO SOLUTION EXISTS")
            } else if solns.count == 1 {
                print("Puzzle solution:")
                restore_state(solns[0])
                print_puzzle()
                print("SOLUTION IS UNIQUE")
            } else {
                 print("MULTIPLE SOLUTIONS EXIST; HERE IS ONE SOLUTION:")
                 restore_state(solns[0])
                 print_puzzle()
            }
            if rate_puzzle {
                
                var score_list = [Int]()
                // so rating is deterministic function of puzzle
                // TODO random.seed(1)
                for _ in (0..<rating_times) {
                    restore_state(state)
                    let solns = [[(Pos, Int, PossibilitiesArray)]]()
                    let _ = try! solve(numwanted:1, depth: 0, solns: solns).count
                    score_list.append(score(moves_made:moves_made,guesses_made:guesses_made,guess_depth:guess_depth))
                }
                score_list.sort()
                let rating = score_list[rating_times/2]
                print("Puzzle rating: \(rating)")
                restore_state(state)
                if rating == number_of_undefined_posns() {
                    print("(easy)")
                } else if rating < score(moves_made:n*n,guesses_made:5,guess_depth:1) {
                    print("(moderate)")
                } else {
                    print("(hard)")
                }
            }
            if save_puzzle {
                if !arg.hasPrefix("-") {
                    print("Puzzle read from file '\(arg)' will not be re-saved.")
                } else {
                    try! write_to_file(puzzle_filename:filename, header_string:header_string)
                    print("Puzzle saved to file: \(filename)")
                }
            }
        }
    }
}
/*
 //print(usageString)

// initialize(n: 9, nr: 3, nc: 3)

//do {
//    let state = save_state()
//    try set_pos(r: 0, c: 0, v: 1)
//    print_puzzle()
//    restore_state(state)
//    print_puzzle()
//    try set_pos(r: 0, c: 0, v: 1)
//    print_puzzle()
//} catch {
//    print("Ex")
//}

//generate_puzzle()
//print_puzzle()
*/

main(args:[String](CommandLine.arguments.dropFirst()))
