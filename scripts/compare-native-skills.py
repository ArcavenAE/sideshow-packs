#!/usr/bin/env python3
"""Compare a native bmad skills tree with a sideshow-bound one.

usage: compare-native-skills.py NATIVE_SKILLS BOUND_SKILLS STORE_VERSION_DIR

Reports the skill-name sets, the files that differ, and the residual after
reversing the declared rewrite on the bound side: the store path written back
to {project-root}/_bmad/, and the appended sideshow fallback-resolution block
removed. Exit 0 when the residual is 0, 1 otherwise. Read-only.
"""
import collections
import os
import re
import sys

REF = "{project-root}/_bmad/"
BLOCK = re.compile(
    r"\n\n---\n\n<!-- sideshow:fallback-resolution:begin -->.*?"
    r"<!-- sideshow:fallback-resolution:end -->\n",
    re.S,
)


def files(root):
    out = {}
    for d, _, fs in os.walk(root, followlinks=True):
        for f in fs:
            p = os.path.join(d, f)
            out[os.path.relpath(p, root)] = p
    return out


def text(p):
    with open(p, "rb") as fh:
        return fh.read().decode("utf8", "replace")


def kind(k):
    if k.count("/") == 1 and k.endswith("/SKILL.md"):
        return "SKILL.md"
    return "md" if k.endswith(".md") else "other" + os.path.splitext(k)[1]


def main():
    nat, bnd, store = sys.argv[1:4]
    a, b = files(nat), files(bnd)
    print("skill names equal:", sorted(os.listdir(nat)) == sorted(os.listdir(bnd)),
          len(os.listdir(nat)))
    print("files native", len(a), "bound", len(b),
          "only native", len(set(a) - set(b)), "only bound", len(set(b) - set(a)))
    diff = [k for k in sorted(set(a) & set(b)) if text(a[k]) != text(b[k])]
    print("differing files", len(diff), dict(collections.Counter(map(kind, diff))))
    sp = store.rstrip("/") + "/"
    bad = []
    with_block = 0
    for k in diff:
        y = text(b[k])
        if "sideshow:fallback-resolution:begin" in y:
            with_block += 1
        if text(a[k]) != BLOCK.sub("", y.replace(sp, REF)):
            bad.append(k)
    print("with fallback block", with_block, "store-path only", len(diff) - with_block)
    unchanged = [k for k in a if k not in set(diff) and k in b and REF in text(a[k])]
    print("files carrying", REF, "that are byte-equal in both trees:", len(unchanged))
    print("residual after declared rewrite:", len(bad))
    for k in bad[:20]:
        print("  residual:", k)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
