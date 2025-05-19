package http_hash

import "core:fmt"
import "core:math/rand"
import "base:runtime"
import "core:mem"
import "core:hash/xxhash"
import "core:hash"

BUCKET_COUNT :: 128

Test_Header :: struct {
    key: []u8,
    value: []u8,
    precomputed_idx: u64,
}

common_headers := [?]Test_Header {
    {transmute([]u8)string("Host"), transmute([]u8)string("www.example.com"), 13416917362057783887 & (BUCKET_COUNT - 1)},
    {transmute([]u8)string("Connection"), transmute([]u8)string("keep-alive"), 13118390000363561740 & (BUCKET_COUNT - 1)}, // Or "close"
    {transmute([]u8)string("Content-Type"), transmute([]u8)string("application/json"), 12804758402103004436 & (BUCKET_COUNT - 1)}, // Or "text/html", "application/x-www-form-urlencoded", etc.
    {transmute([]u8)string("Content-Length"), transmute([]u8)string("123"), 449329715466641104 & (BUCKET_COUNT - 1)}, // Example length
    {transmute([]u8)string("User-Agent"), transmute([]u8)string("Mozilla/5.0 (YourApp/1.0)"), 15681415265888807480 & (BUCKET_COUNT - 1)},
    {transmute([]u8)string("Accept"), transmute([]u8)string("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"), 13352063277170595465 & (BUCKET_COUNT - 1)},
    {transmute([]u8)string("Cache-Control"), transmute([]u8)string("no-cache"), 6683910725962449236 & (BUCKET_COUNT - 1)}, // Or "max-age=0"
    {transmute([]u8)string("Accept-Encoding"), transmute([]u8)string("gzip, deflate, br"), 15371409845389592348 & (BUCKET_COUNT - 1)}, // Common encodings
    {transmute([]u8)string("Accept-Language"), transmute([]u8)string("en-US,en;q=0.5"), 15894663165230168565 & (BUCKET_COUNT - 1)}, // Example languages
};
// Less Common Headers (randomly include these for varied test cases)
less_common_headers := [?]Test_Header {
    {transmute([]u8)string("Referer"), transmute([]u8)string("https://www.example.com/previous-page"), 11861277726012033922 & (BUCKET_COUNT - 1)}, // Note the common misspelling "Referer"
    {transmute([]u8)string("Cookie"), transmute([]u8)string("sessionid=abcde12345; csrftoken=FGHJK67890"), 13696674242553187990 & (BUCKET_COUNT - 1)}, // Example cookies
    {transmute([]u8)string("Authorization"), transmute([]u8)string("Bearer your_token_here"), 8784672000562863350 & (BUCKET_COUNT - 1)}, // Example auth token
    {transmute([]u8)string("If-Modified-Since"), transmute([]u8)string("Tue, 15 Nov 2022 12:00:00 GMT"), 4657765253307276538 & (BUCKET_COUNT - 1)}, // Example date
    {transmute([]u8)string("If-None-Match"), transmute([]u8)string("\"abcdef123456\""), 18376419898620002833 & (BUCKET_COUNT - 1)}, // Example ETag value
    {transmute([]u8)string("X-Requested-With"), transmute([]u8)string("XMLHttpRequest"), 3660188399589234597 & (BUCKET_COUNT - 1)}, // Common for AJAX requests
    {transmute([]u8)string("DNT"), transmute([]u8)string("1"), 18226642915552992130 & (BUCKET_COUNT - 1)}, // Do Not Track
    {transmute([]u8)string("Upgrade-Insecure-Requests"), transmute([]u8)string("1"), 9932066763065563196 & (BUCKET_COUNT - 1)},
    {transmute([]u8)string("Via"), transmute([]u8)string("1.1 proxy-server"), 10395304764522445740 & (BUCKET_COUNT - 1)}, // Example proxy
    {transmute([]u8)string("Server"), transmute([]u8)string("YourWebServer/1.0"), 11499086243070896108 & (BUCKET_COUNT - 1)}, // Example server name (often in responses)
    {transmute([]u8)string("ETag"), transmute([]u8)string("\"abcdef123456\""), 17802453777123907757 & (BUCKET_COUNT - 1)}, // Example ETag (often in responses)
    {transmute([]u8)string("Expires"), transmute([]u8)string("Tue, 15 Nov 2023 12:00:00 GMT"), 14251010686742252949 & (BUCKET_COUNT - 1)}, // Example expiration date (often in responses)
    {transmute([]u8)string("Pragma"), transmute([]u8)string("no-cache"), 512424240408842492 & (BUCKET_COUNT - 1)}, // Older cache control (often in responses)
    {transmute([]u8)string("Strict-Transport-Security"), transmute([]u8)string("max-age=31536000; includeSubDomains; preload"), 5236953830423320535 & (BUCKET_COUNT - 1)}, // HSTS
    {transmute([]u8)string("Content-Security-Policy"), transmute([]u8)string("default-src 'self'"), 12093386995647260114 & (BUCKET_COUNT - 1)}, // CSP
    {transmute([]u8)string("X-Content-Type-Options"), transmute([]u8)string("nosniff"), 11732346818424412208 & (BUCKET_COUNT - 1)}, // Security header {"X-Frame-Options", "DENY", 4313135796493096389}, // Security header
    {transmute([]u8)string("X-XSS-Protection"), transmute([]u8)string("1; mode=block"), 837297764874094624 & (BUCKET_COUNT - 1)}, // Security header
    {transmute([]u8)string("Access-Control-Allow-Origin"), transmute([]u8)string("*"), 18203170181510824321 & (BUCKET_COUNT - 1)}, // CORS header (often in responses)
    {transmute([]u8)string("X-Forwarded-For"), transmute([]u8)string("192.168.1.100"), 6416270139725299187 & (BUCKET_COUNT - 1)}, // Client IP behind a proxy
    {transmute([]u8)string("X-Api-Key"), transmute([]u8)string("your_api_key"), 16070554342849164953 & (BUCKET_COUNT - 1)}, // Example custom header
    {transmute([]u8)string("Correlation-ID"), transmute([]u8)string("a1b2c3d4e5f6"), 9165641619253713877 & (BUCKET_COUNT - 1)}, // Example tracing header
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

hash_init :: proc(header_map: ^Http_Header_Map_Hash, arena: runtime.Allocator) {
    header_map.buckets = make([]Http_Header_Entry, BUCKET_COUNT, arena)
}

hash_insert :: proc(header_map: ^Http_Header_Map_Hash, key: []u8, value: []u8) {
    using header_map
    // TODO(louis): Check the length and return an error if the map is full
    digest := xxhash.XXH3_64_default(key)
    for idx := 0; idx < len(buckets); idx += 1 {
        key_idx := (digest + u64(idx)) & (BUCKET_COUNT - 1)
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

hash_get_precomputed :: proc(
    header_map: ^Http_Header_Map_Hash, 
    key: []u8, 
    digest: u64
) -> (result: []u8, err: bool) {
    using header_map

    for idx := 0; idx < len(buckets); idx += 1 {
        key_idx := (digest + u64(idx)) & (BUCKET_COUNT - 1)
        field := buckets[key_idx]
        if field.key == nil {
            err = true
            return
        }

        if memory_compare(key, field.key) {
            result = field.value
            return
        }
    }

    err = true
    return
}

hash_get :: proc(header_map: ^Http_Header_Map_Hash, key: []u8) -> (result: []u8, err: bool) {
    using header_map
    digest := xxhash.XXH3_64_default(key)
    for idx := 0; idx < len(buckets); idx += 1 {
        key_idx := (digest + u64(idx)) & (BUCKET_COUNT - 1)
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
    fields: []Test_Header
}

init_messages :: proc(messages: []Http_Message) -> (result: u64) {
    unused_fields := make([]u32, len(less_common_headers), context.temp_allocator)
    for &msg in messages {
        unused_field_count := len(unused_fields)
        for &unused_field, idx in unused_fields {
            unused_field = u32(idx)
        }
        // TODO(louis): Maybe initialize the distribution and not draw from the rng
        random_field_count := rand.int_max(len(less_common_headers))
        msg.fields = make([]Test_Header, len(common_headers)+random_field_count, context.temp_allocator)
        for idx in 0..<len(common_headers) {
            field := &msg.fields[idx]
            field^ = common_headers[idx]
        }
        for idx in 0..<random_field_count {
            field := &msg.fields[len(common_headers)+idx]
            field_idx := rand.choice(unused_fields[:unused_field_count])
            field^ = less_common_headers[field_idx]
            unused_field_count -= 1
            unused_fields[field_idx] = unused_fields[unused_field_count]
        }

        result += u64(len(common_headers)) + u64(random_field_count)
    }

    return
}

/* main :: proc() {
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

            for field in msg.fields {
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

            for field in msg.fields {
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
    hash_init(&hash_map, arena_alloc)

    for tester_is_testing(&hash_tester) {
        tester_begin_time(&hash_tester)
        for msg, idx in messages {
            for field in msg.fields {
                hash_insert(&hash_map, field.key, field.value)
            }

            for field in msg.fields {
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
} */
