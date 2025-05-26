package http

import "base:runtime"

Arena :: struct {
    start_addr: uintptr,
    len: uintptr,
    offset: uintptr 
}

arena_free :: proc(arena: ^Arena) {
    arena.offset = 0
}

arena_init :: proc(arena: ^Arena, start_addr: uintptr, len: uintptr) {
    arena.start_addr = start_addr
    arena.len = len
    arena.offset = 0
}

arena_push_array_unchecked :: proc(arena: ^Arena, $Type: typeid, count: uintptr) -> (result: []Type) {
    when ODIN_DEBUG {
        assert(arena.offset+size_of(Type)*count <= arena.len)
    }
    ptr := arena.start_addr + arena.offset
    result = ([^]Type)(ptr)[:count]
    arena.offset += count*size_of(Type)
    return
}

arena_push_array :: proc(arena: ^Arena, $Type: typeid, count: uintptr) -> (result: []Type, err: bool) {
    if arena.offset+size_of(Type)*count > arena.len {
        err = true
        return
    }

    ptr := arena.start_addr + arena.offset
    result = ([^]Type)(ptr)[:count]
    arena.offset += count*size_of(Type)
    return
}

arena_push_size :: proc(arena: ^Arena, size: uintptr) -> (result: uintptr, err: bool) {
    if arena.offset+uintptr(size) > arena.len {
        err = true
        return
    }

    result = arena.start_addr + arena.offset
    arena.offset += size
    return
}

arena_push_size_unchecked :: proc(arena: ^Arena, size: uintptr) -> (result: uintptr) {
    when ODIN_DEBUG {
        assert(arena.offset+size <= arena.len)
    }
    result = arena.start_addr + arena.offset
    arena.offset += size
    return
}

u32_to_string :: proc(x: u32, arena: ^Arena) -> (result: []u8) {
    n := x
    if n == 0 {
        result = arena_push_array_unchecked(arena, u8, 1)
        result[0] = '0'
        return
    } 

    digits: u32
    for n > 0 {
        digits += 1
        n /= 10
    }

    n = x
    result = arena_push_array_unchecked(arena, u8, uintptr(digits))
    #reverse for &c in result {
        c = u8(n % 10) + '0'
        assert(c >= '0' && c <= '9')
        n /= 10
    }

    return
}

string_to_u32 :: proc(input: []u8) -> (number: u32, err: bool) {
    number = 0
    for c in input {
        n := c - '0'
        if n < 0 || n > 9 {
            err = true
            return
        }

        number = 10 * number + u32(n)
    }

    return number, false
}

memory_copy :: proc(dest: []u8, src: []u8) {
    if len(src) > len(dest) {
        return
    }

    for i in 0..<len(src) {
        dest[i] = src[i]
    }
}

memory_find_char :: proc(haystack: []u8, needle: u8) -> (u32, bool) {
    for c, idx in haystack {
        if c == needle {
            return u32(idx), true
        }
    }

    return 0, false
}

memory_set :: proc(buffer: []u8, value: u8) {
    for &c in buffer {
        c = value
    }
}


str_len :: proc(buffer: []u8) -> (result: u32) {
    for c, idx in buffer {
        if c == 0 {
            result = u32(idx)
            return
        }
    }

    result = u32(len(buffer))
    return
}


memory_find :: proc(haystack: []u8, needle: []u8) -> (u32, bool) {
    end := len(haystack) - len(needle)
    haystackI: []u8
    outer: for i in 0..=end {
        haystackI = haystack[i:]
        for k in 0..<len(needle) {
            if haystackI[k] != needle[k] {
                continue outer; 
            }
        }

        return u32(i), true
    }

    return 0, false
}

memory_compare :: proc(a: []u8, b: []u8) -> bool {
    if len(a) != len(b) {
        return false
    }

    for i in 0..<len(a) {
        if a[i] != b[i] {
            return false
        }
    }

    return true
}
