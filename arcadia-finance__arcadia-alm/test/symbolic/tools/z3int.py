#!/usr/bin/env -S python3 -I
"""Local SMT solver command for `forge test --symbolic`: QF_BV queries are translated exactly to integer arithmetic
and raced against the original query, both on z3."""

import codecs
import itertools
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading
import time

Z3 = os.environ.get("Z3INT_Z3") or shutil.which("z3") or "/opt/homebrew/bin/z3"
RACE_DELAY = float(os.environ.get("Z3INT_RACE_DELAY", "0.25"))
TIMEOUT = os.environ.get("Z3INT_TIMEOUT")
LOG_DIR = os.environ.get("Z3INT_LOG")
INT_OPTIONS = ["", "(set-option :smt.arith.solver 2)\n"]
MAX_MASK_RUNS = 16
MAX_SHIFT_CASES = 64
DELIMITERS = ' \t\r\n();|"'


class Unsupported(Exception):
    pass


class Empty(Exception):
    pass


class InvalidModel(Exception):
    pass


# S-expressions


def tokens(text):
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
        elif c == ";":
            j = text.find("\n", i)
            i = n if j < 0 else j + 1
        elif c in "()":
            yield c
            i += 1
        elif c == "|":
            j = text.index("|", i + 1)
            body = text[i + 1 : j]
            yield (
                body
                if body and not any(ch in DELIMITERS for ch in body)
                else text[i : j + 1]
            )
            i = j + 1
        elif c == '"':
            j = i + 1
            while True:
                j = text.index('"', j)
                if j + 1 < n and text[j + 1] == '"':
                    j += 2
                    continue
                break
            yield text[i : j + 1]
            i = j + 1
        else:
            j = i
            while j < n and text[j] not in DELIMITERS:
                j += 1
            yield text[i:j]
            i = j


def parse(text):
    stack, out = [], []
    for tok in tokens(text):
        if tok == "(":
            stack.append([])
        elif tok == ")":
            node = stack.pop()
            (stack[-1] if stack else out).append(node)
        else:
            (stack[-1] if stack else out).append(tok)
    if stack:
        raise ValueError("unbalanced s-expression")
    return out


def unparse(t):
    if isinstance(t, str):
        return t
    return "(" + " ".join(unparse(x) for x in t) + ")"


def key(t):
    return t if isinstance(t, str) else tuple(key(x) for x in t)


class Splitter:
    """Cuts a character stream into complete top-level commands."""

    def __init__(self):
        self.buf = ""
        self.pos = 0
        self.start = None
        self.depth = 0
        self.mode = None

    def feed(self, chunk):
        self.buf += chunk
        out = []
        i, buf = self.pos, self.buf
        while i < len(buf):
            c = buf[i]
            if self.mode == ";":
                if c == "\n":
                    self.mode = None
            elif self.mode == "|":
                if c == "|":
                    self.mode = None
            elif self.mode == '"':
                if c == '"':
                    self.mode = None
            elif c == ";":
                self.mode = ";"
            elif c == "|":
                self.mode = "|"
            elif c == '"':
                self.mode = '"'
            elif c == "(":
                if self.depth == 0:
                    self.start = i
                self.depth += 1
            elif c == ")":
                self.depth -= 1
                if self.depth == 0:
                    out.append(buf[self.start : i + 1])
                    self.start = None
            i += 1
        cut = self.start if self.start is not None else i
        self.buf = buf[cut:]
        self.pos = i - cut
        if self.start is not None:
            self.start = 0
        return out


# Sorts and literals


def sort_of(s):
    if s == "Bool":
        return "Bool"
    if isinstance(s, list) and len(s) == 3 and s[0] == "_" and s[1] == "BitVec":
        return int(s[2])
    raise Unsupported(f"sort {unparse(s)}")


def literal(t):
    """Returns (value, width) for a bit-vector literal, or None."""
    if isinstance(t, str):
        if t.startswith("#x"):
            return int(t[2:], 16), 4 * (len(t) - 2)  # noqa: FURB166
        if t.startswith("#b"):
            return int(t[2:], 2), len(t) - 2  # noqa: FURB166
        return None
    if (
        len(t) == 3
        and t[0] == "_"
        and isinstance(t[1], str)
        and t[1].startswith("bv")
        and t[1][2:].isdigit()
    ):
        return int(t[1][2:]), int(t[2])
    return None


def bv_text(v, w):
    if w % 4 == 0:
        return "#x" + format(v, "0" + str(w // 4) + "x")
    return "#b" + format(v, "0" + str(w) + "b")


def num(v):
    return str(v) if v >= 0 else f"(- {-v})"


# Bit-vector evaluation, used to validate models and answer get-value


def evaluate(t, scope):
    if isinstance(t, str):
        if t in scope:
            return scope[t]
        if t == "true":
            return True
        if t == "false":
            return False
        lit = literal(t)
        if lit is None:
            raise Unsupported(f"symbol {t}")
        return lit
    lit = literal(t)
    if lit is not None:
        return lit
    head = t[0]
    if head == "let":
        inner = dict(scope)
        for name, val in t[1]:
            inner[name] = evaluate(val, scope)
        return evaluate(t[2], inner)
    if head == "!":
        return evaluate(t[1], scope)
    args = [evaluate(a, scope) for a in t[1:]]
    if isinstance(head, list):
        return eval_indexed(head, args)
    return eval_op(head, args)


def eval_indexed(head, args):
    op, idx = head[1], [int(x) for x in head[2:]]
    (v, w) = args[0]
    if op == "extract":
        i, j = idx
        return (v >> j) & ((1 << (i - j + 1)) - 1), i - j + 1
    if op == "zero_extend":
        return v, w + idx[0]
    if op == "sign_extend":
        k = idx[0]
        return (v + ((1 << (w + k)) - (1 << w)) if v >> (w - 1) else v), w + k
    if op == "repeat":
        out = 0
        for _ in range(idx[0]):
            out = (out << w) | v
        return out, w * idx[0]
    if op in ("rotate_left", "rotate_right"):
        k = idx[0] % w
        if op == "rotate_right":
            k = (w - k) % w
        return ((v << k) | (v >> (w - k))) & ((1 << w) - 1), w
    raise Unsupported(f"indexed {op}")


def eval_op(op, args):
    if op == "not":
        return not args[0]
    if op == "and":
        return all(args)
    if op == "or":
        return any(args)
    if op == "xor":
        out = False
        for a in args:
            out ^= a
        return out
    if op == "=>":
        out = args[-1]
        for a in reversed(args[:-1]):
            out = (not a) or out
        return out
    if op == "=":
        return all(args[i] == args[i + 1] for i in range(len(args) - 1))
    if op == "distinct":
        return len(set(args)) == len(args)
    if op == "ite":
        return args[1] if args[0] else args[2]
    w = args[0][1]
    m = (1 << w) - 1
    vals = [a[0] for a in args]
    if op in ("bvadd", "bvmul", "bvand", "bvor", "bvxor", "concat") and len(vals) > 2:
        acc = args[0]
        for a in args[1:]:
            acc = eval_op(op, [acc, a])
        return acc
    if op == "concat":
        return (vals[0] << args[1][1]) | vals[1], w + args[1][1]
    a = vals[0]
    b = vals[1] if len(vals) > 1 else None
    if op == "bvnot":
        return m - a, w
    if op == "bvneg":
        return (-a) & m, w
    if op == "bvadd":
        return (a + b) & m, w
    if op == "bvsub":
        return (a - b) & m, w
    if op == "bvmul":
        return (a * b) & m, w
    if op == "bvudiv":
        return (m if b == 0 else a // b), w
    if op == "bvurem":
        return (a if b == 0 else a % b), w
    if op == "bvand":
        return a & b, w
    if op == "bvor":
        return a | b, w
    if op == "bvxor":
        return a ^ b, w
    if op == "bvnand":
        return m - (a & b), w
    if op == "bvnor":
        return m - (a | b), w
    if op == "bvxnor":
        return m - (a ^ b), w
    if op == "bvshl":
        return ((a << b) & m if b < w else 0), w
    if op == "bvlshr":
        return (a >> b if b < w else 0), w
    if op == "bvashr":
        s = a - (1 << w) if a >> (w - 1) else a
        return (s >> min(b, w - 1)) & m, w
    if op == "bvcomp":
        return (1 if a == b else 0), 1
    msb_a, msb_b = a >> (w - 1), (b >> (w - 1)) if b is not None else 0
    if op in ("bvsdiv", "bvsrem", "bvsmod"):
        na, nb = (-a) & m, (-b) & m
        if op == "bvsdiv":
            if not msb_a and not msb_b:
                return eval_op("bvudiv", [(a, w), (b, w)])
            if msb_a and not msb_b:
                return eval_op("bvneg", [eval_op("bvudiv", [(na, w), (b, w)])])
            if not msb_a and msb_b:
                return eval_op("bvneg", [eval_op("bvudiv", [(a, w), (nb, w)])])
            return eval_op("bvudiv", [(na, w), (nb, w)])
        if op == "bvsrem":
            if not msb_a and not msb_b:
                return eval_op("bvurem", [(a, w), (b, w)])
            if msb_a and not msb_b:
                return eval_op("bvneg", [eval_op("bvurem", [(na, w), (b, w)])])
            if not msb_a and msb_b:
                return eval_op("bvurem", [(a, w), (nb, w)])
            return eval_op("bvneg", [eval_op("bvurem", [(na, w), (nb, w)])])
        u = eval_op("bvurem", [(na if msb_a else a, w), (nb if msb_b else b, w)])
        if u[0] == 0 or (not msb_a and not msb_b):
            return u
        if msb_a and not msb_b:
            return eval_op("bvadd", [eval_op("bvneg", [u]), (b, w)])
        if not msb_a and msb_b:
            return eval_op("bvadd", [u, (b, w)])
        return eval_op("bvneg", [u])
    sa = a - (1 << w) if msb_a else a
    sb = b - (1 << w) if msb_b else b
    cmp = {
        "bvult": a < b,
        "bvule": a <= b,
        "bvugt": a > b,
        "bvuge": a >= b,
        "bvslt": sa < sb,
        "bvsle": sa <= sb,
        "bvsgt": sa > sb,
        "bvsge": sa >= sb,
    }
    if op in cmp:
        return cmp[op]
    raise Unsupported(f"op {op}")


# Translation to integer arithmetic


class IntT:
    """An integer term: expression, interval [lo, hi] it provably lies in, bit width (None when not a bit-vector),
    and tz, a number of low bits it provably has zero."""

    __slots__ = ("e", "hi", "lo", "tz", "w")

    def __init__(self, e, lo, hi, w, tz=0):
        self.e, self.lo, self.hi, self.w, self.tz = e, lo, hi, w, tz


def zeros(v):
    return (v & -v).bit_length() - 1 if v else 1 << 16


class BoolT:
    __slots__ = ("e",)

    def __init__(self, e):
        self.e = e


COMPARE = {"bvult": (0, "<"), "bvule": (0, "<="), "bvugt": (1, "<"), "bvuge": (1, "<=")}
SIGNED_COMPARE = {
    "bvslt": (0, "<"),
    "bvsle": (0, "<="),
    "bvsgt": (1, "<"),
    "bvsge": (1, "<="),
}


class Translator:
    """Translates a QF_BV assertion set to an equisatisfiable integer one.

    Every bit-vector term of width n becomes an integer equal to its unsigned value, so it lies in [0, 2^n).
    Wrap-around and division by zero are encoded exactly. Intervals drop a wrap only where they prove it never
    happens. Intervals may use bounds from top-level asserted comparisons with a literal ("facts"). Each fact is
    re-asserted on its subject's translation, so a model of the result satisfies every fact and every bound used.
    """

    def __init__(self, decls, defs, asserts):
        self.decls, self.defs, self.asserts = decls, defs, asserts
        self.out = []
        self.memo = {}
        self.count = 0
        self.syms = {}
        self.facts = {}
        self.fact_heads = set()
        self.fact_exprs = {}
        self.trace = None
        self.origin = {}

    def run(self):
        try:
            return self.translate()
        except Empty:
            return "(assert false)\n"

    def translate(self):
        self.prepare()
        body = [self.tr(a, {}).e for a in self.asserts]
        for k, (lo, hi) in self.facts.items():
            e = self.fact_exprs.get(k)
            if e is None:
                continue
            self.out.append(f"(assert (and (<= {num(lo)} {e}) (<= {e} {num(hi)})))")
        self.out.extend(f"(assert {e})" for e in body if e != "true")
        return "\n".join(self.out) + "\n"

    def prepare(self):
        for a in self.asserts:
            self.collect(a)
        for k in self.facts:
            if not isinstance(k, str):
                self.fact_heads.add((k[0], len(k)))
        for name, s in self.decls.items():
            self.syms[name] = self.declare(name, s)
        for name, s, body in self.defs:
            r = self.tr(body, {})
            if s == "Bool":
                if not isinstance(r, BoolT):
                    raise Unsupported("define-fun sort")
                self.syms[name] = r
            else:
                if not isinstance(r, IntT) or r.w != s:
                    raise Unsupported("define-fun sort")
                self.syms[name] = self.fact(name, r)

    def declare(self, name, s):
        if s == "Bool":
            self.out.append(f"(declare-fun {name} () Bool)")
            return BoolT(name)
        self.out.append(f"(declare-fun {name} () Int)")
        self.out.append(f"(assert (and (<= 0 {name}) (< {name} {1 << s})))")
        return self.fact(name, IntT(name, 0, (1 << s) - 1, s))

    # Facts

    def collect(self, a):
        if isinstance(a, list) and a and a[0] == "and":
            for x in a[1:]:
                self.collect(x)
            return
        neg = isinstance(a, list) and len(a) == 2 and a[0] == "not"
        t = a[1] if neg else a
        if not isinstance(t, list) or len(t) != 3:
            return
        op, x, y = t
        if op == "=" and not neg:
            for subj, lit in ((x, literal(y)), (y, literal(x))):
                if lit is not None and literal(subj) is None:
                    self.add_fact(subj, lit[0], lit[0])
            return
        if op not in COMPARE:
            return
        swap, rel = COMPARE[op]
        if swap:
            x, y = y, x
        strict = rel == "<"
        if neg:
            x, y, strict = y, x, not strict
        lx, ly = literal(x), literal(y)
        if ly is not None and lx is None:
            self.add_fact(x, 0, ly[0] - 1 if strict else ly[0])
        elif lx is not None and ly is None:
            self.add_fact(y, lx[0] + 1 if strict else lx[0], (1 << lx[1]) - 1)

    def add_fact(self, subj, lo, hi):
        k = key(subj)
        old = self.facts.get(k)
        if old is not None:
            lo, hi = max(lo, old[0]), min(hi, old[1])
        if lo > hi:
            raise Empty
        self.facts[k] = (lo, hi)

    def fact(self, k, r):
        f = self.facts.get(k)
        if f is None:
            return r
        self.fact_exprs.setdefault(k, r.e)
        lo, hi = max(r.lo, f[0]), min(r.hi, f[1])
        if lo > hi:
            raise Empty
        if lo == hi:
            return IntT(num(lo), lo, hi, r.w, zeros(lo))
        return IntT(r.e, lo, hi, r.w, r.tz)

    # Output

    def mk(self, body, lo, hi, w, tz=0):
        if lo > hi:
            raise Empty
        if lo == hi:
            return IntT(num(lo), lo, hi, w, zeros(lo))
        if "(" not in body:
            return IntT(body, lo, hi, w, tz)
        name = self.memo.get(body)
        if name is None:
            self.count += 1
            name = f"_i{self.count}"
            self.memo[body] = name
            self.out.append(f"(define-fun {name} () Int {body})")
        return IntT(name, lo, hi, w, tz)

    def mkb(self, body):
        if "(" not in body:
            return BoolT(body)
        name = self.memo.get(body)
        if name is None:
            self.count += 1
            name = f"_b{self.count}"
            self.memo[body] = name
            self.out.append(f"(define-fun {name} () Bool {body})")
        return BoolT(name)

    def const(self, v, w):
        return IntT(num(v), v, v, w, zeros(v))

    # Terms

    def tr(self, t, env):
        if isinstance(t, str):
            if t in env:
                return env[t]
            if t in ("true", "false"):
                return BoolT(t)
            lit = literal(t)
            if lit is not None:
                return self.const(*lit)
            if t in self.syms:
                return self.syms[t]
            raise Unsupported(f"symbol {t}")
        lit = literal(t)
        if lit is not None:
            return self.const(*lit)
        head = t[0]
        if head == "let":
            inner = dict(env)
            for name, val in t[1]:
                inner[name] = self.tr(val, env)
            return self.tr(t[2], inner)
        if head == "!":
            return self.tr(t[1], env)
        r = self.tr_op(t, env)
        if (
            not env
            and isinstance(r, IntT)
            and self.fact_heads
            and (key(head), len(t)) in self.fact_heads
        ):
            r = self.fact(key(t), r)
        if self.trace is not None and not env:
            self.trace.append((t, r))
        return r

    def tr_op(self, t, env):
        head = t[0]
        args = [self.tr(a, env) for a in t[1:]]
        if isinstance(head, list):
            if head[0] != "_":
                raise Unsupported(f"head {unparse(head)}")
            return self.indexed(head[1], [int(x) for x in head[2:]], args[0])
        if not isinstance(head, str):
            raise Unsupported("head")
        if head in ("not", "and", "or", "xor", "=>"):
            return self.boolean(head, args)
        if head in ("=", "distinct"):
            if isinstance(args[0], BoolT):
                if head == "=":
                    return self.boolean(
                        "and",
                        [
                            self.mkb(f"(= {a.e} {b.e})")
                            for a, b in itertools.pairwise(args)
                        ],
                    )
                pairs = [
                    self.mkb(f"(= {a.e} {b.e})")
                    for i, a in enumerate(args)
                    for b in args[i + 1 :]
                ]
                return self.boolean("not", [self.boolean("or", pairs)])
            if head == "=":
                return self.boolean(
                    "and", [self.eq(a, b) for a, b in itertools.pairwise(args)]
                )
            pairs = [self.eq(a, b) for i, a in enumerate(args) for b in args[i + 1 :]]
            return self.boolean("not", [self.boolean("or", pairs)])
        if head == "ite":
            c, a, b = args
            if c.e == "true":
                return a
            if c.e == "false":
                return b
            if isinstance(a, BoolT):
                return self.mkb(f"(ite {c.e} {a.e} {b.e})")
            return self.ite(c, a, b)
        if any(not isinstance(a, IntT) for a in args):
            raise Unsupported(f"sorts of {head}")
        if head in COMPARE:
            swap, rel = COMPARE[head]
            a, b = (args[1], args[0]) if swap else args
            return self.lt(a, b) if rel == "<" else self.le(a, b)
        if head in SIGNED_COMPARE:
            swap, rel = SIGNED_COMPARE[head]
            a, b = (args[1], args[0]) if swap else args
            a, b = self.signed(a), self.signed(b)
            return self.lt(a, b) if rel == "<" else self.le(a, b)
        n = args[0].w
        if (
            head in ("bvadd", "bvmul", "bvand", "bvor", "bvxor", "concat")
            and len(args) > 2
        ):
            acc = args[0]
            for a in args[1:]:
                acc = self.binary(head, acc, a)
            return acc
        if len(args) == 1:
            if head == "bvnot":
                return self.bvnot(args[0])
            if head == "bvneg":
                return self.neg(args[0])
            raise Unsupported(f"op {head}")
        if len(args) != 2:
            raise Unsupported(f"arity of {head}")
        if head in ("bvadd", "bvmul", "bvand", "bvor", "bvxor", "concat"):
            return self.binary(head, args[0], args[1])
        a, b = args
        if head == "bvsub":
            return self.sub(a, b)
        if head == "bvudiv":
            return self.udiv(a, b)
        if head == "bvurem":
            return self.urem(a, b)
        if head in ("bvsdiv", "bvsrem", "bvsmod"):
            return self.signed_division(head, a, b)
        if head in ("bvshl", "bvlshr", "bvashr"):
            return self.shift(head, a, b)
        if head in ("bvnand", "bvnor", "bvxnor"):
            return self.bvnot(
                self.binary(
                    {"bvnand": "bvand", "bvnor": "bvor", "bvxnor": "bvxor"}[head], a, b
                )
            )
        if head == "bvcomp":
            return self.ite(self.eq(a, b), self.const(1, 1), self.const(0, 1))
        raise Unsupported(f"op {head} width {n}")

    def binary(self, op, a, b):
        if op == "bvadd":
            return self.add(a, b)
        if op == "bvmul":
            return self.mul(a, b)
        if op == "concat":
            return self.concat(a, b)
        return self.bitwise(op, a, b)

    def boolean(self, op, args):
        es = [a.e for a in args]
        if op == "not":
            e = es[0]
            if e in ("true", "false"):
                return BoolT("false" if e == "true" else "true")
            return self.mkb(f"(not {e})")
        if op == "and":
            if "false" in es:
                return BoolT("false")
            es = [e for e in es if e != "true"]
            if not es:
                return BoolT("true")
            return (
                BoolT(es[0]) if len(es) == 1 else self.mkb("(and " + " ".join(es) + ")")
            )
        if op == "or":
            if "true" in es:
                return BoolT("true")
            es = [e for e in es if e != "false"]
            if not es:
                return BoolT("false")
            return (
                BoolT(es[0]) if len(es) == 1 else self.mkb("(or " + " ".join(es) + ")")
            )
        if op == "=>":
            out = args[-1]
            for a in reversed(args[:-1]):
                out = self.boolean("or", [self.boolean("not", [a]), out])
            return out
        return self.mkb("(xor " + " ".join(es) + ")")

    def lt(self, a, b):
        if a.hi < b.lo:
            return BoolT("true")
        if a.lo >= b.hi:
            return BoolT("false")
        return self.mkb(f"(< {a.e} {b.e})")

    def le(self, a, b):
        if a.hi <= b.lo:
            return BoolT("true")
        if a.lo > b.hi:
            return BoolT("false")
        return self.mkb(f"(<= {a.e} {b.e})")

    def eq(self, a, b, depth=0):
        if a.hi < b.lo or b.hi < a.lo:
            return BoolT("false")
        if a.e == b.e:
            return BoolT("true")
        if depth < 2:
            for q, y in ((a, b), (b, a)):
                r = self.quotient_eq(q, y, depth)
                if r is not None:
                    return r
        return self.mkb(f"(= {a.e} {b.e})")

    def quotient_eq(self, q, y, depth):
        """(x * y mod 2^n) / x == y holds exactly when x * y < 2^n, for x > 0."""
        o = self.origin.get(q.e)
        if o is None:
            return None
        if o[0] == "ite":
            c, a, b = o[1:]
            if any(self.origin.get(t.e, ("",))[0] == "udiv" for t in (a, b)):
                return self.bite(c, self.eq(a, y, depth + 1), self.eq(b, y, depth + 1))
            return None
        if o[0] != "udiv":
            return None
        p, x = o[1:]
        po = self.origin.get(p.e)
        if po is None or po[0] != "mul":
            return None
        u, v, prod = po[1:]
        if not ((u.e == x.e and v.e == y.e) or (v.e == x.e and u.e == y.e)):
            return None
        fits = self.lt(prod, self.const(1 << q.w, None))
        if x.lo > 0:
            return fits
        return self.bite(
            self.eq(x, self.const(0, x.w)),
            self.eq(y, self.const((1 << q.w) - 1, q.w)),
            fits,
        )

    def bite(self, c, a, b):
        if c.e == "true":
            return a
        if c.e == "false":
            return b
        if a.e == b.e:
            return a
        return self.mkb(f"(ite {c.e} {a.e} {b.e})")

    def ite(self, c, a, b):
        if c.e == "true":
            return a
        if c.e == "false":
            return b
        if a.e == b.e:
            return IntT(a.e, max(a.lo, b.lo), min(a.hi, b.hi), a.w, max(a.tz, b.tz))
        r = self.mk(
            f"(ite {c.e} {a.e} {b.e})",
            min(a.lo, b.lo),
            max(a.hi, b.hi),
            a.w,
            min(a.tz, b.tz),
        )
        self.origin.setdefault(r.e, ("ite", c, a, b))
        return r

    def wrap(self, s, w):
        """s mod 2^w for an integer s known to lie in [s.lo, s.hi]."""
        m, tz = 1 << w, min(s.tz, w)
        if s.lo >= 0 and s.hi < m:
            return IntT(s.e, s.lo, s.hi, w, tz)
        if s.lo // m == s.hi // m:
            c = (s.lo // m) * m
            return self.mk(f"(- {s.e} {num(c)})", s.lo - c, s.hi - c, w, tz)
        if -m <= s.lo and s.hi < m:
            return self.mk(f"(ite (< {s.e} 0) (+ {s.e} {m}) {s.e})", 0, m - 1, w, tz)
        if 0 <= s.lo and s.hi < 2 * m:
            return self.mk(f"(ite (< {s.e} {m}) {s.e} (- {s.e} {m}))", 0, m - 1, w, tz)
        return self.mk(f"(mod {s.e} {m})", 0, m - 1, w, tz)

    def add(self, a, b):
        return self.wrap(
            self.mk(
                f"(+ {a.e} {b.e})", a.lo + b.lo, a.hi + b.hi, None, min(a.tz, b.tz)
            ),
            a.w,
        )

    def sub(self, a, b):
        if b.hi == 0:
            return a
        return self.wrap(
            self.mk(
                f"(- {a.e} {b.e})", a.lo - b.hi, a.hi - b.lo, None, min(a.tz, b.tz)
            ),
            a.w,
        )

    def mul(self, a, b):
        p = self.mk(f"(* {a.e} {b.e})", a.lo * b.lo, a.hi * b.hi, None, a.tz + b.tz)
        r = self.wrap(p, a.w)
        self.origin.setdefault(r.e, ("mul", a, b, p))
        return r

    def neg(self, a):
        return self.wrap(self.mk(f"(- {a.e})", -a.hi, -a.lo, None, a.tz), a.w)

    def bvnot(self, a):
        m = (1 << a.w) - 1
        return self.mk(f"(- {m} {a.e})", m - a.hi, m - a.lo, a.w)

    def udiv(self, a, b):
        m = (1 << a.w) - 1
        if b.lo > 0:
            r = self.mk(f"(div {a.e} {b.e})", a.lo // b.hi, a.hi // b.lo, a.w)
        elif b.hi == 0:
            return self.const(m, a.w)
        else:
            r = self.mk(
                f"(ite (= {b.e} 0) {m} (div {a.e} {b.e}))", a.lo // b.hi, m, a.w
            )
        self.origin.setdefault(r.e, ("udiv", a, b))
        return r

    def urem(self, a, b):
        if b.lo > a.hi or b.hi == 0:
            return a
        if b.lo > 0:
            return self.mk(f"(mod {a.e} {b.e})", 0, min(a.hi, b.hi - 1), a.w)
        return self.mk(f"(ite (= {b.e} 0) {a.e} (mod {a.e} {b.e}))", 0, a.hi, a.w)

    def signed(self, a):
        h, m = 1 << (a.w - 1), 1 << a.w
        tz = min(a.tz, a.w)
        if a.hi < h:
            return IntT(a.e, a.lo, a.hi, None, tz)
        if a.lo >= h:
            return self.mk(f"(- {a.e} {m})", a.lo - m, a.hi - m, None, tz)
        return self.mk(f"(ite (< {a.e} {h}) {a.e} (- {a.e} {m}))", -h, h - 1, None, tz)

    def msb(self, a):
        return self.le(self.const(1 << (a.w - 1), None), a)

    def signed_division(self, op, a, b):
        sa, sb = self.msb(a), self.msb(b)
        pa, pb = self.boolean("not", [sa]), self.boolean("not", [sb])
        na, nb = self.neg(a), self.neg(b)
        both_pos = self.boolean("and", [pa, pb])
        a_neg = self.boolean("and", [sa, pb])
        b_neg = self.boolean("and", [pa, sb])
        if op == "bvsdiv":
            return self.ite(
                both_pos,
                self.udiv(a, b),
                self.ite(
                    a_neg,
                    self.neg(self.udiv(na, b)),
                    self.ite(b_neg, self.neg(self.udiv(a, nb)), self.udiv(na, nb)),
                ),
            )
        if op == "bvsrem":
            return self.ite(
                both_pos,
                self.urem(a, b),
                self.ite(
                    a_neg,
                    self.neg(self.urem(na, b)),
                    self.ite(b_neg, self.urem(a, nb), self.neg(self.urem(na, nb))),
                ),
            )
        u = self.urem(self.ite(sa, na, a), self.ite(sb, nb, b))
        return self.ite(
            self.boolean("or", [self.eq(u, self.const(0, a.w)), both_pos]),
            u,
            self.ite(
                a_neg,
                self.add(self.neg(u), b),
                self.ite(b_neg, self.add(u, b), self.neg(u)),
            ),
        )

    def concat(self, a, b):
        s = 1 << b.w
        return self.mk(
            f"(+ (* {s} {a.e}) {b.e})",
            a.lo * s + b.lo,
            a.hi * s + b.hi,
            a.w + b.w,
            min(a.tz + b.w, b.tz),
        )

    def extract(self, a, i, j):
        t = (
            a
            if j == 0
            else self.mk(
                f"(div {a.e} {1 << j})", a.lo >> j, a.hi >> j, None, max(0, a.tz - j)
            )
        )
        return self.wrap(t, i - j + 1)

    def indexed(self, op, idx, a):
        if not isinstance(a, IntT):
            raise Unsupported(f"sort of {op}")
        if op == "extract":
            return self.extract(a, idx[0], idx[1])
        if op == "zero_extend":
            return IntT(a.e, a.lo, a.hi, a.w + idx[0], a.tz)
        if op == "sign_extend":
            k, h, tz = idx[0], 1 << (a.w - 1), min(a.tz, a.w)
            ext = (1 << (a.w + k)) - (1 << a.w)
            if a.hi < h:
                return IntT(a.e, a.lo, a.hi, a.w + k, tz)
            if a.lo >= h:
                return self.mk(f"(+ {a.e} {ext})", a.lo + ext, a.hi + ext, a.w + k, tz)
            return self.mk(
                f"(ite (< {a.e} {h}) {a.e} (+ {a.e} {ext}))",
                a.lo,
                a.hi + ext,
                a.w + k,
                tz,
            )
        if op == "repeat":
            out = a
            for _ in range(idx[0] - 1):
                out = self.concat(out, a)
            return out
        if op in ("rotate_left", "rotate_right"):
            k = idx[0] % a.w
            if op == "rotate_right":
                k = (a.w - k) % a.w
            if k == 0:
                return a
            return self.concat(
                self.extract(a, a.w - k - 1, 0), self.extract(a, a.w - 1, a.w - k)
            )
        raise Unsupported(f"indexed {op}")

    def shift_const(self, op, a, c):
        n = a.w
        if op == "bvshl":
            if c >= n:
                return self.const(0, n)
            return self.mul(a, self.const(1 << c, n))
        if op == "bvlshr":
            if c >= n:
                return self.const(0, n)
            return self.mk(
                f"(div {a.e} {1 << c})", a.lo >> c, a.hi >> c, n, max(0, a.tz - c)
            )
        c = min(c, n - 1)
        if c == 0:
            return a
        s = self.signed(a)
        q = self.mk(
            f"(div {s.e} {1 << c})", s.lo >> c, s.hi >> c, None, max(0, s.tz - c)
        )
        return self.wrap(q, n)

    def shift(self, op, a, b):
        if b.lo == b.hi:
            return self.shift_const(op, a, b.lo)
        top = min(b.hi, a.w)
        if top - b.lo > MAX_SHIFT_CASES:
            raise Unsupported(f"{op} by a variable amount")
        out = self.shift_const(op, a, top)
        for k in range(top - 1, b.lo - 1, -1):
            out = self.ite(
                self.eq(b, self.const(k, b.w)), self.shift_const(op, a, k), out
            )
        return out

    def and_const(self, a, mask):
        n = a.w
        mask &= (1 << a.hi.bit_length()) - 1
        if mask == 0:
            return self.const(0, n)
        runs, i = [], 0
        while mask >> i:
            if (mask >> i) & 1:
                j = i
                while (mask >> (j + 1)) & 1:
                    j += 1
                runs.append((i, j))
                i = j + 1
            else:
                i += 1
        if len(runs) > MAX_MASK_RUNS:
            raise Unsupported("bvand mask with many runs")
        parts = []
        for lo_bit, hi_bit in runs:
            x = self.extract(a, hi_bit, lo_bit)
            parts.append(
                x
                if lo_bit == 0
                else self.mk(
                    f"(* {1 << lo_bit} {x.e})", x.lo << lo_bit, x.hi << lo_bit, None
                )
            )
        out = parts[0]
        for p in parts[1:]:
            out = self.mk(f"(+ {out.e} {p.e})", out.lo + p.lo, out.hi + p.hi, None)
        return IntT(out.e, out.lo, min(out.hi, a.hi), n, max(a.tz, runs[0][0]))

    def bitwise(self, op, a, b):
        n = a.w
        m = (1 << n) - 1
        if b.lo == b.hi and a.lo != a.hi:
            a, b = b, a
        if a.lo == a.hi:
            c = a.lo
            if op == "bvand":
                return self.and_const(b, c)
            x = self.and_const(b, c)
            tz = min(b.tz, zeros(c))
            if op == "bvor":
                return self.mk(
                    f"(- (+ {b.e} {c}) {x.e})", max(b.lo, c), min(b.hi + c, m), n, tz
                )
            return self.mk(
                f"(- (+ {b.e} {c}) (* 2 {x.e}))",
                max(0, b.lo - c, c - b.hi),
                min(b.hi + c, m),
                n,
                tz,
            )
        if a.hi < (1 << min(b.tz, n)) or b.hi < (1 << min(a.tz, n)):
            if op == "bvand":
                return self.const(0, n)
            return self.mk(
                f"(+ {a.e} {b.e})", a.lo + b.lo, min(a.hi + b.hi, m), n, min(a.tz, b.tz)
            )
        if b.hi <= 1 and a.hi > 1:
            a, b = b, a
        if a.hi <= 1:
            bit = self.extract(b, 0, 0)
            if op == "bvand":
                return self.mk(f"(* {a.e} {bit.e})", 0, min(1, b.hi), n)
            if op == "bvor":
                return self.mk(
                    f"(+ {b.e} (* {a.e} (- 1 {bit.e})))", b.lo, min(b.hi + 1, m), n
                )
            return self.mk(
                f"(+ {b.e} (* {a.e} (- 1 (* 2 {bit.e}))))",
                max(0, b.lo - 1),
                min(b.hi + 1, m),
                n,
            )
        raise Unsupported(f"{op} of two variable terms")


# Solving


SENTINEL = """
import os, signal, sys, time
parent = int(sys.argv[1])
while os.getppid() == parent:
    time.sleep(0.2)
os.killpg(os.getpgrp(), signal.SIGKILL)
"""


class Group:
    """Solver children in one process group, killed by a sentinel if this process dies."""

    def __init__(self):
        self.sentinel = None

    def spawn(self, args):
        if self.sentinel is None:
            self.sentinel = subprocess.Popen(
                [sys.executable, "-I", "-c", SENTINEL, str(os.getpid())],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                **pgroup(0),
            )
        return subprocess.Popen(
            args,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            **pgroup(self.sentinel.pid),
        )

    def close(self):
        if self.sentinel is not None:
            try:
                os.killpg(self.sentinel.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.sentinel.wait()
            self.sentinel = None


def pgroup(pgid):
    return {"process_group": pgid}


class Solver:
    def __init__(self, group, text, kind):
        args = [Z3, "-in"] + ([f"-T:{TIMEOUT}"] if TIMEOUT else [])
        self.kind = kind
        self.proc = group.spawn(args)
        self.errors = []
        threading.Thread(
            target=self.write, args=(text + "(check-sat)\n",), daemon=True
        ).start()

    def write(self, text):
        try:
            self.proc.stdin.write(text.encode())
            self.proc.stdin.flush()
        except (BrokenPipeError, OSError):
            pass

    def status(self):
        while True:
            line = self.proc.stdout.readline().decode()
            if not line:
                return "unknown"
            line = line.strip()
            if line in ("sat", "unsat", "unknown"):
                return line
            if line == "timeout":
                return "unknown"
            if line:
                self.errors.append(line)

    def ask(self, command):
        self.write(command + "\n")
        out, depth, started = [], 0, False
        while True:
            line = self.proc.stdout.readline().decode()
            if not line:
                break
            out.append(line)
            for tok in tokens(line):
                if tok == "(":
                    depth += 1
                    started = True
                elif tok == ")":
                    depth -= 1
            if started and depth <= 0 or (not started and line.strip()):
                break
        return "".join(out)

    def kill(self):
        try:
            self.proc.kill()
        except ProcessLookupError:
            pass
        self.proc.wait()


class Session:
    def __init__(self):
        self.group = Group()
        self.frames = []
        self.logic = None
        self.raw = []
        self.decls = {}
        self.order = []
        self.defs = []
        self.asserts = []
        self.answer = None
        self.model = None
        self.source = None

    def run(self, stream):
        splitter = Splitter()
        decoder = codecs.getincrementaldecoder("utf-8")()
        try:
            while True:
                chunk = os.read(stream, 1 << 16)
                if not chunk:
                    break
                for text in splitter.feed(decoder.decode(chunk)):
                    if self.command(text) == "exit":
                        return
        finally:
            self.drop_source()
            self.group.close()

    def emit(self, text):
        sys.stdout.write(text if text.endswith("\n") else text + "\n")
        sys.stdout.flush()

    def command(self, text):
        cmd = parse(text)[0]
        head = cmd[0]
        if head == "exit":
            return "exit"
        if head == "check-sat":
            self.check()
        elif head == "get-model":
            self.get_model()
        elif head == "get-value":
            self.get_value(cmd[1], text)
        elif head in (
            "get-info",
            "get-option",
            "get-assertions",
            "get-proof",
            "get-unsat-core",
        ):
            if self.source is not None:
                self.emit(self.source.ask(text))
            else:
                self.emit('(error "unsupported")')
        else:
            if head == "push":
                for _ in range(int(cmd[1]) if len(cmd) > 1 else 1):
                    self.frames.append(
                        (
                            len(self.raw),
                            dict(self.decls),
                            list(self.order),
                            len(self.defs),
                            len(self.asserts),
                        )
                    )
            elif head == "pop":
                for _ in range(int(cmd[1]) if len(cmd) > 1 else 1):
                    n_raw, self.decls, self.order, n_defs, n_asserts = self.frames.pop()
                    del self.raw[n_raw:], self.defs[n_defs:], self.asserts[n_asserts:]
            elif head == "declare-fun":
                self.declare(cmd[1], cmd[2], cmd[3])
            elif head == "declare-const":
                self.declare(cmd[1], [], cmd[2])
            elif head == "define-fun":
                self.define(cmd)
            elif head == "assert":
                self.asserts.append(cmd[1])
            elif head == "set-logic":
                self.logic = cmd[1]
            self.raw.append(text)
        return None

    def declare(self, name, params, s):
        try:
            if params:
                raise Unsupported("uninterpreted function")
            self.decls[name] = sort_of(s)
        except Unsupported:
            self.decls[name] = None
        self.order.append(name)

    def define(self, cmd):
        _, name, params, s, body = cmd
        try:
            if params:
                raise Unsupported("define-fun with parameters")
            self.defs.append((name, sort_of(s), body))
        except Unsupported:
            self.defs.append((name, None, body))

    def translate(self):
        if self.logic not in (None, "QF_BV", "ALL"):
            raise Unsupported(f"logic {self.logic}")
        if any(s is None for s in self.decls.values()) or any(
            d[1] is None for d in self.defs
        ):
            raise Unsupported("non bit-vector declaration")
        return Translator(self.decls, self.defs, self.asserts).run()

    def drop_source(self):
        if self.source is not None:
            self.source.kill()
            self.source = None

    def check(self):
        self.drop_source()
        self.answer, self.model = None, None
        started = time.monotonic()
        original = "".join(t + "\n" for t in self.raw)
        try:
            translated, reason = self.translate(), ""
        except Unsupported as e:
            translated, reason = None, str(e)
        except RecursionError:
            translated, reason = None, "recursion depth"
        stamp = self.log_query(original, translated) if LOG_DIR else None
        results = queue.Queue()
        running = {}

        def launch(kind, text):
            solver = Solver(self.group, text, kind)
            running[kind] = solver
            threading.Thread(
                target=lambda: results.put((kind, solver.status())), daemon=True
            ).start()

        statuses = {}
        winner = None
        if translated is not None:
            for i, options in enumerate(INT_OPTIONS):
                launch(f"int{i}", options + translated)
        else:
            launch("bv", original)
        deadline = started + RACE_DELAY
        while winner is None and len(statuses) < len(running):
            wait = None
            if "bv" not in running:
                wait = max(0.0, deadline - time.monotonic())
            try:
                kind, st = results.get(timeout=wait)
            except queue.Empty:
                launch("bv", original)
                continue
            if kind != "bv" and st == "sat":
                try:
                    self.model = self.int_model(running[kind])
                except InvalidModel as e:
                    reason = f"invalid model: {e}"
                    sys.stderr.write(f"z3int: {reason}\n")
                    st = "invalid"
            statuses[kind] = st
            if st in ("sat", "unsat"):
                winner = kind
            elif "bv" not in running:
                launch("bv", original)
        for kind, solver in running.items():
            if kind == "bv" and winner == "bv":
                self.source = solver
            else:
                solver.kill()
        self.answer = statuses[winner] if winner else "unknown"
        if winner == "bv":
            for line in self.source.errors:
                self.emit(line)
        self.emit(self.answer)
        if LOG_DIR:
            self.log(stamp, statuses, winner, reason, time.monotonic() - started)

    def int_model(self, solver):
        ints = [n for n in self.order if self.decls.get(n) is not None]
        values = {}
        if ints:
            reply = parse(solver.ask("(get-value (" + " ".join(ints) + "))"))
            if not reply or not isinstance(reply[0], list):
                raise InvalidModel(f"get-value reply {reply!r}")
            for name, val in reply[0]:
                values[name] = val
        model = {}
        for name in ints:
            s = self.decls[name]
            v = values.get(name)
            if s == "Bool":
                if v not in ("true", "false"):
                    raise InvalidModel(f"{name} = {v!r}")
                model[name] = v == "true"
            else:
                if not isinstance(v, str) or not v.isdigit() or int(v) >= 1 << s:
                    raise InvalidModel(f"{name} = {v!r}")
                model[name] = (int(v), s)
        scope = dict(model)
        try:
            for name, _, body in self.defs:
                scope[name] = evaluate(body, scope)
            for a in self.asserts:
                if evaluate(a, scope) is not True:
                    raise InvalidModel("an assertion is false under the integer model")
        except Unsupported as e:
            raise InvalidModel(str(e))
        return scope

    def get_model(self):
        if self.source is not None:
            self.emit(self.source.ask("(get-model)"))
            return
        if self.answer != "sat" or self.model is None:
            self.emit('(error "model is not available")')
            return
        lines = ["("]
        names = [n for n in self.order if n in self.model] + [
            d[0] for d in self.defs if d[0] in self.model
        ]
        seen = set()
        for name in names:
            if name in seen:
                continue
            seen.add(name)
            v = self.model[name]
            if isinstance(v, bool):
                lines.append(
                    f"  (define-fun {name} () Bool {'true' if v else 'false'})"
                )
            else:
                lines.append(
                    f"  (define-fun {name} () (_ BitVec {v[1]}) {bv_text(*v)})"
                )
        lines.append(")")
        self.emit("\n".join(lines))

    def get_value(self, terms, text):
        if self.source is not None:
            self.emit(self.source.ask(text))
            return
        if self.answer != "sat" or self.model is None:
            self.emit('(error "model is not available")')
            return
        out = []
        for t in terms:
            v = evaluate(t, self.model)
            out.append(
                f"({unparse(t)} {('true' if v else 'false') if isinstance(v, bool) else bv_text(*v)})"
            )
        self.emit("(" + "\n ".join(out) + ")")

    def log_query(self, original, translated):
        stamp = f"{time.time_ns()}.{os.getpid()}"
        with open(os.path.join(LOG_DIR, f"q.{stamp}.smt2"), "w") as f:
            f.write(original + "(check-sat)\n")
        if translated is not None:
            with open(os.path.join(LOG_DIR, f"t.{stamp}.smt2"), "w") as f:
                f.write(translated + "(check-sat)\n")
        return stamp

    def log(self, stamp, statuses, winner, reason, elapsed):
        ints = [v for k, v in statuses.items() if k != "bv"]
        decided = [v for v in ints if v in ("sat", "unsat")]
        fields = [
            stamp,
            self.answer,
            winner or "-",
            (decided or ints or ["-"])[0],
            statuses.get("bv", "-"),
        ]
        fields += [f"{elapsed:.3f}", reason or "-"]
        with open(os.path.join(LOG_DIR, "log.tsv"), "a") as f:
            f.write("\t".join(fields) + "\n")


def translate_text(text):
    session = Session()
    for t in Splitter().feed(text):
        if parse(t)[0][0] not in ("check-sat", "get-model", "get-value", "exit"):
            session.command(t)
    return session.translate()


def main():
    if "--version" in sys.argv[1:]:
        os.execv(Z3, [Z3, "--version"])
    if "--translate" in sys.argv[1:]:
        sys.stdout.write(translate_text(sys.stdin.read()))
        return
    sys.setrecursionlimit(1 << 16)
    threading.stack_size(1 << 28)
    worker = threading.Thread(target=Session().run, args=(sys.stdin.fileno(),))
    worker.start()
    worker.join()


if __name__ == "__main__":
    main()
