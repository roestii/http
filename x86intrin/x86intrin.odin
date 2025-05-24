package x86intrin 

foreign import x86intrin "x86intrin.asm"

foreign x86intrin {
    // maybe use #force_inline
    @(link_name="_pause")
    pause :: proc "c" () ---
    @(link_name="_mfence")
    mfence :: proc "c" () ---
}
