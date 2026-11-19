/* Harmless synthetic ARM/Thumb test firmware B — documented diffs vs A. */
typedef unsigned int u32;

volatile u32 g_state = 0;

__attribute__((noinline)) u32 add_values(u32 a, u32 b) {
    /* STRUCTURAL CHANGE: extra add / different math */
    return a + b + 1u;
}

__attribute__((noinline)) u32 mul_values(u32 a, u32 b) {
    return a * b;
}

/* ADDED function */
__attribute__((noinline)) u32 xor_values(u32 a, u32 b) {
    return a ^ b;
}

__attribute__((noinline)) u32 compare_and_branch(u32 x, u32 y) {
    /* STRUCTURAL CHANGE: extra call + different branch */
    if (x >= y) {
        return xor_values(add_values(x, y), 3u);
    }
    return mul_values(x, 3u);
}

/* REMOVED loop_accumulate — replaced by simpler helper */
__attribute__((noinline)) u32 process_input(u32 v) {
    g_state = compare_and_branch(v, 10u);
    return xor_values(g_state, 0x5Au);
}

void reset_handler(void) {
    (void)process_input(7u);
    for (;;) { }
}

__attribute__((section(".isr_vector"), used))
void (* const g_vectors[])(void) = {
    (void (*)(void))0x20001000,
    reset_handler,
};
