package compress

import os "core:os"
import fmt "core:fmt"

main :: proc() {
    args := os.args
    if len(args) != 4 {
        fmt.eprintln("usage: ./finn -(c|d) in_filename out_filename")
        return
    }

    // parse flag
    compress : bool
    if (args[1] == "-c") { compress = true }
    else if (args[1] == "-d") { compress = false }
    else {
        fmt.eprintln("invalid flag specified, expected -(c|d) but got:", args[1])
        return
    }

    // init the file to read from
    in_filename := args[2]
    in_hdl, in_err := os.open(in_filename) // read-only
    defer os.close(in_hdl)
    if in_err != os.ERROR_NONE {
        fmt.eprintln("error opening input file:", in_err)
        return
    }

    // init the file to write to
    out_filename := args[3]
    out_hdl, out_err := os.open(out_filename, os.O_CREATE | os.O_TRUNC | os.O_RDWR) // FIXME: some permissions are weird...
    defer os.close(out_hdl)
    if out_err != os.ERROR_NONE {
        fmt.eprintln("error opening output file:", out_err)
        return
    }

    // dispatch accordingly
    if compress {
        emitter_main(in_hdl, out_hdl)
    } else {
        consumer_main(in_hdl, out_hdl)
    }
}

emitter_main :: proc(in_hdl: os.Handle, out_hdl: os.Handle) {
    in_err, out_err: os.Errno

    // init
    block: ^Block
    emitter := Emitter{}

    // keep track of the expected bits written/read
    ttl_hdr, ttl_bits: int

    // loop through the input file 1 page at a time
    page: [4096]u8 // Read pagewise
    bytes_read, bytes_written: int
    for {
        // construct our block structure from input
        bytes_read, in_err = os.read(in_hdl, page[:])
        if in_err != os.ERROR_NONE {
            fmt.eprintln("error reading from input file:", in_err)
            break
        }
        if bytes_read == 0 { break }

        // create our block structure
        block = create_blocks(&page, bytes_read)

        t_hdr, _ := size_blocks(block)
        ttl_hdr += t_hdr

        // then we can repeatedly emit our block structure until it is
        // all output
        t_bits := 0
        for {
            // reinit the emitter
            emitter.posn = 0
            emitter.ok = true

            // output as many blocks into our page buffer and return the
            // remaining block to be output
            block = emit_blocks(&emitter, block)
            ok := write_emitter(out_hdl, &emitter)
            if !ok { return }
            t_bits += 8 * emitter.posn
            if block == nil { break }
        }
        ttl_bits += t_bits
    }
    ttl_bits += int(emitter.used)
    // include the possibly partially filled last bit
    emitter.buf[0] = emitter.rem
    emitter.posn = 1
    write_emitter(out_hdl, &emitter)

    fmt.println(ttl_bits / 8, ":", ttl_hdr / 8)
}

write_emitter :: proc(hdl: os.Handle, emitter: ^Emitter) -> bool {
    bytes_written, out_err := os.write(hdl, emitter.buf[:emitter.posn])
    if out_err != os.ERROR_NONE || bytes_written == 0 {
        fmt.eprintln("error writing to output file:", out_err)
        return false
    }
    if bytes_written != emitter.posn {
        fmt.eprintln("error writing all bytes to output file:", bytes_written, emitter.posn)
        return false
    }
    return true
}

consumer_main :: proc(in_hdl: os.Handle, out_hdl: os.Handle) {
    in_err, out_err: os.Errno

    // init
    block: ^Block
    consumer := Consumer{}

    // keep track of the expected bits written/read
    ttl_hdr, ttl_bits: int

    // loop through the input file 1 page* at a time (or as much as the consumer can take)
    page: [4096]u8 // Read pagewise
    bytes_read, bytes_written: int
    for {
        // get input
        bytes_read, in_err = os.read(in_hdl, consumer.buf[consumer.size:])
        if bytes_read == 0 { break }

        // reinit the consumer
        consumer.size += bytes_read
        consumer.ok = true
        consumer.posn = 0   // set back to start of buffer

        // construct our block structure from input
        block = consume_blocks(&consumer)

        _, t_hdr := size_blocks(block)
        ttl_hdr += t_hdr

        // then we can output our consumed bytes
        t_bits := 0
        for {
            bytes_written, block = output_blocks(&page, block)
            ok := write_page(out_hdl, &page, bytes_written)
            if !ok { return }
            t_bits += 8 * bytes_written

            if block == nil { break }
        }

        // check if we need to account for our rollback
        if !consumer.ok {
            for byte, i in consumer.buf[consumer.posn:consumer.size] {
                consumer.buf[i] = byte
            }
            consumer.size = consumer.size - consumer.posn
        }
        
        ttl_bits += t_bits
    }
    fmt.println(ttl_bits / 8, ":", ttl_hdr / 8)
}

write_page :: proc(hdl: os.Handle, page: ^[4096]u8, size: int) -> bool {
    bytes_written, out_err := os.write(hdl, page[:size])
    if out_err != os.ERROR_NONE || bytes_written == 0 {
        fmt.eprintln("error writing to output file:", out_err)
        return false
    }
    if bytes_written != size {
        fmt.eprintln("error writing all bytes to output file:", bytes_written, size)
        return false
    }
    return true
}
