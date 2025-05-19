package http

import "base:runtime"
import "core:net"
import "core:mem"
import "core:fmt"

CONNS_PER_THREAD :: 128
CONN_REQ_BUF_SIZE :: 2 * mem.Megabyte
CONN_RES_BUF_SIZE :: 2 * mem.Megabyte
CONN_SCRATCH_SIZE :: 4 * mem.Megabyte // This includes the header map as well as the output buffer for compressed content
MEM_PER_CONN :: size_of(Client_Connection) + CONN_REQ_BUF_SIZE + CONN_RES_BUF_SIZE + CONN_SCRATCH_SIZE
NTHREADS :: 6
MEMORY : u64 : NTHREADS * CONNS_PER_THREAD * MEM_PER_CONN

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
    when ODIN_DEBUG {
        fmt.println("Acquiring ", idx)
    }
    return
}

pool_release :: proc(pool: ^Connection_Pool, idx: u32, loc := #caller_location) {
    when ODIN_DEBUG {
        fmt.printfln("Releasing connection %d from {:v}", idx, loc)
    }
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
