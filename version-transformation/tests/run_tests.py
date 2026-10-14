"""Run both CCMM migrations on the sample records and validate the results.

Usage:
    python3 run_tests.py <CCMM-2.0.0 checkout> <CCMM-1.1.0 checkout> [output dir]

    <CCMM-2.0.0 checkout>  techlib/CCMM at tag v2.0.0 (or main)
    <CCMM-1.1.0 checkout>  techlib/CCMM at branch 1.1.0 (or tag 1.1.0)

Needs: pip install saxonche xmlschema
The schemas import GML 3.2.1 from schemas.opengis.net. If that host is not
reachable, pass a local copy with GML_DIR=/path/to/gml/3.2.1 (folder with gml.xsd).

For each sample it runs: forward transformation, validation against the target
XSD, backward transformation of the result (round trip), validation again.
"""
import os
import sys
from pathlib import Path

import xmlschema
from saxonche import PySaxonProcessor

HERE = Path(__file__).resolve().parent
DOWN = HERE.parent / "ccmm-2.0.0-to-1.1.0.xslt"
UP = HERE.parent / "ccmm-1.1.0-to-2.0.0.xslt"


def schema(xsd):
    gml = os.environ.get("GML_DIR")
    local = {}
    if gml:
        for scheme in ("http", "https"):
            local[f"{scheme}://schemas.opengis.net/gml/3.2.1/gml.xsd"] = str(Path(gml) / "gml.xsd")
    return xmlschema.XMLSchema11(str(xsd), uri_mapper=lambda u: local.get(u, u))


def main():
    v20, v11 = Path(sys.argv[1]), Path(sys.argv[2])
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else HERE / "out"
    xsd20, xsd11 = schema(v20 / "dataset/schema.xsd"), schema(v11 / "dataset/schema.xsd")
    failures = 0
    with PySaxonProcessor(license=False) as proc:
        xslt = proc.new_xslt30_processor()
        down = xslt.compile_stylesheet(stylesheet_file=str(DOWN))
        up = xslt.compile_stylesheet(stylesheet_file=str(UP))
        jobs = [
            ("2.0.0-to-1.1.0", down, xsd11, up, xsd20,
             sorted((v20 / "_metadata-samples/xml").glob("*.xml")) + sorted((HERE / "edge-cases").glob("v2.0.0-*.xml"))),
            ("1.1.0-to-2.0.0", up, xsd20, down, xsd11,
             sorted((v11 / "_metadata-samples/xml").glob("*.xml")) + sorted((HERE / "edge-cases").glob("v1.1.0-*.xml"))),
        ]
        for name, fwd, fwd_xsd, back, back_xsd, sources in jobs:
            (out / name).mkdir(parents=True, exist_ok=True)
            (out / (name + "-roundtrip")).mkdir(parents=True, exist_ok=True)
            for src in sources:
                tgt = out / name / src.name
                rt = out / (name + "-roundtrip") / src.name
                fwd.transform_to_file(source_file=str(src), output_file=str(tgt))
                back.transform_to_file(source_file=str(tgt), output_file=str(rt))
                for label, f, x in (("forward", tgt, fwd_xsd), ("round trip", rt, back_xsd)):
                    errors = list(x.iter_errors(str(f)))
                    status = "VALID" if not errors else f"{len(errors)} error(s)"
                    print(f"{name:16} {label:10} {src.name:32} {status}")
                    for e in errors[:5]:
                        print("      ", e.path, "|", (e.reason or "")[:200])
                    failures += bool(errors)
    print("OK" if not failures else f"{failures} invalid output(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
