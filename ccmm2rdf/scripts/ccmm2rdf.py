#!/usr/bin/env python3
"""
Transform a CCMM XML instance into both RDF (Turtle) and JSON-LD, using a
Dataspecer-generated lifting.xslt and context.jsonld pulled directly from a
GitHub repo.

Pipeline:
    1. Download the given branch of the GitHub repo (full tarball - lifting.xslt
       pulls in dozens of sibling lifting.xslt files via relative <xsl:import>,
       so the whole repo layout has to be on disk, not just the one file).
    2. XML instance --(lifting.xslt, XSLT 3.0 via Saxon/C)--> RDF/XML
       -> saved as Turtle in output/<name>.ttl
    3. RDF --(rdflib expand)--> JSON-LD --(pyld frame, using context.jsonld)-->
       a single nested tree matching the class's context/schema shape
       -> saved as JSON-LD in output/<name>.jsonld

Install once:
    pip install saxonche rdflib pyld

Usage:
    python ccmm2rdf.py ccmm_sample.xml \\
        --repo techlib/CCMM --branch 1.2.0 \\
        --lifting dataset/lifting.xslt \\
        --context dataset/context.jsonld \\
        --outdir output

    # Optional: override the root @type used for JSON-LD framing (auto-detected
    # by default, from the first rdf:Description in the lifted RDF/XML):
        --type-iri http://www.w3.org/ns/dcat#Dataset
"""

import argparse
import json
import re
import tarfile
import tempfile
import urllib.request
from pathlib import Path

from saxonche import PySaxonProcessor
from rdflib import Graph
from pyld import jsonld


def download_repo(repo: str, branch: str, cache_dir: Path) -> Path:
    """Download & extract a GitHub repo branch via codeload, return the extracted root folder."""
    owner_repo = repo.strip("/")
    repo_name = owner_repo.split("/")[-1]
    extracted_root = cache_dir / f"{repo_name}-{branch}"
    if extracted_root.exists():
        print(f"Using cached checkout at {extracted_root}")
        return extracted_root

    url = f"https://codeload.github.com/{owner_repo}/tar.gz/refs/heads/{branch}"
    tar_path = cache_dir / f"{repo_name}-{branch}.tar.gz"
    print(f"Downloading {url} ...")
    urllib.request.urlretrieve(url, tar_path)

    with tarfile.open(tar_path) as tar:
        tar.extractall(cache_dir)

    if not extracted_root.exists():
        # GitHub tarballs sometimes normalize branch names (slashes -> dashes etc.)
        candidates = [p for p in cache_dir.iterdir() if p.is_dir() and p.name.startswith(repo_name)]
        if not candidates:
            raise SystemExit(f"Could not find extracted folder for {repo}@{branch} under {cache_dir}")
        extracted_root = candidates[0]

    return extracted_root


def resolve_instance(instance_arg: str, workdir: Path) -> Path:
    """Accept either a local file path or a URL for the XML instance.
    (argparse type=Path would mangle "https://" into "https:/" by collapsing
    the double slash, and Saxon's own URL fetching isn't reliable across
    environments/proxies either - so if it looks like a URL, download it
    ourselves to a local temp file and always hand Saxon a local path.)"""
    if re.match(r"^https?://", instance_arg):
        local_path = workdir / Path(instance_arg).name
        print(f"Downloading instance XML from {instance_arg} ...")
        urllib.request.urlretrieve(instance_arg, local_path)
        return local_path
    return Path(instance_arg)


def lift_to_rdf_xml(instance_xml: Path, lifting_xslt: Path) -> str:
    """XSLT 3.0 lifting transform: CCMM XML instance -> RDF/XML string."""
    with PySaxonProcessor(license=False) as proc:
        xslt_processor = proc.new_xslt30_processor()
        executable = xslt_processor.compile_stylesheet(stylesheet_file=str(lifting_xslt))
        return executable.transform_to_string(source_file=str(instance_xml))


def detect_root_type(rdf_xml: str) -> str | None:
    """Best-effort: the lifting.xslt output lists the root entity's rdf:Description
    first, so grab the first rdf:type resource in the document as the default
    framing type if the user didn't specify one explicitly."""
    m = re.search(r'<rdf:type\s+rdf:resource="([^"]+)"', rdf_xml)
    return m.group(1) if m else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("instance", help="CCMM XML instance file (local path or URL)")
    parser.add_argument("--repo", required=True, help="GitHub repo, e.g. techlib/CCMM")
    parser.add_argument("--branch", required=True, help="Branch or tag, e.g. 1.2.0")
    parser.add_argument("--lifting", required=True, help="Path to lifting.xslt within the repo, e.g. dataset/lifting.xslt")
    parser.add_argument("--context", required=True, help="Path to context.jsonld within the repo, e.g. dataset/context.jsonld")
    parser.add_argument("--type-iri", default=None, help="Root @type IRI to frame on (default: auto-detected)")
    parser.add_argument("--context-url", default=None,
                         help="If set, replace the embedded @context in the output JSON-LD with this "
                              "URL instead (e.g. a raw.githubusercontent.com link to context.jsonld). "
                              "Framing itself still uses the real local context file either way - "
                              "this only changes what ends up in the saved document.")
    parser.add_argument("--outdir", type=Path, default=Path("output"), help="Output folder (default: ./output)")
    parser.add_argument("--cache-dir", type=Path, default=Path(tempfile.gettempdir()) / "ccmm_repo_cache",
                         help="Where to cache the downloaded repo checkout")
    args = parser.parse_args()

    args.outdir.mkdir(parents=True, exist_ok=True)
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    args.instance = resolve_instance(args.instance, args.cache_dir)
    name = args.instance.stem

    repo_root = download_repo(args.repo, args.branch, args.cache_dir)
    lifting_xslt = repo_root / args.lifting
    context_path = repo_root / args.context
    for p in (lifting_xslt, context_path):
        if not p.exists():
            raise SystemExit(f"Not found in checkout: {p}")

    # --- 1) Lift XML -> RDF, save RDF/XML + Turtle ---
    print(f"Lifting {args.instance} with {lifting_xslt} ...")
    rdf_xml = lift_to_rdf_xml(args.instance, lifting_xslt)

    raw_path = args.outdir / f"{name}.rdf.xml"
    raw_path.write_text(rdf_xml, encoding="utf-8")
    print(f"  wrote {raw_path}")

    g = Graph()
    g.parse(data=rdf_xml, format="xml")
    print(f"  parsed {len(g)} triples")

    ttl_path = args.outdir / f"{name}.ttl"
    try:
        turtle_str = g.serialize(format="turtle")  # serialize in memory first
        ttl_path.write_text(turtle_str, encoding="utf-8")
        print(f"  wrote {ttl_path}")
    except Exception as e:
        # Usually a malformed URI in the source data, not a script bug.
        # (Serializing to a string first, as above, avoids leaving a
        # truncated/broken .ttl file on disk if this happens mid-write.)
        print(f"  WARNING: could not serialize Turtle ({e})")

    # --- 2) RDF -> JSON-LD, framed against context.jsonld ---
    type_iri = args.type_iri or detect_root_type(rdf_xml)
    if not type_iri:
        raise SystemExit("Could not auto-detect a root @type - pass --type-iri explicitly.")
    print(f"Framing JSON-LD (root type: {type_iri}) ...")

    expanded = json.loads(g.serialize(format="json-ld", auto_compact=False))
    with open(context_path, encoding="utf-8") as f:
        context_doc = json.load(f)

    frame = {
        "@context": context_doc["@context"],
        "@type": type_iri,
        "@embed": "@always",
    }
    framed = jsonld.frame(expanded, frame)

    if args.context_url:
        # Framing needed the real, full context object to do its job - but the
        # saved output doesn't. Swap it for a URL: any compliant JSON-LD
        # processor will fetch and apply it on demand, same result, far
        # smaller/cleaner file, and it stays in sync if the context evolves.
        framed["@context"] = args.context_url

    jsonld_path = args.outdir / f"{name}.jsonld"
    jsonld_path.write_text(json.dumps(framed, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"  wrote {jsonld_path}")

    unresolved = {k for k in _all_keys(framed) if re.match(r"^https?://", k)}
    if unresolved:
        print("\nNote: some deeply-nested property IRIs did not resolve to a short")
        print("term name during framing (known JSON-LD scoped-context limitation,")
        print("data underneath is still correct):")
        for iri in sorted(unresolved):
            print(f"  - {iri}")


def _all_keys(node, found=None):
    if found is None:
        found = set()
    if isinstance(node, dict):
        found.update(node.keys())
        for v in node.values():
            _all_keys(v, found)
    elif isinstance(node, list):
        for item in node:
            _all_keys(item, found)
    return found


if __name__ == "__main__":
    main()