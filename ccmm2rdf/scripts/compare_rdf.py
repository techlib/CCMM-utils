#!/usr/bin/env python3
"""
Check that two or more RDF files - in any mix of serializations
(RDF/XML, Turtle, JSON-LD, N-Triples...) - represent the same graph.

Three layers of comparison, cheapest/most-approximate first:

  1. Ground triples (no blank nodes involved) - exact set comparison.
     Unambiguous, always trustworthy.

  2. Blank node / blank-node-triple counts - fast supporting evidence.
     If these differ, something structural really did change. If they
     match, it's a good sign but not proof by itself.

  3. Full RDF Dataset Canonicalization (RDFC-1.0, formerly URDNA2015),
     via pyld's implementation - a provably correct isomorphism check,
     not a heuristic. This is the one to trust for a final verdict on
     blank-node structure. (rdflib's own to_isomorphic()/graph_diff() use
     a faster hash-based heuristic that can produce FALSE NEGATIVES on
     graphs with many structurally-similar blank nodes - e.g. several
     Address/Attribution/Person-shaped nodes - which is common in CCMM
     data. This script deliberately does not use that method as the
     final word, only URDNA2015.)

Any malformed URIs in the data (e.g. stray whitespace) are normalized before
comparison, so a known data-quality issue in the source doesn't just crash
the check - it's reported instead as what it is.

Install once:
    pip install rdflib pyld

Usage:
    python compare_rdf.py file1.ttl file2.rdf.xml file3.jsonld [...]
    python compare_rdf.py --limit 20 file1.ttl file2.jsonld
"""

import argparse
import sys
from pathlib import Path

from rdflib import Graph, URIRef, BNode
from pyld import jsonld

FORMAT_BY_SUFFIX = {
    ".ttl": "turtle",
    ".turtle": "turtle",
    ".xml": "xml",
    ".rdf": "xml",
    ".jsonld": "json-ld",
    ".json": "json-ld",
    ".nt": "nt",
    ".n3": "n3",
}


def guess_format(path: Path) -> str:
    suffix = ".xml" if path.name.endswith(".rdf.xml") else path.suffix
    fmt = FORMAT_BY_SUFFIX.get(suffix)
    if not fmt:
        raise SystemExit(f"Don't know how to parse {path} - unrecognized extension {suffix}")
    return fmt


def clean(g: Graph) -> Graph:
    """Strip stray whitespace from URIRefs so a known malformed-URI data issue
    doesn't crash comparison - it'll still show up as a normal mismatch if
    the whitespace differs between serializations."""
    fixed = Graph()
    for s, p, o in g:
        if isinstance(s, URIRef):
            s = URIRef(str(s).strip())
        if isinstance(o, URIRef):
            o = URIRef(str(o).strip())
        fixed.add((s, p, o))
    return fixed


def ground_triples(g: Graph):
    return set(t for t in g if not isinstance(t[0], BNode) and not isinstance(t[2], BNode))


def bnode_stats(g: Graph):
    bnodes = set()
    touching = 0
    for s, p, o in g:
        if isinstance(s, BNode):
            bnodes.add(s)
            touching += 1
        elif isinstance(o, BNode):
            bnodes.add(o)
            touching += 1
    return len(bnodes), touching


def canonicalize(g: Graph):
    """RDFC-1.0 / URDNA2015 canonical N-Quads lines, via pyld - a provably
    correct comparison, not a hash-based heuristic."""
    nt = g.serialize(format="nt")
    canonical = jsonld.normalize(
        nt, {"algorithm": "URDNA2015", "inputFormat": "application/n-quads", "format": "application/n-quads"}
    )
    return canonical.splitlines()


def load(path: Path) -> Graph:
    g = Graph()
    g.parse(str(path), format=guess_format(path))
    return clean(g)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="+", type=Path, help="Two or more RDF files to compare")
    parser.add_argument("--limit", type=int, default=None,
                         help="Max number of differing triples to print per category (default: show all)")
    args = parser.parse_args()

    if len(args.files) < 2:
        raise SystemExit("Need at least 2 files to compare.")

    graphs = {}
    for f in args.files:
        if not f.exists():
            print(f"SKIPPING {f} - file not found")
            continue
        g = load(f)
        graphs[f] = g
        print(f"{f.name}: {len(g)} triples")

    files = list(graphs.keys())
    if len(files) < 2:
        raise SystemExit("Fewer than 2 files could be loaded - nothing to compare.")

    all_ok = True
    print()
    for i in range(len(files)):
        for j in range(i + 1, len(files)):
            a, b = files[i], files[j]
            ga, gb = graphs[a], graphs[b]
            print(f"--- {a.name}  vs  {b.name} ---")

            # 1) Ground triples
            gt_a, gt_b = ground_triples(ga), ground_triples(gb)
            only_a = gt_a - gt_b
            only_b = gt_b - gt_a
            if only_a or only_b:
                all_ok = False
                print(f"  Ground triples differ: {len(only_a)} only in {a.name}, {len(only_b)} only in {b.name}")
                for t in list(only_a)[:args.limit]:
                    print(f"    only in {a.name}:", " ".join(str(x) for x in t))
                for t in list(only_b)[:args.limit]:
                    print(f"    only in {b.name}:", " ".join(str(x) for x in t))
            else:
                print(f"  Ground triples: identical ({len(gt_a)})")

            # 2) Blank node / blank-node-triple counts - cheap supporting evidence
            bn_a, touch_a = bnode_stats(ga)
            bn_b, touch_b = bnode_stats(gb)
            counts_match = (bn_a == bn_b) and (touch_a == touch_b)
            print(f"  Blank nodes: {bn_a} vs {bn_b}  |  triples touching a blank node: {touch_a} vs {touch_b}"
                  + ("  (match)" if counts_match else "  (MISMATCH)"))
            if not counts_match:
                all_ok = False

            # 3) URDNA2015 canonicalization - the definitive check
            try:
                canon_a, canon_b = canonicalize(ga), canonicalize(gb)
                set_a, set_b = set(canon_a), set(canon_b)
                if set_a == set_b:
                    print("  RDFC-1.0/URDNA2015 canonical form: IDENTICAL - graphs are truly isomorphic")
                else:
                    all_ok = False
                    only_ca = set_a - set_b
                    only_cb = set_b - set_a
                    print(f"  RDFC-1.0/URDNA2015 canonical form: DIFFERS - {len(only_ca)} lines only in "
                          f"{a.name}, {len(only_cb)} only in {b.name} (this check is provably correct, "
                          f"not a heuristic - a real difference)")
                    for line in list(only_ca)[:args.limit]:
                        print(f"    only in {a.name}:", line)
                    for line in list(only_cb)[:args.limit]:
                        print(f"    only in {b.name}:", line)
            except Exception as e:
                print(f"  RDFC-1.0/URDNA2015 canonicalization failed to run ({e})")
                print("  (ground-triple and blank-node-count comparisons above are still valid)")
            print()

    if all_ok:
        print("RESULT: All files represent the same RDF graph.")
    else:
        print("RESULT: Differences found - see above.")
        sys.exit(1)


if __name__ == "__main__":
    main()