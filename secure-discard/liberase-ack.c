/*
 * RM-680 compatibility shim for an already-erased recovery path.
 *
 * Nokia softupd gates its genuine bb5_devlock_reset() call on the eMMC erase
 * ioctl return value.  Acknowledge that prerequisite only for the exact
 * complete RM-680 eMMC user area.  No MMC erase command is sent.  Every other
 * secure-discard range is rejected fail-closed; unrelated ioctls pass through.
 */

typedef unsigned long long u64;

#define ARM_EABI_NR_IOCTL 54L
#define ARM_EABI_NR_WRITE 4L
#define BLKSECDISCARD_REQUEST 0x127dUL
#define EXPECTED_OFFSET 0ULL
#define EXPECTED_LENGTH 15896412160ULL
#define EINVAL_VALUE 22
#define MAX_ERRNO 4095UL

extern int *__errno_location(void);
extern int unsetenv(const char *name);

static long arm_syscall3(long number, long arg0, long arg1, long arg2)
{
    register long r0 __asm__("r0") = arg0;
    register long r1 __asm__("r1") = arg1;
    register long r2 __asm__("r2") = arg2;
    register long r7 __asm__("r7") = number;

    __asm__ volatile(
        "svc 0"
        : "+r" (r0)
        : "r" (r1), "r" (r2), "r" (r7)
        : "memory", "cc");
    return r0;
}

static int syscall_result(long result)
{
    if ((unsigned long)result >= (unsigned long)-MAX_ERRNO) {
        *__errno_location() = (int)-result;
        return -1;
    }
    return (int)result;
}

static int raw_ioctl(int fd, unsigned long request, void *argument)
{
    return syscall_result(arm_syscall3(ARM_EABI_NR_IOCTL, fd,
                                       (long)request, (long)argument));
}

static void raw_message(const char *message, unsigned long length)
{
    (void)arm_syscall3(ARM_EABI_NR_WRITE, 2, (long)message, (long)length);
}

/* Do not leak LD_PRELOAD into mkfs, dosfslabel, or other softupd children. */
__attribute__((constructor))
static void erase_ack_init(void)
{
    static const char message[] =
        "n950-erase-ack: exact RM-680 user area only\n";

    (void)unsetenv("LD_PRELOAD");
    raw_message(message, sizeof(message) - 1U);
}

__attribute__((visibility("default")))
int ioctl(int fd, unsigned long request, ...)
{
    __builtin_va_list arguments;
    void *argument;

    __builtin_va_start(arguments, request);
    argument = __builtin_va_arg(arguments, void *);
    __builtin_va_end(arguments);

    if (request == BLKSECDISCARD_REQUEST) {
        u64 *range;

        if (argument == (void *)0) {
            *__errno_location() = EINVAL_VALUE;
            return -1;
        }

        range = (u64 *)argument;
        if (range[0] == EXPECTED_OFFSET && range[1] == EXPECTED_LENGTH)
            return 0;

        *__errno_location() = EINVAL_VALUE;
        return -1;
    }

    return raw_ioctl(fd, request, argument);
}
