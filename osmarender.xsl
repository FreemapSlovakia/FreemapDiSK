<?xml version="1.0" encoding="UTF-8"?>
<!--
==============================================================================

Osmarender 6.0.8
    with - fixed mask 
         - new area generation
         - selective bezier hint
         - one node way filtered out
         - filtered out missing multipolygon relation members from areas
         - filtered out missing node ref from ways

==============================================================================

Copyright (C) 2006-2007  Etienne Cherdlu, Jochen Topf, Jozef Vince

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA

==============================================================================
-->
<xsl:stylesheet
  xmlns="http://www.w3.org/2000/svg"
  xmlns:svg="http://www.w3.org/2000/svg"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
  xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
  xmlns:cc="http://web.resource.org/cc/"
  xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:osmxapi='http://www.informationfreeway.org/osmxapi/0.5'
  xmlns:exslt="http://exslt.org/common"
  xmlns:msxsl="urn:schemas-microsoft-com:xslt"
  xmlns:fn="http://www.w3.org/2005/xpath-functions"
  exclude-result-prefixes="exslt msxsl"
  version="1.0" >

    <xsl:output method="xml" omit-xml-declaration="no" indent="yes" encoding="UTF-8"/>

    <!-- This msxsl script extension fools msxsl into interpreting exslt extensions as msxsl ones, so 
       we can write code using exslt extensions even though msxsl only recognises the msxsl extension 
       namespace.  Thanks to David Carlisle for this: http://dpcarlisle.blogspot.com/2007/05/exslt-node-set-function.html -->
    <msxsl:script language="JScript" implements-prefix="exslt">
        this['node-set'] =  function (x) {
        return x;
        }
    </msxsl:script>

    <xsl:param name="osmfile" select="/rules/data/@file"/>
    <xsl:param name="title" select="/rules/@title"/>

    <xsl:param name="scale" select="/rules/@scale"/>
    <xsl:param name="symbolScale" select="/rules/@symbolScale"/>
    <xsl:param name='textAttenuation' select='/rules/@textAttenuation'/>
    <xsl:param name='lineSpacing' select='/rules/@lineSpacing'/>
    <xsl:param name="withOSMLayers" select="/rules/@withOSMLayers"/>
    <xsl:param name="svgBaseProfile" select="/rules/@svgBaseProfile"/>
    <xsl:param name="symbolsDir" select="/rules/@symbolsDir"/>

    <!-- skip generating ways and areas - for freemaps names layer -->
    <xsl:param name="processWays" select="/rules/@processWays"/>

    <!-- Show relations -->
    <xsl:param name="showRelationRoute" select="/rules/@showRelationRoute"/>

    <xsl:param name="meter2pixelFactor" select="/rules/@meter2pixel"/>

    <xsl:param name="minlat"/>
    <xsl:param name="maxlat"/>
    <xsl:param name="minlon"/>
    <xsl:param name="maxlon"/>

    <xsl:key name="nodeById" match="/osm/node" use="@id"/>
    <xsl:key name="wayById" match="/osm/way" use="@id"/>
    <xsl:key name="wayByNode" match="/osm/way" use="nd/@ref"/>
    <xsl:key name="relationByWay" match="/osm/relation" use="member/@ref"/>
    <xsl:key name="relationById" match="/osm/relation" use="@id"/>

    <xsl:variable name="data" select="document($osmfile)"/>

    <!-- Use a web-service (if available) to get the current date -->
    <xsl:variable name="date">2011-01-01</xsl:variable>
    <xsl:variable name="year">2011</xsl:variable>



    <!-- Calculate the size of the bounding box based on the file content -->
    <xsl:variable name="bllat">
        <xsl:for-each select="$data/osm/node/@lat">
            <xsl:sort data-type="number" order="ascending"/>
            <xsl:if test="position()=1">
                <xsl:value-of select="."/>
            </xsl:if>
        </xsl:for-each>
    </xsl:variable>
    <xsl:variable name="bllon">
        <xsl:for-each select="$data/osm/node/@lon">
            <xsl:sort data-type="number" order="ascending"/>
            <xsl:if test="position()=1">
                <xsl:value-of select="."/>
            </xsl:if>
        </xsl:for-each>
    </xsl:variable>
    <xsl:variable name="trlat">
        <xsl:for-each select="$data/osm/node/@lat">
            <xsl:sort data-type="number" order="descending"/>
            <xsl:if test="position()=1">
                <xsl:value-of select="."/>
            </xsl:if>
        </xsl:for-each>
    </xsl:variable>
    <xsl:variable name="trlon">
        <xsl:for-each select="$data/osm/node/@lon">
            <xsl:sort data-type="number" order="descending"/>
            <xsl:if test="position()=1">
                <xsl:value-of select="."/>
            </xsl:if>
        </xsl:for-each>
    </xsl:variable>
    <xsl:variable name="bottomLeftLatitude">
        <xsl:choose>
            <xsl:when test="$minlat">
                <xsl:value-of select="$minlat"/>
            </xsl:when>
            <xsl:when test="/rules/bounds">
                <xsl:value-of select="/rules/bounds/@minlat"/>
            </xsl:when>
            <xsl:when test="$data/osm/bounds">
                <xsl:value-of select="$data/osm/bounds/@minlat"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$bllat"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:variable>
    <xsl:variable name="bottomLeftLongitude">
        <xsl:choose>
            <xsl:when test="$minlon">
                <xsl:value-of select="$minlon"/>
            </xsl:when>
            <xsl:when test="/rules/bounds">
                <xsl:value-of select="/rules/bounds/@minlon"/>
            </xsl:when>
            <xsl:when test="$data/osm/bounds">
                <xsl:value-of select="$data/osm/bounds/@minlon"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$bllon"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:variable>
    <xsl:variable name="topRightLatitude">
        <xsl:choose>
            <xsl:when test="$maxlat">
                <xsl:value-of select="$maxlat"/>
            </xsl:when>
            <xsl:when test="/rules/bounds">
                <xsl:value-of select="/rules/bounds/@maxlat"/>
            </xsl:when>
            <xsl:when test="$data/osm/bounds">
                <xsl:value-of select="$data/osm/bounds/@maxlat"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$trlat"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:variable>
    <xsl:variable name="topRightLongitude">
        <xsl:choose>
            <xsl:when test="$maxlon">
                <xsl:value-of select="$maxlon"/>
            </xsl:when>
            <xsl:when test="/rules/bounds">
                <xsl:value-of select="/rules/bounds/@maxlon"/>
            </xsl:when>
            <xsl:when test="$data/osm/bounds">
                <xsl:value-of select="$data/osm/bounds/@maxlon"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$trlon"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:variable>

    <xsl:variable name="dataWidth" select="(number($topRightLongitude)-number($bottomLeftLongitude))*$scale"/>
    <xsl:variable name="dataHeight" select="(number($topRightLatitude)-number($bottomLeftLatitude))*$scale"/>

    <xsl:variable name="km" select="($scale)"/>

    <xsl:variable name="documentWidth">
        <xsl:choose>
            <xsl:when test="$dataWidth &gt; (number(/rules/@minimumMapWidth) * $km)">
                <xsl:value-of select="$dataWidth"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="number(/rules/@minimumMapWidth) * $km"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:variable>

    <xsl:variable name="documentHeight">
        <xsl:choose>
            <xsl:when test="$dataHeight &gt; (number(/rules/@minimumMapHeight) * $km)">
                <xsl:value-of select="$dataHeight"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="number(/rules/@minimumMapHeight) * $km"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:variable>

    <xsl:variable name="width" select="($documentWidth + $dataWidth) div 2"/>
    <xsl:variable name="height" select="($documentHeight + $dataHeight) div 2"/>


    <!-- Main template -->
    <xsl:template match="/rules">
        <!-- Include an external css stylesheet if one was specified in the rules file -->
        <xsl:if test="@xml-stylesheet">
            <xsl:processing-instruction name="xml-stylesheet">
                href="<xsl:value-of select="@xml-stylesheet"/>" type="text/css"
            </xsl:processing-instruction>
        </xsl:if>

        <xsl:variable name="svgWidth" select="$documentWidth"/>
        <xsl:variable name="svgHeight" select="$documentHeight"/>

        <svg id="main"
		  version="1.1"
		  baseProfile="{$svgBaseProfile}"
		  width="{$svgWidth}px"
		  height="{$svgHeight}px"
		  preserveAspectRatio="none"
          viewBox="0 0 {$svgWidth} {$svgHeight}">
            <xsl:if test="/rules/@interactive='yes'">
                <xsl:attribute name="onscroll">fnOnScroll(evt)</xsl:attribute>
                <xsl:attribute name="onzoom">fnOnZoom(evt)</xsl:attribute>
                <xsl:attribute name="onload">fnOnLoad(evt)</xsl:attribute>
                <xsl:attribute name="onmousedown">fnOnMouseDown(evt)</xsl:attribute>
                <xsl:attribute name="onmousemove">fnOnMouseMove(evt)</xsl:attribute>
                <xsl:attribute name="onmouseup">fnOnMouseUp(evt)</xsl:attribute>
            </xsl:if>
            <!-- required for some of the filters working with backgroud images -->
            <xsl:if test="/rules/@withFilters='yes'">
                <xsl:attribute name="enable-background">new</xsl:attribute>
            </xsl:if>

            <xsl:call-template name="metadata"/>

            <defs id="defs-rulefile">
                <!-- Get any <defs> and styles from the rules file -->
                <xsl:copy-of select="defs/*"/>
            </defs>
            <!-- Symbols -->

            <xsl:if test="$symbolsDir != ''">
                <!-- Get all symbols mentioned in the rules file from the symbolsDir -->
                <defs id="defs-symbols">
                    <xsl:for-each select="/rules//symbol/@ref">
                        <xsl:copy-of select="document(concat($symbolsDir,'/', ., '.svg'))/svg:svg/svg:defs/svg:symbol"/>
                    </xsl:for-each>
                </defs>
            </xsl:if>

            <defs id="defs-included">
                <!-- Included defs -->
                <xsl:for-each select="//include">
                    <xsl:copy-of select="document(@ref)/svg:svg/*"/>
                </xsl:for-each>
            </defs>

            <!-- Pre-generate named path definitions for all ways -->
            <xsl:if test="$processWays='yes'">
                <xsl:variable name="allWays" select="$data/osm/way"/>
                <defs id="defs-ways">
                    <xsl:for-each select="$allWays">
                        <xsl:call-template name="generateWayPaths"/>
                    </xsl:for-each>
                </defs>
            </xsl:if>

            <!-- Clipping rectangle for map -->
            <clipPath id="map-clipping">
                <rect id="map-clipping-rect" x="0px" y="0px" height="{$documentHeight}px" width="{$documentWidth}px"/>
            </clipPath>

            <g id="map" clip-path="url(#map-clipping)" inkscape:groupmode="layer" inkscape:label="Map" transform="translate(0,0)">
                <!-- Draw a nice background layer -->
                <rect id="background" x="0px" y="0px" height="{$documentHeight}px" width="{$documentWidth}px" class="map-background"/>

                <!-- Process all the rules drawing all map features -->
                <xsl:call-template name="processRules"/>
            </g>
        </svg>

    </xsl:template>

    <!-- Path Fragment Drawing -->
    <xsl:template name="drawPath">
        <xsl:param name='instruction' />
        <xsl:param name='pathId'/>
        <xsl:param name='pathPrefix'/>
        <xsl:param name='extraClasses'/>
        <xsl:param name='extraStyles'/>
        <xsl:variable name="maskRef">
            <xsl:if test="$instruction/@mask-class != ''">
                <xsl:call-template name="replace-string">
                    <xsl:with-param name="text" select="concat('mask_',$instruction/@mask-class,'_',$pathId)"/>
                    <xsl:with-param name="replace" >
                        <xsl:text > </xsl:text>
                    </xsl:with-param>
                    <xsl:with-param name="with" >
                        <xsl:text >_</xsl:text>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:if>
        </xsl:variable >
        <xsl:variable name="pathRef" select="concat($pathPrefix,'',$pathId)"/>

        <xsl:call-template name='generateMask'>
            <xsl:with-param name='instruction' select='$instruction'/>
            <xsl:with-param name='pathRef' select='$pathRef'/>
            <xsl:with-param name='maskRef' select='$maskRef'/>
            <xsl:with-param name="maskMode" select="'way'" />
        </xsl:call-template>
        <use xlink:href="#{$pathRef}">
            <!-- Copy all attributes from instruction -->
            <xsl:apply-templates select="$instruction/@*" mode="copyAttributes" />
            <!-- Add in any extra classes -->
            <xsl:attribute name="class">
                <xsl:value-of select='$instruction/@class'/>
                <xsl:text> </xsl:text>
                <xsl:value-of select="$extraClasses"/>
            </xsl:attribute>
            <!-- If there is a mask class then include the mask attribute -->
            <xsl:if test='$instruction/@mask-class'>
                <xsl:attribute name="mask">
                    <xsl:value-of select ="concat('url(#',$maskRef,')')" />
                </xsl:attribute>
            </xsl:if>
            <xsl:call-template name="getSvgAttributesFromOsmTags"/>
            <!-- Add additional style definitions if set -->
            <xsl:if test="string($extraStyles) != ''">
                <xsl:attribute name="style">
                    <xsl:value-of select="$extraStyles"/>
                </xsl:attribute>
            </xsl:if>
        </use>
    </xsl:template >



    <xsl:template name='generateMask'>
        <xsl:param name='instruction' />
        <xsl:param name='pathRef'/>
        <xsl:param name='maskRef'/>
        <xsl:param name='maskMode'/>
        <!-- If the instruction has a mask class -->
        <xsl:if test='$instruction/@mask-class'>
            <xsl:message>
                maskRef: <xsl:value-of select='$maskRef'/>
                pathRef: <xsl:value-of select='$pathRef'/>
            </xsl:message>
            <mask id="{$maskRef}" maskUnits="userSpaceOnUse">
                <!-- Required for Inkscape bug -->
                <xsl:choose>
                    <xsl:when test="$maskMode = 'area'">
                        <use xlink:href="#{$pathRef}" class="{$instruction/@mask-class}" />
                    </xsl:when>
                    <xsl:when test="$maskMode = 'way'">
                        <use xlink:href="#{$pathRef}" class="{$instruction/@mask-class} osmarender-stroke-linecap-round osmarender-mask-black" />
                        <use xlink:href="#{$pathRef}" class="{$instruction/@class} osmarender-mask-white" />
                        <use xlink:href="#{$pathRef}" class="{$instruction/@mask-class} osmarender-stroke-linecap-round osmarender-mask-black" />
                    </xsl:when>
                </xsl:choose>
            </mask>
        </xsl:if>
    </xsl:template >



    <!-- Draw a line for the current <way> element using the formatting of the current <line> instruction -->
    <xsl:template name="drawWay">
        <xsl:param name="instruction"/>
        <xsl:param name="way"/>
        <!-- The current way element if applicable -->
        <xsl:param name="layer"/>

        <xsl:variable name="extraClasses">
            <xsl:if test="$instruction/@suppress-markers-tag != ''">
                <xsl:variable name="suppressMarkersTag" select="$instruction/@suppress-markers-tag" />
                <xsl:variable name="firstNode" select="key('nodeById',$way/nd[1]/@ref)"/>
                <xsl:variable name="firstNodeMarkerGroupConnectionCount"
							  select="count(key('wayByNode',$firstNode/@id)/tag[@k=$suppressMarkersTag and ( @v = 'yes' or @v = 'true' )])" />
                <xsl:variable name="lastNode" select="key('nodeById',$way/nd[last()]/@ref)"/>
                <xsl:variable name="lastNodeMarkerGroupConnectionCount"
							  select="count(key('wayByNode',$lastNode/@id)/tag[@k=$suppressMarkersTag and ( @v = 'yes' or @v = 'true' )])" />

                <xsl:if test="$firstNodeMarkerGroupConnectionCount > 1">osmarender-no-marker-start</xsl:if>
                <xsl:if test="$lastNodeMarkerGroupConnectionCount > 1"> osmarender-no-marker-end</xsl:if>
            </xsl:if>
        </xsl:variable>

        <!-- honor-width feature
           If current instruction has 'honor-width' set to 'yes', make use of the
           way's 'width' tag by adding an extra 'style' attribute to current way
           (setting stroke-width to a new value).      -->
        <xsl:variable name='extraStyles'>
            <xsl:if test="$instruction/@honor-width = 'yes'">
                <!-- Get minimum width, use default of '0.1' if not set -->
                <xsl:variable name='minimumWayWidth'>
                    <xsl:choose>
                        <xsl:when test='$instruction/@minimum-width'>
                            <xsl:value-of select='$instruction/@minimum-width'/>
                        </xsl:when>
                        <xsl:otherwise>0.1</xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                <xsl:variable name='maximumWayWidth'>
                    <xsl:choose>
                        <xsl:when test='$instruction/@maximum-width'>
                            <xsl:value-of select='$instruction/@maximum-width'/>
                        </xsl:when>
                        <xsl:otherwise>100</xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                <xsl:variable name='givenWidth'>
                    <xsl:variable name='width'>
                        <xsl:choose>
                            <xsl:when test="contains($way/tag[@k = 'width']/@v, ' m')">
                                <xsl:value-of select="substring-before($way/tag[@k = 'width']/@v, ' m')" />
                            </xsl:when>
                            <xsl:when test="contains($way/tag[@k = 'width']/@v, 'm')">
                                <xsl:value-of select="substring-before($way/tag[@k = 'width']/@v, 'm')" />
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:value-of select="$way/tag[@k = 'width']/@v"/>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:variable>
                    <xsl:choose>
                        <xsl:when test='$width &lt; $minimumWayWidth'>
                            <xsl:value-of select='$minimumWayWidth'/>
                        </xsl:when>
                        <xsl:when test='$width &gt; $maximumWayWidth'>
                            <xsl:value-of select='$maximumWayWidth'/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:value-of select='$width'/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                <xsl:if test="number($givenWidth) &gt; 0">
                    <!-- Get scaling factor, use default of '1' (no scaling) if not set -->
                    <xsl:variable name='scaleFactor'>
                        <xsl:choose>
                            <xsl:when test="$instruction/@width-scale-factor != ''">
                                <xsl:value-of select='$instruction/@width-scale-factor'/>
                            </xsl:when>
                            <xsl:otherwise>1</xsl:otherwise>
                        </xsl:choose>
                    </xsl:variable>
                    <xsl:variable name='pixelOffset'>
                        <xsl:choose>
                            <xsl:when test="$instruction/@pixel-offset != ''">
                                <xsl:value-of select='$instruction/@pixel-offset'/>
                            </xsl:when>
                            <xsl:otherwise>0</xsl:otherwise>
                        </xsl:choose>
                    </xsl:variable>
                    <!-- Set extraStyles' value -->
                    <xsl:if test="number($givenWidth) &gt; 0">
                        <xsl:choose>
                            <xsl:when test="number($meter2pixelFactor)">
                                <xsl:value-of select="concat('stroke-width:', ($scaleFactor * $givenWidth * $meter2pixelFactor + $pixelOffset), 'px')"/>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:value-of select="concat('stroke-width:', ($scaleFactor * $givenWidth * 0.1375 + $pixelOffset), 'px')"/>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:if>
                </xsl:if>
            </xsl:if>
        </xsl:variable>

        <xsl:if test ="$extraStyles != ''">
            <xsl:message>
                WayId: <xsl:value-of select='$way/@id'/>
                extraStyles: <xsl:value-of select='$extraStyles'/>
            </xsl:message>
        </xsl:if>

        <xsl:choose>
            <!-- !!! Dodi -->
            <xsl:when test="$instruction/@bezier-hint='no'">
                <xsl:call-template name='drawPath'>
                    <xsl:with-param name='pathPrefix' select="'x_way_normal_'" />
                    <xsl:with-param name='pathId' select="$way/@id"/>
                    <xsl:with-param name='instruction' select='$instruction'/>
                    <xsl:with-param name="extraClasses" select='$extraClasses'/>
                    <xsl:with-param name="extraStyles" select='$extraStyles'/>
                </xsl:call-template>
            </xsl:when>

            <xsl:when test="$instruction/@smart-linecap='no'">
                <xsl:call-template name='drawPath'>
                    <xsl:with-param name='pathPrefix' select="'way_normal_'"/>
                    <xsl:with-param name='pathId' select="$way/@id"/>
                    <xsl:with-param name='instruction' select='$instruction'/>
                    <xsl:with-param name="extraClasses" select='$extraClasses'/>
                    <xsl:with-param name="extraStyles" select='$extraStyles'/>
                </xsl:call-template>
            </xsl:when>

            <xsl:otherwise>
                <xsl:call-template name="drawWayWithSmartLinecaps">
                    <xsl:with-param name="instruction" select="$instruction"/>
                    <xsl:with-param name="way" select="$way"/>
                    <xsl:with-param name="layer" select="$layer"/>
                    <xsl:with-param name="extraClasses" select='$extraClasses'/>
                    <xsl:with-param name="extraStyles" select='$extraStyles'/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>


    <xsl:template name="drawWayWithSmartLinecaps">
        <xsl:param name="instruction"/>
        <xsl:param name="way"/>
        <!-- The current way element if applicable -->
        <xsl:param name="layer"/>
        <xsl:param name="extraClasses"/>
        <xsl:param name="extraStyles"/>

        <!-- The first half of the first segment and the last half of the last segment are treated differently from the main
			part of the way path.  The main part is always rendered with a butt line-cap.  Each end fragement is rendered with
			either a round line-cap, if it connects to some other path, or with its default line-cap if it is not connected
			to anything.  That way, cul-de-sacs etc are terminated with round, square or butt as specified in the style for the
			way. -->


        <!-- For the first half segment in the way, count the number of segments that link to the from-node of this segment.
			Also count links where the layer tag is less than the layer of this way, if there are links on a lower layer then
			we can safely draw a butt line-cap because the lower layer will already have a round line-cap. -->

        <!-- Process the first node in the way -->
        <xsl:variable name="firstNode" select='key("nodeById",$way/nd[key("nodeById",@ref)][1]/@ref)'/>

        <!-- Process the last node in the way -->
        <xsl:variable name="lastNode" select='key("nodeById",$way/nd[key("nodeById",@ref)][last()]/@ref)'/>

        <!-- Count the number of ways connecting to the from node. If there is only one (the current way) then draw a default line.  -->
        <xsl:variable name="firstNodeConnectionCount" select="count(key('wayByNode',$firstNode/@id))" />

        <!-- Count the number of ways connecting to the last node. If there is only one (the current way) then draw a default line.  -->
        <xsl:variable name="lastNodeConnectionCount" select="count(key('wayByNode',$lastNode/@id))" />

        <!-- Count the number of connectors at a layer lower than the current layer -->
        <xsl:variable name="firstNodeLowerLayerConnectionCount" select="
			count(key('wayByNode',$firstNode/@id)/tag[@k='layer' and @v &lt; $layer]) +
			count(key('wayByNode',$firstNode/@id)[count(tag[@k='layer'])=0 and $layer &gt; 0]) " />

        <!-- Count the number of connectors at a layer higher than the current layer -->
        <!-- <xsl:variable name="firstNodeUpperLayerConnectionCount" select="
			count(key('wayByNode',$firstNode/@id)/tag[@k='layer' and @v &gt; $layer]) +
			count(key('wayByNode',$firstNode/@id)[count(tag[@k='layer'])=0 and $layer &lt; 0]) " /> -->


        <!-- Count the number of connectors at a layer lower than the current layer -->
        <xsl:variable name="lastNodeLowerLayerConnectionCount" select="
			count(key('wayByNode',$lastNode/@id)/tag[@k='layer' and @v &lt; $layer]) +
			count(key('wayByNode',$lastNode/@id)[count(tag[@k='layer'])=0 and $layer &gt; 0]) " />

        <!-- Count the number of connectors at a layer higher than the current layer -->
        <!-- <xsl:variable name="lastNodeUpperLayerConnectionCount" select="
			count(key('wayByNode',$lastNode/@id)/tag[@k='layer' and @v &gt; $layer]) +
			count(key('wayByNode',$lastNode/@id)[count(tag[@k='layer'])=0 and $layer &lt; 0]) " /> -->

        <xsl:if test='count($way/nd[key("nodeById",@ref)]) &gt; 1'>
            <xsl:choose>
                <xsl:when test="($firstNodeConnectionCount &gt; 1) and
                        ($lastNodeConnectionCount &gt; 1) and
                        ($firstNodeLowerLayerConnectionCount=0) and
                        ($lastNodeLowerLayerConnectionCount=0)">
                    <!-- most common "special case" -  we can safely draw round line ends for core and casing -->
                    <xsl:call-template name='drawPath'>
                        <xsl:with-param name='pathPrefix' select="'way_normal_'" />
                        <xsl:with-param name='pathId' select="$way/@id"/>
                        <xsl:with-param name='instruction' select='$instruction'/>
                        <xsl:with-param name="extraClasses">
                            <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-round
                        </xsl:with-param>
                        <xsl:with-param name="extraStyles"  select='$extraStyles' />
                    </xsl:call-template>
                </xsl:when>

                <xsl:when test="($firstNodeConnectionCount &gt; 1) and
                        ($lastNodeConnectionCount &gt; 1) and
                        ($firstNodeLowerLayerConnectionCount &gt; 0) and
                        ($lastNodeLowerLayerConnectionCount &gt; 0)">
                    <!-- most common "special case - bridges " -  we can safely draw round line ends for cores and butt for casings -->
                    <xsl:choose>
                        <!-- round for cores -->
                        <xsl:when test="$instruction/@smart-linecap='core'">
                            <xsl:call-template name='drawPath'>
                                <xsl:with-param name='pathPrefix' select="'way_normal_'" />
                                <xsl:with-param name='pathId' select="$way/@id"/>
                                <xsl:with-param name='instruction' select='$instruction'/>
                                <xsl:with-param name="extraClasses">
                                    <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-round
                                </xsl:with-param>
                                <xsl:with-param name="extraStyles"  select='$extraStyles' />

                            </xsl:call-template>
                        </xsl:when>
                        <xsl:otherwise >
                            <!-- butt for casings -->
                            <xsl:call-template name='drawPath'>
                                <xsl:with-param name='pathPrefix' select="'way_normal_'" />
                                <xsl:with-param name='pathId' select="$way/@id"/>
                                <xsl:with-param name='instruction' select='$instruction'/>
                                <xsl:with-param name="extraClasses">
                                    <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-butt
                                </xsl:with-param>
                                <xsl:with-param name="extraStyles"  select='$extraStyles' />
                            </xsl:call-template>
                        </xsl:otherwise>
                    </xsl:choose >
                </xsl:when>

                <!-- other less common cases -->
                <xsl:otherwise >
                    <!-- First draw the middle section of the way with round linecaps -->
                    <xsl:call-template name='drawPath'>
                        <xsl:with-param name='pathPrefix' select="'way_mid_'" />
                        <xsl:with-param name='pathId' select="$way/@id"/>
                        <xsl:with-param name='instruction' select='$instruction'/>
                        <xsl:with-param name="extraClasses">
                            <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-round osmarender-no-marker-start osmarender-no-marker-end
                        </xsl:with-param>
                        <xsl:with-param name="extraStyles"  select='$extraStyles' />
                    </xsl:call-template>

                    <xsl:choose>

                        <!-- No connection to node - SMART SQUARE END-->
                        <xsl:when test="$firstNodeConnectionCount=1">
                            <xsl:call-template name='drawPath'>
                                <xsl:with-param name='pathPrefix' select="'way_start_'" />
                                <xsl:with-param name='pathId' select="$way/@id"/>
                                <xsl:with-param name='instruction' select='$instruction'/>
                                <xsl:with-param name="extraClasses" >
                                    <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-square osmarender-no-marker-end
                                </xsl:with-param>
                                <xsl:with-param name="extraStyles"  select='$extraStyles' />
                            </xsl:call-template>
                        </xsl:when>

                        <xsl:when test="$firstNodeLowerLayerConnectionCount>0">
                            <!-- lower layer node/way exists -->
                            <xsl:choose>

                                <!-- smart line caps for cores -->
                                <xsl:when test="$instruction/@smart-linecap='core'">
                                    <xsl:call-template name='drawPath'>
                                        <xsl:with-param name='pathPrefix' select="'way_start_'" />
                                        <xsl:with-param name='pathId' select="$way/@id"/>
                                        <xsl:with-param name='instruction' select='$instruction'/>
                                        <xsl:with-param name="extraClasses">
                                            <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-butt osmarender-no-marker-end
                                        </xsl:with-param>
                                        <xsl:with-param name='extraStyles' select='$extraStyles'/>
                                    </xsl:call-template>
                                </xsl:when>

                                <xsl:otherwise >
                                    <!-- smart line caps for casings -->
                                    <xsl:call-template name='drawPath'>
                                        <xsl:with-param name='pathPrefix' select="'way_start_'" />
                                        <xsl:with-param name='pathId' select="$way/@id"/>
                                        <xsl:with-param name='instruction' select='$instruction'/>
                                        <xsl:with-param name="extraClasses" >
                                            <xsl:value-of select="$extraClasses"/>  osmarender-stroke-linecap-butt osmarender-no-marker-end
                                        </xsl:with-param>
                                        <xsl:with-param name='extraStyles' select='$extraStyles'/>
                                    </xsl:call-template>
                                </xsl:otherwise>
                            </xsl:choose>

                        </xsl:when>

                        <xsl:otherwise>

                            <!-- has node/way on current or on higher layer-->
                            <xsl:call-template name='drawPath'>
                                <xsl:with-param name='pathPrefix' select="'way_start_'" />
                                <xsl:with-param name='pathId' select="$way/@id"/>
                                <xsl:with-param name='instruction' select='$instruction'/>
                                <xsl:with-param name="extraClasses">
                                    <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-round osmarender-no-marker-end
                                </xsl:with-param>
                                <xsl:with-param name='extraStyles' select='$extraStyles'/>
                            </xsl:call-template>
                        </xsl:otherwise>
                    </xsl:choose>

                    <xsl:choose>
                        <!-- No connection to node - SMART SQUARE END-->
                        <xsl:when test="$lastNodeConnectionCount=1">
                            <xsl:call-template name='drawPath'>
                                <xsl:with-param name='pathPrefix' select="'way_end_'" />
                                <xsl:with-param name='pathId' select="$way/@id"/>
                                <xsl:with-param name='instruction' select='$instruction'/>
                                <xsl:with-param name="extraClasses">
                                    <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-square osmarender-no-marker-start
                                </xsl:with-param>
                                <xsl:with-param name='extraStyles' select='$extraStyles'/>
                            </xsl:call-template>
                        </xsl:when>
                        <xsl:when test="$lastNodeLowerLayerConnectionCount>0">
                            <!-- lower layer node/way exists -->

                            <xsl:choose>

                                <xsl:when test="$instruction/@smart-linecap='core'">
                                    <!-- smart line caps for cores -->
                                    <xsl:call-template name='drawPath'>
                                        <xsl:with-param name='pathPrefix' select="'way_end_'" />
                                        <xsl:with-param name='pathId' select="$way/@id"/>
                                        <xsl:with-param name='instruction' select='$instruction'/>
                                        <xsl:with-param name="extraClasses">
                                            <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-round osmarender-no-marker-start
                                        </xsl:with-param>
                                        <xsl:with-param name='extraStyles' select='$extraStyles'/>
                                    </xsl:call-template>
                                </xsl:when>
                                <xsl:otherwise >
                                    <!-- smart line caps for casings -->
                                    <xsl:call-template name='drawPath'>
                                        <xsl:with-param name='pathPrefix' select="'way_end_'" />
                                        <xsl:with-param name='pathId' select="$way/@id"/>
                                        <xsl:with-param name='instruction' select='$instruction'/>
                                        <xsl:with-param name="extraClasses">
                                            <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-butt osmarender-no-marker-start
                                        </xsl:with-param>
                                        <xsl:with-param name='extraStyles' select='$extraStyles'/>
                                    </xsl:call-template>
                                </xsl:otherwise>
                            </xsl:choose>
                        </xsl:when>

                        <xsl:otherwise>
                            <!-- has node/way on current or on higher layer-->
                            <xsl:call-template name='drawPath'>
                                <xsl:with-param name='pathPrefix' select="'way_end_'" />
                                <xsl:with-param name='pathId' select="$way/@id"/>
                                <xsl:with-param name='instruction' select='$instruction'/>
                                <xsl:with-param name="extraClasses">
                                    <xsl:value-of select="$extraClasses"/> osmarender-stroke-linecap-round osmarender-no-marker-start
                                </xsl:with-param>
                                <xsl:with-param name='extraStyles' select='$extraStyles'/>
                            </xsl:call-template>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:otherwise>
            </xsl:choose >
        </xsl:if >
    </xsl:template>


    <!-- Draw a circle for the current <node> element using the formatting of the current <circle> instruction -->
    <xsl:template name="drawCircle">
        <xsl:param name="instruction"/>

        <xsl:variable name="x" select="(@lon*$scale)"/>
        <xsl:variable name="y" select="(@lat*$scale)"/>

        <circle cx="{$x}" cy="{$y}">
            <xsl:apply-templates select="$instruction/@*" mode="copyAttributes"/>
            <!-- Copy all the svg attributes from the <circle> instruction -->
        </circle>
    </xsl:template>


    <!-- Draw a symbol for the current <node> element using the formatting of the current <symbol> instruction -->
    <xsl:template name="drawSymbol">
        <xsl:param name="instruction"/>

        <xsl:variable name="x" select="(@lon*$scale)"/>
        <xsl:variable name="y" select="(@lat*$scale)"/>

        <g transform="translate({$x},{$y}) scale({$symbolScale})">
            <use>
                <xsl:if test="$instruction/@ref">
                    <xsl:attribute name="xlink:href">
                        <xsl:value-of select="concat('#symbol-', $instruction/@ref)"/>
                    </xsl:attribute>
                </xsl:if>
                <xsl:apply-templates select="$instruction/@*" mode="copyAttributes"/>
                <!-- Copy all the attributes from the <symbol> instruction -->
            </use>
        </g>
    </xsl:template>

    <xsl:template name="replace-string">
        <xsl:param name="text"/>
        <xsl:param name="replace"/>
        <xsl:param name="with"/>
        <xsl:choose>
            <xsl:when test="contains($text,$replace)">
                <xsl:value-of select="substring-before($text,$replace)"/>
                <xsl:value-of select="$with"/>
                <xsl:call-template name="replace-string">
                    <xsl:with-param name="text" select="substring-after($text,$replace)"/>
                    <xsl:with-param name="replace" select="$replace"/>
                    <xsl:with-param name="with" select="$with"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$text"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Render the appropriate attribute of the current <node> element using the formatting of the current <text> instruction -->
    <xsl:template name="renderText">
        <xsl:param name="instruction"/>

        <xsl:variable name="xo" select="(@lon*$scale)"/>
        <xsl:variable name="yo" select="(@lat*$scale)"/>
        <xsl:variable name="x" select="round($xo*256) div 256"/>
        <xsl:variable name="y" select="round($yo*256) div 256"/>

        <xsl:variable name="text_orig">
            <xsl:value-of select="$instruction/@text-prefix"/>
            <xsl:value-of select="tag[@k=$instruction/@k]/@v"/>
            <xsl:value-of select="$instruction/@text-postfix"/>
        </xsl:variable>
        <xsl:variable name="text2">
            <xsl:call-template name="replace-string">
                <xsl:with-param name="text" select='$text_orig' />
                <xsl:with-param name="replace" >
                    <xsl:text > nad </xsl:text>
                </xsl:with-param>
                <xsl:with-param name="with"  >
                    <xsl:text > nad_</xsl:text>
                </xsl:with-param>
            </xsl:call-template>
        </xsl:variable>
        <xsl:variable name="text3">
            <xsl:call-template name="replace-string">
                <xsl:with-param name="text" select='$text2' />
                <xsl:with-param name="replace">
                    <xsl:text > pod </xsl:text>
                </xsl:with-param>
                <xsl:with-param name="with" >
                    <xsl:text > pod_</xsl:text>
                </xsl:with-param>
            </xsl:call-template >
        </xsl:variable>

        <xsl:variable name="text4">
            <xsl:call-template name="replace-string">
                <xsl:with-param name="text" select='$text3' />
                <xsl:with-param name="replace" >
                    <xsl:text > pri </xsl:text>
                </xsl:with-param>
                <xsl:with-param name="with">
                    <xsl:text > pri_</xsl:text>
                </xsl:with-param>
            </xsl:call-template >
        </xsl:variable>

        <xsl:variable name="text5">
            <xsl:call-template name="replace-string">
                <xsl:with-param name="text" select='$text4' />
                <xsl:with-param name="replace" >
                    <xsl:text > na </xsl:text>
                </xsl:with-param>
                <xsl:with-param name="with">
                    <xsl:text > na_</xsl:text>
                </xsl:with-param>
            </xsl:call-template >
        </xsl:variable>

        <xsl:variable name="text">
            <xsl:call-template name="replace-string">
                <xsl:with-param name="text" select='$text5' />
                <xsl:with-param name="replace" >
                    <xsl:text > - </xsl:text>
                </xsl:with-param>
                <xsl:with-param name="with">
                    <xsl:text > -_</xsl:text>
                </xsl:with-param>
            </xsl:call-template >
        </xsl:variable>

        <xsl:variable name="wordCount" select="1 + string-length($text) - string-length(translate($text,' ',''))"/>
        <xsl:variable name='clineSpacing'>
            <xsl:choose>
                <xsl:when test='$instruction/@x-line-spacing'>
                    <xsl:value-of select='$instruction/@x-line-spacing'/>
                </xsl:when>
                <xsl:when test='number($lineSpacing)'>
                    <xsl:value-of select='$lineSpacing'/>
                </xsl:when>
                <xsl:otherwise>0</xsl:otherwise>
            </xsl:choose>
        </xsl:variable>

        <xsl:choose>
            <xsl:when test='$wordCount > 0 and $clineSpacing > 0'>
                <!-- ked nie je nastavena hodnota line spacing... potom radsej nechat text v jednom riadku-->
                <xsl:variable name='sy'>
                    <xsl:choose>
                        <xsl:when test='$instruction/@x-text-block-anchor = "top"'>
                            <xsl:value-of select ="$y - (($wordCount - 1 ) * $clineSpacing) "/>
                        </xsl:when>
                        <xsl:when test='$instruction/@x-text-block-anchor = "bottom"'>
                            <xsl:value-of select ="$y"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:value-of select ="$y - ((($wordCount - 1 ) * $clineSpacing) div 2)"/>
                        </xsl:otherwise>
                    </xsl:choose >
                </xsl:variable >
                <xsl:call-template name ='renderTextLines'>
                    <xsl:with-param name="instruction" select ="$instruction"/>
                    <xsl:with-param name='text' select ="$text"/>
                    <xsl:with-param name='wordCount' select ="$wordCount"/>
                    <xsl:with-param name='lineSpacing' select ="$clineSpacing"/>
                    <xsl:with-param name='x' select ="$x"/>
                    <xsl:with-param name='y' select ="$sy"/>
                </xsl:call-template>
            </xsl:when >
            <xsl:otherwise >
                <text>
                    <xsl:apply-templates select="$instruction/@*" mode="copyAttributes"/>
                    <xsl:attribute name="x">
                        <xsl:value-of select="$x"/>
                    </xsl:attribute>
                    <xsl:attribute name="y">
                        <xsl:value-of select="$y"/>
                    </xsl:attribute>
                    <xsl:call-template name="getSvgAttributesFromOsmTags"/>
                    <xsl:value-of select="$text_orig"/>
                </text>
            </xsl:otherwise>
        </xsl:choose >
    </xsl:template>

    <xsl:template name="renderTextPathLabels">
        <xsl:param name="instruction"/>
        <xsl:param name="pathId"/>
        <xsl:param name='text'/>
        <xsl:param name='labelNo'/>
        <xsl:param name='offsetStep'/>

        <xsl:choose >
            <xsl:when test ='$labelNo &gt; 1 '>
                <xsl:call-template name='renderTextPathLabels'>
                    <xsl:with-param name="instruction" select ="$instruction"/>
                    <xsl:with-param name="pathId" select ="$pathId"/>
                    <xsl:with-param name='text' select ="$text"/>
                    <xsl:with-param name='labelNo' select ="$labelNo - 1"/>
                    <xsl:with-param name='offsetStep' select ="$offsetStep"/>
                </xsl:call-template>
            </xsl:when>
        </xsl:choose>
        <text>
            <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-text"/>
            <textPath xlink:href="#{$pathId}">
                <xsl:attribute name='startOffset'>
                    <xsl:value-of select ='($labelNo - 0.5) * $offsetStep'/>%
                </xsl:attribute>
                <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-textPath"/>
                <xsl:call-template name="getSvgAttributesFromOsmTags"/>
                <xsl:value-of select="$text"/>
            </textPath>
        </text>
    </xsl:template>
    <!-- Render the appropriate attribute of the current <way> element using the formatting of the current <textPath> instruction -->
    <xsl:template name="renderTextPath">
        <xsl:param name="instruction"/>
        <xsl:param name="pathId"/>
        <xsl:param name="pathDirection"/>
        <xsl:param name='text'/>
        <xsl:variable name ='alltext' >
            <xsl:value-of select="$instruction/@text-prefix"/>
            <xsl:value-of select="tag[@k=$instruction/@k]/@v"/>
            <xsl:value-of select="$instruction/@text-postfix"/>
        </xsl:variable>

        <xsl:variable name='pathLength'>
            <xsl:call-template name='getPathLength'>
                <xsl:with-param name='nodes' select='nd'/>
                <xsl:with-param name='pathId' select='$pathId'/>
            </xsl:call-template>
        </xsl:variable>

        <xsl:variable name='pathLengthMultiplier'>
            <!-- This factor is used to adjust the path-length for comparison with text along a path to determine whether it will fit. -->
            <xsl:choose>
                <xsl:when test='$instruction/@textAttenuation'>
                    <xsl:value-of select='$instruction/@textAttenuation'/>
                </xsl:when>
                <xsl:when test='string($textAttenuation)'>
                    <xsl:value-of select='$textAttenuation'/>
                </xsl:when>
                <xsl:otherwise>99999999</xsl:otherwise>
            </xsl:choose>
        </xsl:variable>

        <xsl:variable name='textLength' select='(string-length($alltext)*$pathLengthMultiplier)' />

        <xsl:choose>
            <!-- do we have x-multi-labeling ? -->
            <xsl:when test='$instruction/@x-multi-labeling'>
                <xsl:variable name='noLabels' select='floor(($pathLength) div ($instruction/@x-multi-labeling * (string-length($alltext))))' />
                <xsl:choose>
                    <xsl:when test='$noLabels &gt; 0'>
                        <xsl:variable name='offsetStep' select=' 100 div ($noLabels)' />

                        <xsl:call-template name='renderTextPathLabels'>
                            <xsl:with-param name="instruction" select ="$instruction"/>
                            <xsl:with-param name="pathId" select ="$pathId"/>
                            <xsl:with-param name='text' select ="$alltext"/>
                            <xsl:with-param name='labelNo' select ="$noLabels"/>
                            <xsl:with-param name='offsetStep' select ="$offsetStep"/>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:otherwise >
                        <xsl:choose>
                            <xsl:when test='($pathLength) &gt; ($textLength)'>
                                <text>
                                    <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-text"/>
                                    <textPath xlink:href="#{$pathId}" startOffset="50%">
                                        <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-textPath"/>
                                        <xsl:call-template name="getSvgAttributesFromOsmTags"/>
                                        <xsl:value-of select="$alltext"/>
                                    </textPath>
                                </text>
                            </xsl:when>
                        </xsl:choose>
                    </xsl:otherwise>
                </xsl:choose >
            </xsl:when >
            <!-- do we have x-label-scaling=no ? -->
            <xsl:when test="$instruction/@x-label-scaling='no'">
                <xsl:choose>
                    <xsl:when test='($pathLength) &gt; ($textLength)'>
                        <text>
                            <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-text"/>
                            <textPath xlink:href="#{$pathId}">
                                <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-textPath"/>
                                <xsl:call-template name="getSvgAttributesFromOsmTags"/>
                                <xsl:value-of select="$alltext"/>
                            </textPath>
                        </text>
                    </xsl:when>
                    <xsl:otherwise />
                    <!-- Otherwise don't render the text -->
                </xsl:choose>
            </xsl:when >
            <xsl:otherwise >
                <xsl:variable name='textLength90' select='($textLength *.9)' />
                <xsl:variable name='textLength80' select='($textLength *.8)' />
                <xsl:variable name='textLength70' select='($textLength *.7)' />
                <xsl:choose>
                    <xsl:when test='($pathLength) &gt; ($textLength)'>
                        <text>
                            <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-text"/>
                            <textPath xlink:href="#{$pathId}">
                                <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-textPath"/>
                                <xsl:call-template name="getSvgAttributesFromOsmTags"/>
                                <xsl:value-of select="$alltext"/>
                            </textPath>
                        </text>
                    </xsl:when>
                    <xsl:when test='($pathLength) &gt; ($textLength90)'>
                        <text>
                            <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-text"/>
                            <textPath xlink:href="#{$pathId}">
                                <xsl:attribute name='font-size'>90%</xsl:attribute>
                                <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-textPath"/>
                                <xsl:call-template name="getSvgAttributesFromOsmTags"/>
                                <xsl:value-of select="$alltext"/>
                            </textPath>
                        </text>
                    </xsl:when>
                    <xsl:when test='($pathLength) &gt; ($textLength80)'>
                        <text>
                            <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-text"/>
                            <textPath xlink:href="#{$pathId}">
                                <xsl:attribute name='font-size'>80%</xsl:attribute>
                                <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-textPath"/>
                                <xsl:call-template name="getSvgAttributesFromOsmTags"/>
                                <xsl:value-of select="$alltext"/>
                            </textPath>
                        </text>
                    </xsl:when>
                    <xsl:when test='($pathLength) &gt; ($textLength70)'>
                        <text>
                            <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-text"/>
                            <textPath xlink:href="#{$pathId}">
                                <xsl:attribute name='font-size'>70%</xsl:attribute>
                                <xsl:apply-templates select="$instruction/@*" mode="renderTextPath-textPath"/>
                                <xsl:call-template name="getSvgAttributesFromOsmTags"/>
                                <xsl:value-of select="$alltext"/>
                            </textPath>
                        </text>
                    </xsl:when>
                    <xsl:otherwise />
                    <!-- Otherwise don't render the text -->
                </xsl:choose>
            </xsl:otherwise>
        </xsl:choose >
    </xsl:template>

    <xsl:template name='getPathLength'>
        <xsl:param name='pathId'/>
        <xsl:param name='nodes'/>
        <xsl:choose >
            <xsl:when test='key("wayById",@id)/tag[@k="lenght"]'>
                <xsl:value-of select ='key("wayById",@id)/tag[@k="lenght"]/@v'/>
            </xsl:when>
            <xsl:otherwise >
                <xsl:call-template name='getPathLengthRecursive'>
                    <xsl:with-param name='nodes' select='$nodes' />
                </xsl:call-template >
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template >

    <xsl:template name='getPathLengthRecursive'>
        <xsl:param name='sumLon' select='number("0")' />
        <!-- initialise sum to zero -->
        <xsl:param name='sumLat' select='number("0")' />
        <!-- initialise sum to zero -->
        <xsl:param name='nodes'/>
        <xsl:choose>
            <xsl:when test='$nodes[1] and $nodes[2]'>
                <xsl:variable name='fromNode' select='key("nodeById",$nodes[1]/@ref)'/>
                <xsl:variable name='toNode' select='key("nodeById",$nodes[2]/@ref)'/>
                <xsl:variable name='lengthLon' select='($fromNode/@lon)-($toNode/@lon)'/>
                <xsl:variable name='absLengthLon'>
                    <xsl:choose>
                        <xsl:when test='$lengthLon &lt; 0'>
                            <xsl:value-of select='$lengthLon * -1'/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:value-of select='$lengthLon'/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                <xsl:variable name='lengthLat' select='($fromNode/@lat)-($toNode/@lat)'/>
                <xsl:variable name='absLengthLat'>
                    <xsl:choose>
                        <xsl:when test='$lengthLat &lt; 0'>
                            <xsl:value-of select='$lengthLat * -1'/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:value-of select='$lengthLat'/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                <xsl:call-template name='getPathLengthRecursive'>
                    <xsl:with-param name='sumLon' select='$sumLon+$absLengthLon'/>
                    <xsl:with-param name='sumLat' select='$sumLat+$absLengthLat'/>
                    <xsl:with-param name='nodes' select='$nodes[position()!=1]'/>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="sqrt">
                    <xsl:with-param name="num" select="((($sumLon)*($sumLon))+(($sumLat)*($sumLat)))" />
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Suppress the following attributes, allow everything else -->
    <xsl:template match="@startOffset|@method|@spacing|@lengthAdjust|@textLength|@k|@x-name-direction|@textAttenuation|@x-multi-labeling" mode="renderTextPath-text" />

    <xsl:template match="@*" mode="renderTextPath-text">
        <xsl:copy/>
    </xsl:template>

    <!-- Allow the following attributes, suppress everything else -->
    <xsl:template match="@startOffset|@method|@spacing|@lengthAdjust|@textLength" mode="renderTextPath-textPath">
        <xsl:copy/>
    </xsl:template>

    <xsl:template match="@*" mode="renderTextPath-textPath" />


    <!-- If there are any tags like <tag k="svg:font-size" v="5"/> then add these as attributes of the svg output -->
    <xsl:template name="getSvgAttributesFromOsmTags">
        <xsl:for-each select="tag[contains(@k,'svg:')]">
            <xsl:attribute name="{substring-after(@k,'svg:')}">
                <xsl:value-of select="@v"/>
            </xsl:attribute>
        </xsl:for-each>
    </xsl:template>


    <xsl:template name="renderArea">
        <xsl:param name="instruction"/>
        <xsl:param name="pathId"/>

        <xsl:variable name='relation' select="key('relationByWay',@pathId)[tag[@k='type' and @v='multipolygon']]"/>
        <xsl:variable name='relation_count' select="count(key('relationByWay',@id)[tag[@k='type' and @v='multipolygon']])"/>
        <!-- DODI: render this area ??? -->
        <xsl:variable name='refarea'>
            <xsl:choose>
                <xsl:when test='$relation_count = 0'>
                    <!-- Handle simple ways, with no parts of multipologons.-->
                    <xsl:text>1</xsl:text>
                </xsl:when>
                <xsl:when test='$relation_count = 1'>
                    <xsl:text>1</xsl:text>
                </xsl:when>
                <xsl:otherwise>
                    <!-- Handle multipolygons.
                         Draw area only once, draw the outer one first if we know which is it, else just draw the first one 
                         NOT FOR NOW -->
                    <xsl:text>0</xsl:text>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:if test="$refarea">

            <xsl:variable name="maskRef">
                <xsl:if test="$instruction/@mask-class != ''">
                    <xsl:call-template name="replace-string">
                        <xsl:with-param name="text" select="concat('mask_',$instruction/@mask-class,'_',$pathId)"/>
                        <xsl:with-param name="replace" >
                            <xsl:text > </xsl:text>
                        </xsl:with-param>
                        <xsl:with-param name="with" >
                            <xsl:text >_</xsl:text>
                        </xsl:with-param>
                    </xsl:call-template>
                </xsl:if>
            </xsl:variable >

            <xsl:variable name="pathRef" >
                <xsl:choose >
                    <xsl:when test="$instruction/@bezier-hint='no'">
                        <xsl:value-of select="concat('x_area_',$pathId)"/>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:value-of select="concat('area_',$pathId)"/>
                    </xsl:otherwise >
                </xsl:choose >
            </xsl:variable>
            <xsl:call-template name='generateMask'>
                <xsl:with-param name='instruction' select='$instruction'/>
                <xsl:with-param name='maskRef' select='$maskRef'/>
                <xsl:with-param name='pathRef' select='$pathRef'/>
                <xsl:with-param name="maskMode" select="'area'" />
            </xsl:call-template>


            <use xlink:href="#{$pathRef}" style="fill-rule:evenodd" >
                <xsl:apply-templates select="$instruction/@*" mode="copyAttributes"/>
                <!-- If there is a mask class then include the mask attribute -->
                <xsl:if test="$instruction/@mask-class != ''">
                    <xsl:attribute name="mask">
                        <xsl:value-of select ="concat('url(#',$maskRef,')')" />
                    </xsl:attribute>
                </xsl:if>
            </use>

        </xsl:if>
    </xsl:template>


    <!-- Templates to process line, circle, text, etc. instructions -->
    <!-- Each template is passed a variable containing the set of elements that need to
         be processed.  The set of elements is already determined by the rules, so
         these templates don't need to know anything about the rules context they are in. -->

    <!-- Process a <line> instruction -->
    <xsl:template match="line">
        <xsl:param name="elements"/>
        <xsl:param name="layer"/>

        <!-- This is the instruction that is currently being processed -->
        <xsl:variable name="instruction" select="."/>

        <!-- For each way -->
        <xsl:if test="$processWays='yes'">
            <xsl:apply-templates select="$elements" mode="line">
                <xsl:with-param name="instruction" select="$instruction"/>
                <xsl:with-param name="layer" select="$layer"/>
            </xsl:apply-templates>
        </xsl:if>
    </xsl:template>


    <!-- Suppress output of any unhandled elements -->
    <xsl:template match="*" mode="line"/>


    <!-- Draw lines for a way  -->
    <xsl:template match="way" mode="line">
        <xsl:param name="instruction"/>
        <xsl:param name="layer"/>

        <!-- The current <way> element -->
        <xsl:variable name="way" select="."/>

        <!-- DODI: !!!WORKAROUND!!! skip one node ways-->
        <xsl:if test="count($way/nd) &gt; 1">
            <xsl:call-template name="drawWay">
                <xsl:with-param name="instruction" select="$instruction"/>
                <xsl:with-param name="way" select="$way"/>
                <xsl:with-param name="layer" select="$layer"/>
            </xsl:call-template>
        </xsl:if >
    </xsl:template>


    <!-- Draw lines for a relation -->
    <xsl:template match="relation" mode="line">
        <xsl:param name="instruction"/>
        <xsl:param name="layer"/>

        <xsl:variable name="relation" select="@id"/>

        <xsl:if test="(tag[@k='type']/@v='route') and ($showRelationRoute!='~|no')">
            <!-- Draw lines for a RelationRoute -->
            <xsl:for-each select="$data/osm/relation[@id=$relation]/member[@type='way']">
                <xsl:variable name="wayid" select="@ref"/>

                <xsl:for-each select="$data/osm/way[@id=$wayid]">
                    <!-- The current <way> element -->
                    <xsl:variable name="way" select="."/>

                    <!-- DODI: !!!WORKAROUND!!! skip one node ways-->
                    <xsl:if test="count($way/nd) &gt; 1">
                        <xsl:call-template name="drawWay">
                            <xsl:with-param name="instruction" select="$instruction"/>
                            <xsl:with-param name="way" select="$way"/>
                            <xsl:with-param name="layer" select="$layer"/>
                        </xsl:call-template>
                    </xsl:if >
                </xsl:for-each >
            </xsl:for-each >
        </xsl:if>

        <!-- Handle other types of Relations if necessary -->

    </xsl:template>
    <!-- Process an <area> instruction -->
    <xsl:template match="area">
        <xsl:param name="elements"/>

        <!-- This is the instruction that is currently being processed -->
        <xsl:variable name="instruction" select="."/>

        <!-- For each way -->

        <xsl:if test="$processWays='yes'">
            <xsl:apply-templates select="$elements" mode="area">
                <xsl:with-param name="instruction" select="$instruction"/>
            </xsl:apply-templates>
        </xsl:if>
    </xsl:template>

    <!-- Discard anything that is not matched by a more specific template -->
    <xsl:template match="*" mode="area"/>


    <!-- Draw area for a <way> -->
    <xsl:template match="way" mode="area">
        <xsl:param name="instruction"/>

        <!-- DODI:  removed because duplicate definition generated if area referenced 2 or more times -->
        <!-- <xsl:call-template name="generateAreaPath"/> -->

        <xsl:call-template name="renderArea">
            <xsl:with-param name="instruction" select="$instruction"/>
            <xsl:with-param name="pathId" select="@id"/>
        </xsl:call-template>
    </xsl:template>


    <!-- Process <circle> instruction -->
    <xsl:template match="circle">
        <xsl:param name="elements"/>
        <xsl:param name="layer"/>

        <!-- This is the instruction that is currently being processed -->
        <xsl:variable name="instruction" select="."/>

        <!-- For each circle -->
        <xsl:apply-templates select="$elements" mode="circle">
            <xsl:with-param name="instruction" select="$instruction"/>
            <xsl:with-param name="layer" select="$layer"/>
            <xsl:with-param name="elements" select="$elements"/>
        </xsl:apply-templates>
    </xsl:template>


    <!-- Suppress output of any unhandled elements -->
    <xsl:template match="*" mode="circle"/>


    <!-- Draw circle for a node -->
    <xsl:template match="node" mode="circle">
        <xsl:param name="instruction"/>
        <xsl:param name="elements"/>

        <xsl:for-each select="$elements[name()='node']">
            <xsl:call-template name="drawCircle">
                <xsl:with-param name="instruction" select="$instruction"/>
            </xsl:call-template>
        </xsl:for-each>

    </xsl:template>


    <!-- Draw circle for a relation -->
    <xsl:template match="relation" mode="circle">
        <xsl:param name="instruction"/>
        <xsl:param name="layer"/>

        <xsl:variable name="relation" select="@id"/>

        <xsl:if test="(tag[@k='type']/@v='route') and ($showRelationRoute!='~|no')">
            <!-- Draw Circles for a RelationRoute Stop -->
            <xsl:for-each select="$data/osm/relation[@id=$relation]/member[@type='node']">
                <xsl:variable name="nodeid" select="@ref"/>

                <xsl:for-each select="$data/osm/node[@id=$nodeid]">
                    <xsl:call-template name="drawCircle">
                        <xsl:with-param name="instruction" select="$instruction"/>
                        <xsl:with-param name="node" select="@id"/>
                    </xsl:call-template>
                </xsl:for-each>
            </xsl:for-each>
        </xsl:if>

        <!-- Handle other types of Relations if necessary -->

    </xsl:template>


    <!-- Process a <symbol> instruction -->
    <xsl:template match="symbol">
        <xsl:param name="elements"/>

        <!-- This is the instruction that is currently being processed -->
        <xsl:variable name="instruction" select="."/>

        <xsl:for-each select="$elements[name()='node']">
            <xsl:call-template name="drawSymbol">
                <xsl:with-param name="instruction" select="$instruction"/>
            </xsl:call-template>
        </xsl:for-each>

    </xsl:template>


    <!-- wayMarker instruction.  Draws a marker on a node that is perpendicular to a way that passes through the node.
       If more than one way passes through the node then the result is a bit unspecified.  -->
    <xsl:template match="wayMarker">
        <xsl:param name="elements"/>

        <!-- This is the instruction that is currently being processed -->
        <xsl:variable name="instruction" select="."/>

        <!-- Process each matched node in turn -->
        <xsl:for-each select="$elements[name()='node']">
            <xsl:variable name='nodeId' select="@id" />

            <xsl:variable name='way' select="key('wayByNode', @id)" />

            <!-- ak vobec najde cestu ktora patri tomu uzlu -->
            <xsl:if test ="$way!=''">
                <xsl:variable name='previousNode' select="key('nodeById', $way/nd[@ref=$nodeId]/preceding-sibling::nd[1]/@ref)" />
                <xsl:variable name='nextNode' select="key('nodeById', $way/nd[@ref=$nodeId]/following-sibling::nd[1]/@ref)" />

                <xsl:variable name='path'>
                    <xsl:choose>
                        <xsl:when test='$previousNode and $nextNode'>
                            <xsl:call-template name="moveToNode">
                                <xsl:with-param name="node" select="$previousNode"/>
                            </xsl:call-template>
                            <xsl:call-template name="lineToNode">
                                <xsl:with-param name="node" select="."/>
                            </xsl:call-template>
                            <xsl:call-template name="lineToNode">
                                <xsl:with-param name="node" select="$nextNode"/>
                            </xsl:call-template>
                        </xsl:when>

                        <xsl:when test='$previousNode'>
                            <xsl:call-template name="moveToNode">
                                <xsl:with-param name="node" select="$previousNode"/>
                            </xsl:call-template>
                            <xsl:call-template name="lineToNode">
                                <xsl:with-param name="node" select="."/>
                            </xsl:call-template>
                            <xsl:call-template name="lineToNode">
                                <xsl:with-param name="node" select="."/>
                            </xsl:call-template>
                        </xsl:when>

                        <xsl:when test='$nextNode'>
                            <xsl:call-template name="moveToNode">
                                <xsl:with-param name="node" select="."/>
                            </xsl:call-template>
                            <xsl:call-template name="lineToNode">
                                <xsl:with-param name="node" select="$nextNode"/>
                            </xsl:call-template>
                            <xsl:call-template name="lineToNode">
                                <xsl:with-param name="node" select="$nextNode"/>
                            </xsl:call-template>
                        </xsl:when>
                    </xsl:choose>
                </xsl:variable>

                <path id="nodePath_{@id}" d="{$path}">
                    <xsl:apply-templates select="$instruction/@*" mode="copyAttributes" />
                </path>
            </xsl:if>

        </xsl:for-each>

    </xsl:template>

    <!-- Process an <areaText> instruction -->
    <xsl:template match="areaText">
        <xsl:param name="elements"/>

        <!-- This is the instruction that is currently being processed -->
        <xsl:variable name="instruction" select="."/>

        <!-- Select all <way> elements that have a key that matches the k attribute of the text instruction -->
        <xsl:apply-templates select="$elements[name()='way'][tag[@k=$instruction/@k]]" mode="areaTextPath">
            <xsl:with-param name="instruction" select="$instruction"/>
        </xsl:apply-templates>
    </xsl:template>


    <xsl:template match="*" mode="areaTextPath"/>


    <xsl:template match="way" mode="areaTextPath">
        <xsl:param name="instruction"/>

        <!-- The current <way> element -->
        <xsl:variable name="way" select="."/>

        <xsl:call-template name="renderAreaText">
            <xsl:with-param name="instruction" select="$instruction"/>
            <xsl:with-param name="pathId" select="concat('way_normal_',@id)"/>
        </xsl:call-template>

    </xsl:template>

    <xsl:template name="renderTextLines">
        <xsl:param name="instruction"/>
        <xsl:param name='text'/>
        <xsl:param name='wordCount'/>
        <xsl:param name='lineSpacing'/>
        <xsl:param name='x'/>
        <xsl:param name='y'/>

        <xsl:variable name ='word'>
            <xsl:choose >
                <xsl:when test ='$wordCount = 1 '>
                    <xsl:value-of  select ="$text" />
                </xsl:when >
                <xsl:otherwise >
                    <xsl:value-of  select ="substring-before($text,' ')" />
                </xsl:otherwise>
            </xsl:choose >
        </xsl:variable >

        <text>
            <xsl:apply-templates select="$instruction/@*" mode="copyAttributes"/>
            <xsl:attribute name="x">
                <xsl:value-of select="$x"/>
            </xsl:attribute>
            <xsl:attribute name="y">
                <xsl:value-of select="$y"/>
            </xsl:attribute>
            <xsl:call-template name="getSvgAttributesFromOsmTags" />
            <xsl:value-of select ="translate($word,'_',' ')"/>
        </text>

        <xsl:choose >
            <xsl:when test ='$wordCount > 0 '>
                <xsl:call-template name='renderTextLines'>
                    <xsl:with-param name="instruction" select ="$instruction"/>
                    <xsl:with-param name='text' select ="substring-after($text,' ')"/>
                    <xsl:with-param name='wordCount' select ="$wordCount - 1"/>
                    <xsl:with-param name='lineSpacing' select ="$lineSpacing"/>
                    <xsl:with-param name='x' select ="$x "/>
                    <xsl:with-param name='y' select ="$y + $lineSpacing"/>
                </xsl:call-template>
            </xsl:when>
        </xsl:choose>
    </xsl:template >


    <xsl:template name="renderAreaText">
        <xsl:param name="instruction"/>

        <xsl:variable name='center'>
            <xsl:call-template name="areaCenter">
                <xsl:with-param name="element" select="." />
            </xsl:call-template>
        </xsl:variable>

        <xsl:variable name="centerLon" select="substring-before($center, ',')" />
        <xsl:variable name="centerLat" select="substring-after($center, ',')" />

        <xsl:variable name="x" select="($centerLon*$scale)"/>
        <xsl:variable name="y" select="($centerLat*$scale)"/>

        <xsl:variable name="text" select="tag[@k=$instruction/@k]/@v"/>
        <xsl:variable name="wordCount" select="1 + string-length($text) - string-length(translate($text,' ',''))"/>
        <xsl:variable name='clineSpacing'>
            <xsl:choose>
                <xsl:when test='$instruction/@x-line-spacing'>
                    <xsl:value-of select='$instruction/@x-line-spacing'/>
                </xsl:when>
                <xsl:when test='number($lineSpacing)'>
                    <xsl:value-of select='$lineSpacing'/>
                </xsl:when>
                <xsl:otherwise>0</xsl:otherwise>
            </xsl:choose>
        </xsl:variable>

        <xsl:choose>
            <xsl:when test='$wordCount > 0 and $clineSpacing > 0'>
                <xsl:variable name='sy'>
                    <xsl:choose>
                        <xsl:when test='$instruction/@x-text-block-anchor = "top"'>
                            <xsl:value-of select ="$y - (($wordCount - 1 ) * $clineSpacing) "/>
                        </xsl:when>
                        <xsl:when test='$instruction/@x-text-block-anchor = "bottom"'>
                            <xsl:value-of select ="$y"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:value-of select ="$y - ((($wordCount - 1 ) * $clineSpacing) div 2)"/>
                        </xsl:otherwise>
                    </xsl:choose >
                </xsl:variable >
                <xsl:call-template name ='renderTextLines'>
                    <xsl:with-param name="instruction" select ="$instruction"/>
                    <xsl:with-param name='text' select ="$text"/>
                    <xsl:with-param name='wordCount' select ="$wordCount"/>
                    <xsl:with-param name='lineSpacing' select ="$clineSpacing"/>
                    <xsl:with-param name='x' select ="$x"/>
                    <xsl:with-param name='y' select ="$sy"/>
                </xsl:call-template>
            </xsl:when >
            <xsl:otherwise >
                <text>
                    <xsl:apply-templates select="$instruction/@*" mode="copyAttributes"/>
                    <xsl:attribute name="x">
                        <xsl:value-of select="$x"/>
                    </xsl:attribute>
                    <xsl:attribute name="y">
                        <xsl:value-of select="$y"/>
                    </xsl:attribute>
                    <xsl:call-template name="getSvgAttributesFromOsmTags"/>
                    <xsl:value-of select="$text"/>
                </text>
            </xsl:otherwise>
        </xsl:choose >

    </xsl:template>

    <!-- Process an <areaSymbol> instruction -->
    <xsl:template match="areaSymbol">
        <xsl:param name="elements"/>

        <!-- This is the instruction that is currently being processed -->
        <xsl:variable name="instruction" select="."/>

        <!-- Select all <way> elements -->
        <xsl:apply-templates select="$elements[name()='way']" mode="areaSymbolPath">
            <xsl:with-param name="instruction" select="$instruction"/>
        </xsl:apply-templates>
    </xsl:template>


    <xsl:template match="*" mode="areaSymbolPath"/>


    <xsl:template match="way" mode="areaSymbolPath">
        <xsl:param name="instruction"/>

        <!-- The current <way> element -->
        <xsl:variable name="way" select="."/>

        <xsl:call-template name="renderAreaSymbol">
            <xsl:with-param name="instruction" select="$instruction"/>
            <xsl:with-param name="pathId" select="concat('way_normal_',@id)"/>
        </xsl:call-template>

    </xsl:template>


    <xsl:template name="renderAreaSymbol">
        <xsl:param name="instruction"/>

        <xsl:variable name='center'>
            <xsl:call-template name="areaCenter">
                <xsl:with-param name="element" select="." />
            </xsl:call-template>
        </xsl:variable>

        <xsl:message>
            areaCenter: <xsl:value-of select="$center" />
        </xsl:message>

        <xsl:variable name="centerLon" select="substring-before($center, ',')" />
        <xsl:variable name="centerLat" select="substring-after($center, ',')" />

        <xsl:variable name="x" select="($centerLon*$scale)"/>
        <xsl:variable name="y" select="($centerLat*$scale)"/>

        <g transform="translate({$x},{$y}) scale({$symbolScale})">
            <use>
                <xsl:if test="$instruction/@ref">
                    <xsl:attribute name="xlink:href">
                        <xsl:value-of select="concat('#symbol-', $instruction/@ref)"/>
                    </xsl:attribute>
                </xsl:if>
                <xsl:apply-templates select="$instruction/@*" mode="copyAttributes"/>
                <!-- Copy all the attributes from the <symbol> instruction -->
            </use>
        </g>
    </xsl:template>

    <!--
      areaCenter: Find a good center point for label/icon placement inside of polygon.
      Algorithm is described at http://bob.cakebox.net/poly-center.php
  -->
    <xsl:template name="areaCenter">
        <xsl:param name="element" />

        <!-- Get multipolygon relation for areas with holes -->
        <xsl:variable name='holerelation' select="key('relationByWay',$element/@id)[tag[@k='type' and @v='multipolygon']]"/>

        <!-- A semicolon-separated list of x,y coordinate pairs of points lying halfway into the polygon at angles to the vertex -->
        <xsl:variable name="points">
            <xsl:call-template name="areacenterPointsInside">
                <xsl:with-param name="element" select="$element" />
                <xsl:with-param name="holerelation" select="$holerelation" />
            </xsl:call-template>
        </xsl:variable>

        <!-- x,y calculated by a simple average over all x/y's in points -->
        <xsl:variable name="mediumpoint">
            <xsl:call-template name="areacenterMediumOfPoints">
                <xsl:with-param name="points" select="$points" />
            </xsl:call-template>
        </xsl:variable>
        <xsl:variable name="mediumpoint_x" select="substring-before($mediumpoint, ',')" />
        <xsl:variable name="mediumpoint_y" select="substring-before(substring-after($mediumpoint, ','), ',')" />
        <xsl:variable name="medium_dist" select="substring-after(substring-after($mediumpoint, ','), ',')" />

        <!-- Find out if mediumpoint is inside or outside the polygon -->
        <xsl:variable name="intersection">
            <xsl:call-template name="areacenterNearestIntersectionInside">
                <xsl:with-param name="x" select="$mediumpoint_x" />
                <xsl:with-param name="y" select="$mediumpoint_y" />
                <xsl:with-param name="edgestart" select="$element/nd[1]" />
                <xsl:with-param name="linepoint_x" select="$mediumpoint_x" />
                <xsl:with-param name="linepoint_y" select="$mediumpoint_y + 1" />
                <xsl:with-param name="holerelation" select="$holerelation" />
            </xsl:call-template>
        </xsl:variable>
        <xsl:variable name="intersection_count" select="substring-before($intersection, ';')" />

        <xsl:variable name="nearestEdge">
            <xsl:call-template name="areacenterNearestEdge">
                <xsl:with-param name="x" select="$mediumpoint_x" />
                <xsl:with-param name="y" select="$mediumpoint_y" />
                <xsl:with-param name="edgestart" select="$element/nd[1]" />
                <xsl:with-param name="holerelation" select="$holerelation" />
            </xsl:call-template>
        </xsl:variable>

        <xsl:choose>
            <xsl:when test="$intersection_count mod 2 = 0 or $nearestEdge div 2 * 1.20 &gt; $medium_dist">
                <!-- Find the best point in $points to use -->
                <xsl:call-template name="areacenterBestPoint">
                    <xsl:with-param name="points" select="$points" />
                    <xsl:with-param name="x" select="$mediumpoint_x" />
                    <xsl:with-param name="y" select="$mediumpoint_y" />
                    <xsl:with-param name="medium_dist" select="$medium_dist" />
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$mediumpoint_x"/>,<xsl:value-of select="$mediumpoint_y"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Returns a semicolon-separated list of x,y pairs -->
    <xsl:template name="areacenterPointsInside">
        <xsl:param name="element" />
        <xsl:param name="holerelation" />

        <!-- iterate over every vertex except the first one, which is also the last -->
        <xsl:for-each select="$element/nd[position() &gt; 1]">
            <xsl:variable name="vertex" select="." />
            <xsl:variable name="prev" select="$vertex/preceding-sibling::nd[1]" />
            <xsl:variable name="nextId">
                <xsl:choose>
                    <xsl:when test="position() &lt; last()">
                        <xsl:value-of select="$vertex/following-sibling::nd[1]/@ref" />
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:value-of select="$vertex/../nd[2]/@ref" />
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:variable>
            <xsl:variable name="next" select="$vertex/../nd[@ref=$nextId]" />

            <!-- Angle at between $prev and $next in $vertex -->
            <xsl:variable name="angle">
                <xsl:call-template name="angleThroughPoints">
                    <xsl:with-param name="from" select="key('nodeById', $prev/@ref)" />
                    <xsl:with-param name="through" select="key('nodeById', $vertex/@ref)" />
                    <xsl:with-param name="to" select="key('nodeById', $next/@ref)" />
                </xsl:call-template>
            </xsl:variable>

            <!-- Calculate a point on the line going through $vertex at $angle -->
            <xsl:variable name="linepoint">
                <xsl:call-template name="areacenterLinepoint">
                    <xsl:with-param name="point" select="key('nodeById', $vertex/@ref)" />
                    <xsl:with-param name="angle" select="$angle" />
                </xsl:call-template>
            </xsl:variable>
            <xsl:variable name="linepoint_x" select="substring-before($linepoint, ',')" />
            <xsl:variable name="linepoint_y" select="substring-after($linepoint, ',')" />

            <!-- Find the nearest intersection between the line vertex-linepoint and the nearest edge inwards into the polygon -->
            <xsl:variable name="intersection">
                <xsl:call-template name="areacenterNearestIntersectionInside">
                    <xsl:with-param name="x" select="key('nodeById', $vertex/@ref)/@lon" />
                    <xsl:with-param name="y" select="key('nodeById', $vertex/@ref)/@lat" />
                    <xsl:with-param name="edgestart" select="../nd[1]" />
                    <xsl:with-param name="linepoint_x" select="$linepoint_x" />
                    <xsl:with-param name="linepoint_y" select="$linepoint_y" />
                    <xsl:with-param name="holerelation" select="$holerelation" />
                </xsl:call-template>
            </xsl:variable>
            <xsl:variable name="intersection_count" select="substring-before($intersection, ';')" />
            <xsl:variable name="intersection_data">
                <xsl:choose>
                    <xsl:when test="$intersection_count mod 2 != 0">
                        <xsl:value-of select="substring-before(substring-after($intersection, ';'), ';')" />
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:value-of select="substring-after(substring-after($intersection, ';'), ';')" />
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:variable>
            <xsl:variable name="intersection_x" select="substring-before($intersection_data, ',')" />
            <xsl:variable name="intersection_y" select="substring-before(substring-after($intersection_data, ','), ',')" />
            <xsl:variable name="intersection_dist" select="substring-before(substring-after(substring-after($intersection_data, ','), ','), ',')" />

            <xsl:variable name="point_x" select="key('nodeById', $vertex/@ref)/@lon + ( $intersection_x - key('nodeById', $vertex/@ref)/@lon ) div 2" />
            <xsl:variable name="point_y" select="key('nodeById', $vertex/@ref)/@lat + ( $intersection_y - key('nodeById', $vertex/@ref)/@lat ) div 2" />

            <xsl:if test="($point_x &lt;= 0 or $point_x &gt; 0)  and ($point_y &lt;= 0 or $point_y &gt; 0)">
                <!-- Only return anything if we actually have a result -->
                <!-- Note: this will produce trailing semicolon, which is nice as it simplifies looping over this later -->
                <xsl:value-of select="$point_x" />,<xsl:value-of select="$point_y" />,<xsl:value-of select="$intersection_dist" />;
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

    <!-- Calculate the angle between $from and $to in $through. Returns answer in radians -->
    <xsl:template name="angleThroughPoints">
        <xsl:param name="from" />
        <xsl:param name="through" />
        <xsl:param name="to" />

        <xsl:variable name="from_x" select="($from/@lon) - ($through/@lon)" />
        <xsl:variable name="from_y" select="$from/@lat - $through/@lat" />
        <xsl:variable name="to_x" select="$to/@lon - $through/@lon" />
        <xsl:variable name="to_y" select="$to/@lat - $through/@lat" />

        <xsl:variable name="from_angle_">
            <xsl:call-template name="atan2">
                <xsl:with-param name="x" select="$from_x" />
                <xsl:with-param name="y" select="$from_y" />
            </xsl:call-template>
        </xsl:variable>
        <xsl:variable name="from_angle" select="$from_angle_ + $pi" />
        <xsl:variable name="to_angle_">
            <xsl:call-template name="atan2">
                <xsl:with-param name="x" select="$to_x" />
                <xsl:with-param name="y" select="$to_y" />
            </xsl:call-template>
        </xsl:variable>
        <xsl:variable name="to_angle" select="$to_angle_ + $pi" />

        <xsl:variable name="min_angle">
            <xsl:choose>
                <xsl:when test="$from_angle &gt; $to_angle">
                    <xsl:value-of select="$to_angle" />
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="$from_angle" />
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:variable name="max_angle">
            <xsl:choose>
                <xsl:when test="$from_angle &gt; $to_angle">
                    <xsl:value-of select="$from_angle" />
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="$to_angle" />
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>

        <xsl:value-of select="$min_angle + ($max_angle - $min_angle) div 2" />
    </xsl:template>

    <!-- atan2 implementation from http://lists.fourthought.com/pipermail/exslt/2007-March/001540.html -->
    <xsl:template name="atan2">
        <xsl:param name="y"/>
        <xsl:param name="x"/>
        <!-- http://lists.apple.com/archives/PerfOptimization-dev/2005/Jan/msg00051.html -->
        <xsl:variable name="PI"    select="number(3.1415926535897)"/>
        <xsl:variable name="PIBY2" select="$PI div 2.0"/>
        <xsl:choose>
            <xsl:when test="$x = 0.0">
                <xsl:choose>
                    <xsl:when test="($y &gt; 0.0)">
                        <xsl:value-of select="$PIBY2"/>
                    </xsl:when>
                    <xsl:when test="($y &lt; 0.0)">
                        <xsl:value-of select="-$PIBY2"/>
                    </xsl:when>
                    <xsl:otherwise>
                        <!-- Error: Degenerate x == y == 0.0 -->
                        <xsl:value-of select="number(NaN)"/>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="z" select="$y div $x"/>
                <xsl:variable name="absZ">
                    <!-- inline abs function -->
                    <xsl:choose>
                        <xsl:when test="$z &lt; 0.0">
                            <xsl:value-of select="- number($z)"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:value-of select="number($z)"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                <xsl:choose>
                    <xsl:when test="($absZ &lt; 1.0)">
                        <xsl:variable name="f1Z" select="$z div (1.0 + 0.28*$z*$z)"/>
                        <xsl:choose>
                            <xsl:when test="($x &lt; 0.0) and ($y &lt; 0.0)">
                                <xsl:value-of select="$f1Z - $PI"/>
                            </xsl:when>
                            <xsl:when test="($x &lt; 0.0)">
                                <xsl:value-of select="$f1Z + $PI"/>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:value-of select="$f1Z"/>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:variable name="f2Z" select="$PIBY2 - ($z div ($z*$z + 0.28))"/>
                        <xsl:choose>
                            <xsl:when test="($y &lt; 0.0)">
                                <xsl:value-of select="$f2Z - $PI"/>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:value-of select="$f2Z"/>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Find a point on the line going through $point at $angle that's guaranteed to be outside the polygon -->
    <xsl:template name="areacenterLinepoint">
        <xsl:param name="point" />
        <xsl:param name="angle" />

        <xsl:variable name="cos_angle">
            <xsl:call-template name="cos">
                <xsl:with-param name="angle" select="$angle"/>
            </xsl:call-template>
        </xsl:variable>

        <xsl:variable name="sin_angle">
            <xsl:call-template name="sin">
                <xsl:with-param name="angle" select="$angle"/>
            </xsl:call-template>
        </xsl:variable>

        <xsl:value-of select="$point/@lon + $cos_angle"/>, <xsl:value-of select="$point/@lat + $sin_angle"/>
    </xsl:template>

    <!-- Constants for trig templates -->
    <xsl:variable name="pi" select="3.1415926535897"/>
    <xsl:variable name="halfPi" select="$pi div 2"/>
    <xsl:variable name="twicePi" select="$pi*2"/>

    <xsl:template name="sin">
        <xsl:param name="angle" />
        <xsl:param name="precision" select="0.00000001"/>

        <xsl:variable name="y">
            <xsl:choose>
                <xsl:when test="not(0 &lt;= $angle and $twicePi > $angle)">
                    <xsl:call-template name="cutIntervals">
                        <xsl:with-param name="length" select="$twicePi"/>
                        <xsl:with-param name="angle" select="$angle"/>
                    </xsl:call-template>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="$angle"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>

        <xsl:call-template name="sineIter">
            <xsl:with-param name="angle2" select="$y*$y"/>
            <xsl:with-param name="res" select="$y"/>
            <xsl:with-param name="elem" select="$y"/>
            <xsl:with-param name="n" select="1"/>
            <xsl:with-param name="precision" select="$precision" />
        </xsl:call-template>
    </xsl:template>

    <xsl:template name="sineIter">
        <xsl:param name="angle2" />
        <xsl:param name="res" />
        <xsl:param name="elem" />
        <xsl:param name="n" />
        <xsl:param name="precision"/>

        <xsl:variable name="nextN" select="$n+2" />
        <xsl:variable name="newElem" select="-$elem*$angle2 div ($nextN*($nextN - 1))" />
        <xsl:variable name="newResult" select="$res + $newElem" />
        <xsl:variable name="diffResult" select="$newResult - $res" />

        <xsl:choose>
            <xsl:when test="$diffResult > $precision or $diffResult &lt; -$precision">
                <xsl:call-template name="sineIter">
                    <xsl:with-param name="angle2" select="$angle2" />
                    <xsl:with-param name="res" select="$newResult" />
                    <xsl:with-param name="elem" select="$newElem" />
                    <xsl:with-param name="n" select="$nextN" />
                    <xsl:with-param name="precision" select="$precision" />
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$newResult"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:template name="cutIntervals">
        <xsl:param name="length"/>
        <xsl:param name="angle"/>

        <xsl:variable name="vsign">
            <xsl:choose>
                <xsl:when test="$angle >= 0">1</xsl:when>
                <xsl:otherwise>-1</xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:variable name="vdiff" select="$length*floor($angle div $length) -$angle"/>
        <xsl:choose>
            <xsl:when test="$vdiff*$angle > 0">
                <xsl:value-of select="$vsign*$vdiff"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="-$vsign*$vdiff"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:template name="cos">
        <xsl:param name="angle" />
        <xsl:param name="precision" select="0.00000001"/>

        <xsl:call-template name="sin">
            <xsl:with-param name="angle" select="$halfPi - $angle" />
            <xsl:with-param name="precision" select="$precision" />
        </xsl:call-template>
    </xsl:template>

    <!-- Find the nearest intersection into the polygon along the line ($x,$y)-$linepoint.
       Can also be used for ray-casting point-in-polygon checking -->
    <xsl:template name="areacenterNearestIntersectionInside">
        <xsl:param name="x" />
        <xsl:param name="y" />
        <xsl:param name="edgestart" />
        <xsl:param name="linepoint_x" />
        <xsl:param name="linepoint_y" />
        <xsl:param name="holerelation" />
        <xsl:param name="intersectioncount_on" select="0" />
        <!-- Number of intersections. Only counts those on segment (x,y)-linepoint -->
        <xsl:param name="nearest_on_x" />
        <xsl:param name="nearest_on_y" />
        <xsl:param name="nearest_on_dist" select="'NaN'" />
        <xsl:param name="nearest_off_x" />
        <xsl:param name="nearest_off_y" />
        <xsl:param name="nearest_off_dist" select="'NaN'" />

        <xsl:choose>
            <!-- If there are no more vertices we don't have a second point for the edge, and are finished -->
            <xsl:when test="$edgestart/following-sibling::nd[1]">
                <xsl:variable name="edgeend" select="$edgestart/following-sibling::nd[1]" />
                <!-- Get the intersection point between the line ($x,$y)-$linepoint and $edgestart-$edgeend -->
                <xsl:variable name="intersection">
                    <xsl:choose>
                        <xsl:when test="( $x = key('nodeById', $edgestart/@ref)/@lon and $y = key('nodeById', $edgestart/@ref)/@lat ) or
			    ( $x = key('nodeById', $edgeend/@ref)/@lon and $y = key('nodeById', $edgeend/@ref)/@lat )">
                            <!-- (x,y) is one of the points in edge, skip -->
                            NoIntersection
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:call-template name="areacenterLinesIntersection">
                                <xsl:with-param name="x1" select="$x" />
                                <xsl:with-param name="y1" select="$y" />
                                <xsl:with-param name="x2" select="$linepoint_x" />
                                <xsl:with-param name="y2" select="$linepoint_y" />
                                <xsl:with-param name="x3" select="key('nodeById', $edgestart/@ref)/@lon" />
                                <xsl:with-param name="y3" select="key('nodeById', $edgestart/@ref)/@lat" />
                                <xsl:with-param name="x4" select="key('nodeById', $edgeend/@ref)/@lon" />
                                <xsl:with-param name="y4" select="key('nodeById', $edgeend/@ref)/@lat" />
                            </xsl:call-template>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>

                <!-- Haul ix, iy, ua and ub out of the csv -->
                <xsl:variable name="ix" select="substring-before($intersection, ',')" />
                <xsl:variable name="iy" select="substring-before(substring-after($intersection, ','), ',')" />
                <xsl:variable name="ua" select="substring-before(substring-after(substring-after($intersection, ','), ','), ',')" />
                <xsl:variable name="ub" select="substring-after(substring-after(substring-after($intersection, ','), ','), ',')" />

                <!-- A) Is there actually an intersection? B) Is it on edge? -->
                <xsl:choose>
                    <xsl:when test="$intersection != 'NoIntersection' and $ub &gt; 0 and $ub &lt;= 1">
                        <xsl:variable name="distance">
                            <xsl:call-template name="areacenterPointDistance">
                                <xsl:with-param name="x1" select="$x" />
                                <xsl:with-param name="y1" select="$y" />
                                <xsl:with-param name="x2" select="$ix" />
                                <xsl:with-param name="y2" select="$iy" />
                            </xsl:call-template>
                        </xsl:variable>

                        <!-- Is intersection on the segment ($x,$y)-$linepoint, or on the other side of ($x,$y)? -->
                        <xsl:variable name="isOnSegment">
                            <xsl:if test="$ua &gt;= 0">Yes</xsl:if>
                        </xsl:variable>

                        <xsl:variable name="isNewNearestOn">
                            <xsl:if test="$isOnSegment = 'Yes' and ( $nearest_on_dist = 'NaN' or $distance &lt; $nearest_on_dist )">Yes</xsl:if>
                        </xsl:variable>

                        <xsl:variable name="isNewNearestOff">
                            <xsl:if test="$isOnSegment != 'Yes' and ( $nearest_off_dist = 'NaN' or $distance &lt; $nearest_off_dist )">Yes</xsl:if>
                        </xsl:variable>

                        <xsl:call-template name="areacenterNearestIntersectionInside">
                            <xsl:with-param name="x" select="$x" />
                            <xsl:with-param name="y" select="$y" />
                            <xsl:with-param name="linepoint_x" select="$linepoint_x" />
                            <xsl:with-param name="linepoint_y" select="$linepoint_y" />
                            <xsl:with-param name="edgestart" select="$edgeend" />
                            <xsl:with-param name="holerelation" select="$holerelation" />
                            <xsl:with-param name="intersectioncount_on" select="$intersectioncount_on + number(boolean($isOnSegment = 'Yes'))" />
                            <xsl:with-param name="nearest_on_dist">
                                <xsl:choose>
                                    <xsl:when test="$isNewNearestOn = 'Yes'">
                                        <xsl:value-of select="$distance" />
                                    </xsl:when>
                                    <xsl:otherwise>
                                        <xsl:value-of select="$nearest_on_dist" />
                                    </xsl:otherwise>
                                </xsl:choose>
                            </xsl:with-param>
                            <xsl:with-param name="nearest_on_x">
                                <xsl:choose>
                                    <xsl:when test="$isNewNearestOn = 'Yes'">
                                        <xsl:value-of select="$ix" />
                                    </xsl:when>
                                    <xsl:otherwise>
                                        <xsl:value-of select="$nearest_on_x" />
                                    </xsl:otherwise>
                                </xsl:choose>
                            </xsl:with-param>
                            <xsl:with-param name="nearest_on_y">
                                <xsl:choose>
                                    <xsl:when test="$isNewNearestOn = 'Yes'">
                                        <xsl:value-of select="$iy" />
                                    </xsl:when>
                                    <xsl:otherwise>
                                        <xsl:value-of select="$nearest_on_y" />
                                    </xsl:otherwise>
                                </xsl:choose>
                            </xsl:with-param>
                            <xsl:with-param name="nearest_off_dist">
                                <xsl:choose>
                                    <xsl:when test="$isNewNearestOff = 'Yes'">
                                        <xsl:value-of select="$distance" />
                                    </xsl:when>
                                    <xsl:otherwise>
                                        <xsl:value-of select="$nearest_off_dist" />
                                    </xsl:otherwise>
                                </xsl:choose>
                            </xsl:with-param>
                            <xsl:with-param name="nearest_off_x">
                                <xsl:choose>
                                    <xsl:when test="$isNewNearestOff = 'Yes'">
                                        <xsl:value-of select="$ix" />
                                    </xsl:when>
                                    <xsl:otherwise>
                                        <xsl:value-of select="$nearest_off_x" />
                                    </xsl:otherwise>
                                </xsl:choose>
                            </xsl:with-param>
                            <xsl:with-param name="nearest_off_y">
                                <xsl:choose>
                                    <xsl:when test="$isNewNearestOff = 'Yes'">
                                        <xsl:value-of select="$iy" />
                                    </xsl:when>
                                    <xsl:otherwise>
                                        <xsl:value-of select="$nearest_off_y" />
                                    </xsl:otherwise>
                                </xsl:choose>
                            </xsl:with-param>
                        </xsl:call-template>
                    </xsl:when>
                    <!-- No intersection, just go on to next edge -->
                    <xsl:otherwise>
                        <xsl:call-template name="areacenterNearestIntersectionInside">
                            <xsl:with-param name="x" select="$x" />
                            <xsl:with-param name="y" select="$y" />
                            <xsl:with-param name="linepoint_x" select="$linepoint_x" />
                            <xsl:with-param name="linepoint_y" select="$linepoint_y" />
                            <xsl:with-param name="edgestart" select="$edgeend" />
                            <xsl:with-param name="holerelation" select="$holerelation" />
                            <xsl:with-param name="intersectioncount_on" select="$intersectioncount_on" />
                            <xsl:with-param name="nearest_on_dist" select="$nearest_on_dist" />
                            <xsl:with-param name="nearest_on_x" select="$nearest_on_x" />
                            <xsl:with-param name="nearest_on_y" select="$nearest_on_y" />
                            <xsl:with-param name="nearest_off_dist" select="$nearest_off_dist" />
                            <xsl:with-param name="nearest_off_x" select="$nearest_off_x" />
                            <xsl:with-param name="nearest_off_y" select="$nearest_off_y" />
                        </xsl:call-template>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:when>
            <!-- Is there a hole in the polygon, and were we working on the outer one? Then we start edge detection against the hole. -->
            <xsl:when test="$holerelation and
		      $holerelation/member[@ref = $edgestart/../@id][@role='outer']">
                <xsl:variable name="nextnode" select="key('wayById', $holerelation/member[@type='way'][@role='inner'][1]/@ref)/nd[1]"/>
                <xsl:call-template name="areacenterNearestIntersectionInside">
                    <xsl:with-param name="x" select="$x" />
                    <xsl:with-param name="y" select="$y" />
                    <xsl:with-param name="linepoint_x" select="$linepoint_x" />
                    <xsl:with-param name="linepoint_y" select="$linepoint_y" />
                    <xsl:with-param name="edgestart" select="$nextnode" />
                    <xsl:with-param name="holerelation" select="$holerelation" />
                    <xsl:with-param name="intersectioncount_on" select="$intersectioncount_on" />
                    <xsl:with-param name="nearest_on_dist" select="$nearest_on_dist" />
                    <xsl:with-param name="nearest_on_x" select="$nearest_on_x" />
                    <xsl:with-param name="nearest_on_y" select="$nearest_on_y" />
                    <xsl:with-param name="nearest_off_dist" select="$nearest_off_dist" />
                    <xsl:with-param name="nearest_off_x" select="$nearest_off_x" />
                    <xsl:with-param name="nearest_off_y" select="$nearest_off_y" />
                </xsl:call-template>
            </xsl:when>
            <!-- Is there a hole in the polygon, and were we working working on one of the inner ones? Then go to the next hole, if there is one -->
            <xsl:when test="$holerelation and
		      $holerelation/member[@ref = $edgestart/../@id][@type='way'][@role='inner']/following-sibling::member[@role='inner']">
                <xsl:variable name="nextnode" select="key('wayById', $holerelation/member[@ref = $edgestart/../@id][@type='way'][@role='inner']/following-sibling::member[@role='inner']/@ref)/nd[1]"/>
                <xsl:call-template name="areacenterNearestIntersectionInside">
                    <xsl:with-param name="x" select="$x" />
                    <xsl:with-param name="y" select="$y" />
                    <xsl:with-param name="linepoint_x" select="$linepoint_x" />
                    <xsl:with-param name="linepoint_y" select="$linepoint_y" />
                    <xsl:with-param name="edgestart" select="$nextnode" />
                    <xsl:with-param name="holerelation" select="$holerelation" />
                    <xsl:with-param name="intersectioncount_on" select="$intersectioncount_on" />
                    <xsl:with-param name="nearest_on_dist" select="$nearest_on_dist" />
                    <xsl:with-param name="nearest_on_x" select="$nearest_on_x" />
                    <xsl:with-param name="nearest_on_y" select="$nearest_on_y" />
                    <xsl:with-param name="nearest_off_dist" select="$nearest_off_dist" />
                    <xsl:with-param name="nearest_off_x" select="$nearest_off_x" />
                    <xsl:with-param name="nearest_off_y" select="$nearest_off_y" />
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <!-- No more edges, return data -->
                <xsl:value-of select="$intersectioncount_on" />;
                <xsl:value-of select="$nearest_on_x"/>,<xsl:value-of select="$nearest_on_y"/>,<xsl:value-of select="$nearest_on_dist"/>;
                <xsl:value-of select="$nearest_off_x"/>,<xsl:value-of select="$nearest_off_y"/>,<xsl:value-of select="$nearest_off_dist"/>;
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Find the distance to the edge nearest (x,y) -->
    <xsl:template name="areacenterNearestEdge">
        <xsl:param name="x" />
        <xsl:param name="y" />
        <xsl:param name="edgestart" />
        <xsl:param name="holerelation" />
        <xsl:param name="nearest_dist" select="'NaN'" />

        <xsl:choose>
            <!-- If there are no more vertices we don't have a second point for the edge, and are finished -->
            <xsl:when test="$edgestart/following-sibling::nd[1]">
                <xsl:variable name="edgeend" select="$edgestart/following-sibling::nd[1]" />

                <xsl:variable name="distance">
                    <xsl:call-template name="areacenterDistancePointSegment">
                        <xsl:with-param name="x" select="$x" />
                        <xsl:with-param name="y" select="$y" />
                        <xsl:with-param name="x1" select="key('nodeById', $edgestart/@ref)/@lon" />
                        <xsl:with-param name="y1" select="key('nodeById', $edgestart/@ref)/@lat" />
                        <xsl:with-param name="x2" select="key('nodeById', $edgeend/@ref)/@lon" />
                        <xsl:with-param name="y2" select="key('nodeById', $edgeend/@ref)/@lat" />
                    </xsl:call-template>
                </xsl:variable>

                <!-- Did we get a valid distance?
	     There is some code in DistancePointSegment that can return NaN in some cases -->
                <xsl:choose>
                    <xsl:when test="string(number($distance)) != 'NaN'">
                        <xsl:call-template name="areacenterNearestEdge">
                            <xsl:with-param name="x" select="$x" />
                            <xsl:with-param name="y" select="$y" />
                            <xsl:with-param name="edgestart" select="$edgeend" />
                            <xsl:with-param name="holerelation" select="$holerelation" />
                            <xsl:with-param name="nearest_dist">
                                <xsl:choose>
                                    <xsl:when test="$nearest_dist = 'NaN' or $distance &lt; $nearest_dist">
                                        <xsl:value-of select="$distance" />
                                    </xsl:when>
                                    <xsl:otherwise>
                                        <xsl:value-of select="$nearest_dist" />
                                    </xsl:otherwise>
                                </xsl:choose>
                            </xsl:with-param>
                        </xsl:call-template>
                    </xsl:when>

                    <xsl:otherwise>
                        <xsl:call-template name="areacenterNearestEdge">
                            <xsl:with-param name="x" select="$x" />
                            <xsl:with-param name="y" select="$y" />
                            <xsl:with-param name="edgestart" select="$edgeend" />
                            <xsl:with-param name="holerelation" select="$holerelation" />
                            <xsl:with-param name="nearest_dist" select="$nearest_dist" />
                        </xsl:call-template>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:when>
            <!-- Is there a hole in the polygon, and were we working on the outer one? Then we start edge detection against the hole. -->
            <xsl:when test="$holerelation and
		      $holerelation/member[@ref = $edgestart/../@id][@role='outer']">
                <xsl:variable name="nextnode" select="key('wayById', $holerelation/member[@type='way'][@role='inner'][1]/@ref)/nd[1]"/>
                <xsl:call-template name="areacenterNearestEdge">
                    <xsl:with-param name="x" select="$x" />
                    <xsl:with-param name="y" select="$y" />
                    <xsl:with-param name="edgestart" select="$nextnode" />
                    <xsl:with-param name="holerelation" select="$holerelation" />
                    <xsl:with-param name="nearest_dist" select="$nearest_dist" />
                </xsl:call-template>
            </xsl:when>
            <!-- Is there a hole in the polygon, and were we working working on one of the inner ones? Then go to the next hole, if there is one -->
            <xsl:when test="$holerelation and
		      $holerelation/member[@ref = $edgestart/../@id][@type='way'][@role='inner']/following-sibling::member[@role='inner']">
                <xsl:variable name="nextnode" select="key('wayById', $holerelation/member[@ref = $edgestart/../@id][@type='way'][@role='inner']/following-sibling::member[@role='inner']/@ref)/nd[1]"/>
                <xsl:call-template name="areacenterNearestEdge">
                    <xsl:with-param name="x" select="$x" />
                    <xsl:with-param name="y" select="$y" />
                    <xsl:with-param name="edgestart" select="$nextnode" />
                    <xsl:with-param name="holerelation" select="$holerelation" />
                    <xsl:with-param name="nearest_dist" select="$nearest_dist" />
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <!-- No more edges, return data -->
                <xsl:value-of select="$nearest_dist" />
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Find the distance between the point (x,y) and the segment x1,y1 -> x2,y2 -->
    <!-- Based on http://local.wasp.uwa.edu.au/~pbourke/geometry/pointline/ and the
       Delphi example by Graham O'Brien -->
    <xsl:template name="areacenterDistancePointSegment">
        <xsl:param name="x" />
        <xsl:param name="y" />
        <xsl:param name="x1" />
        <xsl:param name="y1" />
        <xsl:param name="x2" />
        <xsl:param name="y2" />

        <!-- Constants -->
        <xsl:variable name="EPS" select="0.000001" />
        <xsl:variable name="EPSEPS" select="$EPS * $EPS" />

        <!-- The line magnitude, squared -->
        <xsl:variable name="sqLineMagnitude" select="($x2 - $x1) * ($x2 - $x1) + ($y2 - $y1) * ($y2 - $y1)" />

        <xsl:choose>
            <xsl:when test="sqLineMagnitude &lt; $EPSEPS">
                NaN
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="u" select="( ($x - $x1)*($x2 - $x1) + ($y - $y1)*($y2 - $y1) ) div sqLineMagnitude" />

                <xsl:variable name="result">
                    <xsl:choose>
                        <xsl:when test="u &lt; $EPS or u &gt; 1">
                            <!-- Closest point in not on segment, return shortest distance to an endpoint -->
                            <xsl:variable name="dist1" select="($x1 - $x) * ($x1 - $x) + ($y1 - $y) * ($y1 - $y)" />
                            <xsl:variable name="dist2" select="($x2 - $x) * ($x2 - $x) + ($y2 - $y) * ($y2 - $y)" />

                            <!-- min($dist1, $dist2) -->
                            <xsl:choose>
                                <xsl:when test="$dist1 &lt; $dist2">
                                    <xsl:value-of select="$dist1" />
                                </xsl:when>
                                <xsl:otherwise>
                                    <xsl:value-of select="$dist2" />
                                </xsl:otherwise>
                            </xsl:choose>

                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:variable name="ix" select="$x1 + $u * ($x2 - $x1)" />
                            <xsl:variable name="iy" select="$y1 + $u * ($y2 - $y1)" />
                            <xsl:value-of select="($ix - $x) * ($ix - $x) + ($iy - $y) * ($iy - $y)" />
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>

                <!-- Finally return the square root of the result, as we were working with squared distances -->
                <xsl:call-template name="sqrt">
                    <xsl:with-param name="num" select="$result" />
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>

    </xsl:template>

    <!--
      Finds intersection point between lines x1,y1 -> x2,y2 and x3,y3 -> x4,y4.
      Returns a comma-separated list of x,y,ua,ub or NoIntersection if the lines do not intersect
  -->
    <xsl:template name="areacenterLinesIntersection">
        <xsl:param name="x1" />
        <xsl:param name="y1" />
        <xsl:param name="x2" />
        <xsl:param name="y2" />
        <xsl:param name="x3" />
        <xsl:param name="y3" />
        <xsl:param name="x4" />
        <xsl:param name="y4" />

        <xsl:variable name="denom" select="(( $y4 - $y3 ) * ( $x2 - $x1 )) -
				       (( $x4 - $x3 ) * ( $y2 - $y1 ))" />
        <xsl:variable name="nume_a" select="(( $x4 - $x3 ) * ( $y1 - $y3 )) -
					(( $y4 - $y3 ) * ( $x1 - $x3 ))" />
        <xsl:variable name="nume_b" select="(( $x2 - $x1 ) * ( $y1 - $y3 )) -
					(( $y2 - $y1 ) * ( $x1 - $x3 ))" />

        <xsl:choose>
            <xsl:when test="$denom = 0">
                NoIntersection
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="ua" select="$nume_a div $denom" />
                <xsl:variable name="ub" select="$nume_b div $denom" />

                <!-- x,y,ua,ub -->
                <xsl:value-of select="$x1 + $ua * ($x2 - $x1)" />,<xsl:value-of select="$y1 + $ua * ($y2 - $y1)" />,<xsl:value-of select="$ua" />,<xsl:value-of select="$ub" />
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Distance between two points -->
    <xsl:template name="areacenterPointDistance">
        <xsl:param name="x1" />
        <xsl:param name="y1" />
        <xsl:param name="x2" />
        <xsl:param name="y2" />

        <!-- sqrt( ($x2 - $x1)**2 + ($y2 - $y1)**2 ) -->
        <xsl:call-template name="sqrt">
            <xsl:with-param name="num" select="($x2*$x2 - $x2*$x1 - $x1*$x2 + $x1*$x1) + ($y2*$y2 - $y2*$y1 - $y1*$y2 + $y1*$y1)" />
        </xsl:call-template>
    </xsl:template>

    <xsl:template name="sqrt">
        <xsl:param name="num" select="0"/>
        <!-- The number you want to find the square root of -->
        <xsl:param name="try" select="1"/>
        <!-- The current 'try'.  This is used internally. -->
        <xsl:param name="iter" select="1"/>
        <!-- The current iteration, checked against maxiter to limit loop count -->
        <xsl:param name="maxiter" select="10"/>
        <!-- Set this up to insure against infinite loops -->

        <!-- This template was written by Nate Austin using Sir Isaac Newton's method of finding roots -->

        <xsl:choose>
            <xsl:when test="$try * $try = $num or $iter &gt; $maxiter">
                <xsl:value-of select="$try"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="sqrt">
                    <xsl:with-param name="num" select="$num"/>
                    <xsl:with-param name="try" select="$try - (($try * $try - $num) div (2 * $try))"/>
                    <xsl:with-param name="iter" select="$iter + 1"/>
                    <xsl:with-param name="maxiter" select="$maxiter"/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Returns the medium value of all the points -->
    <xsl:template name="areacenterMediumOfPoints">
        <xsl:param name="points" />
        <xsl:param name="total_x" select="0" />
        <xsl:param name="total_y" select="0" />
        <xsl:param name="total_dist" select="0" />
        <xsl:param name="count" select="0" />

        <xsl:variable name="point" select="substring-before($points, ';')" />

        <xsl:choose>
            <xsl:when test="string-length($point) &gt; 0">
                <xsl:variable name="x" select="substring-before($point, ',')" />
                <xsl:variable name="y" select="substring-before(substring-after($point, ','), ',')" />
                <xsl:variable name="dist" select="substring-after(substring-after($point, ','), ',')" />

                <xsl:call-template name="areacenterMediumOfPoints">
                    <xsl:with-param name="points" select="substring-after($points, ';')" />
                    <xsl:with-param name="total_x" select="$total_x + $x" />
                    <xsl:with-param name="total_y" select="$total_y + $y" />
                    <xsl:with-param name="total_dist" select="$total_dist + $dist" />
                    <xsl:with-param name="count" select="$count + 1" />
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$total_x div $count" />,<xsl:value-of select="$total_y div $count" />,<xsl:value-of select="$total_dist div $count" />
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Returns the coordinates of the point that scores highest.
       The score is based on the distance to (x,y),
       the distance between the point and it's vertex,
       and the medium of that distance in all the points -->
    <xsl:template name="areacenterBestPoint">
        <xsl:param name="points" />
        <xsl:param name="x" />
        <xsl:param name="y" />
        <xsl:param name="nearest_x" />
        <xsl:param name="nearest_y" />
        <xsl:param name="medium_dist" />
        <xsl:param name="nearest_score" />
        <xsl:param name="nearest_dist" select="'NaN'" />

        <xsl:variable name="point" select="substring-before($points, ';')" />

        <xsl:choose>
            <xsl:when test="string-length($point) &gt; 0">
                <xsl:variable name="point_x" select="substring-before($point, ',')" />
                <xsl:variable name="point_y" select="substring-before(substring-after($point, ','), ',')" />
                <xsl:variable name="point_dist" select="substring-after(substring-after($point, ','), ',')" />

                <xsl:variable name="distance">
                    <xsl:call-template name="areacenterPointDistance">
                        <xsl:with-param name="x1" select="$x" />
                        <xsl:with-param name="y1" select="$y" />
                        <xsl:with-param name="x2" select="$point_x" />
                        <xsl:with-param name="y2" select="$point_y" />
                    </xsl:call-template>
                </xsl:variable>

                <xsl:variable name="score" select="0 - $distance + $point_dist + $point_dist - $medium_dist"/>
                <xsl:variable name="isNewNearest" select="$nearest_dist = 'NaN' or $score &gt; $nearest_score" />

                <xsl:call-template name="areacenterBestPoint">
                    <xsl:with-param name="points" select="substring-after($points, ';')" />
                    <xsl:with-param name="x" select="$x" />
                    <xsl:with-param name="y" select="$y" />
                    <xsl:with-param name="medium_dist" select="$medium_dist" />
                    <xsl:with-param name="nearest_dist">
                        <xsl:choose>
                            <xsl:when test="$isNewNearest">
                                <xsl:value-of select="$distance" />
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:value-of select="$nearest_dist" />
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:with-param>
                    <xsl:with-param name="nearest_x">
                        <xsl:choose>
                            <xsl:when test="$isNewNearest">
                                <xsl:value-of select="$point_x" />
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:value-of select="$nearest_x" />
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:with-param>
                    <xsl:with-param name="nearest_y">
                        <xsl:choose>
                            <xsl:when test="$isNewNearest">
                                <xsl:value-of select="$point_y" />
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:value-of select="$nearest_y" />
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:with-param>
                    <xsl:with-param name="nearest_score">
                        <xsl:choose>
                            <xsl:when test="$isNewNearest">
                                <xsl:value-of select="$score" />
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:value-of select="$nearest_score" />
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$nearest_x" />, <xsl:value-of select="$nearest_y" />
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Process a <text> instruction -->
    <xsl:template match="text">
        <xsl:param name="elements"/>

        <!-- This is the instruction that is currently being processed -->
        <xsl:variable name="instruction" select="."/>

        <!-- Select all <node> elements that have a key that matches the k attribute of the text instruction -->
        <xsl:for-each select="$elements[name()='node'][tag[@k=$instruction/@k]]">
            <xsl:call-template name="renderText">
                <xsl:with-param name="instruction" select="$instruction"/>
            </xsl:call-template>
        </xsl:for-each>

        <!-- Select all <way> elements -->
        <xsl:apply-templates select="$elements[name()='way']" mode="textPath">
            <xsl:with-param name="instruction" select="$instruction"/>
        </xsl:apply-templates>
    </xsl:template>


    <!-- Suppress output of any unhandled elements -->
    <xsl:template match="*" mode="textPath"/>


    <!-- Render textPaths for a way -->
    <xsl:template match="way" mode="textPath">
        <xsl:param name="instruction"/>

        <!-- The current <way> element -->
        <xsl:variable name="way" select="."/>

        <!-- DODI: !!!WORKAROUND!!! no text for one node ways-->
        <xsl:if test="count($way/nd) &gt; 1">
            <xsl:variable name='text'>
                <xsl:choose>
                    <xsl:when test='$instruction/@k'>
                        <xsl:value-of select='$instruction/@text-prefix'/>
                        <xsl:value-of select='tag[@k=$instruction/@k]/@v'/>
                        <xsl:value-of select='$instruction/@text-postfix'/>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:apply-templates select='$instruction' mode='textFormat'>
                            <xsl:with-param name='way' select='$way'/>
                        </xsl:apply-templates>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:variable>

            <xsl:if test='string($text)'>

                <xsl:variable name="pathDirection">
                    <xsl:choose>
                        <!-- Manual override, reverse direction -->
                        <xsl:when test="tag[@k='name_direction']/@v='-1' or tag[@k='osmarender:x-name-direction']/@v='-1' or $instruction/@x-name-direction='reverse'">reverse</xsl:when>
                        <!-- Manual override, normal direction -->
                        <xsl:when test="tag[@k='name_direction']/@v='1' or tag[@k='osmarender:x-name-direction']/@v='1' or $instruction/@x-name-direction='normal'">normal</xsl:when>
                        <!-- Automatic, reverse direction -->
                        <xsl:when test="(key('nodeById',($way/nd[key('nodeById',@ref)])[1]/@ref)/@lon &gt; key('nodeById',$way/nd[key('nodeById',@ref)][last()]/@ref)/@lon)">reverse</xsl:when>
                        <!-- Automatic, normal direction -->
                        <xsl:otherwise>normal</xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>

                <xsl:variable name="wayPath">
                    <xsl:choose>
                        <!-- Normal -->
                        <xsl:when test='$pathDirection="normal"'>
                            <xsl:value-of select="concat('way_normal_',@id)"/>
                        </xsl:when>
                        <!-- Reverse -->
                        <xsl:otherwise>
                            <xsl:value-of select="concat('way_reverse_',@id)"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>

                <xsl:call-template name="renderTextPath">
                    <xsl:with-param name="instruction" select="$instruction"/>
                    <xsl:with-param name="pathId" select="$wayPath"/>
                    <xsl:with-param name="pathDirection" select="$pathDirection"/>
                    <xsl:with-param name="text" select="$text"/>
                </xsl:call-template>
            </xsl:if>
        </xsl:if>
    </xsl:template>

    <!-- Process extended form of text instruction -->
    <xsl:template match='text' mode='textFormat'>
        <xsl:param name='way'/>

        <xsl:apply-templates mode='textFormat'>
            <xsl:with-param name='way' select='$way'/>
        </xsl:apply-templates>
    </xsl:template>


    <!-- Substitute a tag in a text instruction -->
    <xsl:template match='text/tag' mode='textFormat'>
        <xsl:param name='way'/>

        <xsl:variable name='key' select='@k'/>
        <xsl:variable name='value'>
            <xsl:choose>
                <xsl:when test='$key="osm:user"'>
                    <xsl:value-of select='$way/@user'/>
                </xsl:when>
                <xsl:when test='$key="osm:timestamp"'>
                    <xsl:value-of select='$way/@timestamp'/>
                </xsl:when>
                <xsl:when test='$key="osm:id"'>
                    <xsl:value-of select='$way/@id'/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select='$way/tag[@k=$key]/@v'/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:choose>
            <xsl:when test='string($value)'>
                <xsl:value-of select='$value'/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select='@default'/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>



    <!-- Generate a way path for the current way element -->
    <xsl:template name="generateWayPaths">
        <!-- DODI: !!!WORKAROUND!!! skip one node ways -->
        <xsl:if test="count(nd[key('nodeById',@ref)]) &gt; 1">

            <!-- Generate a normal way path -->
            <xsl:variable name="pathWayNormal">
                <xsl:call-template name="generateWayPathNormal"/>
            </xsl:variable>
            <xsl:if test="$pathWayNormal!=''">
                <path id="way_normal_{@id}" d="{$pathWayNormal}"/>
                <path id="x_way_normal_{@id}" d="{$pathWayNormal}"/>
            </xsl:if>

            <!-- Generate a normal way path as area -->
            <!-- DODI: !!!WORKAROUND!!! added to generate "area for all ways, yes it is very dirty... but -->
            <xsl:variable name="pathArea">
                <xsl:call-template name="generateAreaPath"/>
            </xsl:variable>
            <!-- DODI: do not draw empty ways/areas-->
            <xsl:if test ="$pathArea!=''">
                <path id="area_{@id}" d="{$pathArea}"/>
                <path id="x_area_{@id}" d="{$pathArea}"/>
            </xsl:if>
            <!-- Generate a reverse way path (if needed) -->
            <xsl:variable name="pathWayReverse">
                <xsl:choose>
                    <!-- Manual override, reverse direction -->
                    <xsl:when test="tag[@k='name_direction']/@v='-1' or tag[@k='osmarender:x-name-direction']/@v='-1'">
                        <xsl:call-template name="generateWayPathReverse"/>
                    </xsl:when>
                    <!-- Manual override, normal direction -->
                    <xsl:when test="tag[@k='name_direction']/@v='1' or tag[@k='osmarender:x-name-direction']/@v='1'">
                        <!-- Generate nothing -->
                    </xsl:when>
                    <!-- Automatic, reverse direction -->
                    <xsl:when test="(key('nodeById',(nd[key('nodeById',@ref)])[1]/@ref)/@lon &gt; key('nodeById',(nd[key('nodeById',@ref)])[last()]/@ref)/@lon)">
                        <xsl:call-template name="generateWayPathReverse"/>
                    </xsl:when>
                </xsl:choose>
            </xsl:variable>
            <xsl:if test="$pathWayReverse!=''">
                <path id="way_reverse_{@id}" d="{$pathWayReverse}"/>
            </xsl:if>

            <!-- Generate the start, middle and end paths needed for smart-linecaps (TM). -->
            <xsl:variable name="pathWayStart">
                <xsl:call-template name="generatePathWayStart"/>
            </xsl:variable>
            <path id="way_start_{@id}" d="{$pathWayStart}"/>

            <xsl:if test="count(nd[key('nodeById',@ref)]) &gt; 1">
                <xsl:variable name="pathWayMid">
                    <xsl:call-template name="generatePathWayMid"/>
                </xsl:variable>
                <path id="way_mid_{@id}" d="{$pathWayMid}"/>
            </xsl:if>

            <xsl:variable name="pathWayEnd">
                <xsl:call-template name="generatePathWayEnd"/>
            </xsl:variable>
            <path id="way_end_{@id}" d="{$pathWayEnd}"/>
        </xsl:if >
    </xsl:template>


    <!-- Generate a normal way path -->
    <xsl:template name="generateWayPathNormal">
        <xsl:variable name='loop' select='nd[1]/@ref=nd[last()]/@ref'/>
        <xsl:for-each select="nd[key('nodeById',@ref)]">
            <xsl:choose>
                <xsl:when test="position()=1">
                    <xsl:call-template name="moveToNode">
                        <xsl:with-param name="node" select="key('nodeById',@ref)"/>
                    </xsl:call-template>
                </xsl:when>
                <xsl:when test="(position()=last()) and ($loop=1)">
                    <xsl:text>Z</xsl:text>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:call-template name="lineToNode">
                        <xsl:with-param name="node" select="key('nodeById',@ref)"/>
                    </xsl:call-template>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:for-each>
    </xsl:template>


    <!-- Generate a reverse way path -->
    <xsl:template name="generateWayPathReverse">
        <xsl:variable name='loop' select='nd[1]/@ref=nd[last()]/@ref'/>
        <xsl:for-each select="nd[key('nodeById',@ref)]">
            <xsl:sort select="position()" data-type="number" order="descending"/>
            <xsl:choose>
                <xsl:when test="position()=1">
                    <xsl:call-template name="moveToNode">
                        <xsl:with-param name="node" select="key('nodeById',@ref)"/>
                    </xsl:call-template>
                </xsl:when>
                <xsl:when test="(position()=last()) and ($loop=1)">
                    <xsl:text>Z</xsl:text>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:call-template name="lineToNode">
                        <xsl:with-param name="node" select="key('nodeById',@ref)"/>
                    </xsl:call-template>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:for-each>
    </xsl:template>

    <!-- These template generates two paths, one for each end of a way.  
         The line to the first node is cut in two so that the join
         between the two paths is not at an angle.  -->
    <xsl:template name="generatePathWayStart">
        <xsl:call-template name="moveToNode">
            <xsl:with-param name="node" select="key('nodeById',(nd[key('nodeById',@ref)])[1]/@ref)"/>
        </xsl:call-template>
        <xsl:call-template name="lineToMidpointPlus">
            <xsl:with-param name="fromNode" select="key('nodeById',(nd[key('nodeById',@ref)])[1]/@ref)"/>
            <xsl:with-param name="toNode" select="key('nodeById',(nd[key('nodeById',@ref)])[2]/@ref)"/>
        </xsl:call-template>
    </xsl:template>


    <xsl:template name="generatePathWayEnd">
        <xsl:call-template name="moveToMidpointMinus">
            <xsl:with-param name="fromNode" select="key('nodeById',(nd[key('nodeById',@ref)])[position()=(last()-1)]/@ref)"/>
            <xsl:with-param name="toNode" select="key('nodeById',(nd[key('nodeById',@ref)])[position()=last()]/@ref)"/>
        </xsl:call-template>
        <xsl:call-template name="lineToNode">
            <xsl:with-param name="node" select="key('nodeById',(nd[key('nodeById',@ref)])[position()=last()]/@ref)"/>
        </xsl:call-template>
    </xsl:template>

    <xsl:template name="generatePathWayMid">
        <xsl:call-template name="moveToMidpointPlus">
            <xsl:with-param name="fromNode" select="key('nodeById',(nd[key('nodeById',@ref)])[1]/@ref)"/>
            <xsl:with-param name="toNode" select="key('nodeById',(nd[key('nodeById',@ref)])[2]/@ref)"/>
        </xsl:call-template>
        <xsl:for-each select="nd[key('nodeById',@ref)][(position()!=1) and (position()!=last())]">
            <xsl:call-template name="lineToNode">
                <xsl:with-param name="node" select="key('nodeById',@ref)"/>
            </xsl:call-template>
        </xsl:for-each>
        <xsl:call-template name="lineToMidpointMinus">
            <xsl:with-param name="fromNode" select="key('nodeById',(nd[key('nodeById',@ref)])[position()=(last()-1)]/@ref)"/>
            <xsl:with-param name="toNode" select="key('nodeById',(nd[key('nodeById',@ref)])[position()=last()]/@ref)"/>
        </xsl:call-template>
    </xsl:template>

    <!-- Generate an area path for the current area element -->
    <xsl:template name="generateAreaPath">
        <xsl:variable name='relation' select="key('relationByWay',@id)[tag[@k='type' and @v='multipolygon']]"/>
        <xsl:variable name='relation_count' select="count(key('relationByWay',@id)[tag[@k='type' and @v='multipolygon']])"/>
        <xsl:choose>
            <xsl:when test='$relation_count = 0'>
                <!-- Handle simple ways, with no parts of multipologons.-->
                <xsl:call-template name='generateAreaSubPath'>
                    <xsl:with-param name='way' select='.'/>
                    <xsl:with-param name='position' select="'1'"/>
                </xsl:call-template>
                <xsl:text>Z</xsl:text>
                <xsl:message>
                    single way <xsl:value-of select='./@id'/>
                </xsl:message>
            </xsl:when>
            <xsl:when test='$relation_count = 1'>
                <xsl:variable name='wayId' select="./@id"/>
                <xsl:variable name='relation_way_member' select="$relation/member[@type='way'][@ref=$wayId]/@role"/>
                <xsl:message>
                    value of relation_way_member <xsl:value-of select='$relation_way_member'/>
                </xsl:message>
                <xsl:choose>
                    <xsl:when test="$relation_way_member='outer'">
                        <!-- som outer: zrobim cely multipolygon-->
                        <xsl:for-each select="$relation/member[@type='way'][key('wayById', @ref)]">
                            <xsl:call-template name='generateAreaSubPath'>
                                <xsl:with-param name='way' select="key('wayById',@ref)"/>
                                <xsl:with-param name='position' select="position()"/>
                            </xsl:call-template>
                        </xsl:for-each>
                        <xsl:text>Z</xsl:text>
                        <xsl:message>
                            way is outer in one relation only <xsl:value-of select='./@id'/>
                        </xsl:message>
                    </xsl:when>
                    <xsl:otherwise>
                        <!-- som inner: zrobim cely multipolygon-->
                        <xsl:call-template name='generateAreaSubPath'>
                            <xsl:with-param name='way' select='.'/>
                            <xsl:with-param name='position' select="'1'"/>
                        </xsl:call-template>
                        <xsl:text>Z</xsl:text>
                        <xsl:message>
                            way is inner in one relation only <xsl:value-of select='./@id'/>
                        </xsl:message>
                    </xsl:otherwise>
                </xsl:choose >
            </xsl:when>
            <xsl:otherwise>
                <!-- Handle multipolygons.
                     Draw area only once, draw the outer one first if we know which is it, else just draw the first one 
                <xsl:variable name='outerway' select="$relation/member[@type='way'][@role='outer']/@ref"/>
                <xsl:variable name='firsrelationmember' select="$relation/member[@type='way'][key('wayById', @ref)][1]/@ref"/>
                <xsl:if test='( $outerway and $outerway=@id ) or ( not($outerway) and $firsrelationmember=@id )'>
                    <xsl:message>
                        <xsl:value-of select='$relation/@id'/>
                    </xsl:message>
                    <xsl:for-each select="$relation/member[@type='way'][key('wayById', @ref)]">
                        <xsl:call-template name='generateAreaSubPath'>
                            <xsl:with-param name='way' select="key('wayById',@ref)"/>
                            <xsl:with-param name='position' select="position()"/>
                        </xsl:call-template>
                    </xsl:for-each>
                    <xsl:text>Z</xsl:text>
                </xsl:if>-->
                <xsl:message>
                    multiple relation member <xsl:value-of select='./@id'/>
                </xsl:message>

            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:template name='generateAreaMultipolygon'>
        <xsl:param name='way'/>
        <xsl:variable name='relation' select="key('relationByWay',@id)[tag[@k='type' and @v='multipolygon']]"/>
        <xsl:for-each select="$relation/member[@type='way'][key('wayById', @ref)]">
            <xsl:call-template name='generateAreaSubPath'>
                <xsl:with-param name='way' select="key('wayById',@ref)"/>
                <xsl:with-param name='position' select="position()"/>
            </xsl:call-template>
        </xsl:for-each>
        <xsl:text>Z</xsl:text>
    </xsl:template >


    <xsl:template name='generateAreaSubPath'>
        <xsl:param name='way'/>
        <xsl:param name='position'/>

        <xsl:variable name='loop' select='$way/nd[1]/@ref=$way/nd[last()]/@ref'/>
        <xsl:message>
            WayId: <xsl:value-of select='$way/@id'/>
            Closed SubArea Polygon: <xsl:value-of select='$loop'/>
            Loop from: <xsl:value-of select='$way/nd[1]/@ref'/>
            Loop to: <xsl:value-of select='$way/nd[last()]/@ref'/>
        </xsl:message>
        <xsl:for-each select="$way/nd[key('nodeById',@ref)]">
            <xsl:choose>
                <xsl:when test="position()=1 and $loop">
                    <xsl:if test='not($position=1)'>
                        <xsl:text>Z</xsl:text>
                    </xsl:if>
                    <xsl:call-template name="moveToNode">
                        <xsl:with-param name="node" select="key('nodeById',@ref)"/>
                    </xsl:call-template>
                </xsl:when>
                <xsl:when test="$position=1 and position()=1 and not($loop=1)">
                    <xsl:call-template name="moveToNode">
                        <xsl:with-param name="node" select="key('nodeById',@ref)"/>
                    </xsl:call-template>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:call-template name="lineToNode">
                        <xsl:with-param name="node" select="key('nodeById',@ref)"/>
                    </xsl:call-template>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:for-each>
    </xsl:template>

    <!-- Generate a MoveTo command for a node -->
    <xsl:template name="moveToNode">
        <xsl:param name='node' />
        <xsl:variable name="x1" select="($node/@lon*$scale)"/>
        <xsl:variable name="y1" select="($node/@lat*$scale)"/>
        <xsl:text>M</xsl:text>
        <xsl:value-of select="$x1"/>
        <xsl:text> </xsl:text>
        <xsl:value-of select="$y1"/>
    </xsl:template>

    <!-- Generate a LineTo command for a nd -->
    <xsl:template name="lineToNode">
        <xsl:param name='node'/>

        <xsl:variable name="x1" select="($node/@lon*$scale)"/>
        <xsl:variable name="y1" select="($node/@lat*$scale)"/>
        <xsl:text>L</xsl:text>
        <xsl:value-of select="$x1"/>
        <xsl:text> </xsl:text>
        <xsl:value-of select="$y1"/>
    </xsl:template>

    <xsl:template name="lineToMidpointPlus">
        <xsl:param name='fromNode'/>
        <xsl:param name='toNode'/>

        <xsl:variable name="x1" select="($fromNode/@lon*$scale)"/>
        <xsl:variable name="y1" select="($fromNode/@lat*$scale)"/>

        <xsl:variable name="x2" select="($toNode/@lon*$scale)"/>
        <xsl:variable name="y2" select="($toNode/@lat*$scale)"/>

        <xsl:text>L</xsl:text>
        <xsl:value-of select="$x1+(($x2 - $x1) div 1.9)"/>
        <xsl:text> </xsl:text>
        <xsl:value-of select="$y1+(($y2 - $y1) div 1.9)"/>
    </xsl:template>

    <xsl:template name="lineToMidpointMinus">
        <xsl:param name='fromNode'/>
        <xsl:param name='toNode'/>

        <xsl:variable name="x1" select="($fromNode/@lon*$scale)"/>
        <xsl:variable name="y1" select="($fromNode/@lat*$scale)"/>

        <xsl:variable name="x2" select="($toNode/@lon*$scale)"/>
        <xsl:variable name="y2" select="($toNode/@lat*$scale)"/>
        <xsl:text>L</xsl:text>
        <xsl:value-of select="$x1+(($x2 - $x1) div 2.1)"/>
        <xsl:text> </xsl:text>
        <xsl:value-of select="$y1+(($y2 - $y1) div 2.1)"/>
    </xsl:template>


    <xsl:template name="moveToMidpointPlus">
        <xsl:param name='fromNode'/>
        <xsl:param name='toNode'/>

        <xsl:variable name="x1" select="($fromNode/@lon*$scale)"/>
        <xsl:variable name="y1" select="($fromNode/@lat*$scale)"/>

        <xsl:variable name="x2" select="($toNode/@lon*$scale)"/>
        <xsl:variable name="y2" select="($toNode/@lat*$scale)"/>
        <xsl:text>M</xsl:text>
        <xsl:value-of select="$x1+(($x2 - $x1) div 1.9)"/>
        <xsl:text> </xsl:text>
        <xsl:value-of select="$y1+(($y2 - $y1) div 1.9)"/>
    </xsl:template>



    <xsl:template name="moveToMidpointMinus">
        <xsl:param name='fromNode'/>
        <xsl:param name='toNode'/>

        <xsl:variable name="x1" select="($fromNode/@lon*$scale)"/>
        <xsl:variable name="y1" select="($fromNode/@lat*$scale)"/>

        <xsl:variable name="x2" select="($toNode/@lon*$scale)"/>
        <xsl:variable name="y2" select="($toNode/@lat*$scale)"/>
        <xsl:text>M</xsl:text>
        <xsl:value-of select="$x1+(($x2 - $x1) div 2.1)"/>
        <xsl:text> </xsl:text>
        <xsl:value-of select="$y1+(($y2 - $y1) div 2.1)"/>
    </xsl:template>



    <!-- Some attribute shouldn't be copied -->
    <xsl:template match="@type|@ref|@scale|@smart-linecap|@text-prefix|@text-postfix|@bezier-hint|@honor-width|@width-scale-factor|@minimum-width|@maximum-width|@x-line-spacing|@pixel-offset|@k|@v|@textAttenuation|@mask-class" mode="copyAttributes" />

    <!-- Copy all other attributes  -->
    <xsl:template match="@*" mode="copyAttributes">
        <xsl:copy/>
    </xsl:template>


    <!-- Rule processing engine -->

    <!-- 

		Calls all templates inside <rule> tags (including itself, if there are nested rules).

		If the global var withOSMLayers is 'no', we don't care about layers and draw everything
		in one go. This is faster and is sometimes useful. For normal maps you want withOSMLayers
		to be 'yes', which is the default.

	-->
    <xsl:template name="processRules">

        <!-- First select all elements - exclude those marked as deleted by JOSM -->
        <xsl:variable name='elements' select="$data/osm/*[not(@action) or not(@action='delete')]" />

        <xsl:choose>

            <!-- Process all the rules, one layer at a time -->
            <xsl:when test="$withOSMLayers='yes'">
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'-5'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'-4'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'-5'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'-3'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'-4'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'-5'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'-2'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'-3'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'-4'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'-1'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'-2'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'-3'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'0'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'-1'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'-2'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'1'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'0'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'-1'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'2'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'1'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'0'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'3'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'2'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'1'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'4'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'3'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'2'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'4'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPrePreLayer">
                    <xsl:with-param name="layer" select="'5'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'3'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processPreLayer">
                    <xsl:with-param name="layer" select="'5'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'4'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
                <xsl:call-template name="processLayer">
                    <xsl:with-param name="layer" select="'5'"/>
                    <xsl:with-param name="elements" select="$elements"/>
                </xsl:call-template>
            </xsl:when>

            <!-- Process all the rules, without looking at the layers -->
            <xsl:otherwise>
                <xsl:apply-templates select="/rules/rule">
                    <xsl:with-param name="elements" select="$elements"/>
                    <xsl:with-param name="layer" select="'0'"/>
                </xsl:apply-templates>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>



    <xsl:template name="processLayer">
        <xsl:param name="layer"/>
        <xsl:param name="elements"/>
        <g inkscape:groupmode="layer" id="layer{$layer}" inkscape:label="Layer {$layer}">
            <xsl:apply-templates select="/rules/rule">
                <xsl:with-param name="elements" select="$elements"/>
                <xsl:with-param name="layer" select="$layer"/>
            </xsl:apply-templates>
        </g>
    </xsl:template>

    <xsl:template name="processPreLayer">
        <xsl:param name="layer"/>
        <xsl:param name="elements"/>
        <g inkscape:groupmode="layer" id="prelayer{$layer}" inkscape:label="PreLayer {$layer}">
            <xsl:apply-templates select="/rules/prerules/rule">
                <xsl:with-param name="elements" select="$elements"/>
                <xsl:with-param name="layer" select="$layer"/>
            </xsl:apply-templates>
        </g>
    </xsl:template>

    <xsl:template name="processPrePreLayer">
        <xsl:param name="layer"/>
        <xsl:param name="elements"/>
        <g inkscape:groupmode="layer" id="preprelayer{$layer}" inkscape:label="PrePreLayer {$layer}">
            <xsl:apply-templates select="/rules/preprerules/rule">
                <xsl:with-param name="elements" select="$elements"/>
                <xsl:with-param name="layer" select="$layer"/>
            </xsl:apply-templates>
        </g>
    </xsl:template>

    <!-- Process a rule at a specific level -->
    <xsl:template match='rule'>
        <xsl:param name="elements"/>
        <xsl:param name="layer"/>

        <!-- If the rule is for a specific layer and we are processing that layer then pass *all* elements 
		     to the rule, otherwise just select the matching elements for this layer. -->
        <xsl:choose>
            <xsl:when test='$layer=@layer'>
                <xsl:call-template name="rule">
                    <xsl:with-param name="elements" select="$elements"/>
                    <xsl:with-param name="layer" select="$layer"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:if test='not(@layer)'>
                    <xsl:call-template name="rule">
                        <xsl:with-param name="elements" select="$elements[
							tag[@k='layer' and @v=$layer]
							or ($layer='0' and count(tag[@k='layer'])=0)
						]"/>
                        <xsl:with-param name="layer" select="$layer"/>
                    </xsl:call-template>
                </xsl:if>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>


    <xsl:template name='rule'>
        <xsl:param name="elements"/>
        <xsl:param name="layer"/>

        <!-- This is the rule currently being processed -->
        <xsl:variable name="rule" select="."/>

        <!-- Make list of elements that this rule should be applied to -->
        <xsl:variable name="eBare">
            <xsl:choose>
                <xsl:when test="$rule/@e='*'">node|way</xsl:when>
                <xsl:when test="$rule/@e">
                    <xsl:value-of select="$rule/@e"/>
                </xsl:when>
                <xsl:otherwise>node|way</xsl:otherwise>
            </xsl:choose>
        </xsl:variable>

        <!-- List of keys that this rule should be applied to -->
        <xsl:variable name="kBare" select="$rule/@k"/>

        <!-- List of values that this rule should be applied to -->
        <xsl:variable name="vBare" select="$rule/@v"/>
        <xsl:variable name="sBare" select="$rule/@s"/>

        <!-- Top'n'tail selectors with | for contains usage -->
        <xsl:variable name="e">
            |<xsl:value-of select="$eBare"/>|
        </xsl:variable>
        <xsl:variable name="k">
            |<xsl:value-of select="$kBare"/>|
        </xsl:variable>
        <xsl:variable name="v">
            |<xsl:value-of select="$vBare"/>|
        </xsl:variable>
        <xsl:variable name="s">
            |<xsl:value-of select="$sBare"/>|
        </xsl:variable>

        <xsl:variable
			  name="selectedElements"
			  select="$elements[contains($e,concat('|',name(),'|'))
            or 
            (contains($e,'|node|') and name()='way' and key('wayByNode',@id))
            ]"/>


        <!-- Patch $s -->
        <xsl:choose>
            <!-- way selector -->
            <xsl:when test="contains($s,'|way|')">
                <xsl:choose>
                    <!-- every key -->
                    <xsl:when test="contains($k,'|*|')">
                        <xsl:choose>
                            <!-- every key ,no value defined -->
                            <xsl:when test="contains($v,'|~|')">
                                <xsl:variable name="elementsWithNoTags" select="$selectedElements[count(key('wayByNode',@id)/tag)=0]"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$elementsWithNoTags"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:when>
                            <!-- every key ,every value -->
                            <xsl:when test="contains($v,'|*|')">
                                <xsl:variable name="allElements" select="$selectedElements"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$allElements"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:when>
                            <!-- every key , selected values -->
                            <xsl:otherwise>
                                <xsl:variable name="allElementsWithValue" select="$selectedElements[key('wayByNode',@id)/tag[contains($v,concat('|',@v,'|'))]]"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$allElementsWithValue"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:when>
                    <!-- no value  -->
                    <xsl:when test="contains($v,'|~|')">
                        <xsl:variable name="elementsWithoutKey" select="$selectedElements[count(key('wayByNode',@id)/tag[contains($k,concat('|',@k,'|'))])=0]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$elementsWithoutKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:when>
                    <!-- every value  -->
                    <xsl:when test="contains($v,'|*|')">
                        <xsl:variable name="allElementsWithKey" select="$selectedElements[key('wayByNode',@id)/tag[contains($k,concat('|',@k,'|'))]]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$allElementsWithKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:when>

                    <!-- defined key and defined value -->
                    <xsl:otherwise>
                        <xsl:variable name="elementsWithKey" select="$selectedElements[
							key('wayByNode',@id)/tag[
								contains($k,concat('|',@k,'|')) and contains($v,concat('|',@v,'|'))
								]
							]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$elementsWithKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:when>

            <!-- other selector -->
            <xsl:otherwise>
                <xsl:choose>
                    <xsl:when test="contains($k,'|*|')">
                        <xsl:choose>
                            <xsl:when test="contains($v,'|~|')">
                                <xsl:variable name="elementsWithNoTags" select="$selectedElements[count(tag)=0]"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$elementsWithNoTags"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:when>
                            <xsl:when test="contains($v,'|*|')">
                                <xsl:variable name="allElements" select="$selectedElements"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$allElements"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:variable name="allElementsWithValue" select="$selectedElements[tag[contains($v,concat('|',@v,'|'))]]"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$allElementsWithValue"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:when>
                    <xsl:when test="contains($v,'|~|')">
                        <xsl:variable name="elementsWithoutKey" select="$selectedElements[count(tag[contains($k,concat('|',@k,'|'))])=0]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$elementsWithoutKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:when test="contains($v,'|*|')">
                        <xsl:variable name="allElementsWithKey" select="$selectedElements[tag[contains($k,concat('|',@k,'|'))]]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$allElementsWithKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:variable name="elementsWithKey" select="$selectedElements[tag[contains($k,concat('|',@k,'|')) and contains($v,concat('|',@v,'|'))]]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$elementsWithKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>


    <xsl:template match="else">
        <xsl:param name="elements"/>
        <xsl:param name="layer"/>

        <!-- This is the previous rule that is being negated -->
        <!-- TODO: abort if no preceding rule element -->
        <xsl:variable name="rule" select="preceding-sibling::rule[1]"/>

        <!-- Make list of elements that this rule should be applied to -->
        <xsl:variable name="eBare">
            <xsl:choose>
                <xsl:when test="$rule/@e='*'">node|way</xsl:when>
                <xsl:when test="$rule/@e">
                    <xsl:value-of select="$rule/@e"/>
                </xsl:when>
                <xsl:otherwise>node|way</xsl:otherwise>
            </xsl:choose>
        </xsl:variable>

        <!-- List of keys that this rule should be applied to -->
        <xsl:variable name="kBare" select="$rule/@k"/>

        <!-- List of values that this rule should be applied to -->
        <xsl:variable name="vBare" select="$rule/@v"/>
        <xsl:variable name="sBare" select="$rule/@s"/>


        <!-- Top'n'tail selectors with | for contains usage -->
        <xsl:variable name="e">
            |<xsl:value-of select="$eBare"/>|
        </xsl:variable>
        <xsl:variable name="k">
            |<xsl:value-of select="$kBare"/>|
        </xsl:variable>
        <xsl:variable name="v">
            |<xsl:value-of select="$vBare"/>|
        </xsl:variable>
        <xsl:variable name="s">
            |<xsl:value-of select="$sBare"/>|
        </xsl:variable>

        <xsl:variable
			  name="selectedElements"
			  select="$elements[contains($e,concat('|',name(),'|'))
              or 
              (contains($e,'|node|') and name()='way'and key('wayByNode',@id))
              ]"/>

        <!-- Patch $s -->
        <xsl:choose>
            <xsl:when test="contains($s,'|way|')">
                <xsl:choose>
                    <xsl:when test="contains($k,'|*|')">
                        <xsl:choose>
                            <xsl:when test="contains($v,'|~|')">
                                <xsl:variable name="elementsWithNoTags" select="$selectedElements[count(key('wayByNode',@id)/tag)!=0]"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$elementsWithNoTags"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:when>
                            <xsl:when test="contains($v,'|*|')">
                                <!-- no-op! -->
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:variable name="allElementsWithValue" select="$selectedElements[not(key('wayByNode',@id)/tag[contains($v,concat('|',@v,'|'))])]"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$allElementsWithValue"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:when>
                    <xsl:when test="contains($v,'|~|')">
                        <xsl:variable name="elementsWithoutKey" select="$selectedElements[count(key('wayByNode',@id)/tag[contains($k,concat('|',@k,'|'))])!=0]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$elementsWithoutKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:when test="contains($v,'|*|')">
                        <xsl:variable name="allElementsWithKey" select="$selectedElements[not(key('wayByNode',@id)/tag[contains($k,concat('|',@k,'|'))])]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$allElementsWithKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:variable name="elementsWithKey" select="$selectedElements[not(
                         key('wayByNode',@id)/tag[
                            contains($k,concat('|',@k,'|')) and contains($v,concat('|',@v,'|'))
                            ]
                         )]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$elementsWithKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:when>

            <xsl:otherwise>
                <!-- not contains $s -->
                <xsl:choose>
                    <xsl:when test="contains($k,'|*|')">
                        <xsl:choose>
                            <xsl:when test="contains($v,'|~|')">
                                <xsl:variable name="elementsWithNoTags" select="$selectedElements[count(tag)!=0]"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$elementsWithNoTags"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:when>
                            <xsl:when test="contains($v,'|*|')">
                                <!-- no-op! -->
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:variable name="allElementsWithValue" select="$selectedElements[not(tag[contains($v,concat('|',@v,'|'))])]"/>
                                <xsl:call-template name="processElements">
                                    <xsl:with-param name="eBare" select="$eBare"/>
                                    <xsl:with-param name="kBare" select="$kBare"/>
                                    <xsl:with-param name="vBare" select="$vBare"/>
                                    <xsl:with-param name="layer" select="$layer"/>
                                    <xsl:with-param name="elements" select="$allElementsWithValue"/>
                                    <xsl:with-param name="rule" select="$rule"/>
                                </xsl:call-template>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:when>
                    <xsl:when test="contains($v,'|~|')">
                        <xsl:variable name="elementsWithoutKey" select="$selectedElements[count(tag[contains($k,concat('|',@k,'|'))])!=0]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$elementsWithoutKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:when test="contains($v,'|*|')">
                        <xsl:variable name="allElementsWithKey" select="$selectedElements[not(tag[contains($k,concat('|',@k,'|'))])]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$allElementsWithKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:variable name="elementsWithKey" select="$selectedElements[not(tag[contains($k,concat('|',@k,'|')) and contains($v,concat('|',@v,'|'))])]"/>
                        <xsl:call-template name="processElements">
                            <xsl:with-param name="eBare" select="$eBare"/>
                            <xsl:with-param name="kBare" select="$kBare"/>
                            <xsl:with-param name="vBare" select="$vBare"/>
                            <xsl:with-param name="layer" select="$layer"/>
                            <xsl:with-param name="elements" select="$elementsWithKey"/>
                            <xsl:with-param name="rule" select="$rule"/>
                        </xsl:call-template>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>


    <xsl:template name="processElements">
        <xsl:param name="eBare"/>
        <xsl:param name="kBare"/>
        <xsl:param name="vBare"/>
        <xsl:param name="layer"/>
        <xsl:param name="elements"/>
        <xsl:param name="rule"/>


        <xsl:if test="$elements">

            <!-- elementCount is the number of elements we started with (just used for the progress message) -->
            <xsl:variable name="elementCount" select="count($elements)"/>
            <!-- If there's a proximity attribute on the rule then filter elements based on proximity -->
            <xsl:choose>
                <xsl:when test='$rule/@verticalProximity'>
                    <xsl:variable name='nearbyElements1'>
                        <xsl:call-template name="proximityFilter">
                            <xsl:with-param name="elements" select="$elements"/>
                            <xsl:with-param name="horizontalProximity" select="$rule/@horizontalProximity div 32"/>
                            <xsl:with-param name="verticalProximity" select="$rule/@verticalProximity div 32"/>
                        </xsl:call-template>
                    </xsl:variable>
                    <xsl:variable name='nearbyElements2'>
                        <xsl:call-template name="proximityFilter">
                            <xsl:with-param name="elements" select="exslt:node-set($nearbyElements1)/*"/>
                            <xsl:with-param name="horizontalProximity" select="$rule/@horizontalProximity div 16"/>
                            <xsl:with-param name="verticalProximity" select="$rule/@verticalProximity div 16"/>
                        </xsl:call-template>
                    </xsl:variable>
                    <xsl:variable name='nearbyElements3'>
                        <xsl:call-template name="proximityFilter">
                            <xsl:with-param name="elements" select="exslt:node-set($nearbyElements2)/*"/>
                            <xsl:with-param name="horizontalProximity" select="$rule/@horizontalProximity div 8"/>
                            <xsl:with-param name="verticalProximity" select="$rule/@verticalProximity div 8"/>
                        </xsl:call-template>
                    </xsl:variable>
                    <xsl:variable name='nearbyElements4'>
                        <xsl:call-template name="proximityFilter">
                            <xsl:with-param name="elements" select="exslt:node-set($nearbyElements3)/*"/>
                            <xsl:with-param name="horizontalProximity" select="$rule/@horizontalProximity div 4"/>
                            <xsl:with-param name="verticalProximity" select="$rule/@verticalProximity div 4"/>
                        </xsl:call-template>
                    </xsl:variable>
                    <xsl:variable name='nearbyElements5'>
                        <xsl:call-template name="proximityFilter">
                            <xsl:with-param name="elements" select="exslt:node-set($nearbyElements4)/*"/>
                            <xsl:with-param name="horizontalProximity" select="$rule/@horizontalProximity div 2"/>
                            <xsl:with-param name="verticalProximity" select="$rule/@verticalProximity div 2"/>
                        </xsl:call-template>
                    </xsl:variable>
                    <xsl:variable name='nearbyElementsRtf'>
                        <xsl:call-template name="proximityFilter">
                            <xsl:with-param name="elements" select="exslt:node-set($nearbyElements5)/*"/>
                            <xsl:with-param name="horizontalProximity" select="$rule/@horizontalProximity"/>
                            <xsl:with-param name="verticalProximity" select="$rule/@verticalProximity"/>
                        </xsl:call-template>
                    </xsl:variable>

                    <!-- Convert nearbyElements rtf to a node-set -->
                    <xsl:variable name="nearbyElements" select="exslt:node-set($nearbyElementsRtf)/*"/>

                    <xsl:message>
                        Processing &lt;rule e="<xsl:value-of select="$eBare"/>" k="<xsl:value-of select="$kBare"/>" v="<xsl:value-of select="$vBare"/>"
                        horizontalProximity="<xsl:value-of select="$rule/@horizontalProximity"/>" verticalProximity="<xsl:value-of select="$rule/@verticalProximity"/>" &gt;
                        Matched by <xsl:value-of select="count($nearbyElements)"/> out of <xsl:value-of select="count($elements)"/> elements for layer <xsl:value-of select="$layer"/>.
                    </xsl:message>

                    <xsl:apply-templates select="*">
                        <xsl:with-param name="layer" select="$layer"/>
                        <xsl:with-param name="elements" select="$nearbyElements"/>
                        <xsl:with-param name="rule" select="$rule"/>
                    </xsl:apply-templates>
                </xsl:when>
                <xsl:otherwise>

                    <xsl:message>
                        Processing &lt;rule e="<xsl:value-of select="$eBare"/>" k="<xsl:value-of select="$kBare"/>" v="<xsl:value-of select="$vBare"/>" &gt;
                        Matched by <xsl:value-of select="count($elements)"/> elements for layer <xsl:value-of select="$layer"/>.
                    </xsl:message>

                    <xsl:apply-templates select="*">
                        <xsl:with-param name="layer" select="$layer"/>
                        <xsl:with-param name="elements" select="$elements"/>
                        <xsl:with-param name="rule" select="$rule"/>
                    </xsl:apply-templates>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:if>
    </xsl:template>


    <!-- Select elements that are not within the specified distance from any other element -->
    <xsl:template name="proximityFilter">
        <xsl:param name="elements"/>
        <xsl:param name="horizontalProximity"/>
        <xsl:param name="verticalProximity"/>

        <!-- Offsetting the rectangle to the right gives better results when there are a solitary pair of adjacent elements.  
         One will get selected but the other won't.  Without the offset neither will get selected.  -->
        <xsl:variable name="topOffset" select="90  + $verticalProximity"/>
        <xsl:variable name="bottomOffset" select="90  - $verticalProximity"/>
        <xsl:variable name="leftOffset" select="180 - ($horizontalProximity * 0.5)"/>
        <xsl:variable name="rightOffset" select="180 + ($horizontalProximity * 1.5)"/>

        <!-- Test each element to see if it is near any other element -->
        <xsl:for-each select="$elements">
            <xsl:variable name="id" select="@id"/>
            <xsl:variable name="top"    select="@lat + $topOffset"/>
            <xsl:variable name="bottom" select="@lat + $bottomOffset"/>
            <xsl:variable name="left"   select="@lon + $leftOffset"/>
            <xsl:variable name="right"  select="@lon + $rightOffset"/>
            <!-- Iterate through all of the elements currently selected and if there are no elements other 
           than the current element in the rectangle then select this element -->
            <xsl:if test="not($elements[not(@id=$id) 
                                  and (@lon+180) &lt; $right
                                  and (@lon+180) &gt; $left 
                                  and (@lat+90)  &lt; $top 
                                  and (@lat+90)  &gt; $bottom
                                  ]
                        )">
                <xsl:copy-of select="."/>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>


    <!-- Draw SVG layers -->
    <xsl:template match="layer">
        <xsl:param name="elements"/>
        <xsl:param name="layer"/>
        <xsl:param name="rule"/>

        <xsl:message>
            Processing SVG layer: <xsl:value-of select="@name"/> (at OSM layer <xsl:value-of select="$layer"/>)
        </xsl:message>

        <xsl:variable name="opacity">
            <xsl:if test="@opacity">
                <xsl:value-of select="concat('opacity:',@opacity,';')"/>
            </xsl:if>
        </xsl:variable>

        <xsl:variable name="filter">
            <xsl:if test="@filter">
                <xsl:value-of select="concat('filter:url(#',@filter,');')"/>
            </xsl:if>
        </xsl:variable>

        <xsl:variable name="display">
            <xsl:if test="(@display='none') or (@display='off')">
                <xsl:text>display:none;</xsl:text>
            </xsl:if>
        </xsl:variable>

        <g inkscape:groupmode="layer" id="{@name}-{$layer}" inkscape:label="{@name}">
            <xsl:if test="concat($opacity,$display,$filter)!=''">
                <xsl:attribute name="style">
                    <xsl:value-of select="concat($opacity,$display,$filter)"/>
                </xsl:attribute>
            </xsl:if>
            <xsl:if test="@transfrom">
                <xsl:attribute name="transform">
                    <xsl:value-of select="@transform"/>
                </xsl:attribute>
            </xsl:if>
            <xsl:apply-templates select="*">
                <xsl:with-param name="layer" select="$layer"/>
                <xsl:with-param name="elements" select="$elements"/>
            </xsl:apply-templates>
        </g>
    </xsl:template>


    <!-- Create a comment in SVG source code and RDF description of license -->
    <xsl:template name="metadata">

        <xsl:comment>

            Copyright (c) <xsl:value-of select="$year"/> OpenStreetMap
            www.openstreetmap.org
            This work is licensed under the
            Creative Commons Attribution-ShareAlike 2.0 License.
            http://creativecommons.org/licenses/by-sa/2.0/

        </xsl:comment>
        <metadata id="metadata">
            <rdf:RDF xmlns="http://web.resource.org/cc/">
                <cc:Work rdf:about="">
                    <cc:license rdf:resource="http://creativecommons.org/licenses/by-sa/2.0/"/>
                    <dc:format>image/svg+xml</dc:format>
                    <dc:type rdf:resource="http://purl.org/dc/dcmitype/StillImage"/>
                    <dc:title>
                        <xsl:value-of select="$title"/>
                    </dc:title>
                    <dc:date>
                        <xsl:value-of select="$date"/>
                    </dc:date>
                    <dc:source>http://www.openstreetmap.org/</dc:source>
                </cc:Work>
                <cc:License rdf:about="http://creativecommons.org/licenses/by-sa/2.0/">
                    <cc:permits rdf:resource="http://web.resource.org/cc/Reproduction"/>
                    <cc:permits rdf:resource="http://web.resource.org/cc/Distribution"/>
                    <cc:permits rdf:resource="http://web.resource.org/cc/DerivativeWorks"/>
                    <cc:requires rdf:resource="http://web.resource.org/cc/Notice"/>
                    <cc:requires rdf:resource="http://web.resource.org/cc/Attribution"/>
                    <cc:requires rdf:resource="http://web.resource.org/cc/ShareAlike"/>
                </cc:License>
            </rdf:RDF>
        </metadata>
    </xsl:template>

</xsl:stylesheet>
