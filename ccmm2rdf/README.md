### XXMM XML to RDF conversion

Script automatically converts XML metadata into RDF using lifting transformation and json-ld contexts generated from dataspecer.

Scripts input is CCMM xml file.

The output is Turtle, XML/RDF and JSON-LD.

##### Running the script

There is an action `Run ccmm2rdf`. Run it with the parameters:
- Direct URL to metadata XML file or folder containing XML files,
- GitHub repository comntaing CCMM specification (e.g. `techlib/CCMM`),
- Branch of the repository (`main` or `1.2.0`),
- Paths to `lifting.xslt` and `context.jsonld` (dafault `dataset/lifting.xslt` and `dataset/context.jsonld`),
- Optional: URL to the json-ld context to link from the transformed metadata (otherwise the whole context will be part of the output JSON-LD file).


##### Sample run

`python scripts/ccmm2rdf.py https://raw.githubusercontent.com/techlib/CCMM/refs/heads/sample-data-1.2/_metadata-samples/xml/ccmm_sample.xml --repo techlib/CCMM --branch 1.2.0 --lifting dataset/lifting.xslt --context dataset/context.jsonld   --context-url "URL_of_JSON_LD _context" --outdir output`

##### Serialization comparison

Script located in `scripts/compare_rdf.py` compares different serializations, presuming they represent the same RDF graph.

Usage: `python compare_rdf.py file1.ttl file2.rdf.xml file3.jsonld [...]`

###### Known limitation: unresolved property names in JSON-LD output

Some nested properties in the output JSON-LD may appear under their full IRI (e.g. https://model.ccmm.cz/vocabulary/ccmm#hasType) instead of the short field name from schema.json/context.jsonld (e.g. resource_type). The values are correct — only the key name is affected. Impact is cosmetic, not a correctness issue — the output is still valid, standards-compliant JSON-LD and reconstructs identical RDF triples on reparse. It's just not guaranteed to match schema.json's exact field names everywhere.
