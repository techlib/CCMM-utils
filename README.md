# CCMM Utilities

This repository contains tools which enable better usage of CCMM.

## Project Organization
While the internal structure of each tool may vary to accommodate specific requirements, they generally follow this convention:
* **`scripts/`**: Source code and execution logic.
* **`output/`**: Destination for generated files and results.

---

## Tools

### 1. flattenCCMM
A utility to normalize and merge multiple CCMM XSD files into one flattened schema.
* **Automation:** This tool is triggered whenever the XSD schemas in the **techlib/CCMM** repository are updated.
* **Credits:** Special thanks to **ccmm-invenio** for the [merge_schemas.py](https://github.com/NRP-CZ/ccmm-invenio/blob/main/ccmm_versions/src/ccmm_versions/merge_schemas.py)` script!

### 2. ceCCMM
A utility to visualize CCMM XSD structures where **mandatory parts are in bold**.
* **Automation:** This tool is triggered if the visualization script is modified or if the flattened schema in **flattenCCMM** changes.

---

## Summary of Triggers

| Tool | Primary Function | Run Trigger |
| :--- | :--- | :--- |
| **flattenCCMM** | Merges multiple XSDs into one. | Changes in `techlib/CCMM` XSDs. |
| **ceCCMM** | Visualizes schema requirements. | Changes to visualization scripts OR the flattened schema. |
