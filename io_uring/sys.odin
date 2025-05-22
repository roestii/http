#+build linux
package io_uring

import "base:intrinsics"
import "core:sys/linux"

IO_Uring_Cqe :: struct {
    user_data: u64,	/* sqe->data submission passed back */
	res: i32,		/* result code for this event */
	flags: u32,

	/*
	 * If the ring is initialized with IORING_SETUP_CQE32, then this field
	 * contains 16-bytes of padding, doubling the size of the CQE.
	 */
	// __u64 big_cqe[],
}

IO_Uring_Op :: enum u8 {
	NOP,
	READV,
	WRITEV,
	FSYNC,
	READ_FIXED,
	WRITE_FIXED,
	POLL_ADD,
	POLL_REMOVE,
	SYNC_FILE_RANGE,
	SENDMSG,
	RECVMSG,
	TIMEOUT,
	TIMEOUT_REMOVE,
	ACCEPT,
	ASYNC_CANCEL,
	LINK_TIMEOUT,
	CONNECT,
	FALLOCATE,
	OPENAT,
	CLOSE,
	FILES_UPDATE,
	STATX,
	READ,
	WRITE,
	FADVISE,
	MADVISE,
	SEND,
	RECV,
	OPENAT2,
	EPOLL_CTL,
	SPLICE,
	PROVIDE_BUFFERS,
	REMOVE_BUFFERS,
	TEE,
	SHUTDOWN,
	RENAMEAT,
	UNLINKAT,
	MKDIRAT,
	SYMLINKAT,
	LINKAT,
	MSG_RING,
	FSETXATTR,
	SETXATTR,
	FGETXATTR,
	GETXATTR,
	SOCKET,
	URING_CMD,
	SEND_ZC,
	SENDMSG_ZC,

	/* this goes last, obviously */
	LAST,
};

IORING_OFF_SQ_RING :: u64(0)
IORING_OFF_CQ_RING :: u64(0x8000000)
IORING_OFF_SQES :: u64(0x10000000)
IORING_OFF_PBUF_RING :: u64(0x80000000)
IORING_OFF_PBUF_SHIFT :: 16
IORING_OFF_MMAP_MASK :: u64(0xf8000000)

IO_Uring_Enter_Bits :: enum u32 {
    GETEVENTS = 0,
    SQ_WAKEUP =	1,
    SQ_WAIT	= 2,
    EXT_ARG	= 3,
    REGISTERED_RING = 4
}

IO_Uring_Enter_Flags :: bit_set[IO_Uring_Enter_Bits; u32]

IO_Uring_SQ_Bits :: enum {
    NEED_WAKEUP = 0, /* needs io_uring_enter wakeup */
    CQ_OVERFLOW = 1, /* CQ ring is overflown */
    TASKRUN = 2 /* task should enter the kernel */
}

IO_Uring_SQ_Flags :: bit_set[IO_Uring_SQ_Bits; u32]

IO_Uring_Feat_Bits :: enum u32 {
    SINGLE_MMAP = 0,
    NODROP = 1,
    SUBMIT_STABLE = 2,
    RW_CUR_POS = 3,
    CUR_PERSONALITY	= 4,
    FAST_POLL = 5,
    POLL_32BITS = 6,
    SQPOLL_NONFIXED	= 7,
    EXT_ARG = 8,
    NATIVE_WORKERS = 9,
    RSRC_TAGS = 10,
    CQE_SKIP = 11,
    LINKED_FILE	= 12,
    REG_REG_RING = 13,
}

IO_Uring_Features :: bit_set[IO_Uring_Feat_Bits; u32]

IO_Uring_Setup_Bits :: enum u32 {
    IOPOLL = 0,	/* io_context is polled */
    SQPOLL = 1,	/* SQ poll thread */
    SQ_AFF = 2,	/* sq_thread_cpu is valid */
    CQSIZE = 3,	/* app defines CQ size */
    CLAMP = 4,	/* clamp SQ/CQ ring sizes */
    ATTACH_WQ = 5,	/* attach to existing wq */
    R_DISABLED = 6,	/* start with ring disabled */
    SUBMIT_ALL = 7,	/* continue submit on error */
}

IO_Uring_Setup_Flags :: bit_set[IO_Uring_Setup_Bits; u32]

IO_Uring_Params :: struct {
    sq_entries: u32,
    cq_entries: u32,
    flags: IO_Uring_Setup_Flags,
    sq_thread_cpu: u32,
    sq_thread_idle: u32,
    features: IO_Uring_Features,
    wq_fd: u32,
	resv: [3]u32,
    sq_off: IO_Sqring_Offsets,
    cq_off: IO_Cqring_Offsets,
}

IO_Sqring_Offsets :: struct {
    head: u32,
	tail: u32,
	ring_mask: u32,
	ring_entries: u32,
	flags: u32,
	dropped: u32,
	array: u32,
	resv1: u32,
	user_addr: u64
}

IO_Cqring_Offsets :: struct {
    head: u32,
	tail: u32,
	ring_mask: u32,
	ring_entries: u32,
	overflow: u32,
	cqes: u32,
	flags: u32,
	resv1: u32,
	user_addr: u64
}

IOSQE_FIXED_FILE_BIT :: 0
IOSQE_IO_DRAIN_BIT :: 1
IOSQE_IO_LINK_BIT :: 2
IOSQE_IO_HARDLINK_BIT :: 3
IOSQE_ASYNC_BIT :: 4
IOSQE_BUFFER_SELECT_BIT :: 5
IOSQE_CQE_SKIP_SUCCESS_BIT :: 6

IO_Sqe_Bits :: enum {
    /* use fixed fileset */
    FIXED_FILE = IOSQE_FIXED_FILE_BIT,
    /* issue after inflight IO */
    IO_DRAIN = IOSQE_IO_DRAIN_BIT,
    /* links next sqe */
    IO_LINK	= IOSQE_IO_LINK_BIT,
    /* like LINK, but stronger */
    IO_HARDLINK	= IOSQE_IO_HARDLINK_BIT,
    /* always go async */
    ASYNC = IOSQE_ASYNC_BIT,
    /* select buffer from sqe->buf_group */
    BUFFER_SELECT = IOSQE_BUFFER_SELECT_BIT,
    /* don't post CQE if request succeeded */
    CQE_SKIP_SUCCESS = IOSQE_CQE_SKIP_SUCCESS_BIT
}

IO_Sqe_Flags :: bit_set[IO_Sqe_Bits; u8]

IO_Uring_Sqe :: struct {
    opcode: IO_Uring_Op,		/* type of operation for this sqe */
	flags: IO_Sqe_Flags,		/* IOSQE_ flags */
	ioprio: u16,		/* ioprio for the request */
	fd: i32,		/* file descriptor to do IO on */
	using _: struct #raw_union {
        off: u64,	/* offset into file */
		addr2: u64,
		_: struct {
            cmd_op: u32,
			__pad1: u32,
		},
	},
    using _: struct #raw_union {
        addr: u64,	/* pointer to buffer or iovecs */
		splice_off_in: u64,
	},
    len: u32,	/* buffer size or number of iovecs */
	using _: struct #raw_union {
        rw_flags: i32, // TODO(louis): this is a __kernel_rwf_t which is supposed to be an int
        fsync_flags: u32,
        poll_events: u32,	/* compatibility */
        poll32_events: u32,	/* word-reversed for BE */
		sync_range_flags: u32,
		msg_flags: u32,
		timeout_flags: u32,
		accept_flags: u32,
		cancel_flags: u32,
		open_flags: u32,
		statx_flags: u32,
		fadvise_advice: u32,
		splice_flags: u32,
		rename_flags: u32,
		unlink_flags: u32,
		hardlink_flags: u32,
		xattr_flags: u32,
		msg_ring_flags: u32,
		uring_cmd_flags: u32,
	},
    user_data: u64,	/* data to be passed back at completion time */
	/* pack this to avoid bogus arm OABI complaints */
	using _: struct #raw_union {
		/* index into fixed buffers, if used */
        buf_index: u16,
		/* for grouped buffer selection */
		buf_group: u16
	},
	/* personality to use, if used */
    personality: u16,
    using _: struct #raw_union {
        splice_fd_in: i32,
        file_index: u32,
		using _: struct {
            addr_len: u16,
			__pad3: [1]u16,
		}
	},
    using _: struct #raw_union {
        using _: struct {
            addr3: u64,
            __pad2: [1]u64,
		},
		/*
		 * If the ring is initialized with IORING_SETUP_SQE128, then
		 * this field is used for 80 bytes of arbitrary command data
		 */
		// cmd: [0]u8;
	},
}

sys_io_uring_setup :: proc "contextless" (entry_count: u32, params: ^IO_Uring_Params) -> (result: int) {
    result = int(intrinsics.syscall(linux.SYS_io_uring_setup, uintptr(entry_count), uintptr(params)))
    return
}

sys_io_uring_register :: proc "contextless" (fd: u32, op_code: u32, args: rawptr, arg_count: u32) -> (result: int) {
    result = int(intrinsics.syscall(
        linux.SYS_io_uring_register, 
        uintptr(fd), 
        uintptr(op_code), 
        uintptr(args), 
        uintptr(arg_count)
    ))
    return
}

Sig_Set :: distinct u32

sys_io_uring_enter :: proc "contextless" (fd: u32, to_submit: u32, min_complete: u32, flags: u32, sig: [^]Sig_Set) -> (result: int) {
    result = int(intrinsics.syscall(
        linux.SYS_io_uring_enter, 
        uintptr(fd), 
        uintptr(to_submit), 
        uintptr(min_complete), 
        uintptr(flags), 
        uintptr(sig)
    ))
    return
}

