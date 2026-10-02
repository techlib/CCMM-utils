# CCMM Utilities

This repository contains tools which enable better usage of CCMM.

## Project Organization
While the internal structure of each tool may vary to accommodate specific requirements, they generally follow this convention:
* **`scripts/`**: Source code and execution logic.
* **`output/`**: Destination for generated files and results.

---

## Tools

### 1. flattenCCMM
A utility to resolve recursive XSD `<xs:include>` directives, consolidate namespaces (`ccmm`, `gml`), and deduplicate `<xs:import>` statements into a single, self-contained flattened schema.

* **Usage:** Can be executed locally via Python (`flatten_schema.py`) or triggered manually via GitHub Actions, which automatically commits the output to `flattenCCMM/output/CCMM_flattened.xsd`.
* **Key Features:**
  * Flattens multi-file XSD architectures into a single schema file.
  * Ensures correct placement and deduplication of external namespace imports (`<xs:import>`).
  * Accepts both local XSD file paths and remote GitHub repository URLs as input.

### 2. ceCCMM
An utility to visualize CCMM XSD structures where **mandatory parts are in bold**.
* **Automation:** This tool is triggered if the visualization script is modified or if the flattened schema in **flattenCCMM** changes.

### 3. ccmm2rdf
An utility transforming xml metadata conformant to the dataset/schema.xsd to the RDF representation using dataset/lifting.xslt.
On the input there is xml metadata file, a repository and branch and on the output are serialized Turtle, XML/RDF and JSON-LD corresponding to the JSON-LD context given by the branch.

Utility also contains the script comparing generated files as a basic ground graph triples, blank nodes and full RDF canonicalization. This checks whether the graph behind specific serializations is the same.

---

## Summary of Triggers

| Tool | Primary Function | Run Trigger |
| :--- | :--- | :--- |
| **flattenCCMM** | Merges multiple XSDs into one. | Changes in `techlib/CCMM` XSDs. |
| **ceCCMM** | Visualizes schema requirements. | Changes to visualization scripts OR the flattened schema. |
