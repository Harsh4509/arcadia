#!/usr/bin/env -S python3 -I
"""Differential checks for z3int.py against z3 on the original bit-vector queries.

corpus DIR...  every *.smt2 query: z3 on the original vs z3 on the translation
random         random 8 and 16 bit formulas: the same comparison, plus an exactness proof per formula that every
               translated subterm equals bv2nat of its bit-vector term and lies in its computed interval
"""

import argparse
import concurrent.futures
import importlib.util
import itertools
import pathlib
import random
import subprocess
import sys
import time

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("z3int", HERE / "z3int.py")
z3int = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z3int)


def run_z3(text, timeout):
    try:
        p = subprocess.run(
            [z3int.Z3, "-in", f"-T:{timeout}"],
            check=False,
            input=text,
            capture_output=True,
            text=True,
            timeout=timeout + 30,
        )
    except subprocess.TimeoutExpired:
        return "unknown", ""
    out = p.stdout.split("\n", 1)
    status = out[0].strip()
    if status not in ("sat", "unsat"):
        status = (
            "unknown"
            if status in ("unknown", "timeout", "")
            else f"error: {p.stdout.strip()[:200]}"
        )
    return status, out[1] if len(out) > 1 else ""


def load(text):
    session = z3int.Session()
    for t in z3int.Splitter().feed(text):
        if z3int.parse(t)[0][0] not in ("check-sat", "get-model", "get-value", "exit"):
            session.command(t)
    return session


def validate(session, reply):
    """Checks an integer get-value reply against the original assertions."""
    ints = [n for n in session.order if session.decls.get(n) is not None]
    values = {}
    if ints:
        parsed = z3int.parse(reply)
        if not parsed or not isinstance(parsed[0], list):
            return f"bad get-value reply {reply[:200]!r}"
        values = {n: v for n, v in parsed[0]}
    scope = {}
    for n in ints:
        s, v = session.decls[n], values.get(n)
        scope[n] = (v == "true") if s == "Bool" else (int(v), s)
    for name, _, body in session.defs:
        scope[name] = z3int.evaluate(body, scope)
    for a in session.asserts:
        if z3int.evaluate(a, scope) is not True:
            return "model violates an assertion"
    return None


def differential(text, timeout):
    """Returns a result dict for one query."""
    session = load(text)
    original = "".join(t + "\n" for t in session.raw) + "(check-sat)\n"
    res = {"translated": False, "reason": "", "bv": "-", "int": "-", "problem": None}
    t0 = time.monotonic()
    res["bv"], _ = run_z3(original, timeout)
    res["bv_time"] = time.monotonic() - t0
    if res["bv"].startswith("error"):
        res["problem"] = f"z3 rejected the original: {res['bv']}"
    try:
        translated = session.translate()
    except z3int.Unsupported as e:
        res["reason"] = str(e)
        return res
    res["translated"] = True
    ints = [n for n in session.order if session.decls.get(n) is not None]
    query = (
        translated
        + "(check-sat)\n"
        + (f"(get-value ({' '.join(ints)}))\n" if ints else "")
    )
    t0 = time.monotonic()
    res["int"], rest = run_z3(query, timeout)
    res["int_time"] = time.monotonic() - t0
    if res["int"].startswith("error"):
        res["problem"] = f"z3 rejected the translation: {res['int']}"
    elif res["int"] == "sat":
        res["problem"] = validate(session, rest)
    if (
        res["bv"] in ("sat", "unsat")
        and res["int"] in ("sat", "unsat")
        and res["bv"] != res["int"]
    ):
        res["problem"] = f"answer mismatch: bv {res['bv']}, int {res['int']}"
    return res


class Traced(z3int.Translator):
    """Maps each bit-vector variable to (bv2nat x) so translated terms can be compared with the originals."""

    def declare(self, name, s):
        if s == "Bool":
            return z3int.BoolT(name)
        return self.fact(name, z3int.IntT(f"(bv2nat {name})", 0, (1 << s) - 1, s))


def exactness(text, timeout):
    """Proves with z3 that every traced subterm translation is exact and inside its interval, under the facts."""
    session = load(text)
    tr = Traced(session.decls, session.defs, session.asserts)
    tr.trace = []
    try:
        tr.translate()
    except z3int.Unsupported as e:
        return "unsupported", str(e)
    except z3int.Empty:
        return check_unsat(
            "".join(t + "\n" for t in session.raw), timeout, "empty translation"
        )
    head = "".join(
        t + "\n" for t in session.raw if not t.startswith(("(assert", "(set-logic"))
    )
    facts = fact_asserts(session, tr)
    defs = [line for line in tr.out if line.startswith("(define-fun")]
    conds = []
    for t, r in tr.trace:
        bv = z3int.unparse(t)
        if isinstance(r, z3int.IntT):
            conds.append(f"(= (bv2nat {bv}) {r.e})")
            conds.append(f"(<= {z3int.num(r.lo)} {r.e} {z3int.num(r.hi)})")
            tz = min(r.tz, 64)
            if tz:
                conds.append(f"(= (mod {r.e} {1 << tz}) 0)")
        else:
            conds.append(f"(= {bv} {r.e})")
    if not conds:
        return "ok", ""
    query = (
        head
        + "\n".join(facts + defs)
        + "\n(assert (not (and "
        + " ".join(conds)
        + ")))\n"
    )
    return check_unsat(query, timeout, "exactness")


def fact_asserts(session, tr):
    """The facts the translation used, as bit-vector assertions."""
    widths = {}
    for t, r in tr.trace:
        if isinstance(r, z3int.IntT):
            widths[z3int.key(t)] = r.w
    out = []
    for k, (lo, hi) in tr.facts.items():
        subj = untuple(k)
        if isinstance(k, str):
            w = session.decls.get(k) or next(d[1] for d in session.defs if d[0] == k)
        else:
            w = widths.get(k)
            if w is None:
                continue
        out.append(f"(assert (bvule (_ bv{lo} {w}) {z3int.unparse(subj)}))")
        out.append(f"(assert (bvule {z3int.unparse(subj)} (_ bv{hi} {w})))")
    return out


def int_eval(t, env, defs, cache):
    if isinstance(t, str):
        if t in env:
            return env[t]
        if t in cache:
            return cache[t]
        if t in defs:
            cache[t] = int_eval(defs[t], env, defs, cache)
            return cache[t]
        if t in ("true", "false"):
            return t == "true"
        return int(t)
    if t[0] == "ite":
        return int_eval(
            t[2] if int_eval(t[1], env, defs, cache) else t[3], env, defs, cache
        )
    op, args = t[0], [int_eval(a, env, defs, cache) for a in t[1:]]
    if op == "+":
        return sum(args)
    if op == "-":
        return -args[0] if len(args) == 1 else args[0] - sum(args[1:])
    if op == "*":
        out = 1
        for a in args:
            out *= a
        return out
    if op == "div":
        return args[0] // args[1] if args[1] > 0 else -(args[0] // -args[1])
    if op == "mod":
        return args[0] % abs(args[1])
    if op == "<":
        return args[0] < args[1]
    if op == "<=":
        return all(x <= y for x, y in itertools.pairwise(args))
    if op == "=":
        return args[0] == args[1]
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
    raise ValueError(f"int op {op}")


def sampled(text, seed, count, timeout):
    """Compares every traced subterm's translation with z3's value of the original subterm on sampled assignments."""
    session = load(text)
    tr = z3int.Translator(session.decls, session.defs, session.asserts)
    tr.trace = []
    try:
        tr.translate()
    except (z3int.Unsupported, z3int.Empty) as e:
        return "skipped", str(e)
    if not tr.trace:
        return "ok", 0
    rng = random.Random(seed)
    defs = {}
    for line in tr.out:
        if line.startswith("(define-fun"):
            d = z3int.parse(line)[0]
            defs[d[1]] = d[4]
    names = [n for n in session.order if session.decls.get(n) is not None]
    head = "".join(
        t + "\n" for t in session.raw if not t.startswith("(assert")
    ) + "\n".join(fact_asserts(session, tr))
    terms = " ".join(z3int.unparse(t) for t, _ in tr.trace)
    assignments, blocks = [], []
    for _ in range(count):
        env = {}
        for n in names:
            s = session.decls[n]
            if s == "Bool":
                env[n] = rng.random() < 0.5
                continue
            lo, hi = tr.facts.get(n, (0, (1 << s) - 1))
            special = [lo, hi, 0, 1, (1 << s) - 1, 1 << (s - 1), (1 << (s - 1)) - 1]
            v = rng.choice(special) if rng.random() < 0.4 else rng.randint(lo, hi)
            env[n] = v
        assignments.append(env)
        eqs = " ".join(
            f"(= {n} {('true' if env[n] else 'false') if session.decls[n] == 'Bool' else z3int.bv_text(env[n], session.decls[n])})"
            for n in names
        )
        blocks.append(
            f"(push)\n(assert (and true {eqs}))\n(check-sat)\n(get-value ({terms}))\n(pop)\n"
        )
    try:
        p = subprocess.run(
            [z3int.Z3, "-in", f"-T:{timeout}"],
            check=False,
            input=head + "\n" + "".join(blocks),
            capture_output=True,
            text=True,
            timeout=timeout + 30,
        )
    except subprocess.TimeoutExpired:
        return "unknown", "timeout"
    replies = z3int.parse(p.stdout)
    checked = 0
    i = 0
    for env in assignments:
        st = replies[i] if i < len(replies) else None
        i += 1
        if st == "unsat":
            i += 1
            continue
        if st != "sat":
            return "unknown", f"status {st!r}"
        values = replies[i]
        i += 1
        if not isinstance(values, list) or len(values) != len(tr.trace):
            return "error", f"get-value reply {z3int.unparse(values)[:300]}"
        cache = {}
        scope = {
            n: (env[n] if session.decls[n] == "Bool" else (env[n], session.decls[n]))
            for n in names
        }
        for name, _, body in session.defs:
            scope[name] = z3int.evaluate(body, scope)
        for (t, r), (_, val) in zip(tr.trace, values):
            ref = z3int.literal(val)
            ref = (val == "true") if ref is None else ref[0]
            mine = z3int.evaluate(t, scope)
            mine = mine if isinstance(mine, bool) else mine[0]
            if mine != ref:
                return (
                    "error",
                    f"evaluator: {z3int.unparse(t)} is {mine}, z3 says {val} under {env}",
                )
            got = int_eval(z3int.parse(r.e)[0], {n: env[n] for n in names}, defs, cache)
            if isinstance(r, z3int.IntT):
                tz = min(r.tz, 1 << 12)
                if got != ref or not (r.lo <= got <= r.hi) or got % (1 << tz):
                    return "error", (
                        f"translation: {z3int.unparse(t)} is {ref}, int {got}, interval [{r.lo}, {r.hi}],"
                        f" tz {r.tz} under {env}"
                    )
            elif got != ref:
                return (
                    "error",
                    f"translation: {z3int.unparse(t)} is {ref}, int {got} under {env}",
                )
        checked += 1
    return "ok", checked


def check_unsat(query, timeout, what):
    st, out = run_z3(query + "(check-sat)\n(get-model)\n", timeout)
    if st == "unsat":
        return "ok", ""
    if st == "sat":
        return "error", f"{what} counterexample:\n{query}\n{out}"
    return "unknown", st


def untuple(k):
    return k if isinstance(k, str) else [untuple(x) for x in k]


# Random formulas


class Gen:
    def __init__(self, rng, width):
        self.r = rng
        self.w = width
        self.vars = {}
        self.defs = {}
        self.lets = []
        self.count = 0

    def lit(self, v, w):
        form = self.r.choice(["_", "b", "x"] if w % 4 == 0 else ["_", "b"])
        if form == "_":
            return f"(_ bv{v} {w})"
        if form == "x":
            return z3int.bv_text(v, w)
        return "#b" + format(v, f"0{w}b")

    def const(self, w):
        v = self.r.choice(
            [
                0,
                1,
                2,
                3,
                (1 << w) - 1,
                1 << (w - 1),
                (1 << (w - 1)) - 1,
                self.r.randrange(1 << w),
                self.r.randrange(16),
            ]
        ) % (1 << w)
        return self.lit(v, w)

    def var(self, w):
        pool = [n for n, vw in self.lets if vw == w] + [
            n for n, vw in self.defs.items() if vw == w
        ]
        pool += [n for n, vw in self.vars.items() if vw == w]
        if pool and self.r.random() < 0.8:
            return self.r.choice(pool)
        name = f"x{len(self.vars)}"
        self.vars[name] = w
        return name

    def leaf(self, w):
        return self.var(w) if self.r.random() < 0.65 else self.const(w)

    def bv(self, w, d):
        r = self.r
        if d <= 0 or r.random() < 0.15:
            return self.leaf(w)
        k = r.random()
        sub = lambda: self.bv(w, d - 1)
        if k < 0.30:
            op = r.choice(
                [
                    "bvadd",
                    "bvsub",
                    "bvmul",
                    "bvudiv",
                    "bvurem",
                    "bvsdiv",
                    "bvsrem",
                    "bvsmod",
                ]
            )
            b = self.const(w) if r.random() < 0.4 else sub()
            if op in ("bvadd", "bvmul") and r.random() < 0.2:
                return f"({op} {sub()} {b} {sub()})"
            return f"({op} {sub()} {b})"
        if k < 0.36:
            return f"({r.choice(['bvneg', 'bvnot'])} {sub()})"
        if k < 0.50:
            op = r.choice(
                ["bvand", "bvor", "bvxor", "bvand", "bvor", "bvnand", "bvnor", "bvxnor"]
            )
            j = r.random()
            if j < 0.5:
                return f"({op} {sub()} {self.mask(w)})"
            if j < 0.8:
                bit = f"(ite {self.boolean(d - 1)} {self.lit(1, w)} {self.lit(0, w)})"
                return (
                    f"({op} {bit} {sub()})"
                    if r.random() < 0.5
                    else f"({op} {sub()} {bit})"
                )
            return f"({op} {sub()} {sub()})"
        if k < 0.62:
            op = r.choice(["bvshl", "bvlshr", "bvashr"])
            if r.random() < 0.6:
                amount = self.lit(r.randrange(w + 3) % (1 << w), w)
            else:
                amount = sub()
            return f"({op} {sub()} {amount})"
        if k < 0.70:
            extra = r.randrange(1, w + 1)
            j = r.randrange(extra + 1)
            return f"((_ extract {j + w - 1} {j}) {self.bv(w + extra, d - 1)})"
        if k < 0.76 and w > 1:
            e = r.randrange(1, w)
            return f"((_ {r.choice(['zero_extend', 'sign_extend'])} {e}) {self.bv(w - e, d - 1)})"
        if k < 0.81 and w > 1:
            a = r.randrange(1, w)
            return f"(concat {self.bv(a, d - 1)} {self.bv(w - a, d - 1)})"
        if k < 0.84:
            return f"((_ {r.choice(['rotate_left', 'rotate_right'])} {r.randrange(w + 2)}) {sub()})"
        if k < 0.86 and w % 2 == 0:
            return f"((_ repeat 2) {self.bv(w // 2, d - 1)})"
        if k < 0.88 and w > 1:
            return f"((_ zero_extend {w - 1}) (bvcomp {self.bv(w, d - 1)} {self.bv(w, d - 1)}))"
        if k < 0.90:
            x, y = sub(), (self.const(w) if r.random() < 0.5 else sub())
            q = f"(bvudiv (bvmul {x} {y}) {x})"
            if r.random() < 0.5:
                q = f"(ite (= {x} {self.lit(0, w)}) {self.lit(0, w)} {q})"
            return f"(ite (= {q} {y}) {self.lit(1, w)} {self.lit(0, w)})"
        if k < 0.93:
            self.count += 1
            name = f"l{self.count}"
            val = self.bv(w, d - 1)
            self.lets.append((name, w))
            body = self.bv(w, d - 1)
            self.lets.pop()
            return f"(let (({name} {val})) {body})"
        return f"(ite {self.boolean(d - 1)} {sub()} {sub()})"

    def mask(self, w):
        r = self.r
        k = r.random()
        if k < 0.3:
            return self.lit((1 << r.randrange(w + 1)) - 1, w)
        if k < 0.5:
            return self.lit(((1 << w) - 1) ^ ((1 << r.randrange(w + 1)) - 1), w)
        return self.const(w)

    def boolean(self, d):
        r = self.r
        if d <= 0 or r.random() < 0.5:
            w = r.choice([self.w, self.w, self.w // 2 or 1])
            op = r.choice(
                [
                    "bvult",
                    "bvule",
                    "bvugt",
                    "bvuge",
                    "bvslt",
                    "bvsle",
                    "bvsgt",
                    "bvsge",
                    "=",
                    "=",
                    "distinct",
                ]
            )
            return f"({op} {self.bv(w, max(d - 1, 0))} {self.bv(w, max(d - 1, 0))})"
        op = r.choice(["not", "and", "or", "xor", "=>", "=", "ite"])
        if op == "not":
            return f"(not {self.boolean(d - 1)})"
        if op == "ite":
            return f"(ite {self.boolean(d - 1)} {self.boolean(d - 1)} {self.boolean(d - 1)})"
        n = r.choice([2, 2, 3])
        return f"({op} " + " ".join(self.boolean(d - 1) for _ in range(n)) + ")"

    def fact(self):
        r = self.r
        names = list(self.vars) + list(self.defs)
        subj = r.choice(names) if names and r.random() < 0.7 else self.bv(self.w, 1)
        w = self.vars.get(subj) or self.defs.get(subj) or self.w
        k = self.lit(r.randrange(1 << w), w)
        forms = [
            "(bvult {s} {k})",
            "(bvule {s} {k})",
            "(bvugt {k} {s})",
            "(not (bvult {s} {k}))",
            "(bvult {k} {s})",
            "(not (bvule {k} {s}))",
            "(bvuge {s} {k})",
        ]
        form = "(= {s} {k})" if r.random() < 0.05 else r.choice(forms)
        return form.format(s=subj, k=k)

    def query(self):
        r = self.r
        defs, asserts = [], []
        for i in range(r.randrange(3)):
            name = f"d{i}"
            body = self.bv(self.w, 2)
            defs.append(f"(define-fun {name} () (_ BitVec {self.w}) {body})")
            self.defs[name] = self.w
        for _ in range(r.randrange(3)):
            asserts.append(self.fact())
        main = [self.boolean(3) for _ in range(r.choice([1, 1, 2]))]
        if r.random() < 0.3:
            main = ["(and " + " ".join(main + [self.fact()]) + ")"]
        asserts += main
        decls = [f"(declare-fun {n} () (_ BitVec {w}))" for n, w in self.vars.items()]
        return (
            "(set-logic QF_BV)\n"
            + "\n".join(decls + defs + [f"(assert {a})" for a in asserts])
            + "\n(check-sat)\n"
        )


def report_problem(out_dir, name, text, detail):
    path = out_dir / f"{name}.smt2"
    path.write_text(text)
    print(f"PROBLEM {path}: {detail}", flush=True)


def summarize(results, label):
    total = len(results)
    translated = [r for r in results if r["translated"]]
    both = [
        r
        for r in translated
        if r["bv"] in ("sat", "unsat") and r["int"] in ("sat", "unsat")
    ]
    reasons = {}
    for r in results:
        if not r["translated"]:
            reasons[r["reason"]] = reasons.get(r["reason"], 0) + 1
    problems = [r for r in results if r["problem"]]
    print(
        f"{label}: {total} queries, {len(translated)} translated, {len(both)} decided by both, {len(problems)} problems"
    )
    for k in ("sat", "unsat", "unknown"):
        print(
            f"  bv {k}: {sum(r['bv'] == k for r in results)}, int {k}: {sum(r['int'] == k for r in translated)}"
        )
    print(
        f"  decided only by int: {sum(r['bv'] not in ('sat', 'unsat') and r['int'] in ('sat', 'unsat') for r in translated)}"
    )
    print(
        f"  decided only by bv: {sum(r['bv'] in ('sat', 'unsat') and r['int'] not in ('sat', 'unsat') for r in translated)}"
    )
    for reason, n in sorted(reasons.items(), key=lambda x: -x[1]):
        print(f"  not translated ({n}): {reason}")
    return len(problems)


def cmd_corpus(args):
    files = sorted(f for d in args.dirs for f in pathlib.Path(d).glob("*.smt2"))
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    results = []
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = {
            pool.submit(differential, f.read_text(), args.timeout): f for f in files
        }
        for fut in concurrent.futures.as_completed(futures):
            f = futures[fut]
            r = fut.result()
            r["file"] = str(f)
            results.append(r)
            if r["problem"]:
                report_problem(out_dir, f.stem, f.read_text(), r["problem"])
    if args.times:
        for r in sorted(results, key=lambda r: r["file"]):
            print(
                f"  {r['file']}\tbv {r['bv']} {r.get('bv_time', 0):.2f}s\tint {r['int']} {r.get('int_time', 0):.2f}s"
                f"\t{r['reason'] or ''}"
            )
    return summarize(results, "corpus")


def cmd_random(args):
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    texts = []
    for w in args.widths:
        for i in range(args.count):
            seed = args.seed * 1_000_003 + w * 100_000 + i
            texts.append((f"w{w}_s{seed}", Gen(random.Random(seed), w).query()))
    results, exact, samples, points = [], {}, {}, 0
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = {
            pool.submit(
                lambda n, t: (
                    differential(t, args.timeout),
                    exactness(t, args.timeout),
                    sampled(t, n, args.samples, args.timeout),
                ),
                n,
                t,
            ): (n, t)
            for n, t in texts
        }
        for fut in concurrent.futures.as_completed(futures):
            name, text = futures[fut]
            r, (status, detail), (s_status, s_detail) = fut.result()
            results.append(r)
            exact[status] = exact.get(status, 0) + 1
            samples[s_status] = samples.get(s_status, 0) + 1
            if s_status == "ok":
                points += s_detail
            if r["problem"]:
                report_problem(out_dir, name, text, r["problem"])
            if status == "error":
                r["problem"] = r["problem"] or "exactness"
                report_problem(out_dir, name + ".exact", text, detail)
            if s_status == "error":
                r["problem"] = r["problem"] or "sampled exactness"
                report_problem(out_dir, name + ".sampled", text, s_detail)
    print(f"exactness proofs: {exact}")
    print(f"sampled exactness: {samples}, {points} assignments checked")
    return summarize(results, f"random widths {args.widths}")


def main():
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("corpus")
    c.add_argument("dirs", nargs="+")
    c.add_argument("--times", action="store_true")
    r = sub.add_parser("random")
    r.add_argument("--count", type=int, default=1000)
    r.add_argument(
        "--widths", type=lambda s: [int(x) for x in s.split(",")], default=[8, 16]
    )
    r.add_argument("--seed", type=int, default=1)
    r.add_argument("--samples", type=int, default=20)
    for x in (c, r):
        x.add_argument("--timeout", type=int, default=30)
        x.add_argument("--jobs", type=int, default=6)
        x.add_argument("--out", default="z3int-problems")
    args = p.parse_args()
    sys.setrecursionlimit(1 << 16)
    problems = cmd_corpus(args) if args.cmd == "corpus" else cmd_random(args)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
