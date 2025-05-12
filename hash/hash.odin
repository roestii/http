package http_hash

import "core:fmt"
import "core:math/rand"
import "base:runtime"
import "core:mem"
import "core:hash/xxhash"
import core_hash "core:hash"


common_headers := [?][]string {
    {"Host", "www.example.com"},
    {"Connection", "keep-alive"}, // Or "close"
    {"Content-Type", "application/json"}, // Or "text/html", "application/x-www-form-urlencoded", etc.
    {"Content-Length", "123"}, // Example length
    {"User-Agent", "Mozilla/5.0 (YourApp/1.0)"},
    {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"},
    {"Cache-Control", "no-cache"}, // Or "max-age=0"
    {"Accept-Encoding", "gzip, deflate, br"}, // Common encodings
    {"Accept-Language", "en-US,en;q=0.5"}, // Example languages
};

// Less Common Headers (randomly include these for varied test cases)
less_common_headers := [?][]string {
    {"Referer", "https://www.example.com/previous-page"}, // Note the common misspelling "Referer"
    {"Cookie", "sessionid=abcde12345; csrftoken=FGHJK67890"}, // Example cookies
    {"Authorization", "Bearer your_token_here"}, // Example auth token
    {"If-Modified-Since", "Tue, 15 Nov 2022 12:00:00 GMT"}, // Example date
    {"If-None-Match", "\"abcdef123456\""}, // Example ETag value
    {"X-Requested-With", "XMLHttpRequest"}, // Common for AJAX requests
    {"DNT", "1"}, // Do Not Track
    {"Upgrade-Insecure-Requests", "1"},
    {"Via", "1.1 proxy-server"}, // Example proxy
    {"Server", "YourWebServer/1.0"}, // Example server name (often in responses)
    {"ETag", "\"abcdef123456\""}, // Example ETag (often in responses)
    {"Expires", "Tue, 15 Nov 2023 12:00:00 GMT"}, // Example expiration date (often in responses)
    {"Pragma", "no-cache"}, // Older cache control (often in responses)
    {"Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload"}, // HSTS
    {"Content-Security-Policy", "default-src 'self'"}, // CSP
    {"X-Content-Type-Options", "nosniff"}, // Security header
    {"X-Frame-Options", "DENY"}, // Security header
    {"X-XSS-Protection", "1; mode=block"}, // Security header
    {"Access-Control-Allow-Origin", "*"}, // CORS header (often in responses)
    {"X-Forwarded-For", "192.168.1.100"}, // Client IP behind a proxy
    {"X-Api-Key", "your_api_key"}, // Example custom header
    {"Correlation-ID", "a1b2c3d4e5f6"}, // Example tracing header
};

memory_compare :: proc(a: []u8, b: []u8) -> (result: bool) {
    if len(a) != len(b) {
        return
    }

    for idx in 0..<len(a) {
        if a[idx] != b[idx] {
            return
        }
    }

    result = true
    return
}

Http_Header_Entry :: struct {
    key: []u8 `fmt:"s"`, // TODO(louis): Explore indirection of values
    value: []u8,
}

Http_Header_Entry_LL :: struct {
    entry: Http_Header_Entry,
    next: ^Http_Header_Entry_LL
}

Http_Header_Map_LL :: struct {
    arena: runtime.Allocator,
    head: ^Http_Header_Entry_LL
}

ll_insert :: proc(header_map: ^Http_Header_Map_LL, key: []u8, value: []u8, arena: runtime.Allocator) {
    field := new(Http_Header_Entry_LL, arena) 
    field.entry.key = key
    field.entry.value = value
    field.next = header_map.head
    header_map.head = field
}

ll_get :: proc(header_map: ^Http_Header_Map_LL, key: []u8) -> (result: []u8, err: bool) {
    field := header_map.head
    for field != nil {
        if memory_compare(field.entry.key, key) {
            result = field.entry.value
            return
        }

        field = field.next
    }

    err = true
    return
}

Http_Header_Map_Array :: struct {
    array: []Http_Header_Entry,
    len: u32
}

array_init :: proc(header_map: ^Http_Header_Map_Array, size: u32, arena: runtime.Allocator) {
    header_map.array = make([]Http_Header_Entry, size, arena)
    header_map.len = 0
}

array_insert :: proc(header_map: ^Http_Header_Map_Array, key: []u8, value: []u8) {
    // TODO(louis): This should return an error if we can't insert
    header_map.array[header_map.len] = { key, value }
    header_map.len += 1
}

array_get :: proc(header_map: ^Http_Header_Map_Array, key: []u8) -> (result: []u8, err: bool) {
    for idx in 0..<header_map.len {
        field := &header_map.array[idx]
        if memory_compare(field.key, key) {
            result = field.value
            return
        }
    }

    err = true
    return
}

Http_Header_Map_Hash :: struct {
    buckets: []Http_Header_Entry,
    count: u32
}

hash_init :: proc(header_map: ^Http_Header_Map_Hash, size: u32, arena: runtime.Allocator) {
    header_map.buckets = make([]Http_Header_Entry, size, arena)
}

hash_insert :: proc(header_map: ^Http_Header_Map_Hash, key: []u8, value: []u8) {
    using header_map
    // TODO(louis): Check the length and return an error if the map is full
    digest := xxhash.XXH32(key)
    for idx := 0; idx < len(buckets); idx += 1 {
        key_idx := (digest + u32(idx)) % u32(len(buckets))
        field := &buckets[key_idx]
        if field.key == nil {
            field^ = { key, value }
            return
        }
    }
}

hash_clear :: proc(header_map: ^Http_Header_Map_Hash) {
    for &bucket in header_map.buckets {
        bucket.key = nil
    }
}

hash_get :: proc(header_map: ^Http_Header_Map_Hash, key: []u8) -> (result: []u8, err: bool) {
    using header_map
    digest := xxhash.XXH32(key)
    defer count += 1
    
    for idx := 0; idx < len(buckets); idx += 1 {
        key_idx := (digest + u32(idx)) % u32(len(buckets))
        field := buckets[key_idx]
        if field.key == nil {
            err = true
            return
        }

        if memory_compare(field.key, key) {
            result = field.value
            return
        }
    }

    err = true
    return
}

MESSAGE_COUNT :: 100000
TIME_TO_TRY :: 10

Http_Message :: struct {
    fields: []Http_Header_Entry
}

init_messages :: proc(messages: []Http_Message) -> (result: u64) {
    for &msg in messages {
        // TODO(louis): Maybe initialize the distribution and not draw from the rng
        random_field_count := rand.int_max(len(less_common_headers))
        msg.fields = make([]Http_Header_Entry, len(common_headers) + random_field_count, context.temp_allocator)

        for idx in 0..<len(common_headers) {
            field := &msg.fields[idx]
            field.key = transmute([]u8)common_headers[idx][0]
            field.value = transmute([]u8)common_headers[idx][1]
        }

        for idx in 0..<random_field_count {
            field := &msg.fields[len(common_headers)+idx]
            // TODO(louis): Make it such that headers are not chosen two times
            header := rand.choice(less_common_headers[:])
            field.key = transmute([]u8)header[0]
            field.value = transmute([]u8)header[1]
        }

        result += u64(len(common_headers)) + u64(random_field_count)
    }

    return
}

main :: proc() {
    messages := make([]Http_Message, MESSAGE_COUNT, context.temp_allocator)
    field_count := init_messages(messages)
    backing_buffer := make([]u8, 4 * runtime.Megabyte, context.temp_allocator)
    arena: mem.Arena
    mem.arena_init(&arena, backing_buffer)
    tester: Repitition_Tester
    tester_init(&tester, TIME_TO_TRY, "Linked List Header Map")
    arena_alloc := mem.arena_allocator(&arena)
    for tester_is_testing(&tester) {
        tester_begin_time(&tester)
        for msg, idx in messages {
            ll_map: Http_Header_Map_LL
            for field in msg.fields {
                ll_insert(&ll_map, field.key, field.value, arena_alloc)
            }

            #reverse for field in msg.fields {
                // TODO(louis): Maybe we have to do something with the value in order to 
                // not get it optimized away
                value, err := ll_get(&ll_map, field.key)
                assert(!err)
            }

            free_all(arena_alloc)
        }

        tester_end_time(&tester)
    }
    
    tester_count_units(&tester, field_count)
    tester_print(&tester)
    array_tester: Repitition_Tester
    tester_init(&array_tester, TIME_TO_TRY, "Array Header Map")
    array_map: Http_Header_Map_Array
    array_init(&array_map, len(common_headers) + len(less_common_headers), arena_alloc)

    for tester_is_testing(&array_tester) {
        tester_begin_time(&array_tester)
        for msg, idx in messages {
            for field in msg.fields {
                array_insert(&array_map, field.key, field.value)
            }

            #reverse for field in msg.fields {
                // TODO(louis): Maybe we have to do something with the value in order to 
                // not get it optimized away
                value, err := array_get(&array_map, field.key)
                assert(!err)
            }

            array_map.len = 0
        }

        tester_end_time(&array_tester)
    }

    free_all(arena_alloc)
    
    tester_count_units(&array_tester, field_count)
    tester_print(&array_tester)

    hash_tester: Repitition_Tester
    tester_init(&hash_tester, TIME_TO_TRY, "Hash Header Map")
    hash_map: Http_Header_Map_Hash
    hash_init(&hash_map, 503, arena_alloc)

    for tester_is_testing(&hash_tester) {
        tester_begin_time(&hash_tester)
        for msg, idx in messages {
            for field in msg.fields {
                hash_insert(&hash_map, field.key, field.value)
            }

            #reverse for field in msg.fields {
                // TODO(louis): Maybe we have to do something with the value in order to 
                // not get it optimized away
                value, err := hash_get(&hash_map, field.key)
                assert(!err)
            }

            hash_map.count = 0
            hash_clear(&hash_map)
        }

        tester_end_time(&hash_tester)
    }
    
    free_all(arena_alloc)
    tester_count_units(&hash_tester, field_count)
    tester_print(&hash_tester)
}
