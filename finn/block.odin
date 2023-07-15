package compress

import os "core:os"
import fmt "core:fmt"

// this sub-package defines our Block structure and Header sub-structure that
// will keep track of the required information when compressing

Header :: struct {
    bits: u8,       // bits is a u8 between the range of [0, 3] (represents 1/2 * the number of bits) (2 bits)
    count: u8,      // count is a u8 between the range of [0, MAX_COUNT] (6 bits)
    root: u8,       // root is a u8 (8 bits)
} // Outputted size is 2 + 6 + 8 = 16 bits

MAX_COUNT :: 64     // the maximum range encompassed in a count of the header

Block :: struct {
    hdr: Header,            // header denoting how the bytes should be encoded (16 bits)
    bytes: [MAX_COUNT]u8,   // these are the bytes containing the difference with the root
    next: ^Block,           // next block in our 'blockchain' ;)
}

// compute the size of the block (in bits) if it were to be emitted and the
// original uncompressed value of the corresponding bits
size_block :: proc(block: Block) -> (int, int) {
    hdr_size := block.hdr.bits == 0 ? 10 : 16
    byte_size := int(block.hdr.bits * 2)
    num_bytes := int(block.hdr.count)
    
    orig_size := block.hdr.bits == 0 ? 8 : (num_bytes * 8)
    return hdr_size + byte_size * num_bytes, orig_size
}

// recursively reverse the order of the linked list of blocks
reverse_blocks :: proc(block: ^Block, next: ^Block = nil) -> ^Block {
    prev := block.next
    block.next = next
    if prev == nil {
        return block
    }
    return reverse_blocks(prev, block)
}

// recursively print the linked list of blocks
print_blocks :: proc(block: ^Block) {
    hdr := block.hdr
    fmt.println(hdr, "=> size:", size_block(block^), block.bytes[:hdr.count])
    if block.next != nil {
        print_blocks(block.next)
    }
}

// recursively free the linked list of blocks
free_blocks :: proc(block: ^Block) {
    if block.next != nil {
        free_blocks(block.next)
    }
    free(block)
}

// create_blocks will iterate through the page of bytes and create a linked
// list of the blocks that represent the data as differenced with the root
// of each block. Currently, it uses a static range of 16 so that the
// differences can be stored as 4 bits (which will hopefully save space) but
// we can expand on this function to add optimizations of searching various
// ranges to determine the best format.
create_blocks :: proc(page: ^[4096]u8, size: int, posn := 0, prev : ^Block = nil) -> ^Block {
    range :: 16                 // TODO: can make this variable of 2^hdr.bits

    if posn == size { // end of processing the page and we can return
        return reverse_blocks(prev) // reverse the order of the blocks as they were stored in reverse
    }

    x := min(size, posn + MAX_COUNT)    // determine the largest window we can consider
    window := page[posn:x]              // fill our window to consider
    w_size := u8(x - posn)              // keep track of how large the window is
    w_posn := u8(1)                     // set to 1 as we get window[0] below

    // init the new block
    block := new(Block)         // allocate our new block
    block.hdr = Header{2, 0, 0}
    block.next = prev           // this will be reversed at the end to allow tail-recursion
    block.bytes[0] = window[0]
    block.hdr.root = window[0]

    // check if we can only enode the current byte in this block
    if w_size == 1 || !(abs(window[1] - block.hdr.root) < range) {
        block.hdr.bits = 0  // denote that we are only encoding a single byte
        // recurse to the next block
        return create_blocks(page, size, posn + 1, block)
    }
  
    // init our incremental values
    cur: u8
    max := block.hdr.root
    for w_posn < w_size { // check if we have reached the end of the window
        cur = window[w_posn]
        if cur < block.hdr.root { // cur is less than the root so lets check if we can set it as the new root
            if max - cur < range { // if we set this as the new root, the window would be still be in range, so do so
                block.hdr.root = cur 
            } else { // otherwise, we can't include this byte in the current block, so break
                break
            }
        } else if max < cur { // the following is the opposite of above but swapping root and max
            if cur - block.hdr.root < range {
                max = cur
            } else {
                break
            }
        }
        // if we didn't trigger either if clause then cur is within the range and we can add it to the block

        // update incrementals
        // NOTE: we do this after the break statements so that if we do break
        // then that byte is the one considered for the next call and not
        // accidently consumed
        block.bytes[w_posn] = cur
        w_posn += 1
    }
    // denote how many bytes we were able to add to the block
    block.hdr.count = w_posn

    // store the differences with the root
    for _, i in block.bytes {
        block.bytes[i] -= block.hdr.root
    }

    // recurse to the next block
    return create_blocks(page, size, posn + int(w_posn), block)
}
