package http

import "core:fmt"
import "core:net"
import "core:mem"
import "core:sys/kqueue"
import "base:runtime"
import "core:sys/posix"

// TODO(louis): Shoudld we have the main function in the platform-specific code or the platform-agnostic code 
// and call into the platform-specific code when needed

// CONSTANTS

CONNS_PER_THREAD :: 4
CONN_REQ_BUF_SIZE :: 2 * mem.Megabyte
CONN_RES_BUF_SIZE :: 2 * mem.Megabyte
CONN_SCRATCH_SIZE :: 4 * mem.Megabyte // This includes the header map as well as the output buffer for compressed content
MEM_PER_CONN :: size_of(Client_Connection) + CONN_REQ_BUF_SIZE + CONN_RES_BUF_SIZE + CONN_SCRATCH_SIZE
NTHREADS :: 6
MEMORY : u64 : NTHREADS * CONNS_PER_THREAD * MEM_PER_CONN

main :: proc() {
    socket, err := init_socket()
    if err != nil {
        fmt.eprintln("Unable to init socket: ", err)
        return
    } 


    base_memory: mem.Arena
    mem.arena_init(&base_memory, make([]u8, MEMORY, context.temp_allocator))
    defer free_all()
    base_arena := mem.arena_allocator(&base_memory)
    conn_pools: [NTHREADS]Connection_Pool
    conn_arenas: [NTHREADS]mem.Arena
    for idx in 0..<len(conn_pools) {
        conn_pool := &conn_pools[idx]
        conn_arena := &conn_arenas[idx]
        pool_init(conn_pool, CONNS_PER_THREAD, base_arena, conn_arena)
    }

    // TODO(louis): This code has to go to the threads
    client: net.TCP_Socket
    source: net.Endpoint
    conn_pool := conn_pools[0]

    // TODO(louis): Proper error handling here as well as in the 
    // http parser
    kq_fd, errno := kqueue.kqueue()
    if errno != .NONE {
        fmt.eprintln("Cannot create kernel queue")
    }

    KEVENT_LIST_LEN :: 16
    kq_change_list: [KEVENT_LIST_LEN]kqueue.KEvent
    kq_event_list: [KEVENT_LIST_LEN]kqueue.KEvent
    server_event := kqueue.KEvent {
        uintptr(socket),
        .Read,
        {.Add, .Error},
        {},
        0,
        nil
    }

    kq_change_list[0] = server_event
    change_count := 1
    for {
        event_count, kq_errno := kqueue.kevent(kq_fd, kq_change_list[:change_count], kq_event_list[:], nil)
        if kq_errno != .NONE {
            fmt.eprintln("Error while polling on kqueue")
            return
        }
        change_count = 0
        for event_idx in 0..<event_count {
            kevent := kq_event_list[event_idx]
            if kevent.ident == uintptr(socket) {
                client, source, err = net.accept_tcp(socket)
                if err != nil {
                    fmt.eprintln("Error while accepting")
                    return
                }

                conn_idx, pool_err := pool_acquire(&conn_pool, client)
                if pool_err {
                    fmt.eprintln("No free connection slots available")
                    return
                }

                if err != nil {
                    fmt.eprintln("Unable to accept on socket: ", err)
                    return
                }

                if change_count >= len(kq_change_list) {
                    // TODO(louis): Handle this properly, this is very slopy
                    fmt.println("No slots left in the change list for the kqueue")
                    return
                }

                new_event := kqueue.KEvent {
                    uintptr(client),
                    .Read,
                    {.Add, .Error},
                    {},
                    0,
                    rawptr(uintptr(conn_idx))
                }
                kq_change_list[change_count] = new_event
                change_count += 1
            } else {
                conn_idx := u32(uintptr(kevent.udata))
                client_conn: ^Client_Connection = &conn_pool.used[conn_idx]
                #partial switch handle_connection(client_conn) {
                case .Closed:
                    connection_reset(client_conn)
                    pool_release(&conn_pool, conn_idx)
                    // TODO(louis): Make sure this works
                    assert(change_count < len(kq_change_list))
                    new_event := kqueue.KEvent {
                        kevent.ident,
                        .Read,
                        {.Delete, .Error},
                        {},
                        0,
                        nil
                    }

                    kq_change_list[change_count] = new_event
                    change_count += 1
                }
            }
        }
    }
}

init_socket :: proc() -> (socket: net.TCP_Socket, err: net.Network_Error) {
    // socket := net.create_socket(.IP4, .TCP) or_return // this is theoretically platform-agnostic but whatever
    // socket = socket.(net.TCP_Socket)
    endpoint := net.Endpoint{ 
        net.IP4_Address{0, 0, 0, 0},
        8080
    }

    socket = net.listen_tcp(endpoint) or_return
    return
}
