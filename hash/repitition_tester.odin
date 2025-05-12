package http_hash

import "core:sys/posix"
import "core:fmt"

OS_FREQUENCY :: 1000000000 

os_get_time :: proc() -> (result: u64) {
    time: posix.timespec
    assert(posix.clock_gettime(.MONOTONIC, &time) == .OK)
    result += OS_FREQUENCY * u64(time.tv_sec) + u64(time.tv_nsec)
    return
}

Tester_State :: enum {
    Uninitialized = 0, 
    Testing, 
    Completed
}

Repitition_Tester :: struct {
    name: string,
    state: Tester_State,
    try_for_time: u64,
    min_time: u64,
    max_time: u64,
    sum_time: u64,
    hit_count: u64,
    accumulated_time: u64,
    time_at_last_min: u64,
    last_start_time: u64,
    unit_count: u64,
    opened_blocks: u32,
    closed_blocks: u32
}

tester_init :: proc(tester: ^Repitition_Tester, try_for_time: u64, name: string) {
    tester.try_for_time = OS_FREQUENCY * try_for_time
    tester.min_time = transmute(u64)i64(-1)
    tester.name = name
}

tester_begin_time :: proc(tester: ^Repitition_Tester) {
    tester.last_start_time = os_get_time()
    tester.opened_blocks += 1
}

tester_end_time :: proc(tester: ^Repitition_Tester) {
    using tester
    tester.closed_blocks += 1
    accumulated_time += os_get_time() - last_start_time
}

tester_count_units :: proc(tester: ^Repitition_Tester, unit_count: u64) {
    tester.unit_count += unit_count
}

tester_is_testing :: proc(tester: ^Repitition_Tester) -> (result: bool) {
    using tester
    #partial switch state {
    case .Uninitialized:
        state = .Testing
    case .Testing:
        assert(opened_blocks == closed_blocks)
        if accumulated_time < min_time {
            min_time = accumulated_time
            time_at_last_min = os_get_time()
        }

        if accumulated_time > max_time {
            max_time = accumulated_time
        }

        sum_time += accumulated_time
        accumulated_time = 0
        hit_count += 1
        current_time := os_get_time()
        if current_time - time_at_last_min > try_for_time {
            state = .Completed
        }
    }

    result = state == .Testing
    return
}

tester_print :: proc(tester: ^Repitition_Tester) {
    using tester
    avg_time := f64(sum_time) / f64(hit_count)
    min_throughput := OS_FREQUENCY * f64(unit_count)/f64(min_time)
    max_throughput := OS_FREQUENCY * f64(unit_count)/f64(max_time)
    avg_throughput := OS_FREQUENCY * f64(unit_count)/f64(avg_time)
    fmt.printfln(
        "%s\n\tmin_time: %f (ms), %f (Gh/s)\n\tmax_time: %f (ms), %f (Gh/s)\n\tavg_time: %f (ms), %f (Gh/s)\n", 
        name, 
        f64(min_time)/1_000_000.0,
        min_throughput/1_000_000.0,
        f64(max_time)/1_000_000.0,
        max_throughput/1_000_000.0,
        avg_time/1_000_000.0, 
        avg_throughput/1_000_000.0,
    )
}
