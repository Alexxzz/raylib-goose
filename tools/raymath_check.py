#!/usr/bin/env python3
"""Checks raymath.goose against raylib's raymath.h, result for result.

Reads the signature of every function raymath.goose declares, calls each
with the same inputs from a C program (which includes raymath.h) and from a
Goose program (which imports rl), and compares every float the two print as
an f32. Both sides do the same float operations in the same order, so the
results are expected to be bit-identical.

Usage: python3 tools/raymath_check.py path/to/raylib/src path/to/goose [cc]
"""

import math
import os
import re
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

FLOATS = [0.3, -1.7, 2.5, 0.0, 1.0, -0.25, 3.75, 0.8, -2.2, 1.5, 0.05, -0.6, 4.0, 0.9, -3.1]
SETS = 5
FIELDS = {
    "Vector2": "x y".split(),
    "Vector3": "x y z".split(),
    "Vector4": "x y z w".split(),
    "Quaternion": "x y z w".split(),
    "Matrix": [f"m{i}" for i in (0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15)],
}


def value(k, p, j):
    return FLOATS[(k * 7 + p * 3 + j * 5) % len(FLOATS)]


def c_lit(t, k, p):
    if t in ("f32", "f64"):
        v = value(k, p, 0)
        return f"{v}f" if t == "f32" else f"{v}"
    vals = ", ".join(f"{value(k, p, j)}f" for j in range(len(FIELDS[t])))
    return f"(({t}){{ {vals} }})"


def goose_lit(t, k, p):
    if t in ("f32", "f64"):
        v = value(k, p, 0)
        return f"({v} as {t})"
    vals = ", ".join(f"{value(k, p, j)}" for j in range(len(FIELDS[t])))
    return f"rl::{t} {{ {vals} }}"


def printers(t, expr):
    """(C statements, Goose statements) printing the value expr of type t."""
    if t == "f32":
        return [f'printf("%.9g\\n", (double){expr});'], [f"print({expr});"]
    if t == "bool":
        return [f'printf("%s\\n", ({expr}) ? "true" : "false");'], [f"print({expr});"]
    m = re.fullmatch(r"f32\[(\d+)\]", t)
    if m:
        n = int(m.group(1))
        return ([f'printf("%.9g\\n", (double){expr}.v[{i}]);' for i in range(n)],
                [f"print({expr}[{i}]);" for i in range(n)])
    return ([f'printf("%.9g\\n", (double){expr}.{f});' for f in FIELDS[t]],
            [f"print({expr}.{f});" for f in FIELDS[t]])


def main():
    include, goose = sys.argv[1], sys.argv[2]
    cc = sys.argv[3] if len(sys.argv) > 3 else "cc"
    src = open(os.path.join(ROOT, "raymath.goose"), encoding="utf-8").read()
    sigs = re.findall(r"^fn ([A-Z]\w*)\((.*?)\)(?: -> (\S+))? \{", src, re.M)

    c = ['#include <stdio.h>', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"', "int main(void) {"]
    g = [f'import rl from "{ROOT}";', "fn main() {"]
    names = []
    for name, params, ret in sigs:
        ptypes = [p.split(":")[1].strip() for p in params.split(",")] if params else []
        for k in range(SETS if ptypes else 1):
            cargs, gargs, outs = [], [], []
            c.append("    {")
            g.append("    {")
            for p, t in enumerate(ptypes):
                if t.endswith("&"):
                    base = t[:-1]
                    var = f"out{p}"
                    c.append(f"        {'float' if base == 'f32' else base} {var} = {c_lit(base, k, p)};")
                    g.append(f"        var {var} = {goose_lit(base, k, p)};")
                    cargs.append(f"&{var}")
                    gargs.append(var)
                    outs.append((base, var))
                else:
                    cargs.append(c_lit(t, k, p))
                    gargs.append(goose_lit(t, k, p))
            ccall, gcall = f"{name}({', '.join(cargs)})", f"rl::{name}({', '.join(gargs)})"
            if ret:
                ct = {"f32": "float", "bool": "int"}.get(ret, ret)
                ct = "float3" if ret == "f32[3]" else "float16" if ret == "f32[16]" else ct
                c.append(f"        {ct} r = {ccall};")
                g.append(f"        let r = {gcall};")
                cp, gp = printers(ret, "r")
            else:
                c.append(f"        {ccall};")
                g.append(f"        {gcall};")
                cp, gp = [], []
            for t, var in outs:
                a, b = printers(t, var)
                cp += a
                gp += b
            c += ["        " + s for s in cp]
            g += ["        " + s for s in gp]
            names += [f"{name}#{k}"] * len(cp)
            c.append("    }")
            g.append("    }")
    c += ["    return 0;", "}"]
    g += ["}"]

    with tempfile.TemporaryDirectory() as tmp:
        csrc, exe, gsrc = (os.path.join(tmp, n) for n in ("rm.c", "rm", "rm.goose"))
        open(csrc, "w").write("\n".join(c) + "\n")
        open(gsrc, "w").write("\n".join(g) + "\n")
        subprocess.run([cc, "-O0", "-ffp-contract=off", "-I", include, csrc, "-o", exe, "-lm"], check=True)
        cout = subprocess.run([exe], check=True, capture_output=True, text=True).stdout.split()
        gout = subprocess.run([goose, "run", "-q", gsrc], check=True, capture_output=True, text=True).stdout.split()

    def f32(s):
        if s in ("true", "false"):
            return s
        x = float(s)
        return "nan" if math.isnan(x) else struct.unpack("<I", struct.pack("<f", x))[0]

    assert len(cout) == len(gout) == len(names), (len(cout), len(gout), len(names))
    bad = [(n, a, b) for n, a, b in zip(names, cout, gout) if f32(a) != f32(b)]
    for n, a, b in bad:
        print(f"mismatch in {n}: C {a}, Goose {b}")
    print(f"{len(sigs)} functions, {len(names) - len(bad)} of {len(names)} results identical")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
