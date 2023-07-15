package compress

// this sub-package defines our Consumer structure which will construct a block
// linked list from a sequence of bytes that was formatted by Emitter

Consumer :: struct {
    buf: [4096]u8,          // buffer sequence to consume from
    size: int,              // number of bytes in the buf
    extra: u8,              // number of overflow bits into last byte
    posn: int,              // current position of buf
    used: u8,               // amount of bits consumed from current byte
    ok: bool,               // denotes if we ran out of bytes to consume
}

// consume_bits will take the specified number of bits from the Consumer buffer
// and return them in a byte in least-significant bit order
consume_bits :: proc(consumer: ^Consumer, bits: u8) -> u8 {
    req_size := consumer.posn + int(consumer.used + bits) / 8
    if 4095 < req_size {
        // not enough bits left in the buf to do and so not ok to coninue
        consumer.ok = false
    }
    if !consumer.ok { // consumer state needs to be rolled back before continuing
        return 0
    }

    byte := consumer.buf[consumer.posn]

    if consumer.used + bits <= 8 {
        // discard the bits that are already consumed
        byte = byte << consumer.used

        // then we update to the new amount of bits used
        consumer.used += bits

        // byte now represents our return value but in the most-significant bit
        // order and may contain some extra bits, so we return the shifted ret
        // such that it is in least-significant bit order and removes those
        // extra bits
        return byte >> (8 - bits)
    }

    // store the unconsumed bits in least-significant bit order in ret
    unconsumed := 8 - consumer.used
    mask := u8(1 << unconsumed - 1)
    ret := byte & mask

    // update consumer.bits to how many more bits we need to take from the next byte
    consumer.used = bits + consumer.used - 8

    // update to next byte
    consumer.posn += 1
    byte = consumer.buf[consumer.posn]
    
    // discard the bits that we wont take
    byte = byte >> (8 - consumer.used)

    // shift our ret to account for the remaining bits
    ret = ret << consumer.used

    return ret | byte
}

// consume bits bits for byte for each byte of the array and store it in the
// array
consume_bytes :: proc(consumer: ^Consumer, bits: u8, bytes: []u8) {
    for _, i in bytes {
        bytes[i] = consume_bits(consumer, bits)
    }
}

// consume a header
consume_header :: proc(consumer: ^Consumer) -> (hdr: Header) {
    hdr.bits = consume_bits(consumer, 2)
    if hdr.bits != 0 { // not a single byte header and will determine the count
        hdr.count = consume_bits(consumer, 6)
    }
    hdr.root = consume_bits(consumer, 8)
    return hdr
}

consume_blocks :: proc(consumer: ^Consumer, prev: ^Block = nil) -> ^Block {
    if consumer.size == consumer.posn {
        return reverse_blocks(prev) // reverse the order of the blocks as they were stored in reverse
    }
  
    // if we are unable to create a block because we run out of bytes to
    // consume then we are required to rollback the consumer to the current
    // state so we can continue when we update the buf with more bytes
    posn, used := consumer.posn, consumer.used

    block := new(Block)
    block.hdr = consume_header(consumer)
    block.next = prev           // this must be reversed at the end to allow tail-recursion
    
    consume_bytes(consumer, block.hdr.bits * 2, block.bytes[:block.hdr.count])

    // rollback the consumer state and free the block memory
    if !consumer.ok {
        consumer.posn = posn
        consumer.used = used
        free(block)
        return reverse_blocks(prev) // reverse the order of the blocks as they were stored in reverse
    }

    return consume_blocks(consumer, block)
}
