/* Offline smoke test for the exact-range RM-680 erase acknowledgement. */
typedef unsigned long long u64;

extern int ioctl(int fd, unsigned long request, ...);
extern int *__errno_location(void);

__attribute__((noreturn))
static void exit_syscall(int status)
{
    register long r0 __asm__("r0") = status;
    register long r7 __asm__("r7") = 1L;
    __asm__ volatile("svc 0" : : "r" (r0), "r" (r7) : "memory", "cc");
    __builtin_unreachable();
}

void _start(void)
{
    u64 expected[2];
    u64 wrong[2];
    int result;

    expected[0] = 0;
    expected[1] = 15896412160ULL;
    result = ioctl(1, 0x127dUL, expected);
    if (result != 0)
        exit_syscall(1);

    wrong[0] = 0;
    wrong[1] = 15896412160ULL - 512ULL;
    result = ioctl(1, 0x127dUL, wrong);
    if (result != -1 || *__errno_location() != 22)
        exit_syscall(2);

    /* An unrelated ioctl must still reach the real syscall. */
    result = ioctl(1, 0x1277UL, expected);
    if (result != -1 || *__errno_location() != 25)
        exit_syscall(3);

    exit_syscall(0);
}
