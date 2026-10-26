// honk: saving and loading game data.
//
// An array of flat values (fixed-size structs, inline strings u8[..k],
// self-relative links T&<u32>) holds no pointers, so its bytes mean the same
// thing in a file as in memory. Saving writes them; loading reads them back
// and lets from_bytes verify every length, tag and link before they become a
// value, so a damaged or hostile file loads as `false`, never as a wild
// reference.

namespace honk;

import std;
import os;

// Writes the array to `path`, replacing the file in one step.
fn save<T>(path: const u8[:], xs: T[>..]&) -> bool {
    return write_file_atomic(path, xs.to_bytes());
}

// Reads an array save wrote. A missing or damaged file gives false and an
// empty array.
fn load<T>(path: const u8[:]) -> T[>..], bool {
    var bytes: u8[>..] = [];
    if !read_file(path, bytes) { return [], false; }
    return from_bytes<T[>..]>(bytes);
}
