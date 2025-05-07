#+vet !using-stmt !using-param
package http

import "core:net"
import "core:fmt"
import "core:mem"
import "base:runtime"

// TODO(louis): Maybe implement this as a hashmap in the future 
Http_Header_Entry :: struct {
    name: []u8 `fmt:"s"`,
    value: []u8 `fmt:"s"`,
    next: ^Http_Header_Entry
}

Http_Header_Map :: struct {
    head: ^Http_Header_Entry
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
    status_code: u16,
}

Client_Connection :: struct {
    client_socket: net.TCP_Socket,
    arena: runtime.Allocator,
    parser: Http_Parser,
    request: Http_Request,
    writer: Writer,
    response: Http_Response
}

get_value :: proc(header_map: ^Http_Header_Map, name: []u8) -> (value: []u8, found: bool) {
    entry := header_map.head
    for entry != nil {
        if memory_compare(entry.name, name) {
            value = entry.value
            found = true
            return
        }

        entry = entry.next
    }

    found = false
    value = nil
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

        entry := new(Http_Header_Entry, connection.arena)
        entry.name = name
        entry.value = value

        tmp := connection.request.header_map.head
        connection.request.header_map.head = entry
        entry.next = tmp
    }

    parser_state = .CompleteHeader
}

Connection_State :: enum {
    Waiting,
    Closed
}

handle_request :: proc(connection: ^Client_Connection) {
    using connection
    switch request.method {
    case .Post:
    case .Get:
        response.status_code = 0 
    }

    return
}

write_response :: proc(connection: ^Client_Connection) {
    using connection
    write(&writer, transmute([]u8)HTTP_VERSION_1_1_LITERAL)   
    write(&writer, u8(' '))   
    write(&writer, transmute([]u8)StatusCodes[response.status_code])

    if response.body != nil {
        write(&writer, response.body) 
    }

    net.send_tcp(client_socket, writer.buffer)
}

handle_connection :: proc(connection: ^Client_Connection) -> (result: Connection_State) {
    using connection
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
            handle_request(connection)
            write_response(connection)
            assert(parser.message_length <= parser.offset)
            if parser.message_length == parser.offset {
                break loop
            }

            free_all(arena)
            memory_copy(parser.buffer, parser.buffer[parser.message_length:parser.offset])
            length_remaining := parser.offset - parser.message_length
            memory_set(parser.buffer[length_remaining:parser.offset], 0)
            parser.offset = parser.offset - parser.message_length
            request.header_map.head = nil
            parser.prev_offset = 0
            parser.parser_state = .IncompleteHeader
            writer.offset = 0
        case .Error:
            net.close(client_socket)
            result = .Closed
            break loop
        case .IncompleteHeader, .CompleteHeader:
            result = .Waiting
            break loop
        }
    }

    return
}

http_parse :: proc(connection: ^Client_Connection) {
    using connection.parser
    if parser_state == .IncompleteHeader {
        found_crlf_2x: bool
        header_end, found_crlf_2x = memory_find(buffer[prev_offset:offset], transmute([]u8)CRLF_2x)
        header_end += u32(len(CRLF))
        if found_crlf_2x {
            parse_header(connection)
        }
    }

    if parser_state == .CompleteHeader {
        content_length_str, cl_found := get_value(&connection.request.header_map, transmute([]u8)CONTENT_LENGTH_LITERAL)
        header_length := header_end + u32(len(CRLF))
        if !cl_found {
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
