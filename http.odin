#+vet !using-stmt !using-param
package http

import "core:net"
import "core:fmt"
import "core:mem"
import "base:runtime"
import "core:hash/xxhash"

// TODO(louis): Maybe implement this as a hashmap in the future 
CONNS_PER_THREAD :: 128
CONN_REQ_BUF_SIZE :: 2 * mem.Megabyte
CONN_RES_BUF_SIZE :: 2 * mem.Megabyte
CONN_SCRATCH_SIZE :: 4 * mem.Megabyte // This includes the header map as well as the output buffer for compressed content
MEM_PER_CONN :: size_of(Client_Connection) + CONN_REQ_BUF_SIZE + CONN_RES_BUF_SIZE + CONN_SCRATCH_SIZE
NTHREADS :: 6

MAX_ASSET_SIZE :: 1 * mem.Megabyte
ASSET_CONTENT_MEMORY :: ASSET_COUNT * MAX_ASSET_SIZE
ASSET_MEMORY :: ASSET_COUNT * size_of(Asset) + ASSET_CONTENT_MEMORY
MEMORY : u64 : NTHREADS * 2 * CONNS_PER_THREAD * MEM_PER_CONN 
BUCKET_COUNT :: 128

Http_Header_Entry :: struct {
    // TODO(louis): We might want to have the key directly stored in the header
    name: []u8 `fmt:"s"`,
    value: []u8 `fmt:"s"`,
    next: ^Http_Header_Entry
}

Http_Header_Map :: struct {
    buckets: []Http_Header_Entry,
    count: u32
}

Status_Code :: bit_field u16 {
    offset: u8 | 8,
    type: u8 | 8
}

Http_Status_Code :: enum u16 {
    Continue = 1 << 8,
    Switching_Protocols = 1 << 8 | 1,
    OK = 2 << 8,
    Created = 2 << 8 | 1,
    Accepted = 2 << 8 | 2,
    Multiple_Choices = 3 << 8,
    Moved_Permanently = 3 << 8 | 1,
    Found = 3 << 8 | 2,
    Bad_Request = 4 << 8,
    Unauthorized = 4 << 8 | 1,
    Payment_Required = 4 << 8 | 2,
    Forbidden = 4 << 8 | 3,
    Not_Found = 4 << 8 | 4,
    Request_Entity_Too_Large = 4 << 8 | 13,
    Internal_Server_Error = 5 << 8,
    Not_Implemented = 5 << 8 | 1,
    Bad_Gateway = 5 << 8 | 2,
    Service_Unavailable = 5 << 8 | 3
}

Http_Method :: enum {
    Get, 
    Post
}

Http_Version :: enum {
    Version_1_1
}

Http_Request :: struct {
    header_map: Http_Header_Map,
    method: Http_Method,
    uri: []u8 `fmt:"s"`,
    body: []u8 `fmt:"s"`,
    version: Http_Version
}

Parser_State :: enum {
    IncompleteHeader = 0,
    CompleteHeader = 1,
    CompleteMessage = 2, 
    Error = 3
}

Http_Parser :: struct {
    parser_state: Parser_State,
    message_length: u32,
    header_end: u32,
    buffer: []u8 `fmt:"s"`,
    offset: u32,
    prev_offset: u32
}

Http_Response :: struct {
    header_map: Http_Header_Map,  
    body: []u8,
    status_code: Http_Status_Code,
}

header_map_init_unchecked :: proc(header_map: ^Http_Header_Map, arena: ^Arena) {
    header_map.buckets = arena_push_array_unchecked(arena, Http_Header_Entry, BMAX_ASSET_SIZE
    header_map.count = 0
}

header_map_init :: proc(header_map: ^Http_Header_Map, arena: runtime.Allocator) {
    header_map.buckets = make([]Http_Header_Entry, BUCKET_COUNT, arena)
    header_map.count = 0
}

header_map_reset :: proc(header_map: ^Http_Header_Map) {
    using header_map
    count = 0
    for &bucket in buckets {
        bucket.name = nil
    }
}

header_map_insert_precomputed :: proc(header_map: ^Http_Header_Map, name: []u8, value: []u8, digest: u64) -> (err: bool) {
    using header_map
    for idx := 0; idx < len(buckets); idx += 1 {
        key_idx := (digest + u64(idx)) & (BUCKET_COUNT - 1)
        field := &buckets[key_idx]

        if field.name == nil {
            field.name = name
            field.value = value
            count += 1
            return
        }
        // TODO(louis): What about duplicates?
    }

    err = true
    return
}

header_map_insert :: proc(header_map: ^Http_Header_Map, name: []u8, value: []u8) -> (err: bool) {
    using header_map
    digest := xxhash.XXH3_64_default(name)

    for idx := 0; idx < len(buckets); idx += 1 {
        key_idx := (digest + u64(idx)) & (BUCKET_COUNT - 1)
        field := &buckets[key_idx]

        if field.name == nil {
            field.name = name
            field.value = value
            count += 1
            return
        }
        // TODO(louis): What about duplicates?
    }

    err = true
    return
}

header_map_get_precomputed :: proc(header_map: ^Http_Header_Map, name: []u8, digest: u64) -> (result: []u8, err: bool) {
    using header_map 

    for idx := 0; idx < len(buckets); idx += 1 {
        key_idx := (digest + u64(idx)) & (BUCKET_COUNT - 1)
        field := &buckets[key_idx]

        if field.name == nil {
            err = true
            return
        }

        if memory_compare(field.name, name) {
            result = field.value
            return
        }
    }

    err = true
    return
}


header_map_get :: proc(header_map: ^Http_Header_Map, name: []u8) -> (result: []u8, err: bool) {
    using header_map
    digest := xxhash.XXH3_64_default(name)

    for idx := 0; idx < len(buckets); idx += 1 {
        key_idx := (digest + u64(idx)) & (BUCKET_COUNT - 1)
        field := &buckets[key_idx]
        if field.name == nil {
            err = true
            return
        }

        if memory_compare(field.name, name) {
            result = field.value
            return
        }
    }

    err = true
    return
}

parse_header :: proc(connection: ^Client_Connection) {
    // TODO(louis): Try this with a tokenization approach, might be easier
    using connection.parser
    method_end, found := memory_find_char(buffer[:header_end], ' ')

    if !found {
        parser_state = .Error
        return
    }

    switch {
    case memory_compare(buffer[:method_end], transmute([]u8)GET_LITERAL):
        connection.request.method = .Get
    case memory_compare(buffer[:method_end], transmute([]u8)POST_LITERAL):
        connection.request.method = .Post
    case:
        parser_state = .Error
        return
    }

    uri_start := method_end + 1
    uri_end, found_uri := memory_find_char(buffer[uri_start:header_end], ' ')
    if !found_uri {
        parser_state = .Error
        return
    }

    uri_end += uri_start
    connection.request.uri = buffer[uri_start:uri_end]
    version_start := uri_end + 1
    version_end, found_version := memory_find(buffer[version_start:header_end], transmute([]u8)CRLF)
    if !found_version {
        parser_state = .Error
        return
    }

    version_end += version_start
    switch {    
    case memory_compare(buffer[version_start:version_end], transmute([]u8)HTTP_VERSION_1_1_LITERAL):
        connection.request.version = .Version_1_1
    case:
        parser_state = .Error
        return
    }

    if version_end + 2 > header_end {
        parser_state = .Error
        return
    }

    if !memory_compare(buffer[version_end:version_end+2], transmute([]u8)CRLF) {
        parser_state = .Error
        return
    }

    message_header_buffer := buffer[version_end+u32(len(CRLF)):header_end]
    for len(message_header_buffer) > 0 {
        value_end, found_crlf := memory_find(message_header_buffer, transmute([]u8)CRLF)
        if !found_crlf {
            parser_state = .Error
            return
        }

        name_end, found_colon := memory_find_char(message_header_buffer[:value_end], ':')
        if !found_colon {
            parser_state = .Error
            return
        }

        name := message_header_buffer[:name_end]
        if message_header_buffer[name_end+1] == ' ' {
            name_end += 1
        }

        value := message_header_buffer[name_end+1:value_end]
        message_header_buffer = message_header_buffer[value_end+u32(len(CRLF)):]

        err := header_map_insert(&connection.request.header_map, name, value)
        if err {
            parser_state = .Error
            return
        }
    }

    parser_state = .CompleteHeader
}

Connection_State :: enum {
    KeepAlive,
    Close
}

handle_request :: proc(conn: ^Client_Connection, asset_store: ^Asset_Store) {
    switch conn.request.method {
    case .Post:
    case .Get:
        // TODO(louis): Verify that it is not possible to have a uri of length zero
        content, asset_err := asset_store_get(asset_store, conn.request.uri[1:])
        if !asset_err {
            conn.response.body = content
            content_length := u32_to_string(u32(len(content)), &conn.arena)
            err := header_map_insert_precomputed(
                &conn.response.header_map, 
                CONTENT_LENGTH_LITERAL, 
                content_length, 
                CONTENT_LENGTH_HASH
            )
            assert(!err)
            conn.response.status_code = .OK
        } else {
            // TODO(louis): We should probably consider reporting back that we should close the connection
            conn.response.status_code = .Not_Found
            err: bool
            // TODO(louis): These should not happen
            err = header_map_insert_precomputed(
                &conn.response.header_map, 
                CONNECTION_LITERAL, 
                CLOSE_LITERAL, 
                CONNECTION_HASH
            )
            assert(!err)
            err = header_map_insert_precomputed(
                &conn.response.header_map, 
                CONTENT_LENGTH_LITERAL, 
                ZERO_LITERAL, 
                CONTENT_LENGTH_HASH 
            )
            assert(!err)
        }
    }

    return
}

// TODO(louis): Handle the errors, please
write_response :: proc(conn: ^Client_Connection) {
    conn.flags |= {.WRITE}
    write(&conn.writer, HTTP_VERSION_1_1_LITERAL)   
    write(&conn.writer, u8(' '))   
    status_code := lookup_status_code(conn.response.status_code)
    write(&conn.writer, transmute([]u8)status_code)
    for bucket in conn.response.header_map.buckets {
        if bucket.name != nil {
            write(&conn.writer, bucket.name)
            write(&conn.writer, ": ")
            write(&conn.writer, bucket.value)
            write(&conn.writer, CRLF)
        }
    }

    write(&conn.writer, CRLF)
    if conn.response.body != nil {
        write(&conn.writer, conn.response.body)
    }
}

handle_connection :: proc(conn: ^Client_Connection, asset_store: ^Asset_Store) {
    if conn.parser.prev_offset == conn.parser.offset {
        // NOTE(louis): This means nothing was read into the buffer indicating that it is full
        conn.response.status_code = .Request_Entity_Too_Large
        err := header_map_insert_precomputed(
            &conn.response.header_map, 
            CONNECTION_LITERAL, 
            CLOSE_LITERAL, 
            CONNECTION_HASH 
        )
        assert(!err)
        write_response(conn)
        conn.flags = {.WRITE, .CLOSE}
        return
    }

    loop: for {
        http_parse(conn)
        switch conn.parser.parser_state {
        case .CompleteMessage:
            handle_request(conn, asset_store)
            write_response(conn)
            // TODO(louis): Improve detection of complete messages
            if conn.parser.message_length == conn.parser.offset {
                arena_free(&conn.arena) 
                conn.parser.offset = 0
                conn.parser.prev_offset = 0
                conn.parser.parser_state = .IncompleteHeader
                conn.request.body = nil
                conn.response.body = nil
                header_map_reset(&conn.request.header_map)
                header_map_reset(&conn.response.header_map)
                break loop
            }

            assert(conn.parser.message_length > conn.parser.offset)
            memory_copy(conn.parser.buffer, conn.parser.buffer[conn.parser.message_length:conn.parser.offset])
            conn.parser.offset = conn.parser.offset - conn.parser.message_length
            conn.parser.prev_offset = 0
            conn.parser.parser_state = .IncompleteHeader
            conn.request.body = nil
            conn.response.body = nil
            header_map_reset(&conn.request.header_map)
            header_map_reset(&conn.response.header_map)
        case .Error:
            conn.response.status_code = .Bad_Request
            header_map_insert_precomputed(
                &conn.response.header_map, 
                CONNECTION_LITERAL, 
                CLOSE_LITERAL, 
                CONNECTION_HASH
            )
            write_response(conn)
            // TODO(louis): Where should we close our conn?
            conn.flags |= {.CLOSE}
            break loop
        case .IncompleteHeader, .CompleteHeader:
            conn.flags |= {.READ}
            break loop
        }
    }

    // TODO(louis): Is this really true
    assert(!(.CLOSE in conn.flags && .READ in conn.flags))
    return
}

http_parse :: proc(conn: ^Client_Connection) {
    if conn.parser.parser_state == .IncompleteHeader {
        found_crlf_2x: bool
        corrected_offset := conn.parser.prev_offset if conn.parser.prev_offset < u32(len(CRLF_2x) - 1) else conn.parser.prev_offset - u32(len(CRLF_2x) - 1)
        conn.parser.header_end, found_crlf_2x = memory_find(conn.parser.buffer[conn.parser.prev_offset:conn.parser.offset], CRLF_2x)
        conn.parser.header_end += u32(len(CRLF))
        if found_crlf_2x {
            parse_header(conn)
        }
    }

    if conn.parser.parser_state == .CompleteHeader {
        content_length_str, cl_err := header_map_get_precomputed(&conn.request.header_map, CONTENT_LENGTH_LITERAL, CONTENT_LENGTH_HASH)
        header_length := conn.parser.header_end + u32(len(CRLF))
        if cl_err {
            conn.parser.message_length = header_length
            conn.parser.parser_state = .CompleteMessage
        } else {
            content_length, err := string_to_u32(content_length_str)
            if err {
                conn.parser.parser_state = .Error
                return
            }

            conn.parser.message_length = header_length + content_length
            if conn.parser.message_length > conn.parser.offset {
                conn.parser.parser_state = .Error
            } else {
                conn.parser.parser_state = .CompleteMessage
                conn.request.body = conn.parser.buffer[header_length:conn.parser.message_length]
            }
        }
    }
}
