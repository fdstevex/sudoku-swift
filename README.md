# sudoku-swift
This is a port of a Sudoku generator written in Python by Ronald L. Rivest in 2006.

It's not great Swift code, but it does generate solved Sudoku. 

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
