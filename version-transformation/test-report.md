# Test report: CCMM 1.1.0 ⇄ 2.0.0 transformations on `_metadata-samples/xml`

Run on 2026-10-09; data-service fixes (A5, A6) and SHACL validation (section E) on 2026-10-13. Inputs: the 4 samples in `techlib/CCMM` tag `v2.0.0` and the 4 samples with the same names on branch `1.1.0` (`1m3t2-78951`, `ccmm_sample`, `dataset-mini`, `dmq82-ed856`), plus the 2 fixtures in `tests/edge-cases/`.

## What was checked

1. **Schema validity.** Each direction, then the round trip back, validated against `dataset/schema.xsd` of the target version (XSD 1.1, Python `xmlschema`). 1.1.0 outputs were also validated against tag `1.1.0`.
2. **Field-level comparison with the native sample.** The samples exist in both versions, so the converted record can be compared with the one the CCMM team wrote by hand. `tests/leafdiff.py` lists every leaf value that differs.
3. **RDF comparison.** Native samples, converted records and round trips were lifted to RDF with each version's own `dataset/lifting.xslt`, then compared as graphs (`tests/rdfdiff.py`, rdflib isomorphism). This checks meaning rather than XML shape, and checks that the outputs work in the repo's own pipeline.
4. **SHACL validation.** The lifted graphs validated with each version's `shacl.ttl` (`tests/shacl_check.py`, pyshacl, no inference), compared result by result with the native sample of the same name. See section E.

## Results

| Check | Result |
|---|---|
| XSD validity, forward | 10/10 valid |
| XSD validity, round trip | 10/10 valid |
| `lifting.xslt` runs on every output | 20/20 |
| Invalid or empty IRIs in the lifted RDF of the outputs | none (the native 1.1.0 samples have both, see C1 and C2) |
| SHACL conformance | 0/20, but also 0/8 native samples; the transformations add no result beyond the expected ones in E3 |

## A. Problems found in the transformations, now fixed

| # | Problem | Fix |
|---|---|---|
| A1 | IRIs with surrounding whitespace (`<iri>\n  https://…</iri>`, in 1.1.0 `1m3t2-78951`) pass XSD validation but `lifting.xslt` copies them raw: 124 triples with invalid IRIs. | Both XSLTs normalise whitespace in `iri`, `resource_url`, `funding_program`. |
| A2 | An empty `conforms_to_specification/iri` (1.1.0 `ccmm_sample`) was copied, so it lifted to the document's base IRI. | 1.1.0 → 2.0.0 drops a `conforms_to` with an empty IRI and leaves a comment with its label. |
| A3 | The empty `<provenance/>` placeholder of the 1.1.0 samples became an empty `<generated_by/>`. | Dropped when it has no IRI and no label. |
| A4 | Distribution `rights` were missing after the upgrade, while every native 2.0.0 sample repeats the dataset access rights there (12 `dct:rights` triples missing in `1m3t2`). | The dataset access rights are copied to each distribution (parameter `access-rights-to-distributions`, default on). |
| A5 | 2.0.0 → 1.1.0 used the data-service `access_url` as the distribution IRI. In `ccmm_sample` that URL is also the `access_service` IRI and the endpoint `resource_url`, so the lifted RDF merged the distribution and the `dcat:DataService` into one node. | The distribution keeps no IRI (blank node); the URL stays in `endpoint_url/resource_url`, which lifts as a `ccmm:resourceUrl` literal (it is added there when it is not already an endpoint). |
| A6 | 1.1.0 → 2.0.0 kept the 1.1.0 distribution IRI and `endpoint_url/iri`. In 1.1.0 `ccmm_sample` both equal the `access_service` IRI, so the 2.0.0 RDF still merged distribution, service and endpoint (found by SHACL: two titles, plain-string title on the service). | The distribution IRI is dropped when it repeats the service or endpoint URL; `endpoint_url/iri` is copied into `resource_url` and dropped when it repeats the service or distribution IRI. The output now has the shape of the native 2.0.0 sample. |

## B. Remaining differences from the native samples (by design or not fixable)

**1.1.0 → 2.0.0**
- **Placeholders** where 2.0.0 needs data 1.1.0 never had: repository description and publisher (`:unkn` unless parameters are set), repository label (= IRI), `dataset-mini` `date_updated` (conversion date, because the 1.1.0 record has no date). The native 2.0.0 samples have real values here, which shows these must be set per repository.
- **Code-list labels** keep 1.1.0 wording (`Date Collected`, `Translated Title`, `is derived from`) where native 2.0.0 uses DataCite terms (`Collected`, `TranslatedTitle`, `isDerivedFrom`). IRIs are correct. *Potential:* replace English labels of the four DataCite lists with the DataCite term; not done, because the 2.0.0 samples are themselves inconsistent (`IsReferencedBy` vs `isCollectedBy`).
- **`ccmm_sample`**: terms-of-use contact person becomes an extra attribution with the ContactPerson role, and the terms-of-use text an extra description of type Other. Native 2.0.0 simply dropped both.
- **`dataset-mini`**: no description in 1.1.0, so the title is used; the licence has no distribution to live on and becomes a description of type Other. Native 2.0.0 lost the licence entirely.
- **Data service endpoint**: 1.1.0 puts the endpoint in `endpoint_url/iri`, native 2.0.0 in `endpoint_url/resource_url`. The upgrade copies it into `resource_url` (A6).
- **Language labels** from the built-in table are lower-case (`čeština`), native uses `Čeština`.

**2.0.0 → 1.1.0**
- **`dataset-mini`**: 2.0.0 has no distribution, so no licence; the output carries the `:unkn` licence where native 1.1.0 had CC BY 4.0. This is the licence gap from the known-issues file, confirmed on a real sample. Set `fallback-licence-iri` for such records.
- Repository description and publisher, RO-Crate link, extra distribution titles and packaging formats are dropped (comments in the output).
- 2.0.0 identifier-scheme notation is dropped (native 1.1.0 has it as a label with `xml:lang=""`, which fails SHACL, see E2). The upgrade restores it for DOI, ORCID, ROR and IČO. 2.0.0 labels (`TranslatedTitle`, `Collected`) stay.

**Round trips.** On the real samples, 2.0.0 → 1.1.0 → 2.0.0 loses only the repository description and publisher (back as `:unkn`) and the RO-Crate link; distribution `rights` come back in the dataset's COAR IRI form. A bounding box given only as WKT (edge-case fixture) is also lost. 1.1.0 → 2.0.0 → 1.1.0 keeps all data; the terms-of-use contact point and description come back in different places.

## C. Problems in the sample records themselves

| # | Sample | Problem |
|---|---|---|
| C1 | 1.1.0 `1m3t2-78951` | File IRIs contain a newline and indentation; lifted RDF has 124 triples with invalid IRIs. Fixed in the 2.0.0 sample. |
| C2 | 1.1.0 `ccmm_sample` | `conforms_to_specification/iri` is empty, so RDF gets `rdf:about=""`. |
| C3 | 2.0.0 `1m3t2-78951` | FORD subject 10606 appears twice; the second copy is labelled `Mikrobiologie ` (trailing space) / `Biological sciences`, which contradicts the code (10606 = Microbiology). |
| C4 | 2.0.0 `ccmm_sample`, `1m3t2`, `dmq82` | Distribution `rights` use `https://vocabularies.coar-repositories.org/access_rights/c_abf2/`, dataset `access_rights` use `http://purl.org/coar/access_right/c_abf2`. Same concept, two IRIs. |
| C5 | 2.0.0 samples | Czech label of the Data Manager role differs: `Manažer dat` (`ccmm_sample`, `1m3t2`) vs `Správce dat` (`dmq82`). |
| C6 | 2.0.0 samples | Relation-type English labels mix cases: `IsReferencedBy` vs `isCollectedBy`, `isDerivedFrom`, `hasMetadata`. |
| C7 | both `ccmm_sample` | `format` and `media_type` IRIs point to the op.europa.eu web page (`https://op.europa.eu/web/eu-vocabularies/concept/-/resource?uri=…`) instead of the authority IRI (`http://publications.europa.eu/resource/authority/file-type/GPKG`). The ZIP value is under `media_type` but is a file type, not an IANA media type. |
| C8 | 1.1.0 samples | Labels with `xml:lang=""` (allowed in 1.1.0, rejected by the 2.0.0 `xs:assert`). Converted to `notation` for identifier schemes and to `und` elsewhere. |
| C9 | 1.1.0 and 2.0.0 `ccmm_sample` | Not the same record: the first time reference changed from Collected to Created, and the publisher changed from a person to an organization. Fine as samples, but it means the 1.1.0/2.0.0 pair cannot serve as an exact conversion test. |
| C10 | 2.0.0 `ccmm_sample` | `access_service/iri` equals `endpoint_url/resource_url` (`https://gis.cenia.gov.cz/id/service/wms/chmu_ovzdusi`), so the service is named by its endpoint URL. Harmless on its own (the endpoint lifts as a `ccmm:resourceUrl` literal on a blank node), but it is what made A5 collide; any other node given the same URL would merge with the service. Passed through unchanged. |
| C11 | 1.1.0 `ccmm_sample` | Distribution, `access_service` and `endpoint_url` share the IRI `https://gis.cenia.gov.cz/id/service/wms/chmu_ovzdusi`, so the lifted RDF has one node typed as both distribution and `dcat:DataService`, with two `dct:title` (SHACL `maxCount`). The 2.0.0 sample fixed this (blank-node distribution, URL in `resource_url`). |

## D. Potential problems not covered by the samples

- **Code-list mapping** (title, date, description and relation types) is checked only for the values in the samples. A CCMM 1.1.0 value without a DataCite twin would give an IRI that does not resolve. Needs the full lists from vocabs.ccmm.cz.
- **Several licences per dataset** and **several bounding boxes** appear only in the edge-case fixtures, not in real samples.
- **Bounding-box union** assumes all boxes share axis order and CRS (checked via `srsName`); boxes that cross the antimeridian would merge wrongly.
- **Extension elements** (CCMM 1.1.0 advertised extensibility): an unknown element is renamed into the target namespace and will fail validation there. That is a deliberate loud failure.
- **Language guess** for 1.1.0 strings without a language uses `primary_language`; a Czech dataset with English location names gets them tagged `cs`.

## E. SHACL validation

Each graph is lifted with its version's `dataset/lifting.xslt` and validated with that version's `shacl.ttl`. `python3 tests/shacl_check.py <CCMM v2.0.0> <CCMM 1.1.0> [run_tests output]` prints the results per file and the difference from the native sample of the same name.

| Graph (4 real samples) | Shapes | Results | Native samples |
|---|---|---|---|
| 2.0.0 → 1.1.0 | 1.1.0 | 143 | 161 |
| 1.1.0 → 2.0.0 | 2.0.0 | 265 | 273 |
| 2.0.0 → 1.1.0 → 2.0.0 | 2.0.0 | 272 | 273 |
| 1.1.0 → 2.0.0 → 1.1.0 | 1.1.0 | 145 | 161 |

Edge cases: `licence-conflict` 37 (1.1.0) / 86 (round trip), `sparse` 64 (2.0.0) / 30 (round trip).

**E1. The shapes reject every native sample.** Nearly all results come from the shapes or lifting, not the data:
- `sh:class` on a superclass with no `rdfs:subClassOf` in the shapes or vocabularies: `prov:Person`/`org:Organization` vs `foaf:Agent`, `ccmm:Distribution-*` vs `dcat:Distribution`, `time:Instant`/`time:Interval` vs `time:TemporalEntity`, `skos:Concept` vs `rdfs:Class`.
- 2.0.0: `skos:prefLabel` `sh:maxCount 1`, so every label in a second language fails (about 200 of the 273 native results). `sh:uniqueLang` was probably meant.
- 1.1.0: `skos:prefLabel` `sh:minCount 1` on code-list values, but the 1.1.0 lifting writes their labels as `rdfs:label`.
- `rdf:langString` required on strings the XSD allows without a language (file titles, 1.1.0 organization names, labels with `xml:lang=""`).

**E2. The 1.1.0 samples are outdated.** Two problems appear only in the native 1.1.0 samples; the 2.0.0 samples do not have them:
- the merged distribution / data service node (C11), and
- labels with `xml:lang=""` (C8), which fail `rdf:langString` (e.g. `CCMM RD 1.1.0`).
The 1.1.0 samples are therefore no reference for good 1.1.0 data; the 2.0.0 → 1.1.0 transformation does not imitate them in either point.

**E3. Results added by the transformations** (compared with the native sample of the same name):
- 1.1.0 → 2.0.0: none after A6 besides expected effects of added content: code-list labels from the built-in table (cs + en) hit the `prefLabel` `maxCount` (`dataset-mini` +3), and the contact person moved to an attribution adds one `foaf:Agent` class result.
- 2.0.0 → 1.1.0: none. Outputs have fewer results than the native 1.1.0 sample (`dataset-mini` equal), because the outputs do not have the two 1.1.0 sample problems from E2 (identifier-scheme notation is dropped instead of becoming a label with `xml:lang=""`). The remaining results are the shape problems from E1.
- 2.0.0 → 1.1.0 → 2.0.0: no new result; `ccmm_sample` loses one (the RO-Crate link is dropped).
