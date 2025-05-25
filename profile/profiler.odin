package profile

import "base:runtime"

Profiler :: struct {
    zones: []Profile_Zone,
    zone_count: u32,
}

profiler_init :: proc(profiler: ^Profiler, arena: runtime.Allocator) {
    profiler.zones = make([]Profile_Zone, MAX_ZONE_COUNT, arena)
    profiler.zone_count = 0
}

zone_new :: proc(profiler: ^Profiler) -> (result: ^Profile_Zone) {
    assert(profiler.zone_count < MAX_ZONE_COUNT)
    result = &profiler.zones[zone_count] 
    zone_count += 1
    return
}
