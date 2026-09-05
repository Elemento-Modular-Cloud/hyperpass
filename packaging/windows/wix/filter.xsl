<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0"
    exclude-result-prefixes="xsl wix"
    xmlns:wix="http://wixtoolset.org/schemas/v4/wxs"
    xmlns="http://wixtoolset.org/schemas/v4/wxs">

    <xsl:output method="xml" indent="yes" omit-xml-declaration="yes" />

    <xsl:strip-space elements="*" />

    <xsl:key name="Filterelpd"
        match="wix:Component[wix:File[contains(@Source, 'elpd.exe')]]" use="@Id" />
    <xsl:key name="FilterElp"
        match="wix:Component[wix:File[contains(@Source, 'elp.exe')]]" use="@Id" />
    <xsl:key name="FilterElpGUI"
        match="wix:Component[wix:File[contains(@Source, 'elp.gui.exe')]]" use="@Id" />
    <xsl:key name="FilterElpApi"
        match="wix:Component[wix:File[contains(@Source, 'elp-api.exe')]]" use="@Id" />

    <!-- Copy all elements and their attributes. -->
    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" />
        </xsl:copy>
    </xsl:template>

    <!-- Except for those that match our filters, do nothing. -->
    <xsl:template
        match="*[ self::wix:Component or self::wix:ComponentRef ][ key( 'Filterelpd', @Id ) ]" />
    <xsl:template
        match="*[ self::wix:Component or self::wix:ComponentRef ][ key( 'FilterElp', @Id ) ]" />
    <xsl:template
        match="*[ self::wix:Component or self::wix:ComponentRef ][ key( 'FilterElpGUI', @Id ) ]" />
    <xsl:template
        match="*[ self::wix:Component or self::wix:ComponentRef ][ key( 'FilterElpApi', @Id ) ]" />
</xsl:stylesheet>
