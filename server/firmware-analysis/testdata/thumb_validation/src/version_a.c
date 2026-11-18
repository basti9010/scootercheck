/* Harmless synthetic ARM/Thumb test firmware A — no scooter logic. */
typedef unsigned int u32;

volatile u32 g_state = 0;

__attribute__((noinline)) u32 add_values(u32 a, u32 b) {
    return a + b;
}

__attribute__((noinline)) u32 mul_values(u32 a, u32 b) {
    return a * b;
}

__attribute__((noinline)) u32 compare_and_branch(u32 x, u32 y) {
    if (x > y) {
        return add_values(x, y);
    }
    return mul_values(x, 2u);
}

__attribute__((noinline)) u32 loop_accumulate(u32 n) {
    u32 acc = 0;
    for (u32 i = 0; i < n; i++) {
        acc = add_values(acc, i);
    }
    return acc;
}

__attribute__((noinline)) u32 process_input(u32 v) {
    g_state = compare_and_branch(v, 10u);
    return loop_accumulate(g_state & 0xFu);
}

void reset_handler(void) {
    (void)process_input(7u);
    for (;;) { }
}

/* Minimal Cortex-M vector table (stack + reset) */
__attribute__((section(".isr_vector"), used))
void (* const g_vectors[])(void) = {
    (void (*)(void))0x20001000,
    reset_handler,
};
