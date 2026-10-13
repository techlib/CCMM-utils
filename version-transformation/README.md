# CCMM 1.1.0 ⇄ 2.0.0 XML transformations

Repository contains XSLT files to transform metadata between CCMM version 2.0.0 and CCMM version 1.1.0 (and opposite). The general purpose for the transformation is caused by the requirement of the users to store metadata already in CCMM v2.0.0 and National Metadata Directory (NMA) accepting only CCMM XML v 1.1.0 at the time.

| File | What it is |
|---|---|
| [`ccmm-2.0.0-to-1.1.0.xslt`](ccmm-2.0.0-to-1.1.0.xslt) | CCMM 2.0.0 record → CCMM 1.1.0 record |
| [`ccmm-2.0.0-to-1.1.0-known-issues.md`](ccmm-2.0.0-to-1.1.0-known-issues.md) | losses, decisions (licences!) and recommendations |
| [`ccmm-1.1.0-to-2.0.0.xslt`](ccmm-1.1.0-to-2.0.0.xslt) | CCMM 1.1.0 record → CCMM 2.0.0 record |
| [`ccmm-1.1.0-to-2.0.0-known-issues.md`](ccmm-1.1.0-to-2.0.0-known-issues.md) | properties without a 2.0.0 candidate, placeholders, recommendations |
| [`tests/run_tests.py`](tests/run_tests.py) | runs both directions + round trips on the samples and validates against the XSDs |
| `tests/edge-cases/` | two extra fixtures: conflicting licences (2.0.0) and a sparse record (1.1.0) |
| `examples/` | outputs of the last test run |
| [`test-report.md`](test-report.md) | comparison with the native samples of both versions, incl. RDF lifting; problems found in the transformations and in the samples |
| `tests/leafdiff.py`, `tests/rdfdiff.py` | the comparison helpers used for the report |
| [`tests/shacl_check.py`](tests/shacl_check.py) | lifts native samples and outputs to RDF and validates them with each version's `shacl.ttl` (report section E) |

Both stylesheets are XSLT 3.0 (like the `lifting.xslt` / `lowering.xslt` in techlib/CCMM) and need Saxon-HE 10+ (Java `saxon-he.jar` or Python `saxonche`).

```
java -jar saxon-he.jar -s:in.xml -xsl:ccmm-2.0.0-to-1.1.0.xslt -o:out.xml
python3 tests/run_tests.py <CCMM checkout at v2.0.0> <CCMM checkout at branch 1.1.0>
```

Every value the transformations had to choose, invent, merge or drop is marked in the output by an XML comment starting with `ccmm-migration:`; placeholders use the value `:unkn`.

Last run (2026-10-09): all 4 samples of each version plus the 2 edge cases are valid against the target `dataset/schema.xsd` (XSD 1.1, validated with Python `xmlschema`), and valid again after the round trip. The 1.1.0 outputs were checked against both branch `1.1.0` and tag `1.1.0`. GML 3.2.1 was loaded from a local copy because schemas.opengis.net was not reachable; the ISO `gmd` schema it imports was stubbed, which only matters for GML coordinate-operation metadata that CCMM does not use.

Rerun 2026-10-13 after the data-service and notation changes: same result; SHACL validation added (`test-report.md` section E).

## What the transformations change

"Comment" = the output carries a `ccmm-migration:` comment at that spot. Anything not listed is copied unchanged apart from the namespace. Details and recommendations are in the known-issues files.

### CCMM 2.0.0 → 1.1.0

**Whole document**

| 2.0.0 | 1.1.0 | Comment |
|---|---|---|
| Namespace `https://schema.ccmm.cz/research-data/2.0` | `https://schema.ccmm.cz/research-data/1.1` (every element) | – |
| `xsi:schemaLocation` pair for 2.0 | 1.1 namespace + `…/1.1.0/dataset/schema.xsd` (param `schema-location`); other pairs (GML) kept | – |
| Whitespace around `iri`, `resource_url`, `funding_program` | Normalised (otherwise lifting produces invalid IRIs) | – |
| XML comments and processing instructions in the source | Removed | – |
| Child order of `dataset` | Reordered for 1.1.0: `terms_of_use` after the languages, keyword subjects after subjects | – |

**Renames (lossless)**

| 2.0.0 | 1.1.0 | Comment |
|---|---|---|
| `qualified_attribution` / `attributed_agent` (dataset, `metadata_identification`, `related_resource`) | `qualified_relation` / `relation` | – |
| `subject/label` | `subject/title` | – |
| `licence` / `licence/title` | `license` / `license/label` | – |
| `distribution_downloadable_file/conforms_to` | `conforms_to_schema` | – |
| `distribution_data_service/conforms_to` | `conforms_to_specification` | – |
| `distribution_downloadable_file/access_url` (plain IRI) | `access_url/iri` | – |
| `bounding_box/gml/gml:Envelope` | `bounding_box` with the envelope's attributes and children | – |
| `geometry/gml/<gml geometry>` | `geometry/<gml geometry>` | – |
| `generated_by` (`iri`, `label`) | `provenance` (`iri`, `label`) | – |

**Value rewrites**

| 2.0.0 | 1.1.0 | Comment |
|---|---|---|
| Code-list IRIs `https://w3id.org/tib/datacite/vocab/{titleType,dateType,descriptionType,relationType}/X` | `https://vocabs.ccmm.cz/registry/codelist/{AlternateTitle,TimeReference,DescriptionType,RelationType}/X` (same local name, labels unchanged) | – |
| `conforms_to_standard` = `…/research-data/2.0.0` | `…/1.1.0`, label `CCMM RD 1.1.0` (params `source-/target-profile-iri`, `target-profile-label`) | yes |
| `location/label` (language-tagged) | `location/name` (plain string, language lost) | – |

**Moves and merges**

| 2.0.0 | 1.1.0 | Comment |
|---|---|---|
| Dataset `access_rights` | `terms_of_use/access_rights` | – |
| `distribution_*/licence` (one per distribution) | One `terms_of_use/license`: the most frequent licence (param `licence-strategy`: `most-frequent` or `first`) | yes, if they differ |
| Distribution licences other than the chosen one | `terms_of_use/description` "Distribution "X" is licensed under …" (param `emit-terms-notes`) | – |
| No distribution licence at all | `license` with param `fallback-licence-iri`, else label `:unkn` | yes |
| `distribution_*/rights` | Removed from the distribution; if it differs from the dataset access rights, a `terms_of_use/description` "… has access rights …" | – |
| `access_service/licence` | Removed; a `terms_of_use/description` "Data service … is licensed under …" | – |
| `keyword` (one per language) | One `subject` with one `title` per keyword (keywords in different languages cannot be paired) | yes |
| `distribution_data_service/@access_url` | Dropped if it equals an endpoint (`endpoint_url/resource_url` or `iri`); else added as `endpoint_url/resource_url` of the first `access_service`; with no `access_service` dropped. Never used as the distribution IRI. | yes, unless it equals an endpoint |

**Dropped (no 1.1.0 counterpart)**

| 2.0.0 | Comment |
|---|---|
| `identifier/scheme/notation` (every identifier, incl. funders, affiliations, related resources) | yes |
| `distribution_*/title` after the first (1..n → 1..1) | yes |
| `distribution_downloadable_file/packaging_format`, `compression_format`, `description` | yes |
| `original_repository/description`, `qualified_attribution`, `record`, `dataset` | yes |
| `metadata_record/title`, `metadata_identification/title` | yes |
| `time_reference/date_information` after the first (0..n → 0..1) | yes |
| `bounding_box/iri` and `wkt` (envelope kept) | yes |
| `bounding_box` with no GML envelope (WKT or IRI only): the whole box | yes, text kept in the comment |
| `generated_by/@ro-crate_json_representation`, `@common_provenance_model_json_representation` | yes |

Distribution `rights` and service licences leave no comment at their position; they only show up as `terms_of_use/description` sentences, and only when they differ from the dataset-level value.

### CCMM 1.1.0 → 2.0.0

**Whole document**

| 1.1.0 | 2.0.0 | Comment |
|---|---|---|
| Namespace `https://schema.ccmm.cz/research-data/1.1` | `https://schema.ccmm.cz/research-data/2.0` (every element) | – |
| `xsi:schemaLocation` pair for 1.1 | 2.0 namespace + `…/2.0.0/dataset/schema.xsd` (param `schema-location`); other pairs (GML) kept | – |
| Whitespace around `iri`, `resource_url`, `funding_program` | Normalised (otherwise lifting produces invalid IRIs) | – |
| `xml:lang=""` (allowed in 1.1.0, rejected by a 2.0.0 assertion) | `xml:lang="und"`; on identifier-scheme labels see `notation` below | – |
| XML comments and processing instructions in the source | Removed | – |
| Child order of `dataset` | Reordered for 2.0.0: contact-point attribution after the attributions, `access_rights` after the languages, keywords after subjects, generated descriptions after descriptions | – |

**Renames (lossless)**

| 1.1.0 | 2.0.0 | Comment |
|---|---|---|
| `qualified_relation` / `relation` | `qualified_attribution` / `attributed_agent` | – |
| `subject/title` | `subject/label` | – |
| `license` / `license/label` | `licence` / `licence/title` | – |
| `conforms_to_schema`, `conforms_to_specification` | `conforms_to` | – |
| `access_url/iri` | `access_url` (plain IRI) | – |
| `bounding_box` (a `gml:EnvelopeType`) | `bounding_box/gml/gml:Envelope` | – |
| `geometry/<gml geometry>` | `geometry/gml/<gml geometry>` | – |
| `provenance` (`iri`, `label`) | `generated_by` (`iri`, `label`) | – |

**Value rewrites**

| 1.1.0 | 2.0.0 | Comment |
|---|---|---|
| Code-list IRIs `https://vocabs.ccmm.cz/registry/codelist/{AlternateTitle,TimeReference,DescriptionType,RelationType}/X` | `https://w3id.org/tib/datacite/vocab/{titleType,dateType,descriptionType,relationType}/X` (same local name, labels unchanged) | – |
| `conforms_to_standard` = `…/research-data/1.1.0` | `…/2.0.0`, label `Czech Core Metadata Model for Research Data 2.0.0` (params `source-/target-profile-iri`, `target-profile-label`) | yes |
| `location/name` (plain string) | `location/label` with a language from param `default-lang`, else `primary_language`, else `und` | – |
| `identifier/scheme/label` with `xml:lang=""` (acronym such as `ORCID`) | `scheme/notation` | – |

**Moves and merges**

| 1.1.0 | 2.0.0 | Comment |
|---|---|---|
| `terms_of_use` | Dissolved into the parts below | – |
| `terms_of_use/access_rights` | Dataset `access_rights`, and a copy as `rights` on every distribution (param `access-rights-to-distributions`) | yes |
| `terms_of_use/license` | `licence` on every distribution | yes |
| `terms_of_use/license` when there is no distribution | `description` of type Other "Licence: …" | yes |
| `terms_of_use/description` | `description` of type Other (param `terms-description-to-description`) | yes |
| `terms_of_use/contact_point` | Dataset `qualified_attribution` with role `…/AgentRole/ContactPerson` (param `contact-role-iri`) | yes |
| `subject` without a subject scheme (free keyword) | One `keyword` per `title`; its `iri` and `definition` are dropped | yes |
| `location/bounding_box` (0..n → 0..1) | Boxes in the same CRS merged into their union; otherwise the first is kept | yes, if more than one |
| `metadata_record/date_updated` (0..n → 1..1) | The latest date | yes, if more than one |
| `access_service/endpoint_url/iri` | Copied into `resource_url` when that is missing; the `iri` is dropped when it repeats the service or distribution IRI | yes |
| Data-service distribution `iri` equal to the service IRI or an endpoint URL | Dropped (blank-node distribution; otherwise the distribution merges with the service in RDF) | yes |

**Added (2.0.0 requires them, 1.1.0 has no source)**

| 2.0.0 | Filled with | Comment |
|---|---|---|
| `metadata_record/date_updated` (1..1) | `date_created`, else param `fallback-date-updated`, else the conversion date | yes |
| `original_repository/label` (1..n) | The repository IRI | yes |
| `original_repository/description` (1..n) | Param `repository-description`, else `:unkn` | yes, without the parameter |
| `original_repository/qualified_attribution` (Publisher) | Organization from params `repository-publisher-name` / `-ror`, else named `:unkn` | yes, without the parameter |
| `description` (1..n) | The dataset title | yes |
| `subject` from a scheme (FORD required) | Subjects with FORD / INSPIRE IRIs get `subject_scheme` inferred from the IRI; with none, a FORD subject with label and code `:unkn` | yes |
| `subject/classification_code` | Last segment of the subject IRI | yes |
| `distribution_data_service/@access_url` (required) | First of `endpoint_url/resource_url`, `endpoint_url/iri`, `access_service/iri`, the distribution `iri`; else `:unkn` | yes |
| `access_service/label` (1..n) | Endpoint title, else distribution title, else the service IRI, else `:unkn` | yes |
| `label` (1..n) on code-list values (role, title / date / description / relation types, resource type, access rights, format, media type, languages) | Built-in table (COAR access rights and resource types, EU languages, main agent roles), else the last segment of the IRI with `xml:lang="en"` | yes, for the IRI fallback |
| `identifier/scheme` label and `notation` for DOI, ORCID, ROR, IČO when missing | Built-in table | – |

**Dropped (no 2.0.0 counterpart)**

| 1.1.0 | Comment |
|---|---|
| `access_url/label` | yes |
| `conforms_to_schema` / `conforms_to_specification` with an empty `iri` (lifts to the document base IRI) | yes, label kept in the comment |
| Empty `<provenance/>` placeholder (no `iri`, no `label`, as in the 1.1.0 samples) | – |
