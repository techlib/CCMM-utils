"""Lift native samples and transformation outputs to RDF and validate them with SHACL.

Usage:
    python3 shacl_check.py <CCMM-2.0.0 checkout> <CCMM-1.1.0 checkout> [run_tests.py output dir]

Each graph is lifted with dataset/lifting.xslt of its version and validated
with that version's shacl.ttl (pyshacl, no inference). The native samples
fail too, so each output is compared with the native sample of the same name:
'+' results appear only in the output, '-' only in the native sample.

Needs: pip install saxonche pyshacl
"""
import collections
import logging
import re
import sys
from pathlib import Path

from pyshacl import validate
from rdflib import Graph, Namespace, RDF
from saxonche import PySaxonProcessor

logging.disable(logging.WARNING)  # rdflib warns on every invalid IRI of native 1.1.0 1m3t2
SH = Namespace("http://www.w3.org/ns/shacl#")
HERE = Path(__file__).resolve().parent


def results(rg):
    for r in rg.subjects(RDF.type, SH.ValidationResult):
        focus, value = rg.value(r, SH.focusNode), rg.value(r, SH.value)
        # blank nodes get new ids on every parse; compare them as _:b
        yield (str(rg.value(r, SH.sourceConstraintComponent)).split("#")[-1].replace("ConstraintComponent", ""),
               re.split(r"[/#]", str(rg.value(r, SH.resultPath)))[-1],
               str(focus) if str(focus).startswith("http") else "_:b",
               "" if value is None else str(value).strip()[:80] if not re.fullmatch(r"N[0-9a-f]{32}", str(value)) else "_:b")


def main():
    v20, v11 = Path(sys.argv[1]), Path(sys.argv[2])
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else HERE / "out"
    vers = {"2.0.0": v20, "1.1.0": v11}
    sets = [
        ("native 2.0.0", "2.0.0", v20 / "_metadata-samples/xml", None),
        ("native 1.1.0", "1.1.0", v11 / "_metadata-samples/xml", None),
        ("2.0.0-to-1.1.0", "1.1.0", out / "2.0.0-to-1.1.0", "native 1.1.0"),
        ("1.1.0-to-2.0.0", "2.0.0", out / "1.1.0-to-2.0.0", "native 2.0.0"),
        ("2.0.0-to-1.1.0-roundtrip", "2.0.0", out / "2.0.0-to-1.1.0-roundtrip", "native 2.0.0"),
        ("1.1.0-to-2.0.0-roundtrip", "1.1.0", out / "1.1.0-to-2.0.0-roundtrip", "native 1.1.0"),
    ]
    shapes = {v: Graph().parse(p / "shacl.ttl") for v, p in vers.items()}
    found = {}
    with PySaxonProcessor(license=False) as proc:
        xslt = proc.new_xslt30_processor()
        lift = {v: xslt.compile_stylesheet(stylesheet_file=str(p / "dataset/lifting.xslt")) for v, p in vers.items()}
        for name, v, folder, native in sets:
            print(f"\n## {name} (shapes {v})" + (f", compared with {native}" if native else ""))
            for f in sorted(folder.glob("*.xml")):
                g = Graph().parse(data=lift[v].transform_to_string(source_file=str(f)), format="xml", publicID="urn:base:")
                _, rg, _ = validate(g, shacl_graph=shapes[v], inference="none")
                found[name, f.name] = c = collections.Counter(results(rg))
                base = found.get((native, f.name))
                print(f"  {f.name:32} triples {len(g):4}  results {sum(c.values()):3}"
                      + (f"  (native {sum(base.values())})" if base is not None else ""))
                if base is not None:
                    for sign, diff in (("+", c - base), ("-", base - c)):
                        for k, n in sorted(diff.items()):
                            print(f"      {sign}{n} {' | '.join(k)}")


if __name__ == "__main__":
    main()
