bits 64

section .text
global _pause 
global _mfence

_pause:
    pause
    ret

_mfence:
    mfence
    ret
