# CCMM 2.0.0 → 1.1.0: known issues and recommendations

Transformation: [`ccmm-2.0.0-to-1.1.0.xslt`](ccmm-2.0.0-to-1.1.0.xslt) (XSLT 3.0, Saxon-HE).

Sources compared: `techlib/CCMM` tag `v2.0.0` (identical XSDs on `main`) and branch `1.1.0` (also checked against tag `1.1.0`).
All four 2.0.0 sample records and the edge-case fixture convert to records that validate against the 1.1.0 `dataset/schema.xsd` (XSD 1.1), and convert back to valid 2.0.0. See [`tests/run_tests.py`](tests/run_tests.py) and the outputs in `examples/`.

Every value the transformation had to choose, merge, invent or drop is marked in the output by an XML comment that starts with `ccmm-migration:`. Searching for that string is the quickest review of a converted record.

## 1. Licence: one per distribution in 2.0.0, exactly one per dataset in 1.1.0

**Problem.** 2.0.0 puts `licence` (1..1) on every distribution, following DCAT-AP. 1.1.0 has a single mandatory `terms_of_use/license` (1..1) for the whole dataset. A 2.0.0 record can therefore have no licence at all (no distributions), one licence repeated on every distribution (the usual case), or several different licences.

**What the XSLT does.**

| Situation in 2.0.0 | Result in 1.1.0 |
|---|---|
| All distributions have the same licence | That licence, once. Licences are compared by IRI, ignoring a trailing `/`; licences without IRI by their titles. |
| Distributions have different licences | One licence is chosen with parameter `licence-strategy`: `most-frequent` (default, ties go to the first in document order) or `first`. Every distribution with a different licence gets a sentence in `terms_of_use/description`, for example *Distribution "WMS service" is licensed under CC BY 4.0 (https://…).* |
| No distribution, so no licence | The IRI in parameter `fallback-licence-iri` if set, otherwise a placeholder `<license><label xml:lang="en">:unkn</label></license>`. 1.1.0 makes `license` mandatory but all its children optional, so the record stays valid. |
| Licence of a data service (`access_service/licence`) | Not a candidate for the dataset licence (it licenses the service, not the data). Kept as a sentence in `terms_of_use/description`. |

`licence/title` becomes `license/label`.

**Recommendations.**
- If a repository uses one licence per dataset, the default is lossless.
- If a record has several licences, the 1.1.0 record cannot state them faithfully. The descriptions keep the information for a human reader, but no machine can read it. Decide per repository whether the most permissive or the most restrictive licence is the safer dataset-level value, and add a strategy for it if needed (for example a lookup that ranks CC licences).
- Set `fallback-licence-iri` when the repository has a default licence for metadata-only records; otherwise review every `:unkn` licence by hand.

## 2. Access rights per distribution

**Problem.** 2.0.0 has dataset `access_rights` (1..1) plus optional `rights` on each distribution. 1.1.0 only has `terms_of_use/access_rights`.

**What the XSLT does.** Dataset `access_rights` goes to `terms_of_use/access_rights`. A distribution whose `rights` differ from the dataset value adds a sentence to `terms_of_use/description`. COAR values are compared by their code, because the samples mix `http://purl.org/coar/access_right/c_abf2` and `https://vocabularies.coar-repositories.org/access_rights/c_abf2/` for the same concept.

**Recommendation.** Agree on one COAR IRI form in 2.0.0 records. The two forms above are the same concept but will not match in any IRI-based tool.

## 3. Code-list IRIs changed

**Problem.** 2.0.0 uses the DataCite linked-data vocabularies; 1.1.0 used CCMM copies of the same lists.

| Element | 2.0.0 IRI prefix | 1.1.0 IRI prefix |
|---|---|---|
| `alternate_title_type` | `https://w3id.org/tib/datacite/vocab/titleType/` | `https://vocabs.ccmm.cz/registry/codelist/AlternateTitle/` |
| `date_type` | `https://w3id.org/tib/datacite/vocab/dateType/` | `https://vocabs.ccmm.cz/registry/codelist/TimeReference/` |
| `description_type` | `https://w3id.org/tib/datacite/vocab/descriptionType/` | `https://vocabs.ccmm.cz/registry/codelist/DescriptionType/` |
| `resource_relation_type` | `https://w3id.org/tib/datacite/vocab/relationType/` | `https://vocabs.ccmm.cz/registry/codelist/RelationType/` |

**What the XSLT does.** Rewrites the prefix and keeps the local name (`Collected`, `IsDerivedFrom`, …). Other IRIs pass through unchanged. Labels are copied as they are, so a converted record shows 2.0.0-style labels (`TranslatedTitle`, `Collected`) where native 1.1.0 records have `Translated Title`, `Date Collected`.

**Recommendations.**
- This assumes every DataCite value exists in the CCMM 1.1.0 list under the same local name. That was true for all values in the samples but was not checked against the full vocabularies (vocabs.ccmm.cz was not reachable from this environment). Check the lists once and add exceptions to the `codelist-map` if needed.
- If 1.1.0 consumers display labels, replace them from the 1.1.0 code lists instead of copying.

## 4. Properties with no 1.1.0 counterpart (dropped)

| 2.0.0 property | Handling |
|---|---|
| `metadata_identification/title` | Dropped. |
| `original_repository/description`, `qualified_attribution` (repository publisher), `record`, `dataset` | Dropped; 1.1.0 repository is only `iri` + `label`. |
| `identifier_scheme/notation` | Dropped (comment keeps it). The 1.1.0 samples carry acronyms such as `ORCID` as a label with `xml:lang=""`, but that fails `rdf:langString` in the 1.1.0 SHACL. The inverse XSLT restores the notation of DOI, ORCID, ROR and IČO from its built-in table. |
| `distribution_downloadable_file/packaging_format`, `compression_format`, `description` | Dropped. |
| `distribution_*/title` beyond the first | Dropped (1.1.0 allows one title). |
| `distribution_data_service/@access_url` | 1.1.0 has no access URL on a data-service distribution. Dropped when it equals an `access_service/endpoint_url` (`resource_url` or `iri`), which is the usual case; otherwise added as an extra `endpoint_url/resource_url` of the first `access_service`; with no `access_service`, dropped (comment keeps the URL). It is never used as the distribution `iri`: the endpoint URL lifts as a `ccmm:resourceUrl` literal, not as a node IRI, while the `access_service/iri` often repeats the same URL, so in RDF the distribution and the `dcat:DataService` would become one node. The distribution stays without IRI unless the source has one. |
| `distribution_*/licence`, `rights` | See sections 1 and 2. |
| `data_service/licence` | See section 1. |
| `location/bounding_box/iri` and `wkt` | Dropped; only a GML envelope can be expressed. A bounding box given only as WKT is lost (comment in the output keeps the text). |
| `generated_by/@common_provenance_model_json_representation`, `@ro-crate_json_representation` | Dropped. `generated_by` (provenance activity) becomes `provenance` (provenance statement) with `iri` and `label`. |
| `time_reference/date_information` beyond the first | Dropped (0..1 in 1.1.0). |

**Recommendations.**
- WKT-only bounding boxes: if they matter, compute the envelope from the WKT coordinates (min/max of the pairs) before running the XSLT, or put the WKT polygon into `location/geometry/wkt` when the location has no other geometry.
- If the RO-Crate / CPM links are needed in 1.1.0, add them as a `related_resource` with an appropriate relation type; there is no dedicated place.

## 5. Structural renames (lossless)

| 2.0.0 | 1.1.0 |
|---|---|
| `qualified_attribution` / `attributed_agent` | `qualified_relation` / `relation` |
| dataset `access_rights` | `terms_of_use/access_rights` |
| `subject/label` | `subject/title` |
| `keyword` (one per language) | one `subject` with a single `title` per keyword. 2.0.0 keywords in different languages cannot be paired, so a keyword with Czech and English forms becomes two subjects where a native 1.1.0 record has one subject with two titles. |
| `location/label` (language-tagged) | `location/name` (plain string, language lost) |
| `bounding_box/gml/gml:Envelope` | `bounding_box` itself (a `gml:EnvelopeType`) |
| `geometry/gml/<gml geometry>` | `geometry/<gml geometry>` |
| `access_url` (plain IRI) | `access_url/iri` |
| `conforms_to` | `conforms_to_schema` (files) / `conforms_to_specification` (services) |
| `licence_document/title` | `license_document/label` |
| `conforms_to_standard` = `https://model.ccmm.cz/research-data/2.0.0` | rewritten to `…/1.1.0` (parameters `source-profile-iri`, `target-profile-iri`, `target-profile-label`), because the output no longer conforms to 2.0.0. |

## 6. Other points to check

- **Schema location.** The output uses `xsi:schemaLocation="https://schema.ccmm.cz/research-data/1.1 https://model.ccmm.cz/research-data/1.1.0/dataset/schema.xsd"` (parameter `schema-location`). The versioned URL is used because the unversioned `https://model.ccmm.cz/research-data/dataset/schema.xsd` always serves the latest version, so records pointing there stop validating when a new version is published. If the source root has an `xsi:schemaLocation`, its CCMM pair is replaced and any other pairs (e.g. GML) are kept.
- **Comments.** XML comments from the source are not copied (they would land in the wrong places); only `ccmm-migration:` comments are written.
- **Whitespace in IRIs.** Text of `iri`, `resource_url` and `funding_program` is whitespace-normalised, because `lifting.xslt` copies raw text into RDF IRIs.
- **Duplicates are not removed.** A subject or keyword that appears twice in the source appears twice in the output (the 2.0.0 sample `1m3t2-78951.xml` has FORD 10606 twice).
- **Namespace check.** The XSLT stops with an error if the root is not `{https://schema.ccmm.cz/research-data/2.0}dataset`.
- **GML.** GML content is copied verbatim; its validity depends on the source record.

## Parameters

| Parameter | Default | Purpose |
|---|---|---|
| `licence-strategy` | `most-frequent` | `most-frequent` or `first`, see section 1 |
| `fallback-licence-iri` | empty | licence used when no distribution has one |
| `emit-terms-notes` | `true()` | write differing distribution licences / rights into `terms_of_use/description` |
| `placeholder` | `:unkn` | value for unknown mandatory content (DataCite convention, already used in CCMM samples) |
| `schema-location` | `https://model.ccmm.cz/research-data/1.1.0/dataset/schema.xsd` | second part of `xsi:schemaLocation` |
| `source-profile-iri`, `target-profile-iri`, `target-profile-label` | CCMM 2.0.0 / 1.1.0 | profile rewrite in `conforms_to_standard` |

Example: `java -jar saxon-he.jar -s:record-2.0.xml -xsl:ccmm-2.0.0-to-1.1.0.xslt -o:record-1.1.xml licence-strategy=first`
