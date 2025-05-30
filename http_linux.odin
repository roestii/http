package http

import "core:fmt"
import "core:sys/linux"
import "core:sys/posix"
import "core:mem"
import "core:net"
import "io_uring"

SERVER_SOCKET_USER_DATA :: transmute(u64)i64(-1)

// TODO(louis): Maybe we have to use non blocking sockets

IO_URING :: #config(IO_URING, true)
Fd_Type :: linux.Fd
Errno :: linux.Errno
// TODO(louis): Should we consider moving the write of the response to the ring as well?
// If we do so, we have to check in our server main loop that the completion queue entry comes from 
// the write. Or maybe there is a way to not have a cqe for the write sqe
send_tcp :: proc(fd: linux.Fd, buffer: []u8) -> (bytes_written: int, errno: linux.Errno){
    bytes_written, errno = linux.send(fd, buffer, {.NOSIGNAL})
    return
}

IO_Uring_Command :: bit_field u64 {
    conn_idx: u32 | 32,
    command: io_uring.IO_Uring_Op | 8
}

server_loop_epoll :: proc(
    server_socket: linux.Fd, 
    conn_pool: ^Connection_Pool, 
    asset_store: ^Asset_Store
) {
    // TODO(louis): Proper error handling here as well as in the 
    // http parser
    efd, errno := linux.epoll_create1({})
    if errno != .NONE {
        fmt.eprintln("Cannot create epoll.")
        return
    }

    server_event := linux.EPoll_Event {
        { .IN },
        { u64 = SERVER_SOCKET_USER_DATA }
    }

    errno = linux.epoll_ctl(efd, .ADD, linux.Fd(server_socket), &server_event)
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

        event_loop: for event_idx in 0..<event_count {
            event := events[event_idx]
            if event.data.u64 == SERVER_SOCKET_USER_DATA {
                client_addr: linux.Sock_Addr_In
                client, accept_err := linux.accept(server_socket, &client_addr, {})
                if accept_err != nil {
                    fmt.eprintln("Error while accepting")
                    return
                }

                conn_idx, pool_err := pool_acquire(conn_pool)
                conn := &conn_pool.conns[conn_idx]
                conn.client_socket = client
                if pool_err {
                    fmt.eprintln("No free connection slots available")
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
                conn := &conn_pool.conns[conn_idx]
                if .HUP in event.events || .ERR in event.events {
                    linux.close(conn.client_socket)
                    connection_reset(conn)
                    pool_release(conn_pool, conn_idx)
                } else {
                    // TODO(louis): Verify that reading into a buffer with size zero returns no error,
                    // because we rely on that fact to handle the corresponding response in the 
                    // platform-agnostic code, i.e. http.odin
                    bytes_read, err := linux.read(conn.client_socket, conn.parser.buffer[conn.parser.offset:])
                    if err != .NONE {
                        epoll_err := linux.epoll_ctl(efd, .DEL, linux.Fd(conn.client_socket), nil)
                        if epoll_err != .NONE {
                            fmt.eprintln("Cannot remove client socket from epoll.")
                            // TODO(louis): We should not return here, probably
                            return
                        }

                        linux.close(conn.client_socket)
                        connection_reset(conn)
                        pool_release(conn_pool, conn_idx)
                    } else {
                        conn.parser.prev_offset = conn.parser.offset
                        conn.parser.offset += u32(bytes_read)
                        handle_connection(conn, asset_store)
                        if .WRITE in conn.flags {
                            bytes_written, send_err := send_tcp(conn.client_socket, conn.writer.buffer[:conn.writer.offset])
                            conn.writer.offset = 0
                            if send_err != .NONE {
                                epoll_err := linux.epoll_ctl(efd, .DEL, linux.Fd(conn.client_socket), nil)
                                if epoll_err != .NONE {
                                    fmt.eprintln("Cannot remove client socket from epoll.")
                                    // TODO(louis): We should not return here, probably
                                    return
                                }
                                linux.close(conn.client_socket)
                                connection_reset(conn)
                                pool_release(conn_pool, conn_idx)
                                continue event_loop
                            }
                        }

                        if .CLOSE in conn.flags {
                            epoll_err := linux.epoll_ctl(efd, .DEL, linux.Fd(conn.client_socket), nil)
                            if epoll_err != .NONE {
                                fmt.eprintln("Cannot remove client socket from epoll.")
                                // TODO(louis): We should not return here, probably
                                return
                            }
                            linux.close(conn.client_socket)
                            connection_reset(conn)
                            pool_release(conn_pool, conn_idx)
                            continue event_loop
                        }
                    }
                }
            }
        }
    }
}

server_loop_io_uring :: proc(
    server_socket: linux.Fd, 
    conn_pool: ^Connection_Pool, 
    asset_store: ^Asset_Store
) {
    ring, errno := io_uring.setup()
    if errno != .NONE {
        fmt.eprintln("Unable to setup io_uring.")
        return
    }

    // TODO(louis): Implement adding to the submission queue and reading from the 
    // completion queue (keep in mind to check the sq_ring flags)

    client_addr: linux.Sock_Addr_In
    client_addr_len := size_of(client_addr)
    errno = io_uring.submit_to_sq_accept(
        &ring, 
        server_socket, 
        &client_addr,
        &client_addr_len,
        SERVER_SOCKET_USER_DATA,
        {.MULTISHOT}
    )

    if errno != .NONE {
        fmt.eprintln("Cannot add multishot accept to submission queue", errno)
        return
    }

    for {
        cqe := io_uring.read_from_cq(&ring)
        if cqe.user_data == SERVER_SOCKET_USER_DATA {
            if cqe.res >= 0 {
                client_fd := linux.Fd(cqe.res)
                conn_idx, pool_err := pool_acquire(conn_pool)
                if !pool_err {
                    conn := &conn_pool.conns[conn_idx]
                    conn.client_socket = client_fd
                    cmd := IO_Uring_Command {
                        conn_idx = conn_idx,
                        command = .RECV
                    }
                    errno = io_uring.submit_to_sq_recv(
                        &ring, 
                        client_fd, 
                        conn.parser.buffer,
                        u64(cmd),
                        {}
                    )

                    if errno != .NONE {
                        linux.close(conn.client_socket)
                        connection_reset(conn)
                        pool_release(conn_pool, conn_idx)
                    }
                } else {
                    linux.close(client_fd)
                }
            } else {
                fmt.eprintln("Cannot accept on server socket", linux.Errno(-cqe.res))
                return
            }
        } else {
            // TODO(louis): Verify that the user data cannot collide
            ioring_cmd := IO_Uring_Command(cqe.user_data)
            conn_idx := ioring_cmd.conn_idx
            cmd := ioring_cmd.command
            conn := &conn_pool.conns[conn_idx]
            if cqe.res >= 0 {
                #partial switch cmd {
                case .RECV:
                    conn.parser.prev_offset = conn.parser.offset
                    conn.parser.offset += u32(cqe.res)
                    handle_connection(conn, asset_store)
                    if .READ in conn.flags {
                        cmd := IO_Uring_Command {
                            conn_idx = conn_idx,
                            command = .RECV
                        }
                        errno = io_uring.submit_to_sq_recv(
                            &ring, 
                            linux.Fd(conn.client_socket), 
                            conn.parser.buffer[conn.parser.offset:],
                            u64(cmd),
                            {}
                        )

                        // TODO(louis): Should we close the connection when our cq overflows?
                        // There may be another write in flight, should we close this then?
                        if errno != .NONE {
                            linux.close(conn.client_socket)
                            connection_reset(conn)
                            pool_release(conn_pool, conn_idx)
                        }
                    }

                    if .WRITE in conn.flags {
                        cmd := IO_Uring_Command {
                            conn_idx = conn_idx,
                            command = .SEND
                        }
                        errno = io_uring.submit_to_sq_send(
                            &ring, 
                            linux.Fd(conn.client_socket), 
                            conn.writer.buffer[:conn.writer.offset],
                            u64(cmd),
                            {.NOSIGNAL}
                        )

                        // TODO(louis): Should we close the connection when our cq overflows?
                        if errno != .NONE {
                            linux.close(conn.client_socket)
                            connection_reset(conn)
                            pool_release(conn_pool, conn_idx)
                        }
                    } else if .CLOSE in conn.flags {
                        assert(.READ not_in conn.flags)
                        linux.close(conn.client_socket)
                        connection_reset(conn)
                        pool_release(conn_pool, conn_idx)
                    }
                case .SEND:
                    if .CLOSE in conn.flags {
                        linux.close(conn.client_socket)
                        connection_reset(conn)
                        pool_release(conn_pool, conn_idx)
                    } else {
                        conn.writer.offset = 0
                    }
                case:
                    assert(false)
                }
            } else {
                linux.close(conn.client_socket)
                connection_reset(conn)
                pool_release(conn_pool, conn_idx)
            }
        }
    }
}

when IO_URING {
    server_loop :: server_loop_io_uring
} else {
    server_loop :: server_loop_epoll
}

linux_read_time :: proc() -> (result: u64) {
    ts, errno := linux.clock_gettime(.MONOTONIC)
    assert(errno == .NONE)
    result = u64(1_000_000_000) * u64(ts.time_sec) + u64(ts.time_nsec)
    return
}

main :: proc() {
    start_startup := linux_read_time() 
    socket, err := init_socket()
    if err != nil {
        fmt.eprintln("Unable to init socket: ", err)
        return
    } 


    base_ptr, base_memory_err := linux.mmap(
        0, uint(MEMORY), {.READ, .WRITE}, 
        {.PRIVATE, .ANONYMOUS}, -1, 0
    )
    if base_memory_err != .NONE {
        fmt.eprintln("Failed to acquire base memory")
        return
    }
    // base_ptr = posix.mmap(rawptr(uintptr(0)), uint(MEMORY), {.READ, .WRITE}, {.PRIVATE, .ANONYMOUS }, -1, 0)

    base_memory: Arena
    arena_init(
        &base_memory,
        uintptr(base_ptr),
        uintptr(MEMORY)
    )

    conn_pools: [NTHREADS]Connection_Pool
    conn_arenas: [NTHREADS]mem.Arena
    for idx in 0..<len(conn_pools) {
        conn_pool := &conn_pools[idx]
        conn_arena := &conn_arenas[idx]
        pool_init_arena(conn_pool, CONNS_PER_THREAD, &base_memory)
    }


    asset_store: Asset_Store
    asset_store_err := asset_store_init(&asset_store, &base_memory)
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

    elapsed_startup := linux_read_time() - start_startup
    fmt.printfln("Startup time: %.2f μs", f64(elapsed_startup)/1_000.0)
    server_loop(socket, &conn_pools[0], &asset_store)
}

init_socket :: proc() -> (socket: linux.Fd, err: net.Network_Error) {
    // socket := net.create_socket(.IP4, .TCP) or_return // this is theoretically platform-agnostic but whatever
    // socket = socket.(net.TCP_Socket)
    endpoint := net.Endpoint{ 
        net.IP4_Address{0, 0, 0, 0},
        8080
    }

    socket_net := net.listen_tcp(endpoint) or_return
    socket = linux.Fd(socket_net)
    // TODO(louis): Use the posix api to setup the socket
    return
}

