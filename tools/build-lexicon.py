#!/usr/bin/env python3
"""Build Sources/PodLyrics/Resources/lexicon.sqlite from ECDICT.

    tools/build-lexicon.py                 # downloads ecdict-sqlite-28.zip into ~/.cache
    tools/build-lexicon.py --source stardict.db

ECDICT (https://github.com/skywind3000/ECDICT, MIT) ships 3.4M entries; we
keep only headwords that carry a frequency rank or an exam tag, plus the
inflected forms needed to map subtitle words back to their headword.

Output schema:

    headwords(word PRIMARY KEY, level INTEGER, rank INTEGER, tags TEXT,
              phonetic TEXT, brief TEXT, translation TEXT)
    forms(form PRIMARY KEY, word TEXT)          -- negotiated -> negotiate

`level` uses the app's exam scale (see Level.swift):
    0 初中  1 高中  2 四级  3 六级  4 考研  5 托福雅思  6 GRE
"""
import argparse
import os
import re
import sqlite3
import sys
import urllib.request
import zipfile

ECDICT_URL = "https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict-sqlite-28.zip"
OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "PodLyrics", "Resources", "lexicon.sqlite")

TAG_LEVEL = {"zk": 0, "gk": 1, "cet4": 2, "cet6": 3, "ky": 4, "toefl": 5, "ielts": 5, "gre": 6}
# Frequency fallback for untagged words (COCA/BNC rank upper bounds per level).
RANK_LEVEL = [(3000, 1), (5000, 2), (8000, 3), (12000, 4), (20000, 5)]
# exchange codes that denote pure inflections of another headword
INFLECTION_CODES = {"p", "d", "i", "3", "s", "r", "t"}
# ECDICT quirks: "does" is listed as the plural of "doe", "AM" is uppercase.
MANUAL_FORMS = {"does": "do", "am": "be", "is": "be", "are": "be", "i": "i"}
# Spoken fillers get a frequency rank that would otherwise make them "六级".
LEVEL_OVERRIDE = {w: 0 for w in "uh um hmm mm huh ah oh wow yeah yep nope okay ok hey".split()}


def fetch_source(cache_dir):
    os.makedirs(cache_dir, exist_ok=True)
    zip_path = os.path.join(cache_dir, "ecdict-sqlite-28.zip")
    if not os.path.exists(zip_path):
        print(f"downloading {ECDICT_URL} ...", file=sys.stderr)
        urllib.request.urlretrieve(ECDICT_URL, zip_path)
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if n.endswith(".db")]
        z.extract(names[0], cache_dir)
        return os.path.join(cache_dir, names[0])


# Collins stars (5 = most common) for words that have neither tag nor rank.
COLLINS_LEVEL = {5: 0, 4: 1, 3: 2, 2: 3, 1: 4}


def level_for(tags, rank, collins):
    levels = [TAG_LEVEL[t] for t in tags.split() if t in TAG_LEVEL]
    if levels:
        return min(levels)
    if rank:
        for bound, lvl in RANK_LEVEL:
            if rank <= bound:
                return lvl
        return 6
    if collins in COLLINS_LEVEL:
        return COLLINS_LEVEL[collins]
    return 6


POS_PREFIX = re.compile(r"^(\[[^\]]*\]|[a-z]+\.|pl\.|abbr\.)\s*")
PARENS = re.compile(r"[（(][^）)]*[）)]")


def brief_of(translation):
    """First sense of the first line, without POS marker, capped for inline use."""
    for line in translation.split("\n"):
        line = POS_PREFIX.sub("", line.strip())
        line = PARENS.sub("", line).strip()
        if not line:
            continue
        senses = [s for s in re.split(r"[,;，；]\s*", line) if s]
        if not senses:
            continue
        out = senses[0]
        if len(senses) > 1 and len(out) + len(senses[1]) <= 9:
            out = out + "，" + senses[1]
        return out if len(out) <= 14 else out[:13] + "…"
    return ""


def parse_exchange(exchange):
    pairs = {}
    for item in exchange.split("/"):
        if ":" in item:
            k, v = item.split(":", 1)
            pairs.setdefault(k, v)
    return pairs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", help="path to ECDICT stardict.db")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    src = args.source or fetch_source(os.path.expanduser("~/.cache/podlyrics-ecdict"))
    con = sqlite3.connect(src)
    rows = con.execute(
        """SELECT word, tag, frq, bnc, collins, oxford, exchange, phonetic, translation
           FROM stardict
           WHERE word NOT LIKE '% %' AND (word GLOB '[a-z]*' OR word IN ('I', 'AM', 'OK'))
             AND translation IS NOT NULL AND translation != ''
             AND (frq > 0 OR bnc > 0 OR tag != '' OR collins > 0 OR oxford > 0)"""
    ).fetchall()
    rows = [(r[0].lower(), *r[1:]) for r in rows]
    print(f"candidate rows: {len(rows)}", file=sys.stderr)
    candidates = {r[0] for r in rows}

    # Inflections with no frequency data of their own (were, been, had).
    extra_forms = []
    for word, exchange in con.execute(
        """SELECT word, exchange FROM stardict
           WHERE exchange LIKE '%0:%' AND exchange LIKE '%1:%'
             AND word NOT LIKE '% %' AND word GLOB '[a-z]*'
             AND (frq IS NULL OR frq = 0) AND (bnc IS NULL OR bnc = 0) AND (tag IS NULL OR tag = '')"""
    ):
        ex = parse_exchange(exchange)
        base, code = ex.get("0"), ex.get("1", "")
        if base and base != word and code and set(code) <= INFLECTION_CODES and base in candidates:
            extra_forms.append((word, base))
    headwords = {}
    forms = {}
    deferred_forms = []
    for word, tag, frq, bnc, collins, oxford, exchange, phonetic, translation in rows:
        tag = tag or ""
        ex = parse_exchange(exchange or "")
        if word in MANUAL_FORMS:
            if MANUAL_FORMS[word] == word:
                ex.pop("0", None); ex.pop("1", None)
            else:
                ex["0"], ex["1"] = MANUAL_FORMS[word], "3"
        # Contractions (don't, we're) are handled by the app's normaliser.
        if "'" in word:
            continue
        base = ex.get("0")
        code = ex.get("1", "")
        # A row whose exchange says "I am the <code> form of <base>" is an
        # inflection (children -> child, was -> be), not a headword of its
        # own, even when ECDICT gives it an exam tag. A bare "0:" without a
        # "1:" code is only a loose association (our -> we) and is ignored.
        if base and base != word and code and set(code) <= INFLECTION_CODES and base in candidates:
            deferred_forms.append((word, base))
            continue
        ranks = [r for r in (frq, bnc) if r and r > 0]
        rank = min(ranks) if ranks else None
        level = LEVEL_OVERRIDE.get(word, level_for(tag, rank, collins or 0))
        headwords[word] = (
            level, rank, tag, phonetic or "",
            brief_of(translation), translation.strip(),
        )
        for k, v in ex.items():
            if k in INFLECTION_CODES and v and v != word:
                forms.setdefault(v, word)

    for form, base in deferred_forms + extra_forms:
        if base in headwords:
            forms.setdefault(form, base)
    # "was" is listed as be's past tense yet also has its own (untagged) row;
    # such rows are inflections, not vocabulary. Keep tagged ones (e.g. "left"
    # is both leave's past tense and an adjective).
    for form, base in list(forms.items()):
        if form in headwords and not headwords[form][2] and base in headwords:
            del headwords[form]
    forms = {f: w for f, w in forms.items() if f not in headwords and w in headwords}

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.exists(out):
        os.remove(out)
    db = sqlite3.connect(out)
    db.executescript(
        """
        CREATE TABLE headwords(
            word TEXT PRIMARY KEY, level INTEGER NOT NULL, rank INTEGER,
            tags TEXT NOT NULL, phonetic TEXT NOT NULL,
            brief TEXT NOT NULL, translation TEXT NOT NULL);
        CREATE TABLE forms(form TEXT PRIMARY KEY, word TEXT NOT NULL);
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
    )
    db.executemany(
        "INSERT INTO headwords VALUES (?,?,?,?,?,?,?)",
        [(w, *v) for w, v in headwords.items()],
    )
    db.executemany("INSERT INTO forms VALUES (?,?)", forms.items())
    db.executemany("INSERT INTO meta VALUES (?,?)", [
        ("source", "ECDICT 1.0.28"), ("schema", "1"),
    ])
    db.commit()
    db.execute("VACUUM")
    db.close()
    size = os.path.getsize(out) / 1e6
    by_level = {}
    for v in headwords.values():
        by_level[v[0]] = by_level.get(v[0], 0) + 1
    print(f"headwords: {len(headwords)}  forms: {len(forms)}  size: {size:.1f} MB", file=sys.stderr)
    print("per level:", dict(sorted(by_level.items())), file=sys.stderr)
    print(f"wrote {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
