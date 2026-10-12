"""
compare_all.py - Complete benchmark comparing:
1. Python baseline (solution.py / unique_permutations_benchmark.py)
2. Pure C (/O2 optimized)
3. Hand-tuned x64 MASM Assembly (SSE2 vector copy, monolithic generator)
"""

import subprocess
import time
from collections import Counter
from math import factorial

# Import Python solution
from unique_permutations_benchmark import Solution, count_unique_perms

TEST_CASES = [
    ("3 elements [1, 1, 2]", [1, 1, 2], 500),
    ("All same (n=8)", [1, 1, 1, 1, 1, 1, 1, 1], 50),
    ("Heavy dupes (n=8)", [1, 1, 1, 2, 2, 2, 3, 3], 20),
    ("Some dupes (n=8)", [1, 1, 2, 2, 3, 3, 4, 4], 10),
    ("No dupes (n=8)", [1, 2, 3, 4, 5, 6, 7, 8], 5),
    ("10-mixed", [1, 1, 2, 2, 3, 3, 4, 4, 5, 5], 3),
    ("9-unique", [1, 2, 3, 4, 5, 6, 7, 8, 9], 3),
    ("10-unique", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 1),
    ("15-unique", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], 1)
]

def benchmark_python(nums, iters):
    # Python code should not run arrays > 10
    if len(nums) > 10:
        return None, count_unique_perms(nums)
    sol = Solution()
    total = 0.0
    count = 0
    for _ in range(iters):
        arr = nums[:]
        t0 = time.perf_counter()
        res = sol.permuteUnique(arr)
        t1 = time.perf_counter()
        total += (t1 - t0) * 1000.0
        count = len(res)
    return total / iters, count

def parse_c_asm_output():
    out = subprocess.check_output([".\\unique_perms.exe"], text=True)
    # Parse lines from BENCHMARK table
    lines = out.splitlines()
    c_asm_map = {}
    in_table = False
    for line in lines:
        if "Test Case" in line and "Perms" in line:
            in_table = True
            continue
        if in_table:
            if line.startswith("---") or not line.strip():
                if line.startswith("---"):
                    continue
                break
            parts = line.split()
            # Format: Name (can be multiple words), n, Perms, C(ms), ASM(ms), Speedup, [OK]
            # Match by status [OK] at end
            if parts and parts[-1] == "[OK]":
                ok_idx = len(parts) - 1
                speedup_str = parts[ok_idx - 1]
                asm_ms = float(parts[ok_idx - 2])
                c_ms = float(parts[ok_idx - 3])
                perms = int(parts[ok_idx - 4])
                n = int(parts[ok_idx - 5])
                name = " ".join(parts[:ok_idx - 5])
                c_asm_map[name] = {
                    "n": n,
                    "perms": perms,
                    "c_ms": c_ms,
                    "asm_ms": asm_ms
                }
    return c_asm_map

def main():
    print("=" * 95)
    print(" BENCHMARK: Python vs Pure C (MSVC /O2) vs Hand-Optimized x64 Assembly (SSE2)")
    print("=" * 95)
    print(f"{'Test Case':<20} {'Perms':>10} {'Python (ms)':>13} {'Pure C (ms)':>13} {'x64 ASM (ms)':>13} {'ASM vs Py':>11} {'ASM vs C':>10}")
    print("-" * 95)

    c_asm_map = parse_c_asm_output()

    key_mapping = {
        "3 elements [1, 1, 2]": "Small (3)",
        "All same (n=8)": "All same",
        "Heavy dupes (n=8)": "Heavy dupes",
        "Some dupes (n=8)": "Some dupes",
        "No dupes (n=8)": "No duplicates",
        "10-mixed": "10-mixed",
        "9-unique": "9-unique",
        "10-unique": "10-unique",
        "15-unique": "15-unique"
    }

    for name, nums, iters in TEST_CASES:
        py_ms, count = benchmark_python(nums, iters)
        mapped_key = key_mapping.get(name)
        c_info = c_asm_map.get(mapped_key)
        py_str = f"{py_ms:>13.3f}" if py_ms is not None else f"{'N/A':>13}"
        if c_info:
            c_ms = c_info["c_ms"]
            asm_ms = c_info["asm_ms"]
            if py_ms is not None:
                py_speedup = f"{py_ms / asm_ms:.1f}x" if asm_ms > 0.0001 else ">1000x"
            else:
                py_speedup = "N/A"
            c_speedup = f"{c_ms / asm_ms:.2f}x" if asm_ms > 0.0001 else "1.00x"
            print(f"{name:<20} {count:>10} {py_str} {c_ms:>13.3f} {asm_ms:>13.3f} {py_speedup:>11} {c_speedup:>10}")
        else:
            print(f"{name:<20} {count:>10} {py_str} {'N/A':>13} {'N/A':>13} {'N/A':>11} {'N/A':>10}")

    print("-" * 95)

if __name__ == "__main__":
    main()
