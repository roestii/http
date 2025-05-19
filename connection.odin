package http

import "base:runtime"
import "core:net"
import "core:mem"

Client_Connection :: struct {
    client_socket: net.TCP_Socket,
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
    using conn
    // NOTE(louis): This just sets the offset of the underlying arena to zero
    free_all(conn.arena) 
    parser.offset = offset
    parser.prev_offset = 0
    parser.parser_state = .IncompleteHeader
    writer.offset = 0
    header_map_reset(&conn.request.header_map)
    header_map_reset(&conn.response.header_map)
}

connection_reset :: proc(conn: ^Client_Connection) {
    using conn
    // NOTE(louis): This just sets the offset of the underlying arena to zero
    free_all(conn.arena) 
    parser.offset = 0
    parser.prev_offset = 0
    parser.parser_state = .IncompleteHeader
    writer.offset = 0
    header_map_reset(&conn.request.header_map)
    header_map_reset(&conn.response.header_map)
}

pool_init :: proc(pool: ^Connection_Pool, len: u32, base_arena: runtime.Allocator, conn_arena: ^mem.Arena) {
    using pool
    free_len = len 
    used_len = 0
    // TODO(louis): Take a look at the memory layout
    free = make([]Client_Connection, len, base_arena)
    used = make([]Client_Connection, len, base_arena)
    for &conn in free {
        using conn
        writer.buffer = make([]u8, CONN_RES_BUF_SIZE, base_arena)
        parser.buffer = make([]u8, CONN_REQ_BUF_SIZE, base_arena)
        header_map_init(&conn.request.header_map, base_arena)
        header_map_init(&conn.response.header_map, base_arena)
        mem.arena_init(conn_arena, make([]u8, CONN_SCRATCH_SIZE, base_arena))
        arena = mem.arena_allocator(conn_arena)
    }
}

pool_acquire :: proc(pool: ^Connection_Pool, client_socket: net.TCP_Socket) -> (idx: u32, err: bool) {
    using pool
    if free_len == 0 {
        err = true
        return
    }

    free_len -= 1
    conn := free[free_len]
    conn.client_socket = client_socket
    used[used_len] = conn
    idx = used_len
    used_len += 1
    return
}

pool_release :: proc(pool: ^Connection_Pool, idx: u32) {
    using pool
    assert(used_len > 0)
    conn := used[idx]
    free[free_len] = conn

    if idx < used_len - 1 {
        last := used[used_len - 1]
        used[idx] = last 
    }

    free_len += 1
    used_len -= 1
}
