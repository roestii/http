package http

import "core:fmt"
import "core:net"
import "core:mem"
import "base:runtime"

// TODO(louis): Shoudld we have the main function in the platform-specific code or the platform-agnostic code 
// and call into the platform-specific code when needed

// CONSTANTS

CONNS_PER_THREAD :: 128
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

    client: net.TCP_Socket
    source: net.Endpoint
    client, source, err = net.accept_tcp(socket)
    if err != nil {
        fmt.println("Unable to accept on socket: ", err)
        return
    }

    base_memory: mem.Arena
    mem.arena_init(&base_memory, make([]u8, MEMORY, context.temp_allocator))
    defer free_all()
    base_arena := mem.arena_allocator(&base_memory)
    for i in 0..<NTHREADS {
        // TODO(louis): Shouldn't the memory for the client connection with all of it's buffers be contiguous
        // Right now we have a chunk of memory for all connections and then the individual buffers
        conns := make([]Client_Connection, CONNS_PER_THREAD, base_arena)
        // TODO(louis): Is it possible to use a pool allocator (free list allocator) without having to initialize the element 
        // each time we acquire an item? In theory yes if we introduce more overhead, i.e. a block list
        // pool_init(conn_base, CONNS_PER_THREAD)

        for &conn in conns {
            using conn
            writer.buffer = make([]u8, CONN_RES_BUF_SIZE, base_arena)
            parser.buffer = make([]u8, CONN_REQ_BUF_SIZE, base_arena)
            tmp_arena: mem.Arena
            arena_base := make([]u8, CONN_SCRATCH_SIZE, base_arena)
            mem.arena_init(&tmp_arena, arena_base)
            arena = mem.arena_allocator(&tmp_arena)
        }
    }

    // TODO(louis): Please fix this setup code... I want multiple threads and a connection pool
    parser: Http_Parser
    parser.buffer = make([]u8, 2048, context.temp_allocator)
    writer: Writer = {
        make([]u8, 2048, context.temp_allocator),
        0
    }
    arena: mem.Arena
    request: Http_Request
    response: Http_Response;
    base_ptr := make([]u8, 2048, context.temp_allocator)
    mem.arena_init(&arena, base_ptr)

    client_connection: Client_Connection = {
        client,
        mem.arena_allocator(&arena),
        parser,
        request,
        writer,
        response,
    }

    loop: for {
        #partial switch handle_connection(&client_connection) {
        case .Closed:
            break loop
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
