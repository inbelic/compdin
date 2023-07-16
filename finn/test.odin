package compress

import testing "core:testing"
import rand "core:math/rand"
import math "core:math"

// here we have our property based testing

gen_page_input :: proc(r: ^rand.Rand) -> ([4096]u8, int, bool) {
    // generates a random input array less than 3000 bytes (less than a page)
    size := int(10 + math.floor(rand.float32(r) * 2990))
    data: [4096]u8
    n := rand.read(data[:size], r)
    return data, size, n == size
}

gen_multi_page_input :: proc(r: ^rand.Rand) -> ([8][4096]u8, [8]int, bool) {
    num_pages := int(math.floor(rand.float32(r) * 7))
    last_size := int(10 + math.floor(rand.float32(r) * 2990))
    sizes : [8]int
    for i in 0..<num_pages {
        sizes[i] = 4096
    }
    sizes[num_pages] = last_size

    data : [8][4096]u8
    ok := true
    for size, i in sizes {
        n := rand.read(data[i][:size], r)
        ok &= n == size
    }
    return data, sizes, ok
}

// test to ensure that the function create_blocks and output_blocks are
// bijective when the input is less than 3000 bytes (doesn't overflow)
ensure_create_output_bijective_single :: proc(t: ^testing.T, r: ^rand.Rand) {
    // generate the inputs
    data, size, ok := gen_page_input(r)
    testing.expect_value(t, ok, true)

    block := create_blocks(&data, size)
    testing.expect_value(t, block != nil, true)
    defer free_blocks(block)

    // store the decoding
    out: [4096]u8
    out_size, out_block := output_blocks(&out, block)

    // check that the entire block is outputted in the chain
    testing.expect_value(t, out_block, nil)

    // check that the output == encode . decode of the input
    testing.expect_value(t, data, out)
}


ensure_create_output_bijective_multi :: proc(t: ^testing.T, r: ^rand.Rand) {
    data, sizes, ok := gen_multi_page_input(r)
    testing.expect_value(t, ok, true)

    out: [16][4096]u8
    out_sizes : [16]int
    out_buf, out_posn:= 0, 0
    out_blocks: [8]^Block
    out_block: ^Block
    for _, i in data {
        if 0 < sizes[i] {
            out_blocks[i] = create_blocks(&data[i], sizes[i])
            testing.expect_value(t, out_blocks[i] != nil, true)

            out_block = out_blocks[i]
            for {
                out_posn, out_block = output_blocks(&out[out_buf], out_block, out_posn)
                if out_block != nil {
                    out_sizes[out_buf] = out_posn
                    out_posn = 0
                    out_buf += 1
                } else { break }
            }

            // check that the entire block is outputted in the chain
            testing.expect_value(t, out_block, nil)
        }
    }
    out_sizes[out_buf] = out_posn

    input: [8 * 4096]u8
    i_posn := 0
    for page, pi in data {
        for i in 0..<sizes[pi] {
            input[i_posn] = page[i]
            i_posn += 1
        }
    }
    output: [8 * 4096]u8
    o_posn := 0
    for page, pi in out {
        for i in 0..<out_sizes[pi] {
            output[o_posn] = page[i]
            o_posn += 1
        }
    }
    testing.expect_value(t, o_posn, i_posn)
    testing.expect_value(t, equal_bytes(input[:i_posn], output[:o_posn]), true)
    for block in out_blocks {
        if block != nil { free_blocks(block) }
    }
}

@(test)
ensure_create_output_bijective :: proc(t: ^testing.T) {
    // just a wrapper to run the underlying test a bunch of times
    seed := rand.uint64()
    r := rand.create(seed)
    testing.log(t, "seed:", seed)
    for _ in 0..<1000 {
        ensure_create_output_bijective_single(t, &r)
    }
    for _ in 0..<1000 {
        ensure_create_output_bijective_multi(t, &r)
    }
}

ensure_emit_consume_bijective_single :: proc(t: ^testing.T, r: ^rand.Rand) {
    // test to ensure that the function create_blocks and output_blocks are
    // bijective when the input is less than 3250 bytes (doesn't overflow)
    data, size, ok := gen_page_input(r)
    testing.expect_value(t, ok, true)

    block := create_blocks(&data, size)
    testing.expect_value(t, block != nil, true)
    defer free_blocks(block)

    emitter := Emitter{}
    emitter.ok = true
    emit_blocks(&emitter, block)
    testing.expect_value(t, emitter.ok, true)
    emitter.buf[emitter.posn] = emitter.rem
    emitter.posn += 1

    consumer := Consumer{emitter.buf, emitter.posn, 0, 0, true}
    out_block := consume_blocks(&consumer)
    testing.expect_value(t, consumer.ok, true)
    testing.expect_value(t, out_block != nil, true)

    // ensure that the block that is reconstructed is equivalent to the one
    // that was emitted
    testing.expect_value(t, equal_blocks(block, out_block), true)

    // store the decoding
    out: [4096]u8
    out_size, nil_block := output_blocks(&out, out_block)

    // check that the entire block is outputted in the chain
    testing.expect_value(t, nil_block, nil)
    // check that the output == encode . decode of the input
    testing.expect_value(t, data == out, true)
}


ensure_emit_consume_bijective_multi :: proc(t: ^testing.T, r: ^rand.Rand) {
    data, sizes, ok := gen_multi_page_input(r)
    testing.expect_value(t, ok, true)

    tmp: [16][4096]u8
    tmp_sizes : [16]int
    tmp_buf, tmp_posn:= 0, 0
    tmp_blocks: [8]^Block
    tmp_block: ^Block
    emitter := Emitter{}
    emitter.ok = true

    // first we encode
    for _, i in data {
        if 0 < sizes[i] {
            tmp_blocks[i] = create_blocks(&data[i], sizes[i])
            testing.expect_value(t, tmp_blocks[i] != nil, true)

            tmp_block = tmp_blocks[i]
            for {
                tmp_block = emit_blocks(&emitter, tmp_block)
                if tmp_block != nil {
                    tmp[tmp_buf] = emitter.buf
                    tmp_sizes[tmp_buf] = emitter.posn
                    tmp_buf += 1
                    emitter.posn = 0
                    emitter.ok = true
                } else { break }
            }

            // check that the entire block is outputted in the chain
            testing.expect_value(t, tmp_block, nil)
        }
    }
    emitter.buf[emitter.posn] = emitter.rem
    emitter.posn += 1
    tmp[tmp_buf] = emitter.buf
    tmp_sizes[tmp_buf] = emitter.posn

    packed_tmp: [16 * 4096]u8
    t_posn := 0
    for page, pi in tmp {
        for i in 0..<tmp_sizes[pi] {
            packed_tmp[t_posn] = page[i]
            t_posn += 1
        }
    }
    ttl_bytes := t_posn
    t_posn = 0

    // then we decode
    consumer := Consumer{}
    out_blocks: [dynamic]^Block
    num_blocks := 0
    for {
        bytes_read := 0
        for i in consumer.size..< 4096 {
            if t_posn < ttl_bytes {
                consumer.buf[i] = packed_tmp[t_posn]
                t_posn += 1
                bytes_read += 1
            }
        }
        consumer.size += bytes_read
        consumer.ok = true
        out_block := consume_blocks(&consumer)
        append(&out_blocks, out_block)
        num_blocks += 1
        if !consumer.ok || t_posn != ttl_bytes {
            unused_bytes := consumer.size - consumer.posn
            for i in 0..<unused_bytes {
                consumer.buf[i] = consumer.buf[i + consumer.posn]
            }
            consumer.posn = 0
            consumer.size = unused_bytes
        } else { break }
    }

    out: [16][4096]u8
    out_sizes : [16]int
    out_buf, out_posn:= 0, 0
    for block in out_blocks {
        out_block := block
        for {
            out_posn, out_block = output_blocks(&out[out_buf], out_block, out_posn)
            if out_block != nil {
                out_sizes[out_buf] = out_posn
                out_posn = 0
                out_buf += 1
            } else { break }
        }
        // check that the entire block is outputted in the chain
        testing.expect_value(t, out_block, nil)
    }
    out_sizes[out_buf] = out_posn

    emitted_block : ^Block = nil
    for block in tmp_blocks {
        if emitted_block == nil {
            emitted_block = block
        } else {
            append_blocks(emitted_block, block)
        }
    }
    consumed_block : ^Block = nil
    for block in out_blocks {
        if consumed_block == nil {
            consumed_block = block
        } else {
            append_blocks(consumed_block, block)
        }
    }
   
    testing.expect_value(t, equal_blocks(consumed_block, emitted_block), true)

    input: [8 * 4096]u8
    i_posn := 0
    for page, pi in data {
        for i in 0..<sizes[pi] {
            input[i_posn] = page[i]
            i_posn += 1
        }
    }
    output: [8 * 4096]u8
    o_posn := 0
    for page, pi in out {
        for i in 0..<out_sizes[pi] {
            output[o_posn] = page[i]
            o_posn += 1
        }
    }
    testing.expect_value(t, o_posn, i_posn)
    testing.expect_value(t, equal_bytes(input[:i_posn], output[:o_posn]), true)
}

@(test)
ensure_emit_consume_bijective :: proc(t: ^testing.T) {
    // just a wrapper to run the underlying test a bunch of times
    seed := rand.uint64()
    r := rand.create(seed)
    testing.log(t, "seed:", seed)
    for i in 0..<1000 {
        ensure_emit_consume_bijective_single(t, &r)
    }
    for i in 0..<1000 {
        ensure_emit_consume_bijective_multi(t, &r)
    }
}
