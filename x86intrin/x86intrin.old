bits 64

section .text
global _pause 
global _mfence
global _read_tsc

_read_tsc:
    rdtsc
    shl rdx, 32
    or rax, rdx
    ret

_pause:
    pause
    ret

_mfence:
    mfence
    ret
