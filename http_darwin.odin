package http

// TODO(louis): What happens if the client closes the connection, we need to know that...

import "core:fmt"
import "core:net"
import "core:mem"
import "core:sys/kqueue"
import "base:runtime"
import "core:sys/posix"

// TODO(louis): Shoudld we have the main function in the platform-specific code or the platform-agnostic code 
// and call into the platform-specific code when needed

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

    asset_store: Asset_Store
    asset_store_init(&asset_store, base_arena)
    // when ODIN_DEBUG {
    //     BASE_DIR :: "assets/"
    //     INDEX_NAME :: "index.html"
    //     index_name := INDEX_NAME
    //     index_content := #load(BASE_DIR + INDEX_NAME, []u8)
    //     content, asset_found := asset_store_get(&asset_store, transmute([]u8)index_name)
    //     assert(asset_found)
    //     assert(memory_compare(content, index_content))
    // }
    // TODO(louis): Remove this, this is purely for debugging purposes

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

                // TODO(louis): Verify that this can never happen
                assert(change_count < len(kq_change_list))

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
                // TODO(louis): Check whether the client closed the connection as kqueue will notify us 
                // when the connection is closed (we should verify that as well)
                conn_idx := u32(uintptr(kevent.udata))
                client_conn: ^Client_Connection = &conn_pool.used[conn_idx]
                if .EOF in kevent.flags {
                    connection_reset(client_conn)
                    pool_release(&conn_pool, conn_idx)
                    net.close(net.TCP_Socket(kevent.ident))
                } else {
                    bytes_read, err := net.recv_tcp(client_conn.client_socket, client_conn.parser.buffer[client_conn.parser.offset:])
                    if err != nil {
                        net.close(client_conn.client_socket)
                        connection_reset(client_conn)
                        pool_release(&conn_pool, conn_idx)
                    } else {
                        #partial switch handle_connection(client_conn, &asset_store) {
                        case .Close:
                            net.close(client_conn.client_socket)
                            connection_reset(client_conn)
                            pool_release(&conn_pool, conn_idx)
                        }
                    }
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
