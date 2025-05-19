#+vet !using-stmt !using-param
package http

import "core:net"
import "core:fmt"
import "core:mem"
import "base:runtime"
import "core:hash/xxhash"

// TODO(louis): Maybe implement this as a hashmap in the future 

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

header_map_init :: proc(header_map: ^Http_Header_Map, arena: runtime.Allocator) {
    using header_map
    buckets = make([]Http_Header_Entry, BUCKET_COUNT, arena)
    count = 0
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
    Closed
}

handle_request :: proc(connection: ^Client_Connection, asset_store: ^Asset_Store) {
    using connection
    switch request.method {
    case .Post:
    case .Get:
        // TODO(louis): Verify that it is not possible to have a uri of length zero
        content, asset_err := asset_store_get(asset_store, request.uri[1:])
        if !asset_err {
            response.body = content
            content_length := u32_to_string(u32(len(content)), arena)
            err := header_map_insert_precomputed(
                &response.header_map, 
                CONTENT_LENGTH_LITERAL, 
                content_length, 
                CONTENT_LENGTH_HASH
            )
            assert(!err)
            response.status_code = .OK
        } else {
            // TODO(louis): We should probably consider reporting back that we should close the connection
            response.status_code = .Not_Found
            err: bool
            // TODO(louis): These should not happen
            err = header_map_insert_precomputed(
                &response.header_map, 
                CONNECTION_LITERAL, 
                CLOSE_LITERAL, 
                CONNECTION_HASH
            )
            assert(!err)
            err = header_map_insert_precomputed(
                &response.header_map, 
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
write_response :: proc(connection: ^Client_Connection) {
    using connection
    write(&writer, HTTP_VERSION_1_1_LITERAL)   
    write(&writer, u8(' '))   
    status_code := lookup_status_code(response.status_code)
    write(&writer, transmute([]u8)status_code)
    for bucket in response.header_map.buckets {
        if bucket.name != nil {
            write(&writer, bucket.name)
            write(&writer, ": ")
            write(&writer, bucket.value)
            write(&writer, CRLF)
        }
    }

    write(&writer, CRLF)
    net.send_tcp(client_socket, writer.buffer[:writer.offset])
    if response.body != nil {
        net.send_tcp(client_socket, response.body)
    }
}

handle_connection :: proc(connection: ^Client_Connection, asset_store: ^Asset_Store) -> (result: Connection_State) {
    using connection
    if parser.offset == u32(len(parser.buffer) - 1) {
        response.status_code = .Request_Entity_Too_Large
        err := header_map_insert_precomputed(
            &response.header_map, 
            CONNECTION_LITERAL, 
            CLOSE_LITERAL, 
            CONNECTION_HASH
        )
        assert(!err)
        write_response(connection)
        net.close(client_socket)
        result = .Closed
        return
    }

    bytes_read, err := net.recv_tcp(client_socket, parser.buffer[parser.offset:])
    if err != nil {
        net.close(client_socket)
        result = .Closed
        return
    }

    parser.prev_offset = parser.offset
    parser.offset += u32(bytes_read)
    loop: for {
        http_parse(connection)
        switch parser.parser_state {
        case .CompleteMessage:
            handle_request(connection, asset_store)
            write_response(connection)
            // TODO(louis): Improve detection of complete messages
            if parser.message_length == parser.offset {
                connection_reset(connection)
                break loop
            }

            assert(parser.message_length > parser.offset)
            memory_copy(parser.buffer, parser.buffer[parser.message_length:parser.offset])
            connection_reset_with_offset(connection, parser.offset - parser.message_length)
        case .Error:
            connection.response.status_code = .Bad_Request
            header_map_insert_precomputed(
                &connection.response.header_map, 
                CONNECTION_LITERAL, 
                CLOSE_LITERAL, 
                CONNECTION_HASH
            )
            write_response(connection)
            // TODO(louis): Where should we close our connection?
            net.close(connection.client_socket)
            result = .Closed
            break loop
        case .IncompleteHeader, .CompleteHeader:
            result = .KeepAlive
            break loop
        }
    }

    return
}

http_parse :: proc(connection: ^Client_Connection) {
    using connection.parser
    if parser_state == .IncompleteHeader {
        found_crlf_2x: bool
        corrected_offset := prev_offset if prev_offset < u32(len(CRLF_2x) - 1) else prev_offset - u32(len(CRLF_2x) - 1)
        header_end, found_crlf_2x = memory_find(buffer[prev_offset:offset], transmute([]u8)CRLF_2x)
        header_end += u32(len(CRLF))
        if found_crlf_2x {
            parse_header(connection)
        }
    }

    if parser_state == .CompleteHeader {
        content_length_str, cl_err := header_map_get_precomputed(&connection.request.header_map, CONTENT_LENGTH_LITERAL, CONTENT_LENGTH_HASH)
        header_length := header_end + u32(len(CRLF))
        if cl_err {
            message_length = header_length
            parser_state = .CompleteMessage
        } else {
            content_length, err := string_to_u32(content_length_str)
            if err {
                parser_state = .Error
                return
            }

            message_length = header_length + content_length
            if message_length > offset {
                parser_state = .Error
            } else {
                parser_state = .CompleteMessage
                connection.request.body = buffer[header_length:message_length]
            }
        }
    }
}
