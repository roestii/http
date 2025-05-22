#+build linux

package io_uring

import "core:sys/linux"
import "core:fmt"
import "base:intrinsics"

ENTRY_COUNT :: 64
SQ_THREAD_IDLE :: 2000

IO_Ring :: struct {
    ring_fd: linux.Fd,
    sring_tail: ^u32,
    sring_mask: ^u32,
    // These flags have to be checked for NEED_WAKEUP
    sring_flags: ^IO_Uring_SQ_Flags,
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
    result.sring_flags = transmute(^IO_Uring_SQ_Flags)(uintptr(sq_ptr) + uintptr(params.sq_off.flags))
    result.sq_entries = (transmute([^]IO_Uring_Sqe)sq_entries_raw)[:params.sq_entries]

    result.cring_tail = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.tail))
    result.cring_mask = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.ring_mask))
    // result.cring_flags = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.flags))
    result.cq_entries = (transmute([^]IO_Uring_Cqe)(uintptr(cq_ptr) + uintptr(params.cq_off.cqes)))[:params.cq_entries]
    return
}

submit_to_sq :: proc(ioring: ^IO_Ring, fd: linux.Fd, op: IO_Uring_Op, buffer: []u8, user_data: u64) -> (err: linux.Errno) {
    tail := ioring.sring_tail^
    mask := ioring.sring_mask^
    sqe := &ioring.sq_entries[tail & mask]

    sqe.fd = i32(fd)
    sqe.addr = u64(uintptr(raw_data(buffer)))
    sqe.len = u32(len(buffer))
    sqe.user_data = user_data
    sqe.opcode = op
    // The previous stores to the sqe cannot be reordered past the store to the tail
    intrinsics.atomic_store(ioring.sring_tail, tail + 1)
    if .NEED_WAKEUP in ioring.sring_flags {
        enter_flags: IO_Uring_Enter_Flags = {.SQ_WAKEUP}
        err = linux.Errno(sys_io_uring_enter(
            u32(ioring.ring_fd), 
            1, 
            1, 
            transmute(u32)enter_flags, 
            transmute([^]Sig_Set)uintptr(0))
        )
        // NOTE(louis): No return needed as there is no code following this
    }

    return
}

read_from_cq :: proc(ioring: ^IO_Ring) {
}
