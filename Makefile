http: http.odin connection.odin assets.odin writer.odin memory.odin literals.odin http_linux.odin http_darwin.odin io_uring/sys.odin io_uring/ioring.odin
	odin build . -o:none -debug

clean:
	rm http
