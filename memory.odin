package http

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
