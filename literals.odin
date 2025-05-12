package http

CRLF_2x := "\r\n\r\n"
CRLF := CRLF_2x[:2]
GET_LITERAL := "GET"
POST_LITERAL := "POST"
HTTP_VERSION_1_1_LITERAL := "HTTP/1.1"
CONTENT_LENGTH_LITERAL := "Content-Length"
ZERO_LITERAL := "0"

CLOSE_LITERAL := "Close"
CONNECTION_LITERAL := "Connection"


// TODO(louis): Complete the error codes
status_codes := [?][]string{
    { 
        "100 Continue\r\n",
        "101 Switching protocols\r\n",
    },
    { 
        "200 OK\r\n",
        "201 Created\r\n",
        "202 Accepted\r\n",
    },
    {
        "300 Multiple Choices\r\n",
        "301 Moved Permanently\r\n",
        "302 Found\r\n",
    },
    {
        "400 Bad Request\r\n",
        "401 Unauthorized\r\n",
        "402 Payment Required\r\n",
        "403 Forbidden\r\n",
        "404 Not Found\r\n"
    },
    {
        "500 Internal Server Error\r\n",
        "501 Not Implemented\r\n",
        "502 Bad Gateway\r\n",
        "503 Service Unavailable\r\n"
    }
}

lookup_status_code :: proc(status_code: Http_Status_Code) -> (result: string) {
    code := Status_Code(status_code)
    result = status_codes[code.type - 1][code.offset]
    return
}

