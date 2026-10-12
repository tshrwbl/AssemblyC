# Unique Permutations in C + x64 MASM Assembly (SSE2 Accelerated)

An implementation of the **Unique Permutations** problem (*LeetCode 47: Permutations II*):
> *"Given a collection of numbers, `nums`, that might contain duplicates, return all possible unique permutations in any order."*

---

## 1. Algorithmic Complexity

| Metric | Complexity | Notes |
|---|---|---|
| **Time Complexity** | $\mathcal{O}(n \cdot N_{\text{unique}})$ | Where $N_{\text{unique}} = \frac{n!}{\prod (c_k!)}$ |
| **Amortized Time per Permutation** | $\mathcal{O}(n)$ (often $\mathcal{O}(1)$ average suffix length) | Fast right-to-left pivot scans |
| **Auxiliary Space** | $\mathcal{O}(1)$ working buffer | In-place state machine generation |
| **Output Space** | $\mathcal{O}(n \cdot N_{\text{unique}})$ | Contiguous flat 1D buffer allocated in a single `malloc` |

---

## 2. Architecture & Hot Paths

### Algorithmic Foundation (Narayana Pandita / `std::next_permutation`)
1. **Sort**: Small arrays ($n \le 16$) are sorted via inlined `asm_insertion_sort` with zero function call overhead; larger arrays fall back to `qsort`.
2. **Pre-allocation**: Exact unique permutation count $N_{\text{unique}} = \frac{n!}{\prod c_k!}$ is computed upfront using 64-bit integer factorials, avoiding dynamic reallocations (`realloc`) or linked-list pointer chasing.
3. **Monolithic Assembly Engine (`asm_generate_all_perms`)**:
   - The entire generation loop (`find_pivot` $\rightarrow$ `find_swap_target` $\rightarrow$ `swap` $\rightarrow$ `reverse_suffix` $\rightarrow$ `copy_to_flat_buffer`) executes **entirely in x64 assembly**.
   - No function call transitions between C and Assembly per permutation ($3.6 \times 10^6$ fewer calls for $n=10$).
   - Register allocation preserves working pointers in non-volatile registers (`rsi`, `r12`, `r14`, `rbp`).
   - Suffix reversals for small lengths ($2, 3, 4$) are unrolled without looping.
   - Suffix reversals for larger lengths utilize SSE2 vector shuffle instructions (`pshufd`).
   - Copies into the output buffer for common sizes ($n=8, 9, 10$) use unrolled 128-bit vector moves (`movdqu`).

---

## 3. Benchmark Results

Measured on Windows x64 (AMD/Intel x86-64, MSVC 19 / `ml64`):

| Test Case | $n$ | Unique Perms | Python 3.12 (ms) | Pure C `/O2` (ms) | x64 ASM SSE2 (ms) | Speedup vs Python | Speedup vs C |
|---|---|---|---|---|---|---|---|
| `[1, 1, 2]` | 3 | 3 | 0.002 | 0.000 | 0.000 | **>1000x** | 1.00x |
| `All same` | 8 | 1 | 0.001 | 0.000 | 0.000 | **>1000x** | 1.00x |
| `Heavy dupes` | 8 | 560 | 0.397 | 0.011 | 0.012 | **33.1x** | 0.92x |
| `Some dupes` | 8 | 2,520 | 1.757 | 0.023 | 0.019 | **92.5x** | **1.21x** |
| `No dupes` | 8 | 40,320 | 31.186 | 0.430 | 0.441 | **70.7x** | 0.98x |
| `10-mixed` | 10 | 113,400 | 97.962 | 1.607 | 1.132 | **86.5x** | **1.42x** |
| `9-unique` | 9 | 362,880 | 346.659 | 4.762 | 3.667 | **94.5x** | **1.30x** |
| `10-unique` | 10 | 3,628,800 | 3,709.160 | 50.534 | 34.772 | **106.7x** | **1.45x** |

---

## 4. How to Build & Run

### Using PowerShell or CMD
```powershell
# Assemble and compile via build.bat
.\build.bat

# Run the C + ASM binary directly
.\unique_perms.exe

# Run with custom input
.\unique_perms.exe 1 1 2 2 3

# Run the complete Python vs C vs ASM comparison
python compare_all.py
```
