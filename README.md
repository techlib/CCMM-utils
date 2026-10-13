# CCMM Utilities

This repository contains tools which enable better usage of CCMM.

## Project Organization
While the internal structure of each tool may vary to accommodate specific requirements, they generally follow this convention:
* **`scripts/`**: Source code and execution logic.
* **`output/`**: Destination for generated files and results.

---

## Tools

### 1. flattenCCMM
An utility to normalize and merge multiple CCMM XSD files into one flattened schema. Once the merging script finishes, the workflow performs an **integration test** by validating CCMM XML samples against the generated XSD.
* **Automation:** This tool is triggered whenever the XSD schemas in the **techlib/CCMM** repository are updated.
* **Credits:** Special thanks to **ccmm-invenio** for the [merge_schemas.py](https://github.com/NRP-CZ/ccmm-invenio/blob/main/ccmm_versions/src/ccmm_versions/merge_schemas.py)` script!

### 2. ceCCMM
An utility to visualize CCMM XSD structures where **mandatory parts are in bold**.
* **Automation:** This tool is triggered if the visualization script is modified or if the flattened schema in **flattenCCMM** changes.

### 3. ccmm2rdf
An utility transforming xml metadata conformant to the dataset/schema.xsd to the RDF representation using dataset/lifting.xslt.
On the input there is xml metadata file, a repository and branch and on the output are serialized Turtle, XML/RDF and JSON-LD corresponding to the JSON-LD context given by the branch.

Utility also contains the script comparing generated files as a basic ground graph triples, blank nodes and full RDF canonicalization. This checks whether the graph behind specific serializations is the same.

### 4. version-transformation
An utility transforming CCMM XML metadata between **CCMM 2.0.0 and CCMM 1.1.0** (both directions) using XSLT 3.0 stylesheets (requires Saxon-HE 10+). It allows storing metadata in CCMM 2.0.0 while the National Metadata Directory (NMA) still accepts only CCMM 1.1.0.
Every value the transformation had to choose, invent, merge or drop is marked in the output by an XML comment starting with `ccmm-migration:`. Losses, decisions and recommendations for each direction are described in the known-issues files.

Utility also contains a test runner which transforms the CCMM samples in both directions including round trips and validates the outputs against the target XSD, plus a SHACL check of the lifted RDF.
* **Automation:** None, the tests are run manually (`python3 tests/run_tests.py <CCMM v2.0.0 checkout> <CCMM 1.1.0 checkout>`).

---

## Summary of Triggers

| Tool | Primary Function | Run Trigger |
| :--- | :--- | :--- |
| **flattenCCMM** | Merges multiple XSDs into one. | Changes in `techlib/CCMM` XSDs. |
| **ceCCMM** | Visualizes schema requirements. | Changes to visualization scripts OR the flattened schema. |
| **ccmm2rdf** | Transforms CCMM XML into RDF (Turtle, RDF/XML, JSON-LD). | Manual workflow run (`workflow_dispatch`) with the XML input, repository and branch. |
| **version-transformation** | Transforms CCMM XML between 2.0.0 and 1.1.0. | Manual. |
