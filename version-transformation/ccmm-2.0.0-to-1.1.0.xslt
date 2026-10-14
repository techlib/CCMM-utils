<?xml version="1.0" encoding="UTF-8"?>
<!--
  CCMM 2.0.0 XML  ==>  CCMM 1.1.0 XML

  Input : a <dataset> in namespace https://schema.ccmm.cz/research-data/2.0
          (techlib/CCMM tag v2.0.0, dataset/schema.xsd)
  Output: a <dataset> in namespace https://schema.ccmm.cz/research-data/1.1
          (techlib/CCMM branch 1.1.0, dataset/schema.xsd)

  XSLT 3.0, tested with Saxon-HE 12/13.
  Known losses and the decisions taken are described in
  ccmm-2.0.0-to-1.1.0-known-issues.md next to this file.

  Every place where the transformation had to invent, choose or merge a value
  is marked in the output by an XML comment starting with "ccmm-migration:".
-->
<xsl:stylesheet version="3.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:map="http://www.w3.org/2005/xpath-functions/map"
    xmlns:m="urn:ccmm:migration"
    xmlns:gml="http://www.opengis.net/gml/3.2"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:s="https://schema.ccmm.cz/research-data/2.0"
    xmlns="https://schema.ccmm.cz/research-data/1.1"
    xpath-default-namespace="https://schema.ccmm.cz/research-data/2.0"
    exclude-result-prefixes="xs map m s">

  <xsl:output method="xml" indent="yes" encoding="UTF-8"/>
  <xsl:strip-space elements="s:*"/>

  <!-- ===================================================== parameters -->

  <!-- Which distribution licence becomes the single dataset licence
       (terms_of_use/license) when distributions carry different licences:
       'most-frequent' (ties broken by document order) or 'first'. -->
  <xsl:param name="licence-strategy" as="xs:string" select="'most-frequent'"/>

  <!-- Licence IRI used when no distribution carries a licence (e.g. a record
       with no distributions). Empty = emit a ":unkn" placeholder licence. -->
  <xsl:param name="fallback-licence-iri" as="xs:string" select="''"/>

  <!-- Write the licences / access rights of distributions that differ from the
       chosen dataset-level values into terms_of_use/description. -->
  <xsl:param name="emit-terms-notes" as="xs:boolean" select="true()"/>

  <!-- Value for mandatory 1.1.0 fields that have no source in 2.0.0. -->
  <xsl:param name="placeholder" as="xs:string" select="':unkn'"/>

  <!-- Location of the CCMM 1.1.0 schema, written into xsi:schemaLocation on
       the output root. The unversioned .../research-data/dataset/schema.xsd
       always serves the latest version, so the versioned URL is used. -->
  <xsl:param name="schema-location" as="xs:string"
      select="'https://model.ccmm.cz/research-data/1.1.0/dataset/schema.xsd'"/>

  <!-- Application profile IRIs: a record that declares conformance to CCMM
       2.0.0 is rewritten to declare CCMM 1.1.0. -->
  <xsl:param name="source-profile-iri" as="xs:string" select="'https://model.ccmm.cz/research-data/2.0.0'"/>
  <xsl:param name="target-profile-iri" as="xs:string" select="'https://model.ccmm.cz/research-data/1.1.0'"/>
  <xsl:param name="target-profile-label" as="xs:string" select="'CCMM RD 1.1.0'"/>

  <!-- ===================================================== code lists -->

  <!-- 2.0.0 re-used the DataCite linked-data vocabularies; 1.1.0 used CCMM
       copies of the same code lists. The local names are identical. -->
  <xsl:variable name="codelist-map" as="map(xs:string, xs:string)" select="map{
      'https://w3id.org/tib/datacite/vocab/titleType/'       : 'https://vocabs.ccmm.cz/registry/codelist/AlternateTitle/',
      'https://w3id.org/tib/datacite/vocab/dateType/'        : 'https://vocabs.ccmm.cz/registry/codelist/TimeReference/',
      'https://w3id.org/tib/datacite/vocab/descriptionType/' : 'https://vocabs.ccmm.cz/registry/codelist/DescriptionType/',
      'https://w3id.org/tib/datacite/vocab/relationType/'    : 'https://vocabs.ccmm.cz/registry/codelist/RelationType/'
    }"/>

  <xsl:function name="m:rewrite-codelist" as="xs:string">
    <xsl:param name="iri" as="xs:string"/>
    <xsl:variable name="v" select="normalize-space($iri)"/>
    <xsl:variable name="prefix" select="map:keys($codelist-map)[starts-with($v, .)][1]"/>
    <xsl:sequence select="if (exists($prefix)) then $codelist-map($prefix) || substring-after($v, $prefix) else $v"/>
  </xsl:function>

  <!-- Key used to decide whether two licences are the same licence. -->
  <xsl:function name="m:licence-key" as="xs:string">
    <xsl:param name="lic" as="element()"/>
    <xsl:sequence select="if (normalize-space($lic/iri)) then replace(normalize-space($lic/iri), '/$', '')
                          else 'title:' || string-join(for $t in $lic/title return normalize-space($t), '|')"/>
  </xsl:function>

  <!-- COAR access rights appear as purl.org/coar/access_right/c_xxxx and as
       vocabularies.coar-repositories.org/access_rights/c_xxxx/. Compare by code. -->
  <xsl:function name="m:rights-key" as="xs:string">
    <xsl:param name="r" as="element()?"/>
    <xsl:variable name="v" select="replace(normalize-space($r/iri), '/$', '')"/>
    <xsl:sequence select="if (matches($v, 'coar.*access_rights?/')) then replace($v, '^.*/', 'coar:') else $v"/>
  </xsl:function>

  <xsl:function name="m:describe" as="xs:string">
    <xsl:param name="e" as="element()?"/>
    <xsl:variable name="names" select="($e/title, $e/label)"/>
    <xsl:variable name="name" select="normalize-space(($names[lang('en')], $names)[1])"/>
    <xsl:variable name="iri" select="normalize-space($e/iri)"/>
    <xsl:sequence select="if ($name and $iri) then $name || ' (' || $iri || ')' else if ($name) then $name else if ($iri) then $iri else $placeholder"/>
  </xsl:function>

  <xsl:function name="m:distribution-name" as="xs:string">
    <xsl:param name="d" as="element()"/>
    <xsl:sequence select="'Distribution &quot;' || normalize-space(($d/title, $d/iri, $d/@access_url, string(count($d/../preceding-sibling::distribution) + 1))[1]) || '&quot;'"/>
  </xsl:function>

  <!-- ===================================================== generic rules -->

  <!-- Every CCMM 2.0 element is renamed into the 1.1 namespace unless a
       specific rule below says otherwise. -->
  <xsl:template match="s:*">
    <xsl:element name="{local-name()}" namespace="https://schema.ccmm.cz/research-data/1.1">
      <xsl:apply-templates select="@*, node()"/>
    </xsl:element>
  </xsl:template>

  <xsl:template match="@*">
    <xsl:copy/>
  </xsl:template>

  <!-- xs:anyURI collapses whitespace; lifting.xslt copies text raw. -->
  <xsl:template match="iri/text() | resource_url/text() | funding_program/text()">
    <xsl:value-of select="normalize-space(.)"/>
  </xsl:template>

  <xsl:template match="gml:*">
    <xsl:copy-of select="." copy-namespaces="no"/>
  </xsl:template>

  <xsl:template match="comment() | processing-instruction()"/>

  <!-- ===================================================== dataset -->

  <xsl:template match="/dataset">
    <dataset xsi:schemaLocation="https://schema.ccmm.cz/research-data/1.1 {$schema-location}">
      <xsl:apply-templates select="@xsi:schemaLocation"/>
      <xsl:apply-templates select="iri, metadata_identification, identifier, version, title,
                                   alternate_title, qualified_attribution, publication_year,
                                   time_reference, resource_type, primary_language, other_language"/>
      <xsl:call-template name="terms-of-use"/>
      <xsl:apply-templates select="subject"/>
      <xsl:if test="keyword">
        <xsl:comment> ccmm-migration: each 2.0.0 keyword became a 1.1.0 subject with a title only </xsl:comment>
        <xsl:apply-templates select="keyword"/>
      </xsl:if>
      <xsl:apply-templates select="description, location, funding_reference, related_resource,
                                   distribution, validation_result, generated_by"/>
    </dataset>
  </xsl:template>

  <!-- The CCMM 2.0 pair of the source xsi:schemaLocation is replaced by the
       1.1 namespace and $schema-location; other pairs (e.g. GML) are kept.
       Without a source xsi:schemaLocation the default on <dataset> stays. -->
  <xsl:template match="/dataset/@xsi:schemaLocation">
    <xsl:variable name="tokens" select="tokenize(normalize-space(.), ' ')"/>
    <xsl:attribute name="xsi:schemaLocation" select="string-join((
        'https://schema.ccmm.cz/research-data/1.1', $schema-location,
        for $i in 1 to count($tokens) idiv 2
        return $tokens[2 * $i - 1][. ne 'https://schema.ccmm.cz/research-data/2.0'] ! (., $tokens[2 * $i])), ' ')"/>
  </xsl:template>

  <xsl:template match="/*" priority="-1">
    <xsl:message terminate="yes">Input root must be {{https://schema.ccmm.cz/research-data/2.0}}dataset, found {{<xsl:value-of select="namespace-uri()"/>}}<xsl:value-of select="local-name()"/></xsl:message>
  </xsl:template>

  <!-- ===================================================== attribution -->

  <xsl:template match="qualified_attribution">
    <qualified_relation>
      <xsl:apply-templates select="iri"/>
      <relation>
        <xsl:apply-templates select="attributed_agent/*"/>
      </relation>
      <xsl:apply-templates select="role"/>
    </qualified_relation>
  </xsl:template>

  <!-- ===================================================== metadata record -->

  <xsl:template match="metadata_record/title | metadata_identification/title">
    <xsl:comment> ccmm-migration: dropped metadata record title "<xsl:value-of select="."/>" </xsl:comment>
  </xsl:template>

  <xsl:template match="conforms_to_standard[normalize-space(iri) = $source-profile-iri]">
    <conforms_to_standard>
      <xsl:comment> ccmm-migration: declared profile rewritten from <xsl:value-of select="$source-profile-iri"/> </xsl:comment>
      <iri><xsl:value-of select="$target-profile-iri"/></iri>
      <label xml:lang="en"><xsl:value-of select="$target-profile-label"/></label>
    </conforms_to_standard>
  </xsl:template>

  <!-- 1.1.0 repository has only iri and label. -->
  <xsl:template match="original_repository">
    <original_repository>
      <xsl:apply-templates select="iri, label"/>
      <xsl:if test="description or qualified_attribution or record or dataset">
        <xsl:comment> ccmm-migration: dropped repository <xsl:value-of select="distinct-values((description, qualified_attribution, record, dataset)/local-name())" separator=", "/> (no 1.1.0 counterpart) </xsl:comment>
      </xsl:if>
    </original_repository>
  </xsl:template>

  <!-- ===================================================== identifier scheme -->

  <!-- 1.1.0 has no skos:notation. The 1.1.0 samples carry the acronym as a
       label with xml:lang="", but that fails rdf:langString in the 1.1.0 SHACL. -->
  <xsl:template match="identifier/scheme">
    <scheme>
      <xsl:apply-templates select="iri, label"/>
      <xsl:if test="notation">
        <xsl:comment> ccmm-migration: dropped notation <xsl:value-of select="notation" separator=" | "/> (no 1.1.0 counterpart) </xsl:comment>
      </xsl:if>
    </scheme>
  </xsl:template>

  <!-- ===================================================== code lists -->

  <xsl:template match="alternate_title_type/iri | date_type/iri | description_type/iri | resource_relation_type/iri">
    <iri><xsl:value-of select="m:rewrite-codelist(.)"/></iri>
  </xsl:template>

  <!-- ===================================================== time reference -->

  <!-- 0..n in 2.0.0, 0..1 in 1.1.0: keep the first one. -->
  <xsl:template match="date_information[preceding-sibling::date_information]">
    <xsl:comment> ccmm-migration: dropped additional date_information "<xsl:value-of select="."/>" </xsl:comment>
  </xsl:template>

  <!-- ===================================================== terms of use -->

  <xsl:template name="terms-of-use">
    <xsl:variable name="dists" select="distribution/(distribution_downloadable_file | distribution_data_service)"/>
    <xsl:variable name="licences" select="$dists/licence"/>
    <xsl:variable name="groups" as="map(*)*">
      <xsl:for-each-group select="$licences" group-by="m:licence-key(.)">
        <xsl:sequence select="map{ 'key': current-grouping-key(), 'count': count(current-group()), 'first': current-group()[1] }"/>
      </xsl:for-each-group>
    </xsl:variable>
    <xsl:variable name="chosen" as="map(*)?"
        select="if ($licence-strategy = 'first') then $groups[1] else sort($groups, (), function($g) { - $g?count })[1]"/>
    <xsl:variable name="dataset-rights" select="access_rights"/>

    <terms_of_use>
      <xsl:apply-templates select="access_rights"/>
      <xsl:choose>
        <xsl:when test="exists($chosen)">
          <xsl:if test="count($groups) gt 1">
            <xsl:comment> ccmm-migration: distributions carry <xsl:value-of select="count($groups)"/> different licences; kept "<xsl:value-of select="$chosen?key"/>" (strategy <xsl:value-of select="$licence-strategy"/>) </xsl:comment>
          </xsl:if>
          <xsl:apply-templates select="$chosen?first"/>
        </xsl:when>
        <xsl:when test="normalize-space($fallback-licence-iri)">
          <xsl:comment> ccmm-migration: no distribution licence in the source; used the configured fallback licence </xsl:comment>
          <license><iri><xsl:value-of select="$fallback-licence-iri"/></iri></license>
        </xsl:when>
        <xsl:otherwise>
          <xsl:comment> ccmm-migration: no distribution licence in the source; licence unknown </xsl:comment>
          <license><label xml:lang="en"><xsl:value-of select="$placeholder"/></label></license>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:if test="$emit-terms-notes">
        <xsl:for-each select="$dists[licence and m:licence-key(licence) ne $chosen?key]">
          <description xml:lang="en"><xsl:value-of select="m:distribution-name(.) || ' is licensed under ' || m:describe(licence) || '.'"/></description>
        </xsl:for-each>
        <xsl:for-each select="$dists[rights and m:rights-key(rights) ne m:rights-key($dataset-rights)]">
          <description xml:lang="en"><xsl:value-of select="m:distribution-name(.) || ' has access rights ' || m:describe(rights) || '.'"/></description>
        </xsl:for-each>
        <xsl:for-each select="$dists/access_service[licence]">
          <description xml:lang="en"><xsl:value-of select="'Data service ' || m:describe(.) || ' is licensed under ' || m:describe(licence) || '.'"/></description>
        </xsl:for-each>
      </xsl:if>
    </terms_of_use>
  </xsl:template>

  <xsl:template match="licence">
    <license>
      <xsl:apply-templates select="iri"/>
      <xsl:for-each select="title">
        <label><xsl:apply-templates select="@*, node()"/></label>
      </xsl:for-each>
    </license>
  </xsl:template>

  <!-- ===================================================== subject / keyword -->

  <xsl:template match="subject/label">
    <title><xsl:apply-templates select="@*, node()"/></title>
  </xsl:template>

  <xsl:template match="dataset/keyword">
    <subject>
      <title><xsl:apply-templates select="@*, node()"/></title>
    </subject>
  </xsl:template>

  <!-- ===================================================== location -->

  <xsl:template match="location">
    <location>
      <xsl:apply-templates select="iri, bounding_box, label, geometry, related_object, relation_type"/>
    </location>
  </xsl:template>

  <!-- 2.0.0: bounding_box { iri?, gml { gml:Envelope }?, wkt? }
       1.1.0: bounding_box is itself a gml:EnvelopeType. -->
  <xsl:template match="location/bounding_box">
    <xsl:variable name="env" select="gml/gml:Envelope"/>
    <xsl:choose>
      <xsl:when test="$env">
        <bounding_box>
          <xsl:copy-of select="$env/@*"/>
          <xsl:copy-of select="$env/*" copy-namespaces="no"/>
        </bounding_box>
        <xsl:if test="normalize-space(wkt) or normalize-space(iri)">
          <xsl:comment> ccmm-migration: dropped bounding_box iri / WKT, GML envelope kept </xsl:comment>
        </xsl:if>
      </xsl:when>
      <xsl:otherwise>
        <xsl:comment> ccmm-migration: bounding box without a GML envelope cannot be expressed in 1.1.0; dropped: <xsl:value-of select="normalize-space(string-join((iri, wkt), ' '))"/> </xsl:comment>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="location/label">
    <name><xsl:value-of select="."/></name>
  </xsl:template>

  <!-- 2.0.0 wraps the GML geometry in <gml>; 1.1.0 has the GML element directly. -->
  <xsl:template match="geometry/gml">
    <xsl:copy-of select="*" copy-namespaces="no"/>
  </xsl:template>

  <!-- ===================================================== distributions -->

  <xsl:template match="distribution_downloadable_file">
    <distribution_downloadable_file>
      <xsl:apply-templates select="iri"/>
      <xsl:call-template name="single-title"/>
      <xsl:for-each select="access_url">
        <access_url><iri><xsl:value-of select="."/></iri></access_url>
      </xsl:for-each>
      <xsl:apply-templates select="download_url"/>
      <xsl:for-each select="conforms_to">
        <conforms_to_schema><xsl:apply-templates select="@*, node()"/></conforms_to_schema>
      </xsl:for-each>
      <xsl:apply-templates select="format, media_type, byte_size, checksum"/>
      <xsl:if test="packaging_format or compression_format or description">
        <xsl:comment> ccmm-migration: dropped <xsl:value-of select="distinct-values((packaging_format, compression_format, description)/local-name())" separator=", "/> (no 1.1.0 counterpart) </xsl:comment>
      </xsl:if>
    </distribution_downloadable_file>
  </xsl:template>

  <!-- 1.1.0 has no access URL on a data service distribution. The URL is
       never used as the distribution IRI: the access service and its endpoint
       usually carry the same URL, and in RDF the distribution would merge with
       them into one node. The endpoint keeps the URL in resource_url. -->
  <xsl:template match="distribution_data_service">
    <xsl:variable name="url" select="normalize-space(@access_url)"/>
    <xsl:variable name="endpoints" select="access_service/endpoint_url/(resource_url, iri) ! normalize-space()"/>
    <distribution_data_service>
      <xsl:apply-templates select="iri"/>
      <xsl:call-template name="single-title"/>
      <xsl:choose>
        <xsl:when test="not($url) or $url = $endpoints">
          <xsl:apply-templates select="access_service"/>
        </xsl:when>
        <xsl:when test="access_service">
          <xsl:apply-templates select="access_service[1]">
            <xsl:with-param name="access-url" select="$url"/>
          </xsl:apply-templates>
          <xsl:apply-templates select="access_service[position() gt 1]"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:comment> ccmm-migration: dropped access_url <xsl:value-of select="$url"/> (1.1.0 has no access URL and there is no access_service to hold it as an endpoint) </xsl:comment>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:for-each select="conforms_to">
        <conforms_to_specification><xsl:apply-templates select="@*, node()"/></conforms_to_specification>
      </xsl:for-each>
      <xsl:apply-templates select="documentation, description"/>
    </distribution_data_service>
  </xsl:template>

  <xsl:template match="access_service">
    <xsl:param name="access-url" as="xs:string?"/>
    <access_service>
      <xsl:apply-templates select="@*, node()"/>
      <xsl:if test="$access-url">
        <xsl:comment> ccmm-migration: distribution access_url added as an endpoint (1.1.0 has no access URL here) </xsl:comment>
        <endpoint_url><resource_url><xsl:value-of select="$access-url"/></resource_url></endpoint_url>
      </xsl:if>
    </access_service>
  </xsl:template>

  <!-- title is 1..n in 2.0.0 and 1..1 in 1.1.0 -->
  <xsl:template name="single-title">
    <title><xsl:value-of select="title[1]"/></title>
    <xsl:if test="title[2]">
      <xsl:comment> ccmm-migration: dropped additional titles: <xsl:value-of select="title[position() gt 1]" separator=" | "/> </xsl:comment>
    </xsl:if>
  </xsl:template>

  <!-- the service licence has no place in 1.1.0 (see terms_of_use notes) -->
  <xsl:template match="data_service/licence | access_service/licence"/>

  <!-- ===================================================== provenance -->

  <xsl:template match="generated_by">
    <provenance>
      <xsl:apply-templates select="iri, label"/>
    </provenance>
    <xsl:if test="@*">
      <xsl:comment> ccmm-migration: dropped provenance JSON links: <xsl:value-of select="for $a in @* return local-name($a) || '=' || $a" separator=", "/> </xsl:comment>
    </xsl:if>
  </xsl:template>

</xsl:stylesheet>
