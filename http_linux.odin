package http
import "core:fmt"
import "core:sys/linux"
import "core:mem"
import "core:net"

NEGATIVE_ONE_U32 :: transmute(u32)i32(-1)

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
    asset_store_err := asset_store_init(&asset_store, base_arena)
    if asset_store_err {
        fmt.eprintln("Cannot initialize static asset store.")
        return
    }
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
    efd, errno := linux.epoll_create1({})
    if errno != .NONE {
        fmt.eprintln("Cannot create epoll.")
        return
    }

    server_event := linux.EPoll_Event {
        { .IN },
        { u32 = NEGATIVE_ONE_U32 }
    }
    errno = linux.epoll_ctl(efd, .ADD, linux.Fd(socket), &server_event)
    if errno != .NONE {
        fmt.eprintln("Cannot add server socket to epoll.")
        return
    }

    MAX_EVENT_COUNT :: 16
    events: [MAX_EVENT_COUNT]linux.EPoll_Event
    for {
        event_count, epoll_err := linux.epoll_wait(efd, raw_data(events[:]), MAX_EVENT_COUNT, -1)
        if epoll_err != .NONE {
            fmt.eprintln("Error while polling on epoll")
            return
        }

        for event_idx in 0..<event_count {
            event := events[event_idx]
            if event.data.u32 == NEGATIVE_ONE_U32 {
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

                new_event := linux.EPoll_Event {
                    { .IN },
                    { u32 = conn_idx }
                }
                // TODO(louis): Handle the error here
                errno = linux.epoll_ctl(efd, .ADD, linux.Fd(client), &new_event)
                if errno != .NONE {
                    fmt.eprintln("Error while adding client connection to epoll.")
                    return
                }

            } else {
                // TODO(louis): Check whether the client closed the connection as kqueue will notify us 
                // when the connection is closed (we should verify that as well)

                // TODO(louis): Somehow we free the connection multiple times, that should not happen...
                // Something is really broken, test this further...
                conn_idx := event.data.u32
                client_conn: ^Client_Connection = &conn_pool.used[conn_idx]
                if .HUP in event.events || .ERR in event.events {
                    net.close(net.TCP_Socket(client_conn.client_socket))
                    connection_reset(client_conn)
                    pool_release(&conn_pool, conn_idx)
                } else {
                    // TODO(louis): Verify that reading into a buffer with size zero returns no error,
                    // because we rely on that fact to handle the corresponding response in the 
                    // platform-agnostic code, i.e. http.odin
                    bytes_read, err := net.recv_tcp(client_conn.client_socket, client_conn.parser.buffer[client_conn.parser.offset:])
                    if err != nil {
                        epoll_err := linux.epoll_ctl(efd, .DEL, linux.Fd(client_conn.client_socket), nil)
                        if epoll_err != .NONE {
                            fmt.eprintln("Cannot remove client socket from epoll.")
                            // TODO(louis): We should not return here, probably
                            return
                        }
                        net.close(client_conn.client_socket)
                        connection_reset(client_conn)
                        pool_release(&conn_pool, conn_idx)
                    } else {
                        client_conn.parser.prev_offset = client_conn.parser.offset
                        client_conn.parser.offset += u32(bytes_read)
                        #partial switch handle_connection(client_conn, &asset_store) {
                        case .Close:
                            epoll_err := linux.epoll_ctl(efd, .DEL, linux.Fd(client_conn.client_socket), nil)
                            if epoll_err != .NONE {
                                fmt.eprintln("Cannot remove client socket from epoll.")
                                // TODO(louis): We should not return here, probably
                                return
                            }

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

