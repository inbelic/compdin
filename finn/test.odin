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

// test to ensure that the function create_blocks and output_blocks are
// bijective when the input is less than 3000 bytes (doesn't overflow)
ensure_create_output_bijective_single :: proc(t: ^testing.T, r: ^rand.Rand) {
    // generate the inputs
    data, size, ok := gen_page_input(r)
    testing.expect_value(t, ok, true)

    // encode with random sized bits
    bits := 1 + int(math.floor(rand.float32(r) * 7))
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

@(test)
ensure_create_output_bijective :: proc(t: ^testing.T) {
    // just a wrapper to run the underlying test a bunch of times
    seed := rand.uint64()
    r := rand.create(seed)
    testing.log(t, "seed:", seed)
    for _ in 0..<10000 {
        ensure_create_output_bijective_single(t, &r)
    }
}

ensure_emit_consume_bijective_single :: proc(t: ^testing.T, r: ^rand.Rand) {
    // test to ensure that the function create_blocks and output_blocks are
    // bijective when the input is less than 3250 bytes (doesn't overflow)
    data, size, ok := gen_page_input(r)
    testing.expect_value(t, ok, true)

    bits := 1 + int(math.floor(rand.float32(r) * 7))
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

@(test)
ensure_emit_consume_bijective :: proc(t: ^testing.T) {
    // just a wrapper to run the underlying test a bunch of times
    seed := rand.uint64()
    r := rand.create(seed)
    testing.log(t, "seed:", seed)
    for i in 0..<10000 {
        ensure_emit_consume_bijective_single(t, &r)
    }
}
