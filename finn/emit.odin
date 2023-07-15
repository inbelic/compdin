package compress

// this sub-package defines our Emitter structure will keep construct a byte
// sequence with the bytes packged together

Emitter :: struct {
    buf: [4096]u8,          // buffer sequence to write to
    posn: int,              // current position of buf
    rem: u8,                // the remainder of the previous byte emitted (most-significant stored)
    used: u8,               // how many bits the remainder contains (from most-significant bit)
    ok: bool,             // denotes if we ran out of space to emit bytes in
}

// byte is assumed to be stored in least-significant bit order and bits denotes
// how many bits of the given byte to write and the ununsed bits are set to 0
emit_bits :: proc(emitter: ^Emitter, byte: u8, bits: u8) {
    req_size := emitter.posn + int(emitter.used + bits) / 8
    if 4095 < req_size {
        // can't add that many bits to emitter and so not ok to continue
        emitter.ok = false
    }
    if !emitter.ok { // emitter state needs to be rolled back before continuing
        return
    }
   
    include: u8 // include denotes what we should include with the current rem byte
    if emitter.used + bits <= 8 {
        // here we just need to shift our bits to align with the unused bits of rem
        include = byte << (8 - emitter.used - bits)
        // then update our rem byte and the number of used bits
        emitter.rem = emitter.rem | include
        emitter.used += bits
        return
    }

    // here we will have filled the rem bit and can emit it
    // so first we shift to the right to get as many bits as we can include in
    // from the current bit with the rem byte and emit it
    to_rem := (emitter.used + bits - 8) // how many bits will be stored in rem after
    include = byte >> to_rem // discard the bits to be stored in rem
    emitter.buf[emitter.posn] = emitter.rem | include // add those bits to current rem and emit
    emitter.posn += 1

    // then we will take the remainding bits from byte that weren't included and
    // store it for the next iteration
    mask := u8(1 << to_rem - 1)
    emitter.used = to_rem
    emitter.rem = (byte & mask) << (8 - emitter.used)
}

// emit bits bits of each byte in an array of bytes stored in least-significant order
emit_bytes :: proc(emitter: ^Emitter, bytes: []u8, bits: u8) {
    for byte in bytes {
        emit_bits(emitter, byte, bits)
    }
}

// emit a header
emit_header :: proc(emitter: ^Emitter, hdr: Header) {
    emit_bits(emitter, hdr.bits, 2)
    if hdr.bits != 0 {
        emit_bits(emitter, hdr.count, 6)
    }
    emit_bits(emitter, hdr.root, 8)
}

// recursively emit the chain of blocks
emit_blocks :: proc(emitter: ^Emitter, block: ^Block) -> ^Block {
    if block == nil {
        emitter.buf[emitter.posn] = emitter.rem
        emitter.posn += 1
        return nil
    }

    // we may not have enough space in the emitter to emit the entire block,
    // so we will record the current emitter state to rollback to if we need
    // to do so on the next block
    posn, rem, used := emitter.posn, emitter.rem, emitter.used

    // emit the header and bytes
    emit_header(emitter, block.hdr)
    emit_bytes(emitter, block.bytes[:block.hdr.count], block.hdr.bits * 2)

    if !emitter.ok {
        // rollback the emitter state
        emitter.posn = posn
        emitter.rem = rem
        emitter.used = used
        return block
    }
    // otherwise, we can continue to the next block
    return emit_blocks(emitter, block.next)
}
