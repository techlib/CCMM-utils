<?xml version="1.0" encoding="UTF-8"?>
<!--
  CCMM 1.1.0 XML  ==>  CCMM 2.0.0 XML

  Input : a <dataset> in namespace https://schema.ccmm.cz/research-data/1.1
          (techlib/CCMM branch 1.1.0, dataset/schema.xsd)
  Output: a <dataset> in namespace https://schema.ccmm.cz/research-data/2.0
          (techlib/CCMM tag v2.0.0, dataset/schema.xsd)

  XSLT 3.0, tested with Saxon-HE 12/13.
  Known gaps (mainly 2.0.0 properties with no 1.1.0 source) and the decisions
  taken are described in ccmm-1.1.0-to-2.0.0-known-issues.md next to this file.

  Every place where the transformation had to invent, derive or move a value
  is marked in the output by an XML comment starting with "ccmm-migration:".
  Search for that string before publishing a converted record.
-->
<xsl:stylesheet version="3.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:map="http://www.w3.org/2005/xpath-functions/map"
    xmlns:m="urn:ccmm:migration"
    xmlns:gml="http://www.opengis.net/gml/3.2"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:s="https://schema.ccmm.cz/research-data/1.1"
    xmlns="https://schema.ccmm.cz/research-data/2.0"
    xpath-default-namespace="https://schema.ccmm.cz/research-data/1.1"
    exclude-result-prefixes="xs map m s">

  <xsl:output method="xml" indent="yes" encoding="UTF-8"/>
  <xsl:strip-space elements="s:*"/>

  <!-- ===================================================== parameters -->

  <!-- Value for mandatory 2.0.0 fields that have no source in 1.1.0. -->
  <xsl:param name="placeholder" as="xs:string" select="':unkn'"/>

  <!-- Language tag for new language-tagged strings whose 1.1.0 source had no
       language (location names, generated descriptions). Empty = derive from
       primary_language (CES -> cs, ENG -> en, ...), else 'und'. -->
  <xsl:param name="default-lang" as="xs:string" select="''"/>

  <!-- original_repository: description and publisher are mandatory in 2.0.0
       and absent in 1.1.0. A converter normally runs for one repository, so
       set these once per repository. -->
  <xsl:param name="repository-description" as="xs:string" select="''"/>
  <xsl:param name="repository-description-lang" as="xs:string" select="'en'"/>
  <xsl:param name="repository-publisher-name" as="xs:string" select="''"/>
  <xsl:param name="repository-publisher-ror" as="xs:string" select="''"/>

  <!-- metadata_record/date_updated is 1..1 in 2.0.0. Used only when the
       record has neither date_updated nor date_created. Empty = today. -->
  <xsl:param name="fallback-date-updated" as="xs:string" select="''"/>

  <!-- Keep terms_of_use/description as a dataset description of type Other. -->
  <xsl:param name="terms-description-to-description" as="xs:boolean" select="true()"/>

  <!-- Copy the dataset access rights to every distribution (dct:rights), as
       the 2.0.0 samples do. -->
  <xsl:param name="access-rights-to-distributions" as="xs:boolean" select="true()"/>

  <!-- terms_of_use/contact_point becomes a qualified_attribution with this role. -->
  <xsl:param name="contact-role-iri" as="xs:string" select="'https://vocabs.ccmm.cz/registry/codelist/AgentRole/ContactPerson'"/>

  <!-- Location of the CCMM 2.0.0 schema, written into xsi:schemaLocation on
       the output root. The unversioned .../research-data/dataset/schema.xsd
       always serves the latest version, so the versioned URL is used. -->
  <xsl:param name="schema-location" as="xs:string"
      select="'https://model.ccmm.cz/research-data/2.0.0/dataset/schema.xsd'"/>

  <xsl:param name="source-profile-iri" as="xs:string" select="'https://model.ccmm.cz/research-data/1.1.0'"/>
  <xsl:param name="target-profile-iri" as="xs:string" select="'https://model.ccmm.cz/research-data/2.0.0'"/>
  <xsl:param name="target-profile-label" as="xs:string" select="'Czech Core Metadata Model for Research Data 2.0.0'"/>

  <xsl:variable name="ns" select="'https://schema.ccmm.cz/research-data/2.0'"/>
  <xsl:variable name="dc-other-description" select="'https://w3id.org/tib/datacite/vocab/descriptionType/Other'"/>
  <xsl:variable name="ford-scheme" select="'https://vocabs.ccmm.cz/registry/codelist/SubjectCategory/'"/>

  <!-- ===================================================== code lists -->

  <xsl:variable name="codelist-map" as="map(xs:string, xs:string)" select="map{
      'https://vocabs.ccmm.cz/registry/codelist/AlternateTitle/'  : 'https://w3id.org/tib/datacite/vocab/titleType/',
      'https://vocabs.ccmm.cz/registry/codelist/TimeReference/'   : 'https://w3id.org/tib/datacite/vocab/dateType/',
      'https://vocabs.ccmm.cz/registry/codelist/DescriptionType/' : 'https://w3id.org/tib/datacite/vocab/descriptionType/',
      'https://vocabs.ccmm.cz/registry/codelist/RelationType/'    : 'https://w3id.org/tib/datacite/vocab/relationType/'
    }"/>

  <xsl:function name="m:rewrite-codelist" as="xs:string">
    <xsl:param name="iri" as="xs:string"/>
    <xsl:variable name="v" select="normalize-space($iri)"/>
    <xsl:variable name="prefix" select="map:keys($codelist-map)[starts-with($v, .)][1]"/>
    <xsl:sequence select="if (exists($prefix)) then $codelist-map($prefix) || substring-after($v, $prefix) else $v"/>
  </xsl:function>

  <!-- Labels for code-list values that 2.0.0 requires (label 1..n) when the
       1.1.0 record has none. Key = IRI without trailing slash. -->
  <xsl:variable name="known-labels" as="map(xs:string, map(xs:string, xs:string))" select="map{
      'http://purl.org/coar/access_right/c_abf2' : map{'en':'open access',          'cs':'otevřený přístup'},
      'http://purl.org/coar/access_right/c_f1cf' : map{'en':'embargoed access',     'cs':'odložené zpřístupnění'},
      'http://purl.org/coar/access_right/c_16ec' : map{'en':'restricted access',    'cs':'omezený přístup'},
      'http://purl.org/coar/access_right/c_14cb' : map{'en':'metadata only access', 'cs':'přístup pouze k metadatům'},
      'http://publications.europa.eu/resource/authority/language/CES' : map{'en':'Czech',   'cs':'čeština'},
      'http://publications.europa.eu/resource/authority/language/ENG' : map{'en':'English', 'cs':'angličtina'},
      'http://publications.europa.eu/resource/authority/language/SLK' : map{'en':'Slovak',  'cs':'slovenština'},
      'http://publications.europa.eu/resource/authority/language/DEU' : map{'en':'German',  'cs':'němčina'},
      'http://publications.europa.eu/resource/authority/language/POL' : map{'en':'Polish',  'cs':'polština'},
      'http://publications.europa.eu/resource/authority/language/FRA' : map{'en':'French',  'cs':'francouzština'},
      'https://vocabs.ccmm.cz/registry/codelist/AgentRole/Creator'                 : map{'en':'Creator',        'cs':'Autor'},
      'https://vocabs.ccmm.cz/registry/codelist/AgentRole/Publisher'               : map{'en':'Publisher',      'cs':'Vydavatel'},
      'https://vocabs.ccmm.cz/registry/codelist/AgentRole/Contributor/DataManager' : map{'en':'Data Manager',   'cs':'Správce dat'},
      'https://vocabs.ccmm.cz/registry/codelist/AgentRole/ContactPerson'           : map{'en':'Contact Person', 'cs':'Kontaktní osoba'},
      'http://purl.org/coar/resource_type/c_ddb1' : map{'en':'dataset',  'cs':'datová sada'},
      'http://purl.org/coar/resource_type/c_18cf' : map{'en':'text',     'cs':'text'},
      'http://purl.org/coar/resource_type/c_5ce6' : map{'en':'software', 'cs':'software'},
      'http://purl.org/coar/resource_type/c_c513' : map{'en':'image',    'cs':'obrázek'},
      'http://purl.org/coar/resource_type/c_6501' : map{'en':'journal article', 'cs':'článek v časopise'}
    }"/>

  <xsl:variable name="known-schemes" as="map(xs:string, map(xs:string, xs:string))" select="map{
      'https://doi.org/'   : map{'label':'Digital Object Identifier',        'notation':'DOI'},
      'https://orcid.org/' : map{'label':'Open Research and Contributor ID', 'notation':'ORCID'},
      'https://ror.org/'   : map{'label':'Research Organization Registry',   'notation':'ROR'},
      'https://www.wikidata.org/entity/Q42302581' : map{'label':'Identification Number (IČO)', 'notation':'IČO'}
    }"/>

  <!-- subject IRIs from which the subject scheme can be inferred -->
  <xsl:variable name="subject-scheme-by-prefix" as="map(xs:string, map(xs:string, xs:string))" select="map{
      'https://vocabs.ccmm.cz/registry/codelist/SubjectCategory/' : map{'iri':'https://vocabs.ccmm.cz/registry/codelist/SubjectCategory/', 'label':'OECD FORD Subject Category (Frascati)'},
      'http://inspire.ec.europa.eu/theme/'  : map{'iri':'https://inspire.ec.europa.eu/theme/', 'label':'INSPIRE theme register'},
      'https://inspire.ec.europa.eu/theme/' : map{'iri':'https://inspire.ec.europa.eu/theme/', 'label':'INSPIRE theme register'}
    }"/>

  <xsl:variable name="lang-by-code" as="map(xs:string, xs:string)"
      select="map{'CES':'cs', 'ENG':'en', 'SLK':'sk', 'DEU':'de', 'POL':'pl', 'FRA':'fr', 'SPA':'es', 'ITA':'it'}"/>

  <xsl:variable name="lang" as="xs:string" select="
      if (normalize-space($default-lang)) then $default-lang
      else ($lang-by-code(replace(normalize-space((/dataset/primary_language/iri)[1]), '^.*/', '')), 'und')[1]"/>

  <xsl:function name="m:local-name-of-iri" as="xs:string">
    <xsl:param name="iri" as="xs:string"/>
    <xsl:sequence select="replace(replace(normalize-space($iri), '[/#]+$', ''), '^.*[/#]', '')"/>
  </xsl:function>

  <!-- ===================================================== generic rules -->

  <xsl:template match="s:*">
    <xsl:element name="{local-name()}" namespace="{$ns}">
      <xsl:apply-templates select="@*, node()"/>
    </xsl:element>
  </xsl:template>

  <xsl:template match="@*">
    <xsl:copy/>
  </xsl:template>

  <!-- xs:anyURI collapses whitespace when validating, but the text is copied
       raw by lifting.xslt and would produce invalid IRIs ("\n  https://..."). -->
  <xsl:template match="iri/text() | resource_url/text() | funding_program/text()">
    <xsl:value-of select="normalize-space(.)"/>
  </xsl:template>

  <!-- 1.1.0 allowed xml:lang="" ; 2.0.0 asserts a non-empty language tag. -->
  <xsl:template match="@xml:lang[not(normalize-space())]">
    <xsl:attribute name="xml:lang" select="'und'"/>
  </xsl:template>

  <xsl:template match="gml:*">
    <xsl:copy-of select="." copy-namespaces="no"/>
  </xsl:template>

  <xsl:template match="comment() | processing-instruction()"/>

  <xsl:template name="placeholder-comment">
    <xsl:param name="what" as="xs:string"/>
    <xsl:comment> ccmm-migration: <xsl:value-of select="$what"/> </xsl:comment>
  </xsl:template>

  <!-- ===================================================== code-list values -->

  <!-- Code-list values: 2.0.0 requires at least one label for most of them. -->
  <xsl:template match="role | alternate_title_type | date_type | resource_type | access_rights
                       | description_type | resource_relation_type | relation_type | format | media_type
                       | language | primary_language | other_language">
    <xsl:element name="{local-name()}" namespace="{$ns}">
      <xsl:apply-templates select="iri"/>
      <xsl:call-template name="labels-or-fallback"/>
    </xsl:element>
  </xsl:template>

  <xsl:template name="labels-or-fallback">
    <xsl:param name="labels" select="label"/>
    <xsl:param name="out-name" select="'label'"/>
    <xsl:variable name="iri" select="m:rewrite-codelist(string(iri))"/>
    <xsl:variable name="known" select="$known-labels(replace($iri, '/$', ''))"/>
    <xsl:choose>
      <xsl:when test="$labels">
        <xsl:for-each select="$labels">
          <xsl:element name="{$out-name}" namespace="{$ns}"><xsl:apply-templates select="@*, node()"/></xsl:element>
        </xsl:for-each>
      </xsl:when>
      <xsl:when test="exists($known)">
        <xsl:for-each select="map:keys($known)">
          <xsl:sort select="."/>
          <xsl:element name="{$out-name}" namespace="{$ns}"><xsl:attribute name="xml:lang" select="."/><xsl:value-of select="$known(.)"/></xsl:element>
        </xsl:for-each>
      </xsl:when>
      <xsl:otherwise>
        <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'label missing in 1.1.0, derived from the IRI'"/></xsl:call-template>
        <xsl:element name="{$out-name}" namespace="{$ns}">
          <xsl:attribute name="xml:lang" select="'en'"/>
          <xsl:value-of select="if (normalize-space($iri)) then m:local-name-of-iri($iri) else $placeholder"/>
        </xsl:element>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="alternate_title_type/iri | date_type/iri | description_type/iri | resource_relation_type/iri">
    <iri><xsl:value-of select="m:rewrite-codelist(.)"/></iri>
  </xsl:template>

  <!-- ===================================================== dataset -->

  <xsl:template match="/dataset">
    <dataset xsi:schemaLocation="https://schema.ccmm.cz/research-data/2.0 {$schema-location}">
      <xsl:apply-templates select="@xsi:schemaLocation"/>
      <xsl:apply-templates select="iri, metadata_identification, identifier, version, title,
                                   alternate_title, qualified_relation"/>
      <xsl:for-each select="terms_of_use/contact_point">
        <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'terms_of_use/contact_point moved here with the contact person role'"/></xsl:call-template>
        <qualified_attribution>
          <attributed_agent><xsl:apply-templates select="*"/></attributed_agent>
          <role>
            <iri><xsl:value-of select="$contact-role-iri"/></iri>
            <xsl:variable name="known" select="$known-labels($contact-role-iri)"/>
            <xsl:choose>
              <xsl:when test="exists($known)">
                <xsl:for-each select="map:keys($known)"><xsl:sort select="."/><label xml:lang="{.}"><xsl:value-of select="$known(.)"/></label></xsl:for-each>
              </xsl:when>
              <xsl:otherwise><label xml:lang="en"><xsl:value-of select="m:local-name-of-iri($contact-role-iri)"/></label></xsl:otherwise>
            </xsl:choose>
          </role>
        </qualified_attribution>
      </xsl:for-each>
      <xsl:apply-templates select="publication_year, time_reference, resource_type, primary_language,
                                   other_language, terms_of_use/access_rights"/>
      <xsl:call-template name="subjects-and-keywords"/>
      <xsl:call-template name="descriptions"/>
      <xsl:apply-templates select="location, funding_reference, related_resource, distribution,
                                   validation_result, provenance"/>
    </dataset>
  </xsl:template>

  <!-- The CCMM 1.1 pair of the source xsi:schemaLocation is replaced by the
       2.0 namespace and $schema-location; other pairs (e.g. GML) are kept.
       Without a source xsi:schemaLocation the default on <dataset> stays. -->
  <xsl:template match="/dataset/@xsi:schemaLocation">
    <xsl:variable name="tokens" select="tokenize(normalize-space(.), ' ')"/>
    <xsl:attribute name="xsi:schemaLocation" select="string-join((
        'https://schema.ccmm.cz/research-data/2.0', $schema-location,
        for $i in 1 to count($tokens) idiv 2
        return $tokens[2 * $i - 1][. ne 'https://schema.ccmm.cz/research-data/1.1'] ! (., $tokens[2 * $i])), ' ')"/>
  </xsl:template>

  <xsl:template match="/*" priority="-1">
    <xsl:message terminate="yes">Input root must be {{https://schema.ccmm.cz/research-data/1.1}}dataset, found {{<xsl:value-of select="namespace-uri()"/>}}<xsl:value-of select="local-name()"/></xsl:message>
  </xsl:template>

  <!-- ===================================================== attribution -->

  <xsl:template match="qualified_relation">
    <qualified_attribution>
      <xsl:apply-templates select="iri"/>
      <attributed_agent>
        <xsl:apply-templates select="relation/*"/>
      </attributed_agent>
      <xsl:apply-templates select="role"/>
    </qualified_attribution>
  </xsl:template>

  <!-- ===================================================== metadata record -->

  <xsl:template match="metadata_identification | metadata_record">
    <xsl:element name="{local-name()}" namespace="{$ns}">
      <xsl:apply-templates select="iri, language, qualified_relation"/>
      <xsl:variable name="updated" select="max(date_updated/xs:date(.))"/>
      <xsl:choose>
        <xsl:when test="exists($updated)">
          <xsl:if test="count(date_updated) gt 1">
            <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'date_updated is 1..1 in 2.0.0; kept the latest of ' || string-join(date_updated, ', ')"/></xsl:call-template>
          </xsl:if>
          <date_updated><xsl:value-of select="$updated"/></date_updated>
        </xsl:when>
        <xsl:when test="date_created">
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'no date_updated in 1.1.0; date_created used'"/></xsl:call-template>
          <date_updated><xsl:value-of select="date_created"/></date_updated>
        </xsl:when>
        <xsl:otherwise>
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'no date_updated / date_created in 1.1.0; conversion date used'"/></xsl:call-template>
          <date_updated><xsl:value-of select="if (normalize-space($fallback-date-updated)) then $fallback-date-updated else current-date() => format-date('[Y0001]-[M01]-[D01]')"/></date_updated>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:apply-templates select="date_created, conforms_to_standard, original_repository"/>
    </xsl:element>
  </xsl:template>

  <xsl:template match="conforms_to_standard[normalize-space(iri) = $source-profile-iri]">
    <conforms_to_standard>
      <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'declared profile rewritten from ' || $source-profile-iri"/></xsl:call-template>
      <iri><xsl:value-of select="$target-profile-iri"/></iri>
      <label xml:lang="en"><xsl:value-of select="$target-profile-label"/></label>
    </conforms_to_standard>
  </xsl:template>

  <xsl:template match="original_repository">
    <original_repository>
      <xsl:apply-templates select="iri"/>
      <xsl:choose>
        <xsl:when test="label"><xsl:apply-templates select="label"/></xsl:when>
        <xsl:otherwise>
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'repository label missing in 1.1.0; IRI used'"/></xsl:call-template>
          <label xml:lang="en"><xsl:value-of select="(normalize-space(iri)[.], $placeholder)[1]"/></label>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:choose>
        <xsl:when test="normalize-space($repository-description)">
          <description xml:lang="{$repository-description-lang}"><xsl:value-of select="$repository-description"/></description>
        </xsl:when>
        <xsl:otherwise>
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'repository description has no 1.1.0 source (set parameter repository-description)'"/></xsl:call-template>
          <description xml:lang="en"><xsl:value-of select="$placeholder"/></description>
        </xsl:otherwise>
      </xsl:choose>
      <qualified_attribution>
        <xsl:if test="not(normalize-space($repository-publisher-name))">
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'repository publisher has no 1.1.0 source (set parameter repository-publisher-name)'"/></xsl:call-template>
        </xsl:if>
        <attributed_agent>
          <organization>
            <xsl:if test="normalize-space($repository-publisher-ror)">
              <identifier>
                <iri><xsl:value-of select="'https://ror.org/' || replace($repository-publisher-ror, '^https?://ror.org/', '')"/></iri>
                <value><xsl:value-of select="replace($repository-publisher-ror, '^https?://ror.org/', '')"/></value>
                <scheme>
                  <iri>https://ror.org/</iri>
                  <label xml:lang="en">Research Organization Registry</label>
                  <notation>ROR</notation>
                </scheme>
              </identifier>
            </xsl:if>
            <name><xsl:value-of select="(normalize-space($repository-publisher-name)[.], $placeholder)[1]"/></name>
          </organization>
        </attributed_agent>
        <role>
          <iri>https://vocabs.ccmm.cz/registry/codelist/AgentRole/Publisher</iri>
          <label xml:lang="cs">Vydavatel</label>
          <label xml:lang="en">Publisher</label>
        </role>
      </qualified_attribution>
    </original_repository>
  </xsl:template>

  <!-- ===================================================== identifier scheme -->

  <!-- 1.1.0 records carry the scheme acronym as a language-less label;
       2.0.0 has skos:notation for it. -->
  <xsl:template match="identifier/scheme">
    <xsl:variable name="known" select="$known-schemes(normalize-space(iri))"/>
    <xsl:variable name="real-labels" select="label[normalize-space(@xml:lang)]"/>
    <xsl:variable name="notations" select="label[not(normalize-space(@xml:lang))]"/>
    <scheme>
      <xsl:apply-templates select="iri"/>
      <xsl:choose>
        <xsl:when test="$real-labels"><xsl:apply-templates select="$real-labels"/></xsl:when>
        <xsl:when test="exists($known)"><label xml:lang="en"><xsl:value-of select="$known?label"/></label></xsl:when>
      </xsl:choose>
      <xsl:choose>
        <xsl:when test="$notations">
          <xsl:for-each select="$notations"><notation><xsl:value-of select="."/></notation></xsl:for-each>
        </xsl:when>
        <xsl:when test="exists($known)"><notation><xsl:value-of select="$known?notation"/></notation></xsl:when>
      </xsl:choose>
    </scheme>
  </xsl:template>

  <!-- ===================================================== subjects / keywords -->

  <xsl:function name="m:scheme-for" as="map(xs:string, xs:string)?">
    <xsl:param name="subject" as="element()"/>
    <xsl:variable name="iri" select="normalize-space($subject/iri)"/>
    <xsl:sequence select="
        if ($subject/subject_scheme) then map{'iri': normalize-space($subject/subject_scheme/iri)}
        else if ($iri) then (for $p in map:keys($subject-scheme-by-prefix)[starts-with($iri, .)] return $subject-scheme-by-prefix($p))[1]
        else ()"/>
  </xsl:function>

  <xsl:template name="subjects-and-keywords">
    <xsl:variable name="controlled" select="subject[exists(m:scheme-for(.))]"/>
    <xsl:variable name="free" select="subject except $controlled"/>
    <xsl:apply-templates select="$controlled"/>
    <xsl:if test="empty($controlled)">
      <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'2.0.0 requires a subject from a scheme (FORD); none in 1.1.0'"/></xsl:call-template>
      <subject>
        <label xml:lang="en"><xsl:value-of select="$placeholder"/></label>
        <classification_code><xsl:value-of select="$placeholder"/></classification_code>
        <subject_scheme>
          <iri><xsl:value-of select="$ford-scheme"/></iri>
          <label xml:lang="en">OECD FORD Subject Category (Frascati)</label>
        </subject_scheme>
      </subject>
    </xsl:if>
    <xsl:if test="$free">
      <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'1.1.0 subjects without a subject scheme became keywords'"/></xsl:call-template>
    </xsl:if>
    <xsl:for-each select="$free/title">
      <keyword><xsl:apply-templates select="@*, node()"/></keyword>
    </xsl:for-each>
    <xsl:for-each select="$free[normalize-space(iri) or definition]">
      <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'dropped keyword IRI / definition: ' || normalize-space(string-join((iri, definition), ' | '))"/></xsl:call-template>
    </xsl:for-each>
  </xsl:template>

  <xsl:template match="subject">
    <xsl:variable name="scheme" select="m:scheme-for(.)"/>
    <subject>
      <xsl:apply-templates select="iri"/>
      <xsl:for-each select="title"><label><xsl:apply-templates select="@*, node()"/></label></xsl:for-each>
      <xsl:apply-templates select="definition"/>
      <xsl:choose>
        <xsl:when test="normalize-space(classification_code)"><xsl:apply-templates select="classification_code"/></xsl:when>
        <xsl:otherwise>
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'classification_code missing in 1.1.0, derived from the subject IRI'"/></xsl:call-template>
          <classification_code><xsl:value-of select="(m:local-name-of-iri(string(iri))[.], $placeholder)[1]"/></classification_code>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:choose>
        <xsl:when test="subject_scheme">
          <subject_scheme>
            <xsl:apply-templates select="subject_scheme/(iri, label)"/>
          </subject_scheme>
        </xsl:when>
        <xsl:otherwise>
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'subject_scheme missing in 1.1.0, inferred from the subject IRI'"/></xsl:call-template>
          <subject_scheme>
            <iri><xsl:value-of select="$scheme?iri"/></iri>
            <label xml:lang="en"><xsl:value-of select="$scheme?label"/></label>
          </subject_scheme>
        </xsl:otherwise>
      </xsl:choose>
    </subject>
  </xsl:template>

  <!-- ===================================================== descriptions -->

  <xsl:template name="descriptions">
    <xsl:apply-templates select="description"/>
    <xsl:if test="empty(description)">
      <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'description is 1..n in 2.0.0; none in 1.1.0, the dataset title is used'"/></xsl:call-template>
      <description>
        <description_text xml:lang="{$lang}"><xsl:value-of select="title"/></description_text>
      </description>
    </xsl:if>
    <xsl:if test="$terms-description-to-description">
      <xsl:for-each select="terms_of_use/description">
        <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'terms_of_use/description has no 2.0.0 counterpart; kept as a description of type Other'"/></xsl:call-template>
        <description>
          <description_text><xsl:apply-templates select="@*, node()"/></description_text>
          <description_type>
            <iri><xsl:value-of select="$dc-other-description"/></iri>
            <label xml:lang="en">Other</label>
          </description_type>
        </description>
      </xsl:for-each>
    </xsl:if>
    <!-- with no distribution the licence has nowhere to go in 2.0.0 -->
    <xsl:if test="empty(distribution) and terms_of_use/license">
      <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'licence has no place in 2.0.0 without a distribution; kept as a description of type Other'"/></xsl:call-template>
      <xsl:variable name="l" select="terms_of_use/license"/>
      <xsl:variable name="name" select="normalize-space(($l/label[lang('en')], $l/label)[1])"/>
      <description>
        <description_text xml:lang="en"><xsl:value-of select="'Licence: ' || string-join(($name[.], normalize-space($l/iri)[.]), ', ')"/></description_text>
        <description_type>
          <iri><xsl:value-of select="$dc-other-description"/></iri>
          <label xml:lang="en">Other</label>
        </description_type>
      </description>
    </xsl:if>
  </xsl:template>

  <!-- ===================================================== location -->

  <xsl:template match="location">
    <location>
      <xsl:apply-templates select="iri"/>
      <xsl:call-template name="bounding-box"/>
      <xsl:for-each select="name">
        <label xml:lang="{$lang}"><xsl:value-of select="."/></label>
      </xsl:for-each>
      <xsl:apply-templates select="geometry, related_object, relation_type"/>
    </location>
  </xsl:template>

  <!-- 1.1.0: bounding_box 0..n, each a gml:EnvelopeType.
       2.0.0: bounding_box 0..1 { gml { gml:Envelope } }.
       Several boxes in the same CRS are merged into their union. -->
  <xsl:template name="bounding-box">
    <xsl:variable name="boxes" select="bounding_box"/>
    <xsl:if test="$boxes">
      <xsl:variable name="mergeable" select="count($boxes) gt 1
          and count(distinct-values($boxes/string(@srsName))) eq 1
          and (every $b in $boxes satisfies ($b/gml:lowerCorner and $b/gml:upperCorner))"/>
      <bounding_box>
        <gml>
          <gml:Envelope>
            <xsl:copy-of select="$boxes[1]/@*"/>
            <xsl:choose>
              <xsl:when test="$mergeable">
                <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="count($boxes) || ' bounding boxes merged into one (union)'"/></xsl:call-template>
                <xsl:variable name="lows" select="$boxes/gml:lowerCorner ! array{ tokenize(normalize-space(.), ' ') ! xs:double(.) }"/>
                <xsl:variable name="ups"  select="$boxes/gml:upperCorner ! array{ tokenize(normalize-space(.), ' ') ! xs:double(.) }"/>
                <xsl:variable name="dims" select="array:size($lows[1])" xmlns:array="http://www.w3.org/2005/xpath-functions/array"/>
                <gml:lowerCorner><xsl:value-of select="for $i in 1 to $dims return min($lows ! .($i))"/></gml:lowerCorner>
                <gml:upperCorner><xsl:value-of select="for $i in 1 to $dims return max($ups ! .($i))"/></gml:upperCorner>
              </xsl:when>
              <xsl:otherwise>
                <xsl:if test="count($boxes) gt 1">
                  <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'2.0.0 allows one bounding box; kept the first of ' || count($boxes)"/></xsl:call-template>
                </xsl:if>
                <xsl:copy-of select="$boxes[1]/*" copy-namespaces="no"/>
              </xsl:otherwise>
            </xsl:choose>
          </gml:Envelope>
        </gml>
      </bounding_box>
    </xsl:if>
  </xsl:template>

  <xsl:template match="geometry">
    <geometry>
      <xsl:apply-templates select="iri, label"/>
      <xsl:for-each select="gml:*">
        <gml><xsl:copy-of select="." copy-namespaces="no"/></gml>
      </xsl:for-each>
      <xsl:apply-templates select="wkt"/>
    </geometry>
  </xsl:template>

  <!-- ===================================================== distributions -->

  <xsl:template name="rights-and-licence">
    <xsl:if test="$access-rights-to-distributions">
      <xsl:for-each select="/dataset/terms_of_use/access_rights">
        <rights>
          <xsl:apply-templates select="iri"/>
          <xsl:call-template name="labels-or-fallback"/>
        </rights>
      </xsl:for-each>
    </xsl:if>
    <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'licence' || (if ($access-rights-to-distributions) then ' and rights' else '') || ' copied from dataset terms_of_use'"/></xsl:call-template>
    <xsl:variable name="l" select="/dataset/terms_of_use/license"/>
    <licence>
      <xsl:apply-templates select="$l/iri"/>
      <xsl:for-each select="$l/label"><title><xsl:apply-templates select="@*, node()"/></title></xsl:for-each>
    </licence>
  </xsl:template>

  <xsl:template match="distribution_downloadable_file">
    <distribution_downloadable_file>
      <xsl:apply-templates select="iri, title"/>
      <xsl:for-each select="access_url">
        <access_url><xsl:value-of select="normalize-space(iri)"/></access_url>
      </xsl:for-each>
      <xsl:if test="access_url/label">
        <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'access_url is a plain IRI in 2.0.0; dropped its labels: ' || string-join(access_url/label, ' | ')"/></xsl:call-template>
      </xsl:if>
      <xsl:apply-templates select="download_url"/>
      <xsl:for-each select="conforms_to_schema">
        <xsl:call-template name="conforms-to"/>
      </xsl:for-each>
      <xsl:apply-templates select="format, media_type, byte_size, checksum"/>
      <xsl:call-template name="rights-and-licence"/>
    </distribution_downloadable_file>
  </xsl:template>

  <xsl:template match="distribution_data_service">
    <xsl:variable name="access-url" select="(access_service/endpoint_url/resource_url, access_service/endpoint_url/iri,
                                             access_service/iri, iri)[normalize-space()][1]"/>
    <distribution_data_service access_url="{if ($access-url) then normalize-space($access-url) else $placeholder}">
      <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'access_url has no 1.1.0 source; taken from ' ||
          (if ($access-url) then local-name($access-url/..) || '/' || local-name($access-url) else 'nothing (placeholder)')"/></xsl:call-template>
      <xsl:choose>
        <xsl:when test="normalize-space(iri) = access_service/(iri, endpoint_url/(iri, resource_url)) ! normalize-space()">
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'distribution IRI dropped, it repeats the access service / endpoint URL: ' || normalize-space(iri)"/></xsl:call-template>
        </xsl:when>
        <xsl:otherwise><xsl:apply-templates select="iri"/></xsl:otherwise>
      </xsl:choose>
      <xsl:apply-templates select="title, access_service"/>
      <xsl:for-each select="conforms_to_specification">
        <xsl:call-template name="conforms-to"/>
      </xsl:for-each>
      <xsl:apply-templates select="documentation"/>
      <xsl:call-template name="rights-and-licence"/>
      <xsl:apply-templates select="description"/>
    </distribution_data_service>
  </xsl:template>

  <!-- An empty IRI is valid xs:anyURI but lifts to the document base IRI. -->
  <xsl:template name="conforms-to">
    <xsl:choose>
      <xsl:when test="normalize-space(iri)">
        <conforms_to><xsl:apply-templates select="iri, label"/></conforms_to>
      </xsl:when>
      <xsl:otherwise>
        <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="local-name() || ' with an empty IRI dropped: ' || string-join(label, ' | ')"/></xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- data_service label is 1..n in 2.0.0 -->
  <xsl:template match="access_service">
    <access_service>
      <xsl:apply-templates select="iri"/>
      <xsl:choose>
        <xsl:when test="label"><xsl:apply-templates select="label"/></xsl:when>
        <xsl:otherwise>
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'data service label missing in 1.1.0'"/></xsl:call-template>
          <label xml:lang="{$lang}"><xsl:value-of select="(normalize-space((endpoint_url/title, ../title)[1])[.], normalize-space(iri), $placeholder)[1]"/></label>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:apply-templates select="endpoint_url"/>
    </access_service>
  </xsl:template>

  <!-- 1.1.0 puts the endpoint URL into endpoint_url/iri, 2.0.0 into
       resource_url (a literal in RDF). The IRI is dropped when it repeats the
       service or distribution IRI, which would merge the nodes in RDF. -->
  <xsl:template match="access_service/endpoint_url">
    <xsl:variable name="iri" select="normalize-space(iri)"/>
    <endpoint_url>
      <xsl:choose>
        <xsl:when test="$iri = (../iri, ../../iri) ! normalize-space()">
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'endpoint IRI dropped, it repeats the access service / distribution IRI; kept as resource_url'"/></xsl:call-template>
        </xsl:when>
        <xsl:otherwise><xsl:apply-templates select="iri"/></xsl:otherwise>
      </xsl:choose>
      <xsl:apply-templates select="identifier, title, alternate_title"/>
      <xsl:choose>
        <xsl:when test="normalize-space(resource_url)"><xsl:apply-templates select="resource_url"/></xsl:when>
        <xsl:when test="$iri">
          <xsl:call-template name="placeholder-comment"><xsl:with-param name="what" select="'resource_url taken from endpoint_url/iri'"/></xsl:call-template>
          <resource_url><xsl:value-of select="$iri"/></resource_url>
        </xsl:when>
      </xsl:choose>
      <xsl:apply-templates select="* except (iri, identifier, title, alternate_title, resource_url)"/>
    </endpoint_url>
  </xsl:template>

  <!-- ===================================================== provenance -->

  <!-- 1.1.0 samples carry an empty <provenance/> placeholder -->
  <xsl:template match="provenance[not(normalize-space(iri) or label)]"/>

  <xsl:template match="provenance">
    <generated_by>
      <xsl:apply-templates select="iri, label"/>
    </generated_by>
  </xsl:template>

</xsl:stylesheet>
