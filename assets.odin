package http

import "core:sys/posix"
import "base:runtime"
import "core:fmt"
import "core:slice"

ASSET_BASE_DIR :: "assets"

ASSET_COUNT :: 128

// TODO(louis): Make this a hash map at some point
Asset :: struct {
    name: []u8,
    content: []u8
}

Asset_Store :: struct {
    assets: []Asset,
    count: u32
}

asset_store_insert :: proc(asset_store: ^Asset_Store, name: []u8, content: []u8) -> (err: bool) {
    if asset_store.count == u32(len(asset_store.assets)) {
        err = true 
        return
    }

    asset_store.assets[asset_store.count] = { name, content }
    asset_store.count += 1
    return
}

asset_store_get :: proc(asset_store: ^Asset_Store, name: []u8) -> (result: []u8, err: bool) {
    for asset in asset_store.assets {
        if asset.name != nil && memory_compare(asset.name, name) {
            result = asset.content
            return
        }
    }

    err = true
    return
}

asset_store_init :: proc(asset_store: ^Asset_Store, arena: ^Arena) -> (err: bool) {
    // TODO(louis): Shouldn't this be in the platform-specific code?
    asset_store.assets = arena_push_array_unchecked(arena, Asset, ASSET_COUNT)
    asset_base_dir := posix.opendir(ASSET_BASE_DIR)
    if asset_base_dir == nil {
        err = true
        return
    }

    entry := posix.readdir(asset_base_dir)
    path_buf: [size_of(entry.d_name) + len(ASSET_BASE_DIR) + 1]u8
    asset_base_path: string = ASSET_BASE_DIR
    memory_copy(path_buf[:], transmute([]u8)asset_base_path)
    path_buf[len(ASSET_BASE_DIR)] = u8('/')
    path_buf_str := cstring(slice.as_ptr(path_buf[:]))
    for entry != nil {
        // TODO(louis): We don't have to copy the entire 1024 bytes of d_name 
        // but for now we leave it like this so that we don't have to overwrite the 
        // content of the path buf for varying sizes of d_name

        if entry.d_type == .REG {
            memory_copy(path_buf[len(ASSET_BASE_DIR)+1:], entry.d_name[:])
            asset_fd := posix.open(path_buf_str, {})
            if asset_fd == -1 {
                fmt.eprintln("Cannot open asset file")
                err = true
                return
            }

            defer posix.close(asset_fd)
            asset_stat: posix.stat_t
            if posix.fstat(asset_fd, &asset_stat) == .FAIL {
                fmt.eprintln("Cannot stat asset")
                err = true
                return
            }

            content, alloc_err := arena_push_array(arena, u8, uintptr(asset_stat.st_size))
            if alloc_err {
                fmt.eprintln("Not enough memory to allocate static asset content")
                err = true
                return
            }

            bytes_read := posix.read(asset_fd, slice.as_ptr(content), len(content))
            if bytes_read < 0 {
                fmt.eprintln("Cannot read from asset file")
                err = true
                return
            }

            name_len := str_len(entry.d_name[:])
            name, name_alloc_err := arena_push_array(arena, u8, uintptr(name_len))
            if name_alloc_err {
                fmt.eprintln("Not enough memory to allocate name of static asset")
                err = true
                return
            }
            memory_copy(name, entry.d_name[:name_len])
            asset_store_insert(asset_store, name, content)
        }

        entry = posix.readdir(asset_base_dir)
    }

    return
}
