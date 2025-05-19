http: http.odin connection.odin assets.odin writer.odin memory.odin literals.odin http_linux.odin http_darwin.odin
	odin build . -o:none -debug

clean:
	rm http
