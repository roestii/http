#+build linux

package io_uring

import "core:sys/linux"
import "core:fmt"

ENTRY_COUNT :: 64
SQ_THREAD_IDLE :: 2000

IO_Ring :: struct {
    ring_fd: linux.Fd,
    sring_tail: ^u32,
    sring_mask: ^u32,
    // These flags have to be checked for NEED_WAKEUP
    sring_flags: ^u32,
    cring_tail: ^u32,
    cring_head: ^u32,
    cring_mask: ^u32,
    // cring_flags: ^u32,
    sq_entries: []IO_Uring_Sqe,
    cq_entries: []IO_Uring_Cqe,
}

setup :: proc() -> (result: IO_Ring, err: linux.Errno) {
    params: IO_Uring_Params
    params.flags = { .SQPOLL }
    params.sq_thread_idle = SQ_THREAD_IDLE
    result.ring_fd = linux.Fd(sys_io_uring_setup(ENTRY_COUNT, &params))
    if result.ring_fd < 0 {
        err = linux.Errno(result.ring_fd)
        return
    }
    assert(.SINGLE_MMAP in params.features)
    sring_size := params.sq_off.array + params.sq_entries * size_of(u32)
    cring_size := params.cq_off.cqes + params.cq_entries * size_of(IO_Uring_Cqe)
    if cring_size > sring_size {
        sring_size = cring_size
    }

    sq_ptr, sq_ptr_mmap_errno := linux.mmap(
        0, 
        uint(sring_size), 
        {.READ, .WRITE}, 
        {.SHARED, .POPULATE}, 
        result.ring_fd,
        i64(IORING_OFF_SQ_RING)
    )

    if sq_ptr_mmap_errno != .NONE {
        err = sq_ptr_mmap_errno
        return
    }

    cq_ptr := sq_ptr
    sq_entries_raw, sqe_mmap_errno := (linux.mmap(
        0,
        uint(params.sq_entries * size_of(IO_Uring_Sqe)),
        {.READ, .WRITE},
        {.SHARED, .POPULATE},
        result.ring_fd,
        i64(IORING_OFF_SQES)
    ))
    if sqe_mmap_errno != .NONE {
        err = sqe_mmap_errno
        return
    }

    result.sring_tail = transmute(^u32)(uintptr(sq_ptr) + uintptr(params.sq_off.tail))
    result.sring_mask = transmute(^u32)(uintptr(sq_ptr) + uintptr(params.sq_off.ring_mask))
    result.sring_flags = transmute(^u32)(uintptr(sq_ptr) + uintptr(params.sq_off.flags))
    result.sq_entries = (transmute([^]IO_Uring_Sqe)sq_entries_raw)[:params.sq_entries]

    result.cring_tail = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.tail))
    result.cring_mask = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.ring_mask))
    // result.cring_flags = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.flags))
    result.cq_entries = (transmute([^]IO_Uring_Cqe)(uintptr(cq_ptr) + uintptr(params.cq_off.cqes)))[:params.cq_entries]
    return
}
