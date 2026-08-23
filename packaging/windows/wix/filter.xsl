<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0"
    exclude-result-prefixes="xsl wix"
    xmlns:wix="http://wixtoolset.org/schemas/v4/wxs"
    xmlns="http://wixtoolset.org/schemas/v4/wxs">

    <xsl:output method="xml" indent="yes" omit-xml-declaration="yes" />

    <xsl:strip-space elements="*" />

    <xsl:key name="FilterHyperpassd"
        match="wix:Component[wix:File[contains(@Source, 'hyperpassd.exe')]]" use="@Id" />
    <xsl:key name="FilterHyperpass"
        match="wix:Component[wix:File[contains(@Source, 'hyperpass.exe')]]" use="@Id" />
    <xsl:key name="FilterHyperpassGUI"
        match="wix:Component[wix:File[contains(@Source, 'hyperpass.gui.exe')]]" use="@Id" />

    <!-- Copy all elements and their attributes. -->
    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" />
        </xsl:copy>
    </xsl:template>

    <!-- Except for those that match our filters, do nothing. -->
    <xsl:template
        match="*[ self::wix:Component or self::wix:ComponentRef ][ key( 'FilterHyperpassd', @Id ) ]" />
    <xsl:template
        match="*[ self::wix:Component or self::wix:ComponentRef ][ key( 'FilterHyperpass', @Id ) ]" />
    <xsl:template
        match="*[ self::wix:Component or self::wix:ComponentRef ][ key( 'FilterHyperpassGUI', @Id ) ]" />
</xsl:stylesheet>
