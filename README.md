# sudoku-swift
This is a port of a Sudoku generator written in Python by Ronald L. Rivest in 2006.

It's not great Swift code, as I was learning Python while porting the original code, but it does work.

You can run it from the command line:

```
> swift Sudoku.swift -g

$ swift Sudoku.swift -g -f

Puzzle generated from seed '529800175' :
 .  .  . | .  9  . | .  .  7 
 .  .  1 | .  .  . | .  .  . 
 .  .  6 | 4  3  . | .  .  . 
------------------------------
 2  .  . | .  7  . | .  .  . 
 8  .  . | .  .  . | .  4  . 
 7  .  . | .  4  9 | .  1  5 
------------------------------
 .  .  . | 1  .  7 | 5  2  . 
 .  4  . | .  .  . | 8  .  9 
 .  .  . | .  .  . | 1  .  . 

Puzzle solution:
 3  8  2 | 6  9  1 | 4  5  7 
 4  9  1 | 7  5  8 | 6  3  2 
 5  7  6 | 4  3  2 | 9  8  1 
------------------------------
 2  1  4 | 5  7  6 | 3  9  8 
 8  5  9 | 2  1  3 | 7  4  6 
 7  6  3 | 8  4  9 | 2  1  5 
------------------------------
 9  3  8 | 1  6  7 | 5  2  4 
 1  4  7 | 3  2  5 | 8  6  9 
 6  2  5 | 9  8  4 | 1  7  3 

SOLUTION IS UNIQUE
Puzzle rating: 134
(moderate)
```

Note that the file is called Sudoku.swift for command-line usage convenience, but if you try to build and run in Xcode, you'll get an error, `Expressions are not allowed at the top level`.  Only a source file named `main.swift` is allowed to have code that's at the top level so if you want to debug it in Xcode, rename `Sudoku.swift` to `main.swift`.
