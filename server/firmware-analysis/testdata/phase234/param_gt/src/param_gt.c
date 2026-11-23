/* Phase 2.3.4 — controlled ARM/Thumb parameter ground truth.
 * Harmless synthetic firmware. No scooter / unlock logic.
 */
typedef unsigned int u32;

volatile u32 g_sink = 0;
volatile u32 g_global = 0;

/* 1) zero parameters */
__attribute__((noinline)) u32 fn_zero_params(void) {
    return g_global + 1u;
}

/* 2) one parameter */
__attribute__((noinline)) u32 fn_one_param(u32 a) {
    return a ^ 0xA5A5A5A5u;
}

/* 3) two parameters */
__attribute__((noinline)) u32 fn_two_params(u32 a, u32 b) {
    return a + b;
}

/* 4) three parameters */
__attribute__((noinline)) u32 fn_three_params(u32 a, u32 b, u32 c) {
    return (a ^ b) + c;
}

/* 5) four parameters (AAPCS: r0-r3) */
__attribute__((noinline)) u32 fn_four_params(u32 a, u32 b, u32 c, u32 d) {
    return a + b + c + d;
}

/* 6) multiple memory accesses */
__attribute__((noinline)) u32 fn_mem_access(u32 *p, u32 n) {
    u32 acc = 0;
    for (u32 i = 0; i < n; i++) {
        acc += p[i];
        p[i] = acc;
    }
    return acc;
}

/* 7) return value + store */
__attribute__((noinline)) u32 fn_with_return(u32 x) {
    g_sink = x;
    return x + 3u;
}

/* 8) indirect call via function pointer */
typedef u32 (*fn1_t)(u32);
__attribute__((noinline)) u32 fn_indirect_call(fn1_t cb, u32 v) {
    if (cb == 0) {
        return 0;
    }
    return cb(v);
}

/* 9) incomplete / hard-to-signature helper (varargs-like packing) */
__attribute__((noinline)) u32 fn_incomplete_sig(u32 packed) {
    u32 a = packed & 0xFFu;
    u32 b = (packed >> 8) & 0xFFu;
    return a + b;
}

/* 10) unusual / opaque calling style (naked-ish via asm barrier) */
__attribute__((noinline)) u32 fn_opaque_cc(u32 a, u32 b) {
    u32 r;
    __asm__ __volatile__("" : "=r"(r) : "r"(a), "r"(b) : "memory");
    return r ^ a ^ b;
}

void reset_handler(void) {
    u32 buf[4] = {1, 2, 3, 4};
    g_sink = fn_zero_params();
    g_sink += fn_one_param(1);
    g_sink += fn_two_params(1, 2);
    g_sink += fn_three_params(1, 2, 3);
    g_sink += fn_four_params(1, 2, 3, 4);
    g_sink += fn_mem_access(buf, 4);
    g_sink += fn_with_return(9);
    g_sink += fn_indirect_call(fn_one_param, 5);
    g_sink += fn_incomplete_sig(0x0102u);
    g_sink += fn_opaque_cc(3, 4);
    for (;;) {
    }
}

__attribute__((section(".isr_vector"), used))
void (*const g_vectors[])(void) = {
    (void (*)(void))0x20001000,
    reset_handler,
};
