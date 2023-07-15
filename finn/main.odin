package compress

import os "core:os"
import fmt "core:fmt"

main :: proc() {
    args := os.args
    if len(args) != 2 {
        fmt.eprintln("usage: ./finn filename")
        return
    }
    
    // Init the file to read from
    filename := args[1]
    in_hdl, in_err := os.open(filename) // read-only
    defer os.close(in_hdl)
    if in_err != os.ERROR_NONE {
        fmt.eprintln("error opening input file:", in_err)
        return
    }

    // Init the file to write to
    out_hdl, out_err := os.open("out.fcf", os.O_CREATE | os.O_TRUNC | os.O_RDWR) // FIXME: some permissions are weird...
    defer os.close(out_hdl)
    if out_err != os.ERROR_NONE {
        fmt.eprintln("error opening output file:", out_err)
        return
    }

    // Loop through the input file 1 page at a time
    page: [4096]u8 // Read pagewise
    bytes_read, bytes_written: int
    for {
        bytes_read, in_err = os.read(in_hdl, page[:])
        if in_err != os.ERROR_NONE {
            fmt.eprintln("error reading from input file:", in_err)
            break
        }
        if bytes_read == 0 { break }

        // Any compression will be placed here
        head_block := create_blocks(&page, bytes_read)
        defer free_blocks(head_block)
        print_blocks(head_block)

        emitter := Emitter{}
        emitter.ok = true

        emit_blocks(&emitter, head_block)
        fmt.println(emitter.ok, emitter.buf[:emitter.posn])

        consumer := Consumer{emitter.buf, emitter.posn, emitter.used, 0, 0, true}
        o_head_block := consume_blocks(&consumer)
        defer free_blocks(o_head_block)
        print_blocks(o_head_block)

        fmt.println(equal_blocks(head_block, o_head_block))

        bytes_read, _ = output_blocks(&page, o_head_block)

        bytes_written, out_err = os.write(out_hdl, page[:bytes_read])
        if out_err != os.ERROR_NONE || bytes_written == 0 {
            fmt.eprintln("error writing to output file:", out_err)
            break
        }
        
        if bytes_written == 0 { break }
    }

    return
}
