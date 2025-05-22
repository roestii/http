package profile

import "core:fmt"

increment :: proc(x: ^u32, loc := #caller_location) {
    fmt.println(loc.procedure)
    x^ += 1
}


main :: proc() {
    x: u32 = 0
    increment(&x)
}
