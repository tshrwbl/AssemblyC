; hot_path.asm - MASM x64 assembly for permutation hot paths (v3)
; 
; v3: Added asm_generate_all_permutations - monolithic generator that keeps
; the working array in registers for n <= 8 and avoids all C function call 
; overhead. The entire permutation generation + copy loop is in assembly.
;
; Assemble with: ml64 /c /Fo hot_path.obj hot_path.asm

.code

;=============================================================================
; int asm_find_pivot(const int* arr, int n)
;=============================================================================
asm_find_pivot PROC
    lea     eax, [edx - 2]
    test    eax, eax
    js      fp_nf
fp_s:
    movsxd  r9, eax
    mov     r10d, DWORD PTR [rcx + r9*4]
    cmp     r10d, DWORD PTR [rcx + r9*4 + 4]
    jl      fp_d
    dec     eax
    jns     fp_s
fp_nf:
    mov     eax, -1
fp_d:
    ret
asm_find_pivot ENDP

;=============================================================================
; int asm_find_swap_target(const int* arr, int pivot_idx, int n)
;=============================================================================
asm_find_swap_target PROC
    movsxd  r9, edx
    mov     r10d, DWORD PTR [rcx + r9*4]
    lea     eax, [r8d - 1]
fst_l:
    movsxd  r9, eax
    cmp     DWORD PTR [rcx + r9*4], r10d
    jg      fst_d
    dec     eax
    jmp     fst_l
fst_d:
    ret
asm_find_swap_target ENDP

;=============================================================================
; void asm_swap(int* a, int* b)
;=============================================================================
asm_swap PROC
    mov     eax, DWORD PTR [rcx]
    mov     r8d, DWORD PTR [rdx]
    mov     DWORD PTR [rcx], r8d
    mov     DWORD PTR [rdx], eax
    ret
asm_swap ENDP

;=============================================================================
; void asm_reverse_segment(int* arr, int left, int right)
;=============================================================================
asm_reverse_segment PROC
    push    rbx
    push    rsi
    push    rdi
    mov     rsi, rcx
    movsxd  rdi, edx
    movsxd  rbx, r8d
    mov     ecx, r8d
    sub     ecx, edx
    inc     ecx
    cmp     ecx, 8
    jl      rs_sc
rs_s2:
    mov     rax, rbx
    sub     rax, rdi
    cmp     rax, 7
    jl      rs_sc
    lea     r8, [rsi + rdi*4]
    movdqu  xmm0, XMMWORD PTR [r8]
    lea     r9, [rsi + rbx*4 - 12]
    movdqu  xmm1, XMMWORD PTR [r9]
    pshufd  xmm2, xmm0, 00011011b
    pshufd  xmm3, xmm1, 00011011b
    movdqu  XMMWORD PTR [r9], xmm2
    movdqu  XMMWORD PTR [r8], xmm3
    add     rdi, 4
    sub     rbx, 4
    jmp     rs_s2
rs_sc:
    cmp     rdi, rbx
    jge     rs_dn
rs_sl:
    mov     eax, DWORD PTR [rsi + rdi*4]
    mov     ecx, DWORD PTR [rsi + rbx*4]
    mov     DWORD PTR [rsi + rdi*4], ecx
    mov     DWORD PTR [rsi + rbx*4], eax
    inc     rdi
    dec     rbx
    cmp     rdi, rbx
    jl      rs_sl
rs_dn:
    pop     rdi
    pop     rsi
    pop     rbx
    ret
asm_reverse_segment ENDP

;=============================================================================
; int asm_next_permutation(int* arr, int n)
;   Returns 1 if advanced, 0 if last permutation.
;   RCX = arr, EDX = n
;=============================================================================
asm_next_permutation PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13

    mov     rsi, rcx
    mov     r12d, edx

    ; Step 1: Find pivot
    lea     eax, [r12d - 2]
    test    eax, eax
    js      np_last

np_fp:
    movsxd  r9, eax
    mov     r10d, DWORD PTR [rsi + r9*4]
    mov     r11d, DWORD PTR [rsi + r9*4 + 4]
    cmp     r10d, r11d
    jl      np_pf
    dec     eax
    jns     np_fp

np_last:
    xor     eax, eax
    jmp     np_exit

np_pf:
    mov     r13d, eax              ; pivot index

    ; Step 2: Find swap target
    lea     ebx, [r12d - 1]
np_ft:
    movsxd  r9, ebx
    cmp     DWORD PTR [rsi + r9*4], r10d
    jg      np_tf
    dec     ebx
    jmp     np_ft

np_tf:
    ; Step 3: Swap
    movsxd  r8, r13d
    movsxd  r9, ebx
    mov     eax, DWORD PTR [rsi + r8*4]
    mov     ecx, DWORD PTR [rsi + r9*4]
    mov     DWORD PTR [rsi + r8*4], ecx
    mov     DWORD PTR [rsi + r9*4], eax

    ; Step 4: Reverse suffix
    lea     edi, [r13d + 1]
    lea     ebx, [r12d - 1]
    movsxd  rdi, edi
    movsxd  rbx, ebx

    cmp     rdi, rbx
    jge     np_ok

np_rl:
    mov     eax, DWORD PTR [rsi + rdi*4]
    mov     ecx, DWORD PTR [rsi + rbx*4]
    mov     DWORD PTR [rsi + rdi*4], ecx
    mov     DWORD PTR [rsi + rbx*4], eax
    inc     rdi
    dec     rbx
    cmp     rdi, rbx
    jl      np_rl

np_ok:
    mov     eax, 1

np_exit:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
asm_next_permutation ENDP

;=============================================================================
; uint64_t asm_generate_all_perms(int* working, int n, int* output, uint64_t max_perms)
;
; MONOLITHIC permutation generator. Generates ALL unique permutations into
; a pre-allocated flat output buffer. Returns the number of permutations.
;
; This eliminates ALL C function call overhead - the entire generate loop
; (next_permutation + copy) runs in assembly without returning to C.
;
;   RCX = working array (sorted input, will be modified in-place)
;   EDX = n (elements per permutation)
;   R8  = output buffer (flat: output[perm_idx * n + elem_idx])
;   R9  = max_perms (capacity)
;
; Returns: number of permutations generated (in RAX)
;=============================================================================
asm_generate_all_perms PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp

    mov     rsi, rcx               ; rsi = working array
    mov     r12d, edx              ; r12d = n
    mov     r14, r8                ; r14 = output buffer
    mov     r15, r9                ; r15 = max_perms
    xor     r13, r13               ; r13 = perm count = 0

    ; Compute byte stride: n * 4
    movsxd  rbp, r12d
    shl     rbp, 2                 ; rbp = n * sizeof(int) = byte stride

    ;--- Copy first permutation (sorted) to output ---
    mov     rdi, r14               ; dst = output[0]
    mov     rcx, rsi               ; src = working
    mov     edx, r12d              ; count
    xor     eax, eax
gap_copy0:
    cmp     eax, edx
    jge     gap_copy0_done
    movsxd  r8, eax
    mov     r9d, DWORD PTR [rcx + r8*4]
    mov     DWORD PTR [rdi + r8*4], r9d
    inc     eax
    jmp     gap_copy0
gap_copy0_done:
    add     r14, rbp               ; advance r14 to next permutation slot
    inc     r13                    ; perm_count = 1

    ;--- Main generation loop ---
gap_loop:
    ; Check capacity
    cmp     r13, r15
    jge     gap_done

    ;--- Next Permutation (inlined) ---
    ; Step 1: Find pivot
    lea     eax, [r12d - 2]
    test    eax, eax
    js      gap_done               ; n <= 1 or last permutation

gap_fp:
    movsxd  r9, eax
    mov     r10d, DWORD PTR [rsi + r9*4]
    cmp     r10d, DWORD PTR [rsi + r9*4 + 4]
    jl      gap_pf
    dec     eax
    jns     gap_fp
    jmp     gap_done               ; Last permutation reached

gap_pf:
    ; eax = pivot index, r10d = pivot value
    mov     ecx, eax               ; save pivot index in ecx

    ; Step 2: Find swap target
    lea     ebx, [r12d - 1]
gap_ft:
    movsxd  r9, ebx
    cmp     DWORD PTR [rsi + r9*4], r10d
    jg      gap_tf
    dec     ebx
    jmp     gap_ft

gap_tf:
    ; Step 3: Swap arr[pivot] and arr[j]
    movsxd  r8, ecx                ; pivot index
    movsxd  r9, ebx                ; j index
    mov     eax, DWORD PTR [rsi + r8*4]
    mov     edx, DWORD PTR [rsi + r9*4]
    mov     DWORD PTR [rsi + r8*4], edx
    mov     DWORD PTR [rsi + r9*4], eax

    ; Step 4: Reverse suffix arr[pivot+1 .. n-1]
    lea     edi, [ecx + 1]         ; left = pivot + 1
    lea     ebx, [r12d - 1]        ; right = n - 1
    movsxd  rdi, edi
    movsxd  rbx, ebx

    cmp     rdi, rbx
    jge     gap_copy

gap_rev:
    mov     eax, DWORD PTR [rsi + rdi*4]
    mov     edx, DWORD PTR [rsi + rbx*4]
    mov     DWORD PTR [rsi + rdi*4], edx
    mov     DWORD PTR [rsi + rbx*4], eax
    inc     rdi
    dec     rbx
    cmp     rdi, rbx
    jl      gap_rev

gap_copy:
    ;--- Copy current permutation to r14 (destination) ---
    ; r14 is already positioned at current permutation buffer slot

    ; Unrolled copy for common sizes
    cmp     r12d, 8
    je      gap_copy_8
    cmp     r12d, 10
    je      gap_copy_10
    cmp     r12d, 11
    je      gap_copy_11
    cmp     r12d, 12
    je      gap_copy_12
    cmp     r12d, 9
    je      gap_copy_9
    cmp     r12d, 3
    je      gap_copy_3

    ; General copy using SSE2 in 16-byte chunks
    xor     eax, eax
gap_cg_sse:
    lea     edx, [eax + 4]
    cmp     edx, r12d
    jg      gap_cg_scalar
    movsxd  r8, eax
    movdqu  xmm0, XMMWORD PTR [rsi + r8*4]
    movdqu  XMMWORD PTR [r14 + r8*4], xmm0
    add     eax, 4
    jmp     gap_cg_sse

gap_cg_scalar:
    cmp     eax, r12d
    jge     gap_copy_done
    movsxd  r8, eax
    mov     edx, DWORD PTR [rsi + r8*4]
    mov     DWORD PTR [r14 + r8*4], edx
    inc     eax
    jmp     gap_cg_scalar

gap_copy_3:
    mov     eax, DWORD PTR [rsi]
    mov     DWORD PTR [r14], eax
    mov     eax, DWORD PTR [rsi + 4]
    mov     DWORD PTR [r14 + 4], eax
    mov     eax, DWORD PTR [rsi + 8]
    mov     DWORD PTR [r14 + 8], eax
    jmp     gap_copy_done

gap_copy_8:
    ; Copy 8 ints = 32 bytes using 2x SSE2
    movdqu  xmm0, XMMWORD PTR [rsi]
    movdqu  xmm1, XMMWORD PTR [rsi + 16]
    movdqu  XMMWORD PTR [r14], xmm0
    movdqu  XMMWORD PTR [r14 + 16], xmm1
    jmp     gap_copy_done

gap_copy_9:
    ; Copy 9 ints = 36 bytes: 2x SSE2 + 1 scalar
    movdqu  xmm0, XMMWORD PTR [rsi]
    movdqu  xmm1, XMMWORD PTR [rsi + 16]
    movdqu  XMMWORD PTR [r14], xmm0
    movdqu  XMMWORD PTR [r14 + 16], xmm1
    mov     eax, DWORD PTR [rsi + 32]
    mov     DWORD PTR [r14 + 32], eax
    jmp     gap_copy_done

gap_copy_10:
    ; Copy 10 ints = 40 bytes: 2x SSE2 + 2 scalar
    movdqu  xmm0, XMMWORD PTR [rsi]
    movdqu  xmm1, XMMWORD PTR [rsi + 16]
    movdqu  XMMWORD PTR [r14], xmm0
    movdqu  XMMWORD PTR [r14 + 16], xmm1
    mov     rax, QWORD PTR [rsi + 32]
    mov     QWORD PTR [r14 + 32], rax
    jmp     gap_copy_done

gap_copy_11:
    ; Copy 11 ints = 44 bytes: 2x SSE2 (32B) + 1 qword (8B) + 1 dword (4B)
    movdqu  xmm0, XMMWORD PTR [rsi]
    movdqu  xmm1, XMMWORD PTR [rsi + 16]
    mov     rax, QWORD PTR [rsi + 32]
    mov     edx, DWORD PTR [rsi + 40]
    movdqu  XMMWORD PTR [r14], xmm0
    movdqu  XMMWORD PTR [r14 + 16], xmm1
    mov     QWORD PTR [r14 + 32], rax
    mov     DWORD PTR [r14 + 40], edx
    jmp     gap_copy_done

gap_copy_12:
    ; Copy 12 ints = 48 bytes: 3x SSE2 (48B)
    movdqu  xmm0, XMMWORD PTR [rsi]
    movdqu  xmm1, XMMWORD PTR [rsi + 16]
    movdqu  xmm2, XMMWORD PTR [rsi + 32]
    movdqu  XMMWORD PTR [r14], xmm0
    movdqu  XMMWORD PTR [r14 + 16], xmm1
    movdqu  XMMWORD PTR [r14 + 32], xmm2
    jmp     gap_copy_done

gap_copy_done:
    add     r14, rbp               ; advance destination pointer by stride
    inc     r13                    ; perm_count++
    jmp     gap_loop

gap_done:
    mov     rax, r13               ; return perm_count

    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
asm_generate_all_perms ENDP

;=============================================================================
; void asm_copy_ints(int* dst, const int* src, int n)
;=============================================================================
asm_copy_ints PROC
    mov     eax, r8d
    test    eax, eax
    jz      ci_done
    cmp     eax, 4
    jl      ci_sc
ci_s2:
    cmp     eax, 4
    jl      ci_sc
    movdqu  xmm0, XMMWORD PTR [rdx]
    movdqu  XMMWORD PTR [rcx], xmm0
    add     rcx, 16
    add     rdx, 16
    sub     eax, 4
    jmp     ci_s2
ci_sc:
    test    eax, eax
    jz      ci_done
ci_sl:
    mov     r8d, DWORD PTR [rdx]
    mov     DWORD PTR [rcx], r8d
    add     rcx, 4
    add     rdx, 4
    dec     eax
    jnz     ci_sl
ci_done:
    ret
asm_copy_ints ENDP

;=============================================================================
; void asm_insertion_sort(int* arr, int n)
;=============================================================================
asm_insertion_sort PROC
    push    rbx
    push    rsi
    push    rdi
    mov     rsi, rcx
    mov     edi, edx
    cmp     edi, 2
    jl      is_d
    mov     ecx, 1
is_o:
    cmp     ecx, edi
    jge     is_d
    movsxd  rax, ecx
    mov     ebx, DWORD PTR [rsi + rax*4]
    lea     edx, [ecx - 1]
is_i:
    cmp     edx, 0
    jl      is_ins
    movsxd  rax, edx
    cmp     DWORD PTR [rsi + rax*4], ebx
    jle     is_ins
    mov     r8d, DWORD PTR [rsi + rax*4]
    mov     DWORD PTR [rsi + rax*4 + 4], r8d
    dec     edx
    jmp     is_i
is_ins:
    movsxd  rax, edx
    mov     DWORD PTR [rsi + rax*4 + 4], ebx
    inc     ecx
    jmp     is_o
is_d:
    pop     rdi
    pop     rsi
    pop     rbx
    ret
asm_insertion_sort ENDP

END
