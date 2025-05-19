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
    using asset_store
    if count == u32(len(assets)) {
        err = true 
        return
    }

    assets[count] = { name, content }
    count += 1
    return
}

asset_store_get :: proc(asset_store: ^Asset_Store, name: []u8) -> (result: []u8, err: bool) {
    using asset_store
    for asset in assets {
        if asset.name != nil && memory_compare(asset.name, name) {
            result = asset.content
            return
        }
    }

    err = true
    return
}

asset_store_init :: proc(asset_store: ^Asset_Store, arena: runtime.Allocator) -> (err: bool) {
    // TODO(louis): Shouldn't this be in the platform-specific code?
    using posix
    using asset_store

    assets = make([]Asset, ASSET_COUNT, arena)
    asset_base_dir := opendir(ASSET_BASE_DIR)
    entry := readdir(asset_base_dir)
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
            asset_fd := open(path_buf_str, {})
            if asset_fd == -1 {
                fmt.eprintln("Cannot open asset file")
                err = true
                return
            }

            defer close(asset_fd)
            asset_stat: stat_t
            if fstat(asset_fd, &asset_stat) == .FAIL {
                fmt.eprintln("Cannot stat asset")
                err = true
                return
            }

            content := make([]u8, asset_stat.st_size, arena)
            bytes_read := read(asset_fd, slice.as_ptr(content), len(content))
            if bytes_read < 0 {
                fmt.eprintln("Cannot read from asset file")
                err := true
                return
            }

            name_len := str_len(entry.d_name[:])
            name := make([]u8, name_len, arena)
            memory_copy(name, entry.d_name[:name_len])
            asset_store_insert(asset_store, name, content)
        }

        entry = readdir(asset_base_dir)
    }

    return
}
