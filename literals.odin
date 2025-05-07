package http

CRLF_2x := "\r\n\r\n"
CRLF := CRLF_2x[:2]
GET_LITERAL := "GET"
POST_LITERAL := "POST"
HTTP_VERSION_1_1_LITERAL := "HTTP/1.1"
CONTENT_LENGTH_LITERAL := "Content-Length"
StatusCodes := [?]string{"200 OK\r\n"}
