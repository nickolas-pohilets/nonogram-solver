# [Nonogram](https://en.wikipedia.org/wiki/Nonogram) Solver

Solver can solve problems up to 64x64. Larger problems could be solved by using `BigUInt` instead of `UInt64`.

Solver algorithm:

1. Generate possible combinations for each column and row.
2. Mark all columns and rows as dirty.
3. Initialize solution cells as unknown.
4. For each dirty column:
 * Delete all the combinations which are conflicting with the known solution cells.
 * Find black and white cells common for all the remaining solutions.
 * Write them into solution, marking affected rows as dirty.
 * Mark all columns as clean.   
5. Repeat for rows, marking columns as dirty.
6. Repeat steps 3-4 until no progress can be made.
7. If solved (no unknown solution cells and exactly one combination for each row and column) - we are done, record the solution and exit.
8. Clone the current solver state for backtracking.
9. Pick a random cell.
10. Assign to be white, marking its row and column as dirty.
11. Proceed recursively from step 4.
12. Backtrack.
13. Assign picked cell to black, marking its row and column as dirty.
14. Proceed recursively from step 4.
