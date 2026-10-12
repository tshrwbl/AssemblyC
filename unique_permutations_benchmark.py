"""
unique_permutations_benchmark.py - Python benchmark for comparison
Implements the same next-permutation algorithm to compare apples-to-apples.
"""
import time
import sys
from itertools import permutations
from math import factorial
from collections import Counter


class Solution:
    """Next-permutation approach (same algorithm as C version)."""

    def permuteUnique(self, nums: list[int]) -> list[list[int]]:
        nums.sort()
        res = [nums[:]]
        n = len(nums)

        while True:
            # Step 1: Find pivot
            i = n - 2
            while i >= 0 and nums[i] >= nums[i + 1]:
                i -= 1
            if i < 0:
                break

            # Step 2: Find swap target
            j = n - 1
            while nums[j] <= nums[i]:
                j -= 1

            # Step 3: Swap
            nums[i], nums[j] = nums[j], nums[i]

            # Step 4: Reverse suffix
            left, right = i + 1, n - 1
            while left < right:
                nums[left], nums[right] = nums[right], nums[left]
                left += 1
                right -= 1

            res.append(nums[:])

        return res


def count_unique_perms(nums):
    """Calculate expected number of unique permutations."""
    n = len(nums)
    total = factorial(n)
    for count in Counter(nums).values():
        total //= factorial(count)
    return total


def benchmark(name, nums, iterations=1):
    """Run benchmark and return (avg_time_ms, perm_count)."""
    sol = Solution()
    total_time = 0.0
    perm_count = 0

    for _ in range(iterations):
        working = nums[:]
        t0 = time.perf_counter()
        result = sol.permuteUnique(working)
        t1 = time.perf_counter()
        total_time += (t1 - t0) * 1000.0
        perm_count = len(result)

    return total_time / iterations, perm_count


def main():
    print("=== Python Unique Permutations Benchmark ===\n")

    cases = [
        ("No duplicates",  [1,2,3,4,5,6,7,8],         5),
        ("Some dupes",     [1,1,2,2,3,3,4,4],          10),
        ("Heavy dupes",    [1,1,1,2,2,2,3,3],          20),
        ("All same",       [1,1,1,1,1,1,1,1],          100),
        ("9-unique",       [1,2,3,4,5,6,7,8,9],        3),
        ("10-unique",      [1,2,3,4,5,6,7,8,9,10],     1),
        ("10-mixed",       [1,1,2,2,3,3,4,4,5,5],      3),
        ("Small (3)",      [1,1,2],                     1000),
    ]

    print(f"{'Test Case':<20} {'n':>6} {'Perms':>12} {'Python (ms)':>14}")
    print("-" * 56)

    results = {}
    for name, nums, iters in cases:
        avg_ms, count = benchmark(name, nums, iters)
        expected = count_unique_perms(nums)
        status = "[OK]" if count == expected else "[MISMATCH!]"
        print(f"{name:<20} {len(nums):>6} {count:>12} {avg_ms:>12.3f}  {status}")
        results[name] = (avg_ms, count)

    print()

    # If command line args provided, run custom input
    if len(sys.argv) > 1:
        nums = [int(x) for x in sys.argv[1:]]
        print(f"Custom input: {nums}")
        t0 = time.perf_counter()
        sol = Solution()
        result = sol.permuteUnique(nums[:])
        t1 = time.perf_counter()
        elapsed = (t1 - t0) * 1000.0
        print(f"Generated {len(result)} unique permutations in {elapsed:.3f} ms")
        if len(result) <= 100:
            for p in result:
                print(f"  {p}")

    return results


if __name__ == "__main__":
    main()
