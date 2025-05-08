package http

import "core:fmt"
import "core:net"
import "core:mem"
import "base:runtime"

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
        fmt.println("Unable to init socket: ", err)
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
    for {
        client, source, err = net.accept_tcp(socket)
        if err != nil {
            fmt.println("Unable to accept on socket: ", err)
            return
        }

        conn_idx, pool_err := pool_acquire(&conn_pool, client)
        if pool_err {
            fmt.println("No free connection slots available")
            return
        }

        client_conn: ^Client_Connection = &conn_pool.used[conn_idx]
        loop: for {
            // TODO(louis): Probably we want the read from the socket to go here as well
            #partial switch handle_connection(client_conn) {
            case .Closed:
                pool_release(&conn_pool, conn_idx)
                break loop
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
