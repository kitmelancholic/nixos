"""pdf2md: born-digital PDF -> Markdown via pymupdf4llm.

Fixes on top of pymupdf4llm:
- monospace (code) lines get spaces/indentation rebuilt from glyph positions,
  since pdfTeX listings often contain no space glyphs;
- Latin 'i' inside Cyrillic words (pdfTeX Ukrainian artifact) becomes 'і'.

Usage: pdf2md input.pdf [output.md]   (images go to <output dir>/images)
"""
import collections
import os
import re
import sys

import pymupdf
import pymupdf4llm

CYR = "А-Яа-яЄєЇїҐґʼ’'"


def mono_lines(page):
    """{line text without whitespace: [(x0, line text with spaces, char width)]}."""
    res = collections.defaultdict(list)
    for b in page.get_text("rawdict")["blocks"]:
        for line in b.get("lines", []):
            chars = [c for s in line["spans"]
                     if "TT" in s["font"] or s["flags"] & 8
                     for c in s["chars"]]
            if not chars:
                continue
            widths = sorted(c["bbox"][2] - c["bbox"][0] for c in chars)
            w = widths[len(widths) // 2] or 5
            txt, prev = "", None
            for c in chars:
                if prev is not None:
                    txt += " " * max(0, round((c["bbox"][0] - prev) / w))
                txt += c["c"]
                prev = c["bbox"][2]
            key = re.sub(r"\s", "", txt)
            if key:
                res[key].append((chars[0]["bbox"][0], txt.rstrip(), w))
    return res


def fix_code(md, lines):
    def repl(m):
        body = m.group(2).split("\n")
        found = []
        for ln in body:
            k = re.sub(r"\s", "", ln)
            found.append(lines[k].pop(0) if lines.get(k) else None)
        xs = [f[0] for f in found if f]
        if not xs:
            return m.group(0)
        x0 = min(xs)
        out = [" " * round((f[0] - x0) / f[2]) + f[1] if f else ln
               for ln, f in zip(body, found)]
        return m.group(1) + "\n".join(out) + m.group(3)
    return re.sub(r"(```[^\n]*\n)(.*?)(\n```)", repl, md, flags=re.S)


def fix_i(t):
    for _ in range(3):  # words like "iнформацiї" need several passes
        t = re.sub(rf"(?<=[{CYR}])i|i(?=[{CYR}])", "і", t)
        t = re.sub(rf"(?<=[{CYR}])I|I(?=[{CYR}])", "І", t)
    # standalone conjunction "i" between Cyrillic words
    return re.sub(r"(?<=[А-Яа-яЄєЇїҐґ,] )i(?= [А-Яа-яЄєЇїҐґ])", "і", t)


def mono_share(doc):
    total = mono = 0
    for page in doc:
        for b in page.get_text("dict")["blocks"]:
            for line in b.get("lines", []):
                for s in line["spans"]:
                    n = len(s["text"].strip())
                    total += n
                    if "TT" in s["font"] or s["flags"] & 8:
                        mono += n
    return mono / total if total else 0


def typewritten_md(doc):
    """Whole document set in a monospace font: plain text, not code blocks."""
    out = []
    for page in doc:
        for ln in page.get_text("text", sort=True).splitlines():
            ln = ln.strip()
            if not ln:
                continue
            letters = re.sub(r"[^A-Za-zА-Яа-яЄєЇїҐґІі]", "", ln)
            if len(ln) <= 20 and letters and letters.isupper():
                ln = "## " + ln
            out.append(ln)
    return "\n\n".join(out) + "\n"


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__.strip().splitlines()[-1])
    pdf = sys.argv[1]
    out_md = sys.argv[2] if len(sys.argv) == 3 else os.path.splitext(pdf)[0] + ".md"
    img_dir = os.path.join(os.path.dirname(os.path.abspath(out_md)), "images")

    doc = pymupdf.open(pdf)
    if mono_share(doc) > 0.9:
        md = fix_i(typewritten_md(doc))
        with open(out_md, "w", encoding="utf-8") as f:
            f.write(md)
        print(f"{out_md}: {len(md)} chars (monospace document, plain text)")
        return

    os.makedirs(img_dir, exist_ok=True)
    chunks = pymupdf4llm.to_markdown(doc, page_chunks=True, write_images=True,
                                     image_path=img_dir, image_format="png",
                                     dpi=150)
    parts = []
    for ch in chunks:
        meta = ch["metadata"]
        page = doc[meta.get("page_number", meta.get("page")) - 1]
        parts.append(fix_code(ch["text"], mono_lines(page)))
    md = fix_i("\n".join(parts)).replace(img_dir + "/", "images/")
    if not os.listdir(img_dir):
        os.rmdir(img_dir)

    with open(out_md, "w", encoding="utf-8") as f:
        f.write(md)
    print(f"{out_md}: {len(md)} chars, {md.count('```') // 2} code blocks")


if __name__ == "__main__":
    main()
