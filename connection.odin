package http

import "base:runtime"
import "core:net"
import "core:mem"
import "core:fmt"

Connection_Bits :: enum u8 {
    READ = 1,
    WRITE = 2, // This tells the main loop that we issued a response send call to the client
    CLOSE = 3 // This tells the main loop that it should close the connection after it consumed the response write
}

Connection_Flags :: bit_set[Connection_Bits; u32]

Client_Connection :: struct {
    client_socket: Fd_Type,
    arena: Arena,
    parser: Http_Parser,
    request: Http_Request,
    writer: Writer,
    response: Http_Response,
    flags: Connection_Flags
}

Connection_Pool :: struct {
    conns: []Client_Connection,
    free: []u32,
    free_len: u32,
}

// connection_reset_with_offset_noflags :: proc(conn: ^Client_Connection, offset: u32) {
//     // NOTE(louis): This just sets the offset of the underlying arena to zero
//     free_all(conn.arena) 
//     conn.parser.offset = offset
//     conn.parser.prev_offset = 0
//     conn.parser.parser_state = .IncompleteHeader
//     conn.writer.offset = 0
//     conn.flags = {}
//     header_map_reset(&conn.request.header_map)
//     header_map_reset(&conn.response.header_map)
// }
// 
// connection_reset_with_offset :: proc(conn: ^Client_Connection, offset: u32) {
//     // NOTE(louis): This just sets the offset of the underlying arena to zero
//     free_all(conn.arena) 
//     conn.parser.offset = offset
//     conn.parser.prev_offset = 0
//     conn.parser.parser_state = .IncompleteHeader
//     conn.writer.offset = 0
//     header_map_reset(&conn.request.header_map)
//     header_map_reset(&conn.response.header_map)
// }
// 
// connection_reset_noflags :: proc(conn: ^Client_Connection) {
//     // NOTE(louis): This just sets the offset of the underlying arena to zero
//     free_all(conn.arena) 
//     conn.parser.offset = 0
//     conn.parser.prev_offset = 0
//     conn.parser.parser_state = .IncompleteHeader
//     conn.writer.offset = 0
//     header_map_reset(&conn.request.header_map)
//     header_map_reset(&conn.response.header_map)
// }

connection_reset :: proc(conn: ^Client_Connection) {
    // NOTE(louis): This just sets the offset of the underlying arena to zero
    arena_free(&conn.arena) 
    conn.parser.offset = 0
    conn.parser.prev_offset = 0
    conn.parser.parser_state = .IncompleteHeader
    conn.writer.offset = 0
    conn.response.body = nil
    conn.request.body = nil
    conn.flags = {}
    header_map_reset(&conn.request.header_map)
    header_map_reset(&conn.response.header_map)
}

pool_init_arena :: proc(
    pool: ^Connection_Pool, 
    len: u32, 
    arena: ^Arena
) {
    pool.free_len = len
    pool.free = arena_push_array_unchecked(arena, u32, uintptr(len))
    pool.conns = arena_push_array_unchecked(arena, Client_Connection, uintptr(len)) 
    for i in 0..<len {
        pool.free[i] = i
    }

    for &conn in pool.conns {
        conn.writer.buffer = arena_push_array_unchecked(arena, u8, CONN_RES_BUF_SIZE)
        conn.writer.offset = 0
        conn.parser.buffer = arena_push_array_unchecked(arena, u8, CONN_REQ_BUF_SIZE)
        conn.parser.offset = 0
        conn.parser.prev_offset = 0
        conn.parser.parser_state = .IncompleteHeader
        header_map_init_unchecked(&conn.request.header_map, arena)
        header_map_init_unchecked(&conn.response.header_map, arena)
        conn.request.body = nil
        conn.response.body = nil
        arena_init(
            &conn.arena,
            arena_push_size_unchecked(arena, CONN_SCRATCH_SIZE),
            CONN_SCRATCH_SIZE
        )
        conn.flags = {}
    }
}

//pool_init :: proc(pool: ^Connection_Pool, len: u32, base_arena: runtime.Allocator, conn_arena: ^mem.Arena) {
//    pool.free_len = len 
//    pool.used_len = 0
//    // TODO(louis): Take a look at the memory layout
//    pool.free = make([]Client_Connection, len, base_arena)
//    pool.used = make([]Client_Connection, len, base_arena)
//    for &conn in pool.free {
//        conn.writer.buffer = make([]u8, CONN_RES_BUF_SIZE, base_arena)
//        conn.parser.buffer = make([]u8, CONN_REQ_BUF_SIZE, base_arena)
//        header_map_init(&conn.request.header_map, base_arena)
//        header_map_init(&conn.response.header_map, base_arena)
//        mem.arena_init(conn_arena, make([]u8, CONN_SCRATCH_SIZE, base_arena))
//        conn.arena = mem.arena_allocator(conn_arena)
//    }
//}

pool_acquire :: proc(pool: ^Connection_Pool) -> (conn_idx: u32, err: bool) {
    if pool.free_len == 0 {
        err = true
        return
    }

    pool.free_len -= 1
    conn_idx = pool.free[pool.free_len]
    /* when ODIV_DEBUG {
        fmt.println("Acquiring ", idx)
    } */
    return
}

pool_release :: proc(pool: ^Connection_Pool, conn_idx: u32/*,loc := #caller_location*/) {
    /* when ODIN_DEBUG {
        fmt.printfln("Releasing connection %d from {:v}", idx, loc)
    } */
    assert(pool.free_len < u32(len(pool.free)))
    pool.free[pool.free_len] = conn_idx
    pool.free_len += 1
}
