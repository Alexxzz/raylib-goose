#!/usr/bin/env python3
"""Checks that rl.goose's structs match raylib.h's, byte for byte.

Compiles a C program that prints sizeof and offsetof for every struct and
field in raylib_api.json, and compares them with the layout gen_bindings.py
gives the Goose structs (whose fields, padding included, are packed).

Usage: python3 tools/check_layout.py path/to/raylib/src [cc]
"""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_bindings import Generator, keyword_safe  # noqa: E402


def main():
    include = sys.argv[1]
    cc = sys.argv[2] if len(sys.argv) > 2 else "cc"
    with open(os.path.join(HERE, "raylib_api.json"), encoding="utf-8") as fh:
        api = json.load(fh)
    g = Generator(api)

    expected = []
    lines = ['#include <stdio.h>', '#include <stddef.h>', '#include "raylib.h"', "int main(void) {"]
    for s in api["structs"]:
        name = s["name"]
        offset = 0
        by_name = {}
        for field, gtype, size, _ in g.struct_fields(name):
            by_name[field] = offset
            offset += size
        expected.append(f"{name} size {offset}")
        lines.append(f'    printf("{name} size %zu\\n", sizeof({name}));')
        for f in s["fields"]:
            expected.append(f"{name}.{f['name']} {by_name[keyword_safe(f['name'])]}")
            lines.append(f'    printf("{name}.{f["name"]} %zu\\n", offsetof({name}, {f["name"]}));')
    lines += ["    return 0;", "}"]

    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "layout.c")
        exe = os.path.join(tmp, "layout")
        with open(src, "w") as fh:
            fh.write("\n".join(lines) + "\n")
        subprocess.run([cc, "-I", include, src, "-o", exe], check=True)
        actual = subprocess.run([exe], check=True, capture_output=True, text=True).stdout.split("\n")

    bad = [(e, a) for e, a in zip(expected, actual) if e != a]
    for e, a in bad:
        print(f"mismatch: rl.goose has {e}, raylib.h has {a}")
    print(f"{len(expected) - len(bad)} of {len(expected)} sizes and offsets match")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
