package profile

import "../x86intrin"

// NOTE(louis): This is from jonathan blow's profiler 

MAX_ZONE_COUNT :: 512
MAX_ZONE_STACK_DEPTH :: 1024
zone_stack: [MAX_ZONE_STACK_DEPTH]^Profile_Zone
stack_pos: u32 = 0

Profile_Zone :: struct {
    name: string,
    start_tsc: u64,
    exclusive_time: u64,
    children_time: u64, 
    entry_count: u64,
}

zone_enter :: proc(zone: ^Profile_Zone) { 
    zone.start_tsc = read_tsc()
    stack_pos += 1
    zone_stack[stack_pos] = zone
    zone.entry_count += 1
}

zone_exit :: proc() {
    zone := zone_stack[]
    zone.exclusive_time = read_tsc() - zone.start_tsc
    stack_pos -= 1
    parent := zone[stack_pos]
    parent.children_time += zone.exclusive_time
}
