#+build linux

package io_uring

import "core:sys/linux"
import "core:fmt"
import "base:intrinsics"
import "../x86intrin"

ENTRY_COUNT :: 64
SQ_THREAD_IDLE :: 10000

Completion_Ring :: struct {
    tail: ^u32,
    head: ^u32,
    mask: ^u32,
    // flags: ^u32,
    entries: []IO_Uring_Cqe,
}

Submission_Ring :: struct {
    tail: ^u32,
    head: ^u32,
    mask: ^u32,
    // These flags have to be checked for NEED_WAKEUP
    flags: ^IO_Uring_SQ_Flags,
    entries: []IO_Uring_Sqe,
}

IO_Ring :: struct {
    ring_fd: linux.Fd,
    sring: Submission_Ring,
    cring: Completion_Ring,
}

setup :: proc() -> (result: IO_Ring, err: linux.Errno) {
    params: IO_Uring_Params
    params.flags = {.SQPOLL}
    fmt.println("flags", transmute(u32)params.flags)
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
    sq_entries_raw, sqe_mmap_errno := linux.mmap(
        0,
        uint(params.sq_entries * size_of(IO_Uring_Sqe)),
        {.READ, .WRITE},
        {.SHARED, .POPULATE},
        result.ring_fd,
        i64(IORING_OFF_SQES)
    )
    if sqe_mmap_errno != .NONE {
        err = sqe_mmap_errno
        return
    }

    result.sring.tail = transmute(^u32)(uintptr(sq_ptr) + uintptr(params.sq_off.tail))
    result.sring.mask = transmute(^u32)(uintptr(sq_ptr) + uintptr(params.sq_off.ring_mask))
    result.sring.flags = transmute(^IO_Uring_SQ_Flags)(uintptr(sq_ptr) + uintptr(params.sq_off.flags))
    result.sring.entries = (transmute([^]IO_Uring_Sqe)sq_entries_raw)[:params.sq_entries]

    result.cring.tail = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.tail))
    result.cring.head = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.head))
    result.cring.mask = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.ring_mask))
    // result.cring_flags = transmute(^u32)(uintptr(cq_ptr) + uintptr(params.cq_off.flags))
    result.cring.entries = (transmute([^]IO_Uring_Cqe)(uintptr(cq_ptr) + uintptr(params.cq_off.cqes)))[:params.cq_entries]
    return
}

submit_to_sq_send :: proc(
    ioring: ^IO_Ring, 
    fd: linux.Fd, 
    buffer: []u8,
    user_data: u64, 
    flags: bit_set[linux.Socket_Msg_Bits; i32]
) -> (err: linux.Errno) {
    sring_flags := intrinsics.atomic_load(ioring.sring.flags)
    if .CQ_OVERFLOW in sring_flags {
        err = .EBUSY 
        return
    }

    tail := intrinsics.atomic_load(ioring.sring.tail)
    mask := ioring.sring.mask^
    sqe := &ioring.sring.entries[tail & mask]

    sqe.fd = i32(fd)
    sqe.addr = u64(uintptr(raw_data(buffer)))
    sqe.len = u32(len(buffer))
    sqe.user_data = user_data
    sqe.opcode = .SEND
    sqe.msg_flags = transmute(u32)flags
    // The previous stores to the sqe cannot be reordered past the store to the tail
    // TODO(louis): Look at the codegen for the atomic store, in reality we probably just need 
    // a fence here
    intrinsics.atomic_store(ioring.sring.tail, tail + 1)
    sring_flags = intrinsics.atomic_load(ioring.sring.flags)
    if .NEED_WAKEUP in sring_flags {
        enter_flags: IO_Uring_Enter_Flags = {.SQ_WAKEUP, .SQ_WAIT}
        err = linux.Errno(sys_io_uring_enter(
            u32(ioring.ring_fd), 
            0, 
            0, 
            transmute(u32)enter_flags, 
            ([^]Sig_Set)(uintptr(0)))
        )
        // NOTE(louis): No return needed as there is no code following this
    }

    return
}

submit_to_sq_recv :: proc(
    ioring: ^IO_Ring, 
    fd: linux.Fd, 
    buffer: []u8,
    user_data: u64,
    flags: bit_set[linux.Socket_Msg_Bits; i32]
) -> (err: linux.Errno) {
    sring_flags := intrinsics.atomic_load(ioring.sring.flags)
    if .CQ_OVERFLOW in sring_flags {
        err = .EBUSY 
        return
    }

    tail := intrinsics.atomic_load(ioring.sring.tail)
    fmt.println("Submitting recv call", tail)
    mask := ioring.sring.mask^
    sqe := &ioring.sring.entries[tail & mask]

    sqe.fd = i32(fd)
    sqe.addr = u64(uintptr(raw_data(buffer)))
    sqe.len = u32(len(buffer))
    sqe.user_data = user_data
    sqe.opcode = .RECV
    sqe.msg_flags = transmute(u32)flags
    // The previous stores to the sqe cannot be reordered past the store to the tail
    // TODO(louis): Look at the codegen for the atomic store, in reality we probably just need 
    // a fence here
    intrinsics.atomic_store(ioring.sring.tail, tail + 1)
    sring_flags = intrinsics.atomic_load(ioring.sring.flags)
    if .NEED_WAKEUP in sring_flags {
        enter_flags: IO_Uring_Enter_Flags = {.SQ_WAKEUP, .SQ_WAIT}
        err = linux.Errno(sys_io_uring_enter(
            u32(ioring.ring_fd), 
            0, 
            0, 
            transmute(u32)enter_flags, 
            ([^]Sig_Set)(uintptr(0)))
        )
        // NOTE(louis): No return needed as there is no code following this
    }

    return
}

Accept_Bits :: enum {
    MULTISHOT = 0
}

submit_to_sq_accept :: proc(
    ioring: ^IO_Ring, 
    fd: linux.Fd, 
    client_addr: ^linux.Sock_Addr_In, 
    client_addr_len: ^int,
    user_data: u64,
    accept_flags: bit_set[Accept_Bits; u16]
) -> (err: linux.Errno) {
    sring_flags := intrinsics.atomic_load(ioring.sring.flags)
    if .CQ_OVERFLOW in sring_flags {
        err = .EBUSY 
        return
    }

    tail := intrinsics.atomic_load(ioring.sring.tail)
    mask := ioring.sring.mask^
    sqe := &ioring.sring.entries[tail & mask]

    sqe.fd = i32(fd)
    sqe.addr = u64(uintptr(client_addr))
    sqe.len = 0
    sqe.addr2 = u64(uintptr(client_addr_len))
    sqe.user_data = user_data
    sqe.opcode = .ACCEPT
    sqe.ioprio = transmute(u16)accept_flags
    sqe.flags = {.ASYNC}
    // The previous stores to the sqe cannot be reordered past the store to the tail
    // TODO(louis): Look at the codegen for the atomic store, in reality we probably just need 
    // a fence here
    intrinsics.atomic_store(ioring.sring.tail, tail + 1)
    sring_flags = intrinsics.atomic_load(ioring.sring.flags)
    if .NEED_WAKEUP in sring_flags {
        enter_flags: IO_Uring_Enter_Flags = {.SQ_WAKEUP, .SQ_WAIT}
        err = linux.Errno(sys_io_uring_enter(
            u32(ioring.ring_fd), 
            0, 
            0, 
            transmute(u32)enter_flags, 
            transmute([^]Sig_Set)uintptr(0))
        )
        // NOTE(louis): No return needed as there is no code following this
    }

    return
}

read_from_cq :: proc(ioring: ^IO_Ring) -> (result: IO_Uring_Cqe) {
    mask := ioring.cring.mask^
    // TODO(louis): Look at the codegen for the atomic load, in reality we probably just need 
    // a fence here
    // All previous stores should be visible here
    head := intrinsics.atomic_load(ioring.cring.head)
    tail := intrinsics.atomic_load(ioring.cring.tail)
    for head == tail { 
        x86intrin.pause() 
        tail = intrinsics.atomic_load(ioring.cring.tail)
    }

    result = ioring.cring.entries[head & mask]
    fmt.println("Got something: ", result.res)
    // Make the store visible to the kernel thread
    intrinsics.atomic_store(ioring.cring.head, head + 1)
    return
}
