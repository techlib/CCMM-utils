#!/usr/bin/env python3
import argparse
import os
import re
import shutil
import subprocess
from lxml import etree

XSD_NS = "http://www.w3.org/2001/XMLSchema"
GML_NS = "http://www.opengis.net/gml/3.2"
GML_SCHEMA_LOC = "https://schemas.opengis.net/gml/3.2.1/gml.xsd"
CCMM_NS = "https://schema.ccmm.cz/research-data/2.0"

NS_MAP = {"xs": XSD_NS}


def parse_github_url(url: str):
    pattern = r"https://github\.com/([^/]+)/([^/]+)(?:/tree/([^/]+)(?:/(.+))?)?"
    match = re.match(pattern, url)
    if not match:
        raise ValueError(f"Not valid GitHub URL: {url}")

    owner, repo, branch, path = match.groups()
    return {
        "owner": owner,
        "repo": repo,
        "branch": branch or "main",
        "path": path or "",
    }


def download_github_repo(gh_info: dict, target_dir: str):
    repo_url = f"https://github.com/{gh_info['owner']}/{gh_info['repo']}.git"
    print(f" Downloading repository {repo_url} (branch: {gh_info['branch']})...")

    cmd = [
        "git",
        "clone",
        "--depth",
        "1",
        "--branch",
        gh_info["branch"],
        repo_url,
        target_dir,
    ]
    subprocess.run(cmd, check=True)


def merge_includes(schema_path: str, visited=None):
    """Recursive replacement <xs:include>"""
    if visited is None:
        visited = set()

    schema_path = os.path.abspath(schema_path)
    if schema_path in visited:
        return None
    visited.add(schema_path)

    if not os.path.exists(schema_path):
        print(f"Warning: File not found: {schema_path}")
        return None

    parser = etree.XMLParser(remove_blank_text=True)
    tree = etree.parse(schema_path, parser)
    root = tree.getroot()

    while True:
        inc = root.find(".//xs:include", namespaces=NS_MAP)
        if inc is None:
            break

        location = inc.get("schemaLocation")
        if not location:
            inc.getparent().remove(inc)
            continue

        inc_path = os.path.normpath(
            os.path.join(os.path.dirname(schema_path), location)
        )

        inc_root = merge_includes(inc_path, visited)

        parent = inc.getparent()
        if inc_root is not None:
            inc_index = parent.index(inc)
            for child in inc_root:
                parent.insert(inc_index, child)
                inc_index += 1

        parent.remove(inc)

    return root


def postprocess_imports_and_namespaces(root: etree._Element):
    """Adding missing name spaces into root element <xs:schema>.
       Gathering all imports and place them into root element <xs:schema>.
    """
    etree.cleanup_namespaces(root)
    nsmap = root.nsmap.copy()
    need_new_root = False

    if "gml" not in nsmap:
        nsmap["gml"] = GML_NS
        need_new_root = True

    if "ccmm" not in nsmap:
        nsmap["ccmm"] = CCMM_NS
        need_new_root = True

    if need_new_root:
        new_root = etree.Element(root.tag, attrib=root.attrib, nsmap=nsmap)
        new_root.extend(list(root))
        root = new_root

    imports = root.findall(".//xs:import", namespaces=NS_MAP)

    unique_imports = []
    seen_imports = set()

    has_gml_import = False
    for imp in imports:
        ns = imp.get("namespace")
        loc = imp.get("schemaLocation")
        if ns == GML_NS:
            has_gml_import = True
        key = (ns, loc)
        if key not in seen_imports:
            seen_imports.add(key)
            unique_imports.append((ns, loc))
        imp.getparent().remove(imp)

    if not has_gml_import:
        key = (GML_NS, GML_SCHEMA_LOC)
        if key not in seen_imports:
            seen_imports.add(key)
            unique_imports.append(key)

    insert_index = 0
    for ns, loc in unique_imports:
        import_attrib = {}
        if ns:
            import_attrib["namespace"] = ns
        if loc:
            import_attrib["schemaLocation"] = loc

        import_elem = etree.Element(
            f"{{{XSD_NS}}}import", attrib=import_attrib
        )
        root.insert(insert_index, import_elem)
        insert_index += 1

    return root


def flatten_xsd(entry_xsd_path: str, output_path: str):
    print(f" Processing XSD: {entry_xsd_path}")

    merged_root = merge_includes(entry_xsd_path)

    if merged_root is None:
        raise RuntimeError("Loading main XSD schema unsuccessful.")

    merged_root = postprocess_imports_and_namespaces(merged_root)

    abs_output = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(abs_output), exist_ok=True)

    merged_tree = etree.ElementTree(merged_root)
    merged_tree.write(
        abs_output, encoding="utf-8", xml_declaration=True, pretty_print=True
    )

    print(f" Done! Merged XSD stored in: {abs_output}")


def main():
    parser = argparse.ArgumentParser(
        description="Flatten XML Schema from GitHub URL or local path."
    )
    parser.add_argument(
        "--input",
        "-i",
        required=True,
        help="GitHub URL or local path to main XSD.",
    )
    parser.add_argument(
        "--output",
        "-o",
        default="output/flattened.xsd",
        help="Output path for merged XSD.",
    )
    args = parser.parse_args()

    if args.input.startswith("http://") or args.input.startswith("https://"):
        gh_info = parse_github_url(args.input)
        temp_dir = os.path.abspath("_tmp_repo")

        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

        try:
            download_github_repo(gh_info, temp_dir)

            subpath = gh_info["path"]
            if not subpath:
                local_xsd_path = os.path.join(temp_dir, "dataset", "schema.xsd")
            else:
                local_xsd_path = os.path.join(temp_dir, subpath)
                if os.path.isdir(local_xsd_path):
                    if os.path.exists(
                        os.path.join(local_xsd_path, "schema.xsd")
                    ):
                        local_xsd_path = os.path.join(
                            local_xsd_path, "schema.xsd"
                        )
                    elif os.path.exists(
                        os.path.join(local_xsd_path, "main.xsd")
                    ):
                        local_xsd_path = os.path.join(local_xsd_path, "main.xsd")

            flatten_xsd(local_xsd_path, args.output)
        finally:
            if os.path.exists(temp_dir):
                shutil.rmtree(temp_dir)
    else:
        local_path = args.input
        if os.path.isdir(local_path):
            if os.path.exists(os.path.join(local_path, "dataset", "schema.xsd")):
                local_path = os.path.join(local_path, "dataset", "schema.xsd")
            elif os.path.exists(os.path.join(local_path, "schema.xsd")):
                local_path = os.path.join(local_path, "schema.xsd")

        flatten_xsd(local_path, args.output)


if __name__ == "__main__":
    main()
