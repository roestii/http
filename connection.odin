package http

import "base:runtime"
import "core:net"
import "core:mem"
import "core:fmt"

Client_Connection :: struct {
    client_socket: Fd_Type,
    arena: runtime.Allocator,
    parser: Http_Parser,
    request: Http_Request,
    writer: Writer,
    response: Http_Response
}

Connection_Pool :: struct {
    free_len: u32,
    used_len: u32,
    free: []Client_Connection,
    used: []Client_Connection
}

connection_reset_with_offset :: proc(conn: ^Client_Connection, offset: u32) {
    // NOTE(louis): This just sets the offset of the underlying arena to zero
    free_all(conn.arena) 
    conn.parser.offset = offset
    conn.parser.prev_offset = 0
    conn.parser.parser_state = .IncompleteHeader
    conn.writer.offset = 0
    header_map_reset(&conn.request.header_map)
    header_map_reset(&conn.response.header_map)
}

connection_reset :: proc(conn: ^Client_Connection) {
    // NOTE(louis): This just sets the offset of the underlying arena to zero
    free_all(conn.arena) 
    conn.parser.offset = 0
    conn.parser.prev_offset = 0
    conn.parser.parser_state = .IncompleteHeader
    conn.writer.offset = 0
    header_map_reset(&conn.request.header_map)
    header_map_reset(&conn.response.header_map)
}

pool_init :: proc(pool: ^Connection_Pool, len: u32, base_arena: runtime.Allocator, conn_arena: ^mem.Arena) {
    pool.free_len = len 
    pool.used_len = 0
    // TODO(louis): Take a look at the memory layout
    pool.free = make([]Client_Connection, len, base_arena)
    pool.used = make([]Client_Connection, len, base_arena)
    for &conn in pool.free {
        conn.writer.buffer = make([]u8, CONN_RES_BUF_SIZE, base_arena)
        conn.parser.buffer = make([]u8, CONN_REQ_BUF_SIZE, base_arena)
        header_map_init(&conn.request.header_map, base_arena)
        header_map_init(&conn.response.header_map, base_arena)
        mem.arena_init(conn_arena, make([]u8, CONN_SCRATCH_SIZE, base_arena))
        conn.arena = mem.arena_allocator(conn_arena)
    }
}

pool_acquire :: proc(pool: ^Connection_Pool, client_socket: Fd_Type) -> (idx: u32, err: bool) {
    if pool.free_len == 0 {
        err = true
        return
    }

    pool.free_len -= 1
    conn := pool.free[pool.free_len]
    conn.client_socket = client_socket
    pool.used[pool.used_len] = conn
    idx = pool.used_len
    pool.used_len += 1
    /* when ODIV_DEBUG {
        fmt.println("Acquiring ", idx)
    } */
    return
}

pool_release :: proc(pool: ^Connection_Pool, idx: u32/*,loc := #caller_location*/) {
    /* when ODIN_DEBUG {
        fmt.printfln("Releasing connection %d from {:v}", idx, loc)
    } */
    assert(pool.used_len > 0)
    conn := pool.used[idx]
    pool.free[pool.free_len] = conn

    if idx < pool.used_len - 1 {
        last := pool.used[pool.used_len - 1]
        pool.used[idx] = last 
    }

    pool.free_len += 1
    pool.used_len -= 1
}
