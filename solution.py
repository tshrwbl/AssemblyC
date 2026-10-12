class Solution:
    def permuteUnique(self, nums: list[int]) -> list[list[int]]:
        nums.sort()
        res = [nums[:]]
        n = len(nums)

        while True:
            # Step 1: Find the largest index i such that nums[i] < nums[i + 1]
            i = n - 2
            while i >= 0 and nums[i] >= nums[i + 1]:
                i -= 1
            if i < 0:
                break  # Reached the last lexicographical permutation

            # Step 2: Find the largest index j such that nums[j] > nums[i]
            j = n - 1
            while nums[j] <= nums[i]:
                j -= 1

            # Step 3: Swap nums[i] and nums[j]
            nums[i], nums[j] = nums[j], nums[i]

            # Step 4: Reverse the suffix from i + 1 to n - 1
            l, r = i + 1, n - 1
            while l < r:
                nums[l], nums[r] = nums[r], nums[l]
                l += 1
                r -= 1

            res.append(nums[:])

        return res


if __name__ == "__main__":
    sol = Solution()
    sample = [1, 1, 2]
    print(f"Permutations for {sample}:")
    print(sol.permuteUnique(sample))
