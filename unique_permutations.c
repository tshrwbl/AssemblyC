/*
 * unique_permutations.c - Highly optimized unique permutation generator
 *
 * Algorithm: Next Permutation (iterative, lexicographic order)
 *   - Sort input, then repeatedly advance to next permutation
 *   - O(n! / product(freq_i!)) permutations generated
 *   - O(n) amortized per permutation
 *   - Zero recursion, zero hash tables, cache-friendly flat memory layout
 *
 * Hot paths delegated to MASM x64 assembly (hot_path.asm):
 *   - asm_next_permutation: fully inlined pivot-find + swap + SSE2 reverse
 *   - asm_insertion_sort: low-overhead sort for small arrays
 *   - asm_copy_ints: SSE2-accelerated int array copy
 *
 * Build:
 *   ml64 /c /Fo hot_path.obj hot_path.asm
 *   cl /O2 /arch:SSE2 unique_permutations.c hot_path.obj /Fe:unique_perms.exe
 *
 * (c) 2026 - Optimized C + Assembly permutation engine
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>  /* QueryPerformanceCounter for high-res timing */
#include <psapi.h>
#pragma comment(lib, "psapi.lib")
#endif

typedef struct {
    double working_set_mb;   /* Physical RAM currently in use */
    double commit_mb;        /* Committed virtual memory (RAM + Pagefile) */
    double avail_phys_mb;    /* Total system available physical RAM */
} MemSnapshot;

static MemSnapshot get_memory_snapshot(void) {
    MemSnapshot snap = {0.0, 0.0, 0.0};
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS_EX pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS*)&pmc, sizeof(pmc))) {
        snap.working_set_mb = (double)pmc.WorkingSetSize / (1024.0 * 1024.0);
        snap.commit_mb = (double)pmc.PrivateUsage / (1024.0 * 1024.0);
    }
    MEMORYSTATUSEX ms;
    ms.dwLength = sizeof(ms);
    if (GlobalMemoryStatusEx(&ms)) {
        snap.avail_phys_mb = (double)ms.ullAvailPhys / (1024.0 * 1024.0);
    }
#endif
    return snap;
}

static void print_mem_snapshot(const char* label, MemSnapshot snap) {
    if (snap.commit_mb >= 1024.0) {
        printf("    %-18s: Commit: %6.2f GB | Resident RAM: %6.2f GB | Sys Avail: %6.2f GB\n",
               label, snap.commit_mb / 1024.0, snap.working_set_mb / 1024.0, snap.avail_phys_mb / 1024.0);
    } else {
        printf("    %-18s: Commit: %6.2f MB | Resident RAM: %6.2f MB | Sys Avail: %6.2f GB\n",
               label, snap.commit_mb, snap.working_set_mb, snap.avail_phys_mb / 1024.0);
    }
}

/*==========================================================================
 * Assembly function declarations (defined in hot_path.asm)
 *========================================================================*/
extern int  asm_find_pivot(const int* arr, int n);
extern int  asm_find_swap_target(const int* arr, int pivot_idx, int n);
extern void asm_swap(int* a, int* b);
extern void asm_reverse_segment(int* arr, int left, int right);
extern int  asm_next_permutation(int* arr, int n);
extern void asm_copy_ints(int* dst, const int* src, int n);
extern void asm_insertion_sort(int* arr, int n);
extern uint64_t asm_generate_all_perms(int* working, int n, int* output, uint64_t max_perms);

/*==========================================================================
 * Pure C fallback implementations (for comparison / correctness reference)
 *========================================================================*/

/* C implementation of next_permutation */
static inline int c_next_permutation(int* arr, int n) {
    /* Step 1: Find pivot */
    int i = n - 2;
    while (i >= 0 && arr[i] >= arr[i + 1])
        i--;
    if (i < 0)
        return 0; /* Last permutation */

    /* Step 2: Find swap target */
    int j = n - 1;
    while (arr[j] <= arr[i])
        j--;

    /* Step 3: Swap */
    int tmp = arr[i];
    arr[i] = arr[j];
    arr[j] = tmp;

    /* Step 4: Reverse suffix */
    int left = i + 1, right = n - 1;
    while (left < right) {
        tmp = arr[left];
        arr[left] = arr[right];
        arr[right] = tmp;
        left++;
        right--;
    }
    return 1;
}

/* Comparison function for qsort */
static int int_compare(const void* a, const void* b) {
    return (*(const int*)a) - (*(const int*)b);
}

/*==========================================================================
 * Factorial and permutation count computation
 *========================================================================*/

static uint64_t factorial(int n) {
    uint64_t f = 1;
    for (int i = 2; i <= n; i++)
        f *= (uint64_t)i;
    return f;
}

/* Count total unique permutations: n! / (freq[0]! * freq[1]! * ... ) */
static uint64_t count_unique_permutations(const int* sorted_arr, int n) {
    if (n <= 1) return (n == 1) ? 1 : 0;

    uint64_t total = factorial(n);
    int run = 1;
    for (int i = 1; i < n; i++) {
        if (sorted_arr[i] == sorted_arr[i - 1]) {
            run++;
        } else {
            if (run > 1)
                total /= factorial(run);
            run = 1;
        }
    }
    if (run > 1)
        total /= factorial(run);

    return total;
}

/*==========================================================================
 * Result structure - flat contiguous memory for cache efficiency
 *========================================================================*/
typedef struct {
    int*     data;       /* Flat array: data[perm_idx * n + elem_idx] */
    uint64_t count;      /* Number of permutations stored */
    uint64_t capacity;   /* Pre-allocated capacity */
    int      n;          /* Elements per permutation */
} PermResult;

static PermResult* result_create(uint64_t capacity, int n) {
    PermResult* r = (PermResult*)malloc(sizeof(PermResult));
    if (!r) return NULL;
    size_t total_bytes = (size_t)capacity * (size_t)n * sizeof(int);
    r->data = (int*)malloc(total_bytes);
    if (!r->data) {
        fprintf(stderr, "\n[ERROR] Out of memory! Failed to allocate %.2f MB (%llu elements)\n",
                (double)total_bytes / (1024.0 * 1024.0), (unsigned long long)capacity * (uint64_t)n);
        free(r);
        return NULL;
    }
    r->count = 0;
    r->capacity = capacity;
    r->n = n;
    return r;
}

static void result_free(PermResult* r) {
    if (r) {
        free(r->data);
        free(r);
    }
}

static inline void result_append_asm(PermResult* r, const int* perm) {
    asm_copy_ints(r->data + r->count * r->n, perm, r->n);
    r->count++;
}

static inline void result_append_c(PermResult* r, const int* perm) {
    memcpy(r->data + r->count * r->n, perm, (size_t)r->n * sizeof(int));
    r->count++;
}

/*==========================================================================
 * Main API: Generate all unique permutations
 *========================================================================*/

/* ASM-accelerated version - uses monolithic assembly generator */
PermResult* permute_unique_asm(int* nums, int n) {
    if (n <= 0) return NULL;

    /* Sort the input (use asm for small, qsort for large) */
    if (n <= 16) {
        asm_insertion_sort(nums, n);
    } else {
        qsort(nums, (size_t)n, sizeof(int), int_compare);
    }

    /* Pre-calculate total permutations for single allocation */
    uint64_t total = count_unique_permutations(nums, n);

    PermResult* result = result_create(total, n);
    if (!result) return NULL;

    /* Call monolithic assembly generator - entire loop in assembly */
    result->count = asm_generate_all_perms(nums, n, result->data, total);

    return result;
}

/* Pure C version (for benchmark comparison) */
PermResult* permute_unique_c(int* nums, int n) {
    if (n <= 0) return NULL;

    qsort(nums, (size_t)n, sizeof(int), int_compare);

    uint64_t total = count_unique_permutations(nums, n);

    PermResult* result = result_create(total, n);
    if (!result) return NULL;

    result_append_c(result, nums);

    while (c_next_permutation(nums, n)) {
        result_append_c(result, nums);
    }

    return result;
}

/*==========================================================================
 * High-resolution timer (Windows)
 *========================================================================*/
#ifdef _WIN32
static double get_time_ms(void) {
    LARGE_INTEGER freq, counter;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&counter);
    return (double)counter.QuadPart / (double)freq.QuadPart * 1000.0;
}
#else
static double get_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1000000.0;
}
#endif

/*==========================================================================
 * Verification: check two results are identical
 *========================================================================*/
static int verify_results(const PermResult* a, const PermResult* b) {
    if (a->count != b->count || a->n != b->n) return 0;
    return memcmp(a->data, b->data,
                  (size_t)a->count * (size_t)a->n * sizeof(int)) == 0;
}

/*==========================================================================
 * Print helpers
 *========================================================================*/
static void print_permutation(const int* perm, int n) {
    printf("[");
    for (int i = 0; i < n; i++) {
        printf("%d", perm[i]);
        if (i < n - 1) printf(", ");
    }
    printf("]");
}

static void print_all_permutations(const PermResult* r, int max_print) {
    uint64_t limit = (r->count < (uint64_t)max_print) ? r->count : (uint64_t)max_print;
    printf("[\n");
    for (uint64_t i = 0; i < limit; i++) {
        printf("  ");
        print_permutation(r->data + i * r->n, r->n);
        if (i < r->count - 1) printf(",");
        printf("\n");
    }
    if (r->count > (uint64_t)max_print) {
        printf("  ... (%llu more)\n", (unsigned long long)(r->count - max_print));
    }
    printf("]\n");
}

/*==========================================================================
 * Benchmark runner
 *========================================================================*/
typedef struct {
    const char* name;
    int*        input;
    int         n;
    int         iterations;
} BenchCase;

static void run_benchmark(const char* label, PermResult* (*func)(int*, int),
                          const int* original, int n, int iterations,
                          double* out_time, uint64_t* out_count) {
    (void)label;
    int* working = (int*)malloc((size_t)n * sizeof(int));
    double total_ms = 0.0;
    uint64_t perm_count = 0;

    for (int iter = 0; iter < iterations; iter++) {
        memcpy(working, original, (size_t)n * sizeof(int));

        double t0 = get_time_ms();
        PermResult* r = func(working, n);
        double t1 = get_time_ms();

        total_ms += (t1 - t0);
        perm_count = r->count;
        result_free(r);
    }

    *out_time = total_ms / iterations;
    *out_count = perm_count;
    free(working);
}

/*==========================================================================
 * Main: demo + benchmark
 *========================================================================*/
int main(int argc, char* argv[]) {
    /* If custom arguments provided, benchmark directly on that input */
    if (argc > 1) {
        int n = argc - 1;
        int* orig = (int*)malloc((size_t)n * sizeof(int));
        int* working_c = (int*)malloc((size_t)n * sizeof(int));
        int* working_asm = (int*)malloc((size_t)n * sizeof(int));

        for (int i = 0; i < n; i++) {
            orig[i] = atoi(argv[i + 1]);
            working_c[i] = orig[i];
            working_asm[i] = orig[i];
        }

        printf("======================================================================\n");
        printf(" Custom Input Benchmark: Pure C (MSVC /O2) vs x64 Assembly (SSE2)\n");
        printf("======================================================================\n\n");
        printf("Input elements (n=%d): ", n);
        print_permutation(orig, n);
        printf("\n");

        /* Pre-calculate unique permutation count and memory */
        int* temp = (int*)malloc((size_t)n * sizeof(int));
        memcpy(temp, orig, (size_t)n * sizeof(int));
        qsort(temp, (size_t)n, sizeof(int), int_compare);
        uint64_t expected_count = count_unique_permutations(temp, n);
        free(temp);

        double mem_mb = (double)(expected_count * (uint64_t)n * sizeof(int)) / (1024.0 * 1024.0);
        printf("Total unique permutations: %llu\n", (unsigned long long)expected_count);
        if (mem_mb >= 1024.0) {
            printf("Memory buffer required   : %.2f GB\n\n", mem_mb / 1024.0);
        } else {
            printf("Memory buffer required   : %.2f MB\n\n", mem_mb);
        }

        /* 1. Run Pure C */
        MemSnapshot mem_c_before = get_memory_snapshot();
        printf("[1/2] Running Pure C (MSVC /O2) ... ");
        fflush(stdout);
        double t0_c = get_time_ms();
        PermResult* res_c = permute_unique_c(working_c, n);
        double t1_c = get_time_ms();
        double c_ms = t1_c - t0_c;
        int c_success = (res_c != NULL);
        uint64_t c_count = res_c ? res_c->count : 0;
        MemSnapshot mem_c_peak = get_memory_snapshot();
        if (!res_c) {
            printf("FAILED (Out of Memory)!\n");
        } else {
            printf("Done in %10.3f ms\n", c_ms);
        }

        MemSnapshot mem_settled = mem_c_peak;
        if (n > 11) {
            /* Free C results before Assembly if n > 11 to avoid holding dual massive buffers in RAM */
            if (res_c) {
                result_free(res_c);
                res_c = NULL;
            }

            /* 10-second cooldown for OS memory manager and page cache to settle */
            printf("\n[Cooldown] Freeing C buffer & waiting 10s for OS memory manager to reclaim & settle pages...\n");
            for (int sec = 10; sec > 0; sec--) {
                printf("\r  Cooldown: %2d seconds remaining... ", sec);
                fflush(stdout);
#ifdef _WIN32
                Sleep(1000);
#endif
            }
            printf("\r  Cooldown complete. Memory settled.                           \n\n");
            mem_settled = get_memory_snapshot();
        }

        /* 2. Run x64 Assembly */
        MemSnapshot mem_asm_before = get_memory_snapshot();
        printf("[2/2] Running x64 MASM (SSE2)   ... ");
        fflush(stdout);
        double t0_asm = get_time_ms();
        PermResult* res_asm = permute_unique_asm(working_asm, n);
        double t1_asm = get_time_ms();
        double asm_ms = t1_asm - t0_asm;
        int asm_success = (res_asm != NULL);
        uint64_t asm_count = res_asm ? res_asm->count : 0;
        MemSnapshot mem_asm_peak = get_memory_snapshot();
        if (!res_asm) {
            printf("FAILED (Out of Memory)!\n");
        } else {
            printf("Done in %10.3f ms\n", asm_ms);
        }

        if (n > 11 && res_asm) {
            result_free(res_asm);
            res_asm = NULL;
        }
        MemSnapshot mem_asm_after = get_memory_snapshot();

        printf("\n----------------------------------------------------------------------\n");
        printf(" TIME & THROUGHPUT BENCHMARK COMPARISON:\n");
        printf("----------------------------------------------------------------------\n");
        printf("  Unique Permutations : %llu\n", (unsigned long long)expected_count);
        printf("  Pure C (/O2) Time   : %10.3f ms\n", c_ms);
        printf("  x64 Assembly Time   : %10.3f ms\n", asm_ms);
        if (c_success && asm_success && asm_ms > 0.0001) {
            double speedup = c_ms / asm_ms;
            printf("  Assembly Speedup    : %10.2fx %s\n", speedup,
                   (speedup >= 1.0) ? "FASTER than C" : "SLOWER than C");
        }

        if (n <= 11 && res_c && res_asm) {
            int match = verify_results(res_c, res_asm);
            printf("  Correctness Check   : %s\n", match ? "[OK - Exact 100% Match]" : "[FAILED - MISMATCH]");
        } else if (n > 11) {
            int count_match = (c_count == expected_count && asm_count == expected_count);
            printf("  Count Verification  : %s (%llu generated)\n",
                   count_match ? "[OK - Exact Count Match]" : "[FAILED - Count Mismatch]",
                   (unsigned long long)asm_count);
            printf("  Correctness Check   : [Skipped for n > 11 to avoid 43GB dual-buffer memory exhaustion]\n");
        }

        printf("\n----------------------------------------------------------------------\n");
        printf(" SPACE COMPLEXITY & MEMORY USAGE COMPARISON:\n");
        printf("----------------------------------------------------------------------\n");
        printf("  Theoretical Space Complexity:\n");
        printf("    - Permutation Storage : O(n * n!) = %.2f %s (Flat contiguous buffer)\n",
               (mem_mb >= 1024.0) ? (mem_mb / 1024.0) : mem_mb,
               (mem_mb >= 1024.0) ? "GB" : "MB");
        printf("    - Auxiliary Overhead  : O(1) in-place stack/registers for both C and ASM\n\n");
        printf("  Pure C (MSVC /O2) Memory Snapshot:\n");
        print_mem_snapshot("Before Run", mem_c_before);
        print_mem_snapshot("Active/Peak Run", mem_c_peak);
        print_mem_snapshot("After 10s Settle", mem_settled);
        printf("\n");
        printf("  x64 MASM (SSE2) Memory Snapshot:\n");
        print_mem_snapshot("Before Run", mem_asm_before);
        print_mem_snapshot("Active/Peak Run", mem_asm_peak);
        print_mem_snapshot("After Run Free", mem_asm_after);
        printf("----------------------------------------------------------------------\n\n");

        if (res_asm && res_asm->count <= 50) {
            printf("Generated permutations:\n");
            print_all_permutations(res_asm, 50);
        }

        if (res_c) result_free(res_c);
        if (res_asm) result_free(res_asm);
        free(orig);
        free(working_c);
        free(working_asm);
        return 0;
    }

    printf("=== Unique Permutations: C + x64 Assembly Engine ===\n\n");

    /* ---- Demo with small input ---- */
    {
        int demo[] = {1, 1, 2};
        int n = 3;
        int* working = (int*)malloc((size_t)n * sizeof(int));
        memcpy(working, demo, (size_t)n * sizeof(int));

        printf("Input: ");
        print_permutation(demo, n);
        printf("\n\n");

        PermResult* r = permute_unique_asm(working, n);
        printf("All %llu unique permutations:\n", (unsigned long long)r->count);
        print_all_permutations(r, 50);
        printf("\n");
        result_free(r);
        free(working);
    }

    /* ---- Benchmark ---- */
    printf("=== BENCHMARK: C (pure) vs C + ASM (SSE2) ===\n");
    printf("%-20s %6s %12s %14s %14s %10s\n",
           "Test Case", "n", "Perms", "C (ms)", "ASM (ms)", "Speedup");
    printf("----------------------------------------------------------------------"
           "------------\n");

    /* Test cases of increasing complexity */
    struct { const char* name; int arr[12]; int n; int iters; } cases[] = {
        { "No duplicates",    {1,2,3,4,5,6,7,8},          8,  5  },
        { "Some dupes",       {1,1,2,2,3,3,4,4},          8,  10 },
        { "Heavy dupes",      {1,1,1,2,2,2,3,3},          8,  20 },
        { "All same",         {1,1,1,1,1,1,1,1},          8,  100},
        { "9-unique",         {1,2,3,4,5,6,7,8,9},        9,  3  },
        { "10-unique",        {1,2,3,4,5,6,7,8,9,10},     10, 1  },
        { "10-mixed",         {1,1,2,2,3,3,4,4,5,5},      10, 3  },
        { "Small (3)",        {1,1,2},                     3,  1000},
    };
    int num_cases = sizeof(cases) / sizeof(cases[0]);

    for (int c = 0; c < num_cases; c++) {
        double c_time, asm_time;
        uint64_t c_count, asm_count;

        run_benchmark("C", permute_unique_c, cases[c].arr, cases[c].n,
                      cases[c].iters, &c_time, &c_count);
        run_benchmark("ASM", permute_unique_asm, cases[c].arr, cases[c].n,
                      cases[c].iters, &asm_time, &asm_count);

        /* Verify correctness */
        int* w1 = (int*)malloc((size_t)cases[c].n * sizeof(int));
        int* w2 = (int*)malloc((size_t)cases[c].n * sizeof(int));
        memcpy(w1, cases[c].arr, (size_t)cases[c].n * sizeof(int));
        memcpy(w2, cases[c].arr, (size_t)cases[c].n * sizeof(int));
        PermResult* r1 = permute_unique_c(w1, cases[c].n);
        PermResult* r2 = permute_unique_asm(w2, cases[c].n);
        int ok = verify_results(r1, r2);
        result_free(r1);
        result_free(r2);
        free(w1);
        free(w2);

        double speedup = c_time / asm_time;
        printf("%-20s %6d %12llu %12.3f %12.3f %9.2fx %s\n",
               cases[c].name, cases[c].n,
               (unsigned long long)c_count,
               c_time, asm_time, speedup,
               ok ? "[OK]" : "[MISMATCH!]");
    }

    printf("\n");
    return 0;
}
