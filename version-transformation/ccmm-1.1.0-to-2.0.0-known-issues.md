# CCMM 1.1.0 → 2.0.0: known issues and recommendations

Transformation: [`ccmm-1.1.0-to-2.0.0.xslt`](ccmm-1.1.0-to-2.0.0.xslt) (XSLT 3.0, Saxon-HE).

Sources compared: `techlib/CCMM` branch `1.1.0` (also tag `1.1.0`) and tag `v2.0.0` (identical XSDs on `main`).
All four 1.1.0 sample records and the sparse edge-case fixture convert to records that validate against the 2.0.0 `dataset/schema.xsd` (XSD 1.1, including its `xs:assert` rules), and convert back to valid 1.1.0. See [`tests/run_tests.py`](tests/run_tests.py) and the outputs in `examples/`.

Validity is reached partly with placeholders. **A valid output is not a finished 2.0.0 record**: every invented, derived or moved value is marked by an XML comment starting with `ccmm-migration:`, and the placeholder value `:unkn` (DataCite convention, already used in CCMM samples) marks content that has no source at all. Review both before publishing.

## 1. 1.1.0 properties with no candidate in 2.0.0

| 1.1.0 property | What the XSLT does | Recommendation |
|---|---|---|
| `terms_of_use` (class) | Dissolved: `access_rights` goes to the dataset, `license` to every distribution (see section 2). | – |
| `terms_of_use/description` | Kept as a dataset `description` of type `…/descriptionType/Other` (parameter `terms-description-to-description`, default on). | If the text is really a rights statement, consider a DCAT-AP `dct:rights` extension in a later CCMM version; CCMM 2.0.0 has no rights statement on the dataset. |
| `terms_of_use/contact_point` | Becomes a dataset `qualified_attribution` with role `https://vocabs.ccmm.cz/registry/codelist/AgentRole/ContactPerson` (parameter `contact-role-iri`). The context "contact for the terms of use" is lost. | Check the role IRI against the AgentRole code list (it is used in the DataCite mapping samples, but the code list was not reachable from here). |
| `terms_of_use/license` when the dataset has **no distribution** | 2.0.0 only has licences on distributions, so there is nowhere to put it. Kept as a description of type Other, e.g. *Licence: Attribution 4.0 International, https://creativecommons.org/licenses/by/4.0/*. | Raise this in CCMM: a metadata-only record (no distribution) cannot state a licence in 2.0.0. |
| `subject` without a subject scheme (free keywords) | Each `title` becomes a `keyword` with the same language. The subject `iri` and `definition`, if any, are dropped (comment keeps them). | – |
| `location/bounding_box` beyond the first (0..n → 0..1) | Boxes with the same `srsName` and `lowerCorner`/`upperCorner` are merged into their union. Otherwise only the first box is kept. | Union is a coarser extent. If the separate boxes matter, express them as separate `location`s. |
| `location/name` (plain string) | Becomes `location/label` with a language tag guessed from the dataset (see section 4). | – |
| Data-service distribution `iri` equal to the `access_service/iri` or an endpoint URL | Dropped (the distribution becomes a blank node, as in the native 2.0.0 sample). The 1.1.0 `ccmm_sample` uses one URL for the distribution, the service and the endpoint; in RDF that makes one node that is both `dcat:Distribution` and `dcat:DataService`, with two titles. | Give distributions their own IRI or none. |
| `access_service/endpoint_url/iri` (1.1.0 puts the endpoint URL here) | Copied into `resource_url` when that is missing, as native 2.0.0 does. The `iri` is dropped when it repeats the service or distribution IRI (it would merge the endpoint with the service node in RDF), kept otherwise. | – |
| `access_url/label`, `access_url/iri` (a `file` object) | 2.0.0 `access_url` is a plain IRI: the IRI is kept, labels dropped. | – |
| `provenance` (provenance statement, `iri` + `label`) | Becomes `generated_by` (provenance activity). The 1.1.0 element was a placeholder, so the semantic change (statement → activity) is harmless in practice. An empty `<provenance/>` (as in the 1.1.0 samples) is dropped. | – |
| `metadata_record/date_updated` (0..n) | 2.0.0 allows exactly one: the latest date is kept. | – |
| `time_reference/date_information` (0..1) | Copied (2.0.0 allows 0..n). | – |
| `identifier/scheme/label` with `xml:lang=""` | Becomes `notation` (that is how 1.1.0 records carry `ORCID`, `ROR`, `DOI`). Known schemes (DOI, ORCID, ROR, IČO) also get the English label used in the 2.0.0 samples. | – |
| Any other `xml:lang=""` | 2.0.0 asserts a non-empty language tag on every language-tagged string; empty tags become `und` (undetermined). | Replace `und` with the real language where known. |

## 2. Licence: one per dataset in 1.1.0, one per distribution in 2.0.0

**What the XSLT does.** `terms_of_use/license` is copied as `licence` into every distribution, of both kinds (`license/label` → `licence/title`). The dataset access rights are also copied into each distribution's `rights`, as the 2.0.0 samples do (parameter `access-rights-to-distributions`, default on).

**Recommendation.** If some distributions of a dataset really have a different licence (for example an API under a different licence than the files), 1.1.0 never said so; review per repository.

## 3. 2.0.0 mandatory properties with no source in 1.1.0

| 2.0.0 property (cardinality) | Filled with | Recommendation |
|---|---|---|
| `original_repository/description` (1..n) | Parameter `repository-description`, else `:unkn`. | Set the parameter: a converter normally runs per repository. |
| `original_repository/qualified_attribution` with Publisher role (1..n) | Organization from parameters `repository-publisher-name` (+ optional `repository-publisher-ror`), else an organization named `:unkn`. | Set the parameters. Do not reuse the dataset publisher blindly: the repository operator can be a different organization. |
| `original_repository/label` (1..n, was 0..n) | The repository IRI. | Set a real name. |
| `metadata_record/date_updated` (1..1, was 0..n) | Latest `date_updated`, else `date_created`, else parameter `fallback-date-updated`, else the conversion date. | Using the conversion date is defensible (the record was updated by the conversion), but say so in your process documentation. |
| `description` (1..n, was 0..n) | The dataset title, as a description without type. | Write a real abstract; DCAT-AP makes `dct:description` mandatory, so a title copy is a weak description. |
| `subject` from a scheme with `classification_code` and `subject_scheme` (1..n each) | 1.1.0 subjects with a `subject_scheme` are kept. Subjects whose IRI starts with the FORD or INSPIRE theme namespace get the scheme inferred and `classification_code` = last segment of the IRI. With no such subject, a placeholder subject in the FORD scheme with label and code `:unkn` is created. | Every 2.0.0 record must have a FORD subject (usage note). Records with the placeholder need manual classification. |
| `distribution_data_service/@access_url` (required) | First of: `access_service/endpoint_url/resource_url`, `endpoint_url/iri`, `access_service/iri`, the distribution `iri`; else `:unkn`. | Check it is the real service endpoint. |
| `access_service/label` (1..n, was 0..n) | Endpoint title, else distribution title, else the service IRI, else `:unkn`. | Set a real service name. |
| `distribution_*/licence` (1..1) | Dataset licence, see section 2. | – |
| `label` (1..n, was 0..n) on code-list values: role, alternate title type, date type, resource type, access rights, description type, relation types, format, media type, languages | Existing labels are kept. Missing ones come from a small built-in table (COAR access rights, common EU languages, the main agent roles, a few COAR resource types), else the last segment of the IRI with `xml:lang="en"` (correct for the DataCite vocabularies, e.g. `Collected`, `IsDerivedFrom`; poor for COAR codes like `c_ddb1`). | Extend the `known-labels` table, or look labels up in the code lists before or after conversion. |

## 4. Language of new language-tagged strings

1.1.0 location names and the dataset title have no language, but their 2.0.0 targets (`location/label`, `description_text`) require one. The XSLT uses parameter `default-lang`, else maps `primary_language` (`CES` → `cs`, `ENG` → `en`, `SLK`, `DEU`, `POL`, `FRA`, `SPA`, `ITA`), else `und`.

**Recommendation.** Set `default-lang` when the repository is known to be monolingual.

## 5. Code-list IRIs changed

1.1.0 used CCMM copies of the DataCite lists; 2.0.0 uses the DataCite linked-data vocabularies. The XSLT rewrites the prefix and keeps the local name:

| Element | 1.1.0 IRI prefix | 2.0.0 IRI prefix |
|---|---|---|
| `alternate_title_type` | `https://vocabs.ccmm.cz/registry/codelist/AlternateTitle/` | `https://w3id.org/tib/datacite/vocab/titleType/` |
| `date_type` | `https://vocabs.ccmm.cz/registry/codelist/TimeReference/` | `https://w3id.org/tib/datacite/vocab/dateType/` |
| `description_type` | `https://vocabs.ccmm.cz/registry/codelist/DescriptionType/` | `https://w3id.org/tib/datacite/vocab/descriptionType/` |
| `resource_relation_type` | `https://vocabs.ccmm.cz/registry/codelist/RelationType/` | `https://w3id.org/tib/datacite/vocab/relationType/` |

Labels are copied unchanged (`Date Collected` stays, where native 2.0.0 records say `Collected`).

**Recommendations.**
- Verify that every value of the CCMM 1.1.0 lists exists in the DataCite vocabularies under the same local name. This held for every value in the samples; the full lists could not be checked from here. A CCMM-only value would produce an IRI that does not resolve.
- Other code lists (agent roles, location relation, FORD subjects, COAR, EU file types and languages) did not change and pass through.
- The samples also changed checksum algorithm IRIs (`https://www.iana.org/go/rfc6920` → SPDX `https://spdx.org/rdf/terms/#d4e4247`). That is a data change, not a schema change, so the XSLT keeps the IRI. If 2.0.0 consumers expect SPDX, add a mapping.

## 6. Structural renames (lossless)

| 1.1.0 | 2.0.0 |
|---|---|
| `qualified_relation` / `relation` | `qualified_attribution` / `attributed_agent` |
| `terms_of_use/access_rights` | dataset `access_rights` |
| `subject/title` | `subject/label` |
| `bounding_box` (a `gml:EnvelopeType`) | `bounding_box/gml/gml:Envelope` |
| `geometry/<gml geometry>` | `geometry/gml/<gml geometry>` |
| `access_url/iri` | `access_url` |
| `conforms_to_schema`, `conforms_to_specification` | `conforms_to`; one with an empty `iri` is dropped (an empty IRI lifts to the document's base IRI in RDF) |
| `license/label` | `licence/title` |
| `conforms_to_standard` = `https://model.ccmm.cz/research-data/1.1.0` | rewritten to `…/2.0.0` (parameters `source-profile-iri`, `target-profile-iri`, `target-profile-label`) |

## 7. Other points to check

- **Schema location.** The output uses `xsi:schemaLocation="https://schema.ccmm.cz/research-data/2.0 https://model.ccmm.cz/research-data/2.0.0/dataset/schema.xsd"` (parameter `schema-location`). The versioned URL is used because the unversioned `https://model.ccmm.cz/research-data/dataset/schema.xsd` always serves the latest version, so records pointing there stop validating when a new version is published. If the source root has an `xsi:schemaLocation`, its CCMM pair is replaced and any other pairs (e.g. GML) are kept.
- **Comments.** Source XML comments are not copied.
- **Whitespace in IRIs.** Text of `iri`, `resource_url` and `funding_program` is whitespace-normalised. XSD validation tolerates `<iri>\n   https://…</iri>`, but `lifting.xslt` copies the raw text and produces invalid IRIs (seen in the 1.1.0 sample `1m3t2-78951.xml`).
- **Namespace check.** The XSLT stops with an error if the root is not `{https://schema.ccmm.cz/research-data/1.1}dataset`.
- **Round trip.** 1.1.0 → 2.0.0 → 1.1.0 is not identity: the contact point comes back as a dataset attribution, the terms description as a dataset description, keywords move after controlled subjects, and generated labels stay.

## Parameters

| Parameter | Default | Purpose |
|---|---|---|
| `placeholder` | `:unkn` | value for unknown mandatory content |
| `default-lang` | empty (derived) | language tag for new language-tagged strings |
| `repository-description`, `repository-description-lang` | empty, `en` | repository description |
| `repository-publisher-name`, `repository-publisher-ror` | empty | repository publisher |
| `fallback-date-updated` | empty (today) | `date_updated` when the record has no date |
| `terms-description-to-description` | `true()` | keep `terms_of_use/description` as a description of type Other |
| `access-rights-to-distributions` | `true()` | copy dataset access rights into each distribution's `rights` |
| `contact-role-iri` | `…/AgentRole/ContactPerson` | role for the former terms-of-use contact point |
| `schema-location` | `https://model.ccmm.cz/research-data/2.0.0/dataset/schema.xsd` | second part of `xsi:schemaLocation` |
| `source-profile-iri`, `target-profile-iri`, `target-profile-label` | CCMM 1.1.0 / 2.0.0 | profile rewrite in `conforms_to_standard` |

Example: `java -jar saxon-he.jar -s:record-1.1.xml -xsl:ccmm-1.1.0-to-2.0.0.xslt -o:record-2.0.xml repository-publisher-name="Národní technická knihovna" default-lang=cs`
