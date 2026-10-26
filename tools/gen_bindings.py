#!/usr/bin/env python3
"""Generate rl.goose, the Goose bindings for raylib, from raylib_api.json.

raylib_api.json is the API description raylib's own parser (tools/rlparser in
the raylib repository) writes for raylib.h. This script turns it into:

  * structs laid out exactly as C lays them out (Goose structs are packed, so
    every byte of C padding becomes an explicit `_padN: u8[k]` field),
  * one `extern "raylib" { ... }` block binding every function that has a
    plain C shape, loaded from the shared library when the program starts,
  * thin Goose wrappers for the functions that take C strings or
    (pointer, count) arrays, so a call can pass `"text"` or a slice,
  * the enum values, colors and other defines as named constants.

Usage: python3 tools/gen_bindings.py [raylib_api.json] [out.goose]
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

GOOSE_KEYWORDS = set("""
import namespace struct enum type fn thread_fn export simd recursive let var
extern const pad reusable if else while for in loop block guard match return
break continue as true false null self bool varint i8 i16 i32 i64 u8 u16 u32
u64 f32 f64 from upto inline checkfree fields types
""".split())

# C scalar -> (Goose type, size). Sizes double as alignments.
SCALARS = {
    "int": ("i32", 4),
    "unsigned int": ("u32", 4),
    "float": ("f32", 4),
    "double": ("f64", 8),
    "bool": ("bool", 1),
    "char": ("u8", 1),
    "unsigned char": ("u8", 1),
    "short": ("i16", 2),
    "unsigned short": ("u16", 2),
}
POINTER_SIZE = 8

# Functions that cannot be bound as a plain extern: they take a C callback
# or are variadic. `long` differs between Windows and the other platforms.
SKIP_REASONS = {}


def keyword_safe(name):
    return name + "_" if name in GOOSE_KEYWORDS else name


# String arguments for which raylib gives NULL a meaning; the wrappers pass
# NULL for an empty string. LoadShader("", "fx.fs") uses the default vertex
# shader.
NULLABLE_STRINGS = {
    "LoadShader": ("vsFileName", "fsFileName"),
    "LoadShaderFromMemory": ("vsCode", "fsCode"),
    "LoadDirectoryFilesEx": ("filter",),
}


def nullable_params(wparams):
    """The wrapper parameters that pass NULL when empty."""
    return [w[1] for w in wparams if w[0] == "slice" or (w[0] == "str" and w[3])]


def null_suffix(slices, nulls):
    """c_Name_null_a_b: the binding that passes NULL for the arrays a and b."""
    return "".join(["_null"] + [f"_{s}" for s in slices if s in nulls]) if nulls else ""


def comment(text):
    text = text.strip()
    return f" // {text}" if text else ""


class Generator:
    def __init__(self, api):
        self.api = api
        self.aliases = {a["name"]: a["type"] for a in api["aliases"]}
        self.callbacks = {c["name"] for c in api["callbacks"]}
        self.structs = {s["name"]: s for s in api["structs"]}
        self.layouts = {}  # struct name -> (size, align)
        self.out = []
        self.skipped = []

    # --- types ---------------------------------------------------------------

    def resolve(self, t):
        """Follows aliases that name a struct (Texture2D -> Texture)."""
        while t in self.aliases and not self.aliases[t].endswith("*"):
            t = self.aliases[t]
        return t

    def is_pointer(self, t):
        t = t.strip()
        if t.endswith("*"):
            return True
        return t in self.aliases and self.aliases[t].endswith("*")

    def field_layout(self, t):
        """(goose type, size, align) of a struct field's C type."""
        m = re.fullmatch(r"(.+)\[(\d+)\]", t)
        if m:
            inner, n = m.group(1), int(m.group(2))
            g, size, align = self.field_layout(inner)
            return f"{g}[{n}]", size * n, align
        if self.is_pointer(t):
            return "u64", POINTER_SIZE, POINTER_SIZE
        if t in SCALARS:
            g, size = SCALARS[t]
            return g, size, size
        r = self.resolve(t)
        if r in self.structs:
            size, align = self.layout(r)
            return t, size, align  # keep the alias name: it is declared too
        raise ValueError(f"unknown field type {t}")

    def layout(self, name):
        if name not in self.layouts:
            self.struct_fields(name)
        return self.layouts[name]

    def struct_fields(self, name):
        """Fields with explicit padding, and records the struct's layout."""
        s = self.structs[name]
        fields, offset, align, pads = [], 0, 1, 0
        has_float = False
        for f in s["fields"]:
            g, size, a = self.field_layout(f["type"])
            if g.startswith("f"):
                has_float = True
            if offset % a:
                gap = a - offset % a
                fields.append((f"_pad{pads}", f"u8[{gap}]", gap, ""))
                pads += 1
                offset += gap
            fields.append((keyword_safe(f["name"]), g, size, f.get("description", "")))
            offset += size
            align = max(align, a)
        if offset % align:
            gap = align - offset % align
            fields.append((f"_pad{pads}", f"u8[{gap}]", gap, "C's tail padding"))
            pads += 1
            offset += gap
        # A small struct is passed in registers, classified by what each
        # eightbyte holds; a pad field could turn a float eightbyte into an
        # integer one. raylib has no such struct, and this keeps it so.
        if pads and offset <= 16 and has_float:
            raise ValueError(f"{name}: padded small struct with floats")
        self.layouts[name] = (offset, align)
        return fields

    def param_type(self, t):
        """Goose type of a raw extern parameter, or None if it cannot cross."""
        t = t.strip()
        if t in self.callbacks or t == "...":
            return None
        if t in SCALARS:
            return SCALARS[t][0]
        is_const = t.startswith("const ")
        base = t[6:] if is_const else t
        if base.endswith("**"):
            # char **, Rectangle **: an out-pointer or an array of pointers.
            return "u64&" if base.startswith("Rectangle") else "u64"
        if base.endswith("*"):
            pointee = base[:-1].strip()
            if pointee == "void":
                return "u64"
            if pointee in SCALARS:
                g = SCALARS[pointee][0]
            elif self.resolve(pointee) in self.structs:
                g = pointee
            else:
                return "u64"
            return f"const {g}&" if is_const else f"{g}&"
        if t in self.aliases and self.aliases[t].endswith("*"):
            return "u64"
        if self.resolve(t) in self.structs:
            return t
        return None

    def return_type(self, t):
        t = t.strip()
        if t == "void":
            return ""
        if t == "long":
            return None
        if self.is_pointer(t):
            return "u64"
        if t in SCALARS:
            return SCALARS[t][0]
        if self.resolve(t) in self.structs:
            return t
        return None

    # --- output --------------------------------------------------------------

    def emit(self, line=""):
        self.out.append(line)

    def gen_structs(self):
        self.emit("// --- structs " + "-" * 64)
        self.emit("//")
        self.emit("// Laid out as C lays them out; `_padN` fields stand for C's padding.")
        self.emit("// Pointers the library owns (Image.data, Font.glyphs, ...) are u64.")
        for s in self.api["structs"]:
            fields = self.struct_fields(s["name"])
            size, _ = self.layouts[s["name"]]
            self.emit()
            self.emit(f"// {s['description']} ({size} bytes)")
            self.emit(f"struct {s['name']} {{")
            width = max(len(f"{n}: {g}") for n, g, _, _ in fields)
            for i, (n, g, _, desc) in enumerate(fields):
                default = ""
                if n.startswith("_pad"):
                    k = int(g[3:-1])
                    default = " = [" + ", ".join(["0"] * k) + "]"
                decl = f"{n}: {g}{default}"
                sep = "," if i < len(fields) - 1 else ""
                self.emit(f"    {(decl + sep).ljust(width + 1)}{comment(desc)}".rstrip())
            self.emit("}")
        self.emit()
        for a in self.api["aliases"]:
            if a["type"].endswith("*"):
                self.emit(f"type {a['name']} = u64;{comment(a.get('description', '') + ' (' + a['type'] + ')')}")
            else:
                self.emit(f"type {a['name']} = {a['type']};{comment(a.get('description', ''))}")
        self.emit()

    def gen_constants(self):
        self.emit("// --- defines " + "-" * 64)
        self.emit()
        old_names = []  # the older names of enum values, after the enums
        for d in self.api["defines"]:
            n, t, v = d["name"], d["type"], d["value"]
            if t == "INT":
                self.emit(f"let {n} = {v};")
            elif t == "STRING":
                self.emit(f'let {n} = "{v}";')
            elif t == "FLOAT":
                self.emit(f"let {n}: f32 = {v};")
            elif t == "FLOAT_MATH":
                expr = v.replace("f", "")
                self.emit(f"let {n}: f32 = {expr};")
            elif t == "COLOR":
                m = re.search(r"\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\s*\}", v)
                self.emit(f"let {n}: Color = Color {{ {', '.join(m.groups())} }};{comment(d['description'])}")
            elif t == "UNKNOWN" and re.fullmatch(r"[A-Z_0-9]+", str(v)):
                old_names.append(f"let {n} = {v};{comment(d['description'])}")
        self.emit()
        self.emit("// --- enums " + "-" * 66)
        self.emit("//")
        self.emit("// Untyped named constants, so each adapts to the i32 or u32 a call takes.")
        for e in self.api["enums"]:
            self.emit()
            self.emit(f"// {e['name']}: {e['description']}")
            width = max(len(v["name"]) for v in e["values"])
            for v in e["values"]:
                self.emit(f"let {v['name'].ljust(width)} = {v['value']};{comment(v['description'])}")
        self.emit()
        self.emit("// Older names, kept by raylib.h.")
        for line in old_names:
            self.emit(line)
        self.emit()

    def plan_function(self, f):
        """Returns (raw params, raw return, wrapper plan) or a skip reason."""
        params = f.get("params", [])
        ret = self.return_type(f["returnType"])
        if ret is None:
            return f"returns {f['returnType']}, which differs between platforms"
        raw = []
        for p in params:
            if p["type"] == "...":
                return "variadic"
            g = self.param_type(p["type"])
            if f["name"].startswith("Unload") and self.is_pointer(p["type"]):
                g = "u64"  # memory the library returned, as a u64
            if g is None:
                return f"takes a C callback ({p['type']})"
            raw.append((keyword_safe(p["name"]), g, p["type"]))
        # The wrapper: C strings become slices, a const array followed by its
        # count becomes one slice.
        wparams, i, wrap = [], 0, False
        while i < len(raw):
            n, g, ct = raw[i]
            if ct == "const char *":
                wparams.append(("str", n, "const u8[:]", n in NULLABLE_STRINGS.get(f["name"], ())))
                wrap = True
            elif (g.startswith("const ") and g.endswith("&") and ct != "const char *"
                  and i + 1 < len(raw) and raw[i + 1][1] == "i32"
                  and re.search(r"(count|size|length|instances)$", raw[i + 1][0], re.I)):
                elem = g[6:-1]
                wparams.append(("slice", n, f"const {elem}[:]", raw[i + 1][0]))
                wrap = True
                i += 1
            else:
                wparams.append(("plain", n, g))
            i += 1
        rt = f["returnType"].strip()
        owned = f["name"].startswith("Load") or f["name"].endswith("Alloc") or f["name"] in (
            "EncodeDataBase64",)
        wret = None
        if rt in ("const char *", "char *") and not owned:
            wret = "string"
            wrap = True
        return raw, ret, (wparams, wret) if wrap else None

    def gen_functions(self):
        plans = []
        for f in self.api["functions"]:
            plan = self.plan_function(f)
            if isinstance(plan, str):
                self.skipped.append((f["name"], plan))
                continue
            plans.append((f, plan))

        self.emit("// --- functions " + "-" * 62)
        self.emit("//")
        self.emit("// Bound from the raylib shared library when the program starts. A")
        self.emit("// function that takes C strings or (pointer, count) arrays is bound as")
        self.emit("// c_Name and wrapped by Name below, which takes Goose slices.")
        self.emit()
        self.emit('extern "raylib" {')
        for f, (raw, ret, wrap) in plans:
            ps = ", ".join(f"{n}: {g}" for n, g, _ in raw)
            r = f" -> {ret}" if ret else ""
            if wrap:
                self.emit(f'    fn c_{f["name"]}({ps}){r} = "{f["name"]}";{comment(f["description"])}')
                nullable = nullable_params(wrap[0])
                for mask in range(1, 1 << len(nullable)):
                    # The same symbol with NULL pointers, for empty slices.
                    nulls = {s for k, s in enumerate(nullable) if mask >> k & 1}
                    nps = ", ".join(f"{n}: {'u64' if n in nulls else g}" for n, g, _ in raw)
                    self.emit(f'    fn c_{f["name"]}{null_suffix(nullable, nulls)}({nps}){r} = "{f["name"]}";')
            else:
                self.emit(f"    fn {f['name']}({ps}){r};{comment(f['description'])}")
        self.emit("}")
        self.emit()
        self.emit("// --- wrappers " + "-" * 63)
        for f, (raw, ret, wrap) in plans:
            if wrap:
                self.gen_wrapper(f, raw, ret, *wrap)
        self.emit()
        self.emit("// Not bound (see README.md):")
        for n, why in self.skipped:
            self.emit(f"//   {n}: {why}")

    def gen_wrapper(self, f, raw, ret, wparams, wret):
        name = f["name"]
        sig, pre = [], []
        slices = nullable_params(wparams)
        for w in wparams:
            sig.append(f"{w[1]}: {w[2]}")
            if w[0] == "str":
                pre.append(f"let {w[1]}_z = cstring({w[1]});")

        def call(nulls):
            args = []
            for w in wparams:
                kind, n = w[0], w[1]
                if kind == "str":
                    args.append("0" if n in nulls else f"{n}_z[0]")
                elif kind == "slice":
                    args += ["0", "0"] if n in nulls else [f"{n}[0]", f"{n}.len as i32"]
                else:
                    args.append(n)
            return f"c_{name}{null_suffix(slices, nulls)}({', '.join(args)})"

        r = " -> u8[>..]" if wret == "string" else (f" -> {ret}" if ret else "")
        if slices and wret == "string":
            raise ValueError(f"{name}: string result and NULL arguments")
        self.emit()
        self.emit(f"fn {name}({', '.join(sig)}){r} {{")
        for p in pre:
            self.emit(f"    {p}")
        # An empty slice has no first element to point at: C gets NULL. So do
        # the empty strings of the arguments for which NULL means something.
        for mask in range((1 << len(slices)) - 1, 0, -1):
            nulls = {s for k, s in enumerate(slices) if mask >> k & 1}
            cond = " && ".join(f"{s}.len {'==' if s in nulls else '!='} 0" for s in slices)
            if ret:
                self.emit(f"    if {cond} {{ return {call(nulls)}; }}")
            else:
                self.emit(f"    if {cond} {{ {call(nulls)}; return; }}")
        if wret == "string":
            self.emit(f"    return ffi::cstr({call(set())});")
        elif ret:
            self.emit(f"    return {call(set())};")
        else:
            self.emit(f"    {call(set())};")
        self.emit("}")

    def generate(self):
        self.emit("// rl: raylib bindings for Goose. GENERATED by tools/gen_bindings.py from")
        self.emit(f"// raylib {self.api_version()}'s raylib_api.json; edit the generator, not this file.")
        self.emit("//")
        self.emit("// Every raylib function keeps its C name, in the namespace rl:")
        self.emit('// rl::InitWindow(800, 450, "Goose"), rl::DrawText("hi", 10, 10, 20, rl::RED).')
        self.emit("// Hand-written helpers are in rl_extras.goose, raymath in raymath.goose.")
        self.emit()
        self.emit("namespace rl;")
        self.emit()
        self.emit("import ffi;")
        self.emit("import rl_extras;")
        self.emit("import raymath;")
        self.emit()
        self.emit("// A NUL-terminated copy of s, for the C functions that take a const char *.")
        self.emit("fn cstring(s: const u8[:]) -> u8[>..] {")
        self.emit("    var z: u8[>..] = [];")
        self.emit("    for c in s { z.push(c); }")
        self.emit("    z.push(0);")
        self.emit("    return z;")
        self.emit("}")
        self.emit()
        self.gen_constants()
        self.gen_structs()
        self.gen_functions()
        return "\n".join(self.out) + "\n"

    def api_version(self):
        for d in self.api["defines"]:
            if d["name"] == "RAYLIB_VERSION":
                return d["value"]
        return "?"


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "raylib_api.json")
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "rl.goose")
    with open(src, encoding="utf-8") as fh:
        api = json.load(fh)
    g = Generator(api)
    text = g.generate()
    with open(dst, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    bound = len(api["functions"]) - len(g.skipped)
    print(f"wrote {dst}: {bound} of {len(api['functions'])} functions bound, {len(g.skipped)} skipped")


if __name__ == "__main__":
    main()
