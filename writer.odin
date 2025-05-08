package http

Writer :: struct {
    buffer: []u8,
    offset: u32
}

write_string :: proc(writer: ^Writer, str: string) -> (err: bool) {
    using writer

    src := transmute([]u8)str
    start := buffer[offset:]
    if len(src) > len(start) {
        err = true 
        return
    }

    memory_copy(start, src)
    offset += u32(len(src))
    return 
}

write_memory :: proc(writer: ^Writer, src: []u8) -> (err: bool) {
    using writer
    start := buffer[offset:]
    if len(src) > len(start) {
        err = true 
        return
    }

    memory_copy(start, src)
    offset += u32(len(src))
    return 
}

write_char :: proc(writer: ^Writer, src: u8) -> (err: bool) {
    using writer
    start := buffer[offset:]
    if len(start) == 0 {
        err = true 
        return
    }

    start[0] = src
    offset += 1
    return 
}

write_number :: proc(writer: ^Writer, number: u32) -> (err: bool) {
    using writer
    n := number
    digits: u32
    for ; n > 0; digits += 1 {
        n /= 10 
    }

    start := buffer[offset:]
    if digits > u32(len(start)) {
        err = true
        return
    }

    n = number
    #reverse for &c in start[:digits] {
        c = u8(n % 10) + '0'
        assert(c >= '0' && c <= '9')
        n /= 10
    }

    offset += digits
    return
}

write :: proc{write_memory, write_char, write_number, write_string}
