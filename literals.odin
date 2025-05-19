package http

CRLF_2x := transmute([]u8)string("\r\n\r\n")
CRLF := CRLF_2x[:2]
GET_LITERAL := transmute([]u8)string("GET")
POST_LITERAL := transmute([]u8)string("POST")
HTTP_VERSION_1_1_LITERAL := transmute([]u8)string("HTTP/1.1")
CONTENT_LENGTH_LITERAL := transmute([]u8)string("Content-Length")
ZERO_LITERAL := transmute([]u8)string("0")
CLOSE_LITERAL := transmute([]u8)string("Close")
CONNECTION_LITERAL := transmute([]u8)string("Connection")

HOST_HASH :: 13416917362057783887 & (BUCKET_COUNT - 1)
CONNECTION_HASH :: 13118390000363561740 & (BUCKET_COUNT - 1) // Or "clos
CONTENT_TYPE_HASH :: 12804758402103004436 & (BUCKET_COUNT - 1) // Or "text/html", "application/x-www-form-urlencoded", et
CONTENT_LENGTH_HASH :: 449329715466641104 & (BUCKET_COUNT - 1) // Example leng
USER_HASH :: 15681415265888807480 & (BUCKET_COUNT - 1)
ACCEPT_HASH :: 13352063277170595465 & (BUCKET_COUNT - 1)
CACHE_CONTROL_HASH :: 6683910725962449236 & (BUCKET_COUNT - 1) // Or "max-age=
ACCEPT_ENCODING_HASH :: 15371409845389592348 & (BUCKET_COUNT - 1) // Common encodin
ACCEPT_LANGUAGE_HASH :: 15894663165230168565 & (BUCKET_COUNT - 1) // Example languag


// TODO(louis): Complete the error codes
status_codes := [?][][]u8{
    { 
        transmute([]u8)string("100 Continue\r\n"),
        transmute([]u8)string("101 Switching protocols\r\n"),
    },
    { 
        transmute([]u8)string("200 OK\r\n"),
        transmute([]u8)string("201 Created\r\n"),
        transmute([]u8)string("202 Accepted\r\n"),
    },
    {
        transmute([]u8)string("300 Multiple Choices\r\n"),
        transmute([]u8)string("301 Moved Permanently\r\n"),
        transmute([]u8)string("302 Found\r\n"),
    },
    {
        transmute([]u8)string("400 Bad Request\r\n"),
        transmute([]u8)string("401 Unauthorized\r\n"),
        transmute([]u8)string("402 Payment Required\r\n"),
        transmute([]u8)string("403 Forbidden\r\n"),
        transmute([]u8)string("404 Not Found\r\n"),
        transmute([]u8)string("405 Method Not Allowed"),
        transmute([]u8)string("406 Not Acceptable"),
        transmute([]u8)string("407 Proxy Authentication Required"),
        transmute([]u8)string("408 Request Timeout"),
        transmute([]u8)string("409 Conflict"),
        transmute([]u8)string("410 Gone"),
        transmute([]u8)string("411 Length Required"),
        transmute([]u8)string("412 Precondition Failed"),
        transmute([]u8)string("413 Request Entity Too Large"),
        transmute([]u8)string("414 URI Too Long"),
        transmute([]u8)string("415 Unsupported Media Type"),
        transmute([]u8)string("416 Range Not Satisfiable"),
        transmute([]u8)string("417 Expectation Failed"),
        transmute([]u8)string("418 I'm a teapot"),
    },
    {
        transmute([]u8)string("500 Internal Server Error\r\n"),
        transmute([]u8)string("501 Not Implemented\r\n"),
        transmute([]u8)string("502 Bad Gateway\r\n"),
        transmute([]u8)string("503 Service Unavailable\r\n")
    }
}

lookup_status_code :: proc(status_code: Http_Status_Code) -> (result: []u8) {
    code := Status_Code(status_code)
    result = status_codes[code.type - 1][code.offset]
    return
}

