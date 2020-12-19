#
#
# original PERL osm module by gary68
# changes (to fit freemap.sk requirements) by MiMiNo
#
# !!! store as Freemap.pm in folder Geo/OSM in lib directory !!!
#
# This module contains a lot of useful functions for working with osm files and data. It also
# includes functions for calculation and output.
#
#
# Copyright (C) 2008, 2009, 2010 Gerhard Schwanz, 2013-2014 Tibor Jamecny
#
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the 
# Free Software Foundation; either version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or 
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program; if not, see <http://www.gnu.org/licenses/>
#
#
# Version 8.4-freemap1
# - removed unnecessary functions
# - added access to <bounds> attributes
# - added option to write OSM files
# - use hash for tags
#
# USAGE
#
# closeOsmFile()
# getBounds()			> (minLon, minLat, maxLon, maxLat)
# getNode3()			> (\%nodeProperties \%nodeTags)
# getRelation3()		> (\%relProperties, \@members, \%relTags)
# getWay3()				> (\%wayProperties, \@nodes, \%wayTags)
# openOsmFile($file)	> osm file open and $line set to the first node (*.osm)
# readOsmFile($file)	> (\%nodes, \%ways, \%relations)
# writeOsmFile($file)	> write nodes, ways and relations to a file
#

package Geo::OSM::Freemap;

use strict;
use warnings;

use LWP::Simple;
use Encode qw(encode);

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION = '8.4-freemap1';

require Exporter;

@ISA = qw(Exporter AutoLoader);

@EXPORT = qw(APIget readOsmFile readOsmData writeOsmFile);

#my $apiUrl = "http://www.openstreetmap.org/api/0.6/";	# way/Id
my $apiUrl = "http://trapi.freemap.sk/trapi/api/0.6/map/";	# way/Id
our $line;
my $defaultPropRef = {
		"timestamp" => "",
		"uid" => "0",
		"user" => "",
		"visible" => "true",
		"version" => "1",
		"changeset" => "1",
	};

########
# file #
########
sub openOsmFile {
	my $fileIn = shift;
	my $osmFileHeader = '';
	my $attrsRequired = 1;
	my @bounds;

	nextLine($fileIn);
	while (defined($line) and !(grep /\<node/, $line)) {
		if (grep /\<\?xml /, $line) { $osmFileHeader .= $line; }
		if (grep /\<osm /, $line) {
			$osmFileHeader .= $line;
			my ($osmFileVersion) = ($line =~ / version=[\'\"](.+?)[\'\"]/);
			if ($osmFileVersion eq "0.5") { $attrsRequired = 0; }
			($osmFileVersion) = ($line =~ / version=[\'\"](.+?)[\'\"]/);
		}
		if (grep /\<bounds /, $line) {
			$osmFileHeader .= $line;
			@bounds = getBounds($line);
		}
		nextLine($fileIn);
		#print "LINE: $line";
	}
	return ($osmFileHeader, $attrsRequired, \@bounds);
}

sub readOsmFile {
	my ($fileName) = @_;
	open(my $fileIn, "<", $fileName) or die "Can't open osm file";
	return readOsmFileHandle($fileIn);
}
	
sub readOsmData {
	my ($content) = @_;
	open(my $dataIn, "<", \$content) or die "Can't open osm data!";
	return readOsmFileHandle($dataIn);
	close($dataIn);
}

sub readOsmFileHandle {
	my ($fileIn) = @_;
	my ($header, $attrsRequired, $bounds) = openOsmFile($fileIn);
	my $ndRef = {};
	my $wayRef = {};
	my $relRef = {};
	if (defined $line) {
		readNodes($fileIn, $ndRef, $attrsRequired);
		readWays($fileIn, $wayRef, $attrsRequired);
		readRelations($fileIn, $relRef, $attrsRequired);
	}
	close($fileIn);
	return ($ndRef, $wayRef, $relRef, $header, $bounds, $attrsRequired);
}

sub readNodes {
	my ($fileIn, $ndRef, $attrsRequired) = @_;
	my ($props, $tags) = getNode3($fileIn, $attrsRequired);
	while (defined $props) {
		$ndRef->{$props->{id}}->{pr} = $props;
		if (%$tags) {	# if there are no tags, do not store an empty hash
			$ndRef->{$props->{id}}->{tg} = $tags;
		}
		($props, $tags) = getNode3($fileIn, $attrsRequired);
	}
}

sub readWays {
	my ($fileIn, $wayRef, $attrsRequired) = @_;
	my ($props, $items, $tags) = getWay3($fileIn, $attrsRequired);
	while (defined $props) {
		$wayRef->{$props->{id}} = { 'pr' => $props, 'nd' => $items, 'tg' => $tags };
		($props, $items, $tags) = getWay3($fileIn, $attrsRequired);
	}
}

sub readRelations {
	my ($fileIn, $relRef, $attrsRequired) = @_;
	my ($props, $items, $tags) = getRelation3($fileIn, $attrsRequired);
	while (defined $props) {
		$relRef->{$props->{id}} = { 'pr' => $props, 'mb' => $items, 'tg' => $tags };
		($props, $items, $tags) = getRelation3($fileIn, $attrsRequired);
	}
}

sub writeOsmFile {
	my ($writeFileName, $writeNdRef, $writeWayRef, $writeRelRef, $writeHeader, $attrsRequired) = @_;
	open(my $fileOut, ">", $writeFileName) or die "Can't write osm file";
	print $fileOut $writeHeader;
	writeOsmObjects($fileOut, "node", $writeNdRef, $attrsRequired);
	writeOsmObjects($fileOut, "way", $writeWayRef, $attrsRequired);
	writeOsmObjects($fileOut, "relation", $writeRelRef, $attrsRequired);
	print $fileOut "</osm>\n";
	close($fileOut);
}

sub writeOsmObjects {
	my ($fileOut, $osmType, $href, $attrsRequired) = @_;
	for my $osmObjId (sort {$a <=> $b} keys %$href) {
		if (defined($osmObjId)) {
			print $fileOut "<$osmType ";
			writeOsmObjProps($fileOut, $href->{$osmObjId}->{pr}, $attrsRequired);
			if (!(defined $href->{$osmObjId}->{mb}) and
				!(defined $href->{$osmObjId}->{nd}) and
				!(defined $href->{$osmObjId}->{tg})) { print $fileOut "/>\n"; }
			else {
				print $fileOut ">\n";
				if (defined $href->{$osmObjId}->{mb}) {
					writeOsmObjMembers($fileOut, $href->{$osmObjId}->{mb});
				}
				if (defined $href->{$osmObjId}->{nd}) {
					writeOsmObjNodes($fileOut, $href->{$osmObjId}->{nd});
				}
				if (defined $href->{$osmObjId}->{tg}) {
					writeOsmObjTags($fileOut, $href->{$osmObjId}->{tg});
				}
				print $fileOut "</$osmType>\n";
			}
		}
	}
}

sub writeOsmObjProps {
	my ($fileOut, $propRef, $attrsRequired) = @_;
	my @props = ("id", "timestamp", "uid", "user", "visible", "version", "changeset", "lat", "lon");
	for my $prop (@props) {
		if (defined $propRef->{$prop}) { print $fileOut "$prop=\"$propRef->{$prop}\" "; }
		elsif ($attrsRequired) {
			if (!($prop eq "lat") and !($prop eq "lon") and !($prop eq "changeset")) {
				print $fileOut "$prop=\"$defaultPropRef->{$prop}\" ";
			}
		}
	}
}

sub writeOsmObjMembers {
	my ($fileOut, $members) = @_;
	for my $membArr (@$members) {
		if (defined($membArr) and (@$membArr > 0)) {
			print $fileOut "<member type=\"$membArr->[0]\" ref=\"$membArr->[1]\" role=\"$membArr->[2]\" />\n";
		}	
	}
}

sub writeOsmObjNodes {
	my ($fileOut, $nodes) = @_;
	for my $nodeId (@$nodes) {
		print $fileOut "<nd ref=\"$nodeId\" />\n" if (defined($nodeId));
	}
}

sub writeOsmObjTags {
	my ($fileOut, $tagRef) = @_;
	for my $tagKey (sort keys %$tagRef) {
		print $fileOut "<tag k=\"$tagKey\" v=\"$tagRef->{$tagKey}\" />\n";
	}
}

sub getBounds {
	my ($data) = @_;
	my ($minlat) = ($data =~ / minlat=[\'\"](.+?)[\'\"]/);
	my ($minlon) = ($data =~ / minlon=[\'\"](.+?)[\'\"]/);
	my ($maxlat) = ($data =~ / maxlat=[\'\"](.+?)[\'\"]/);
	my ($maxlon) = ($data =~ / maxlon=[\'\"](.+?)[\'\"]/);
	# switch position of lat/lon, so it is compatible with other functions
	return ($minlon, $minlat, $maxlon, $maxlat);
}

sub nextLine {
	my ($fileIn) = @_;
	do {
		$line = <$fileIn>;
	} while ((defined $line) and ($line =~ /^<!--/));
}

#########
# NODES #
#########
sub getNode3 {
	my ($fileIn, $attrsRequired) = @_;	
	my $ref0; my $ref1;
	if ($line =~ /^\s*\<node/) {
		($ref0, $ref1) = readNode($fileIn, $attrsRequired);
	}
	else {
		return (undef, undef);
	}
	return ($ref0, $ref1);
} # getNode3

sub readNode {
	my ($fileIn, $attrsRequired) = @_;	
	my $id;
	my $propRef = ();
	my %nodeTags = ();

	($id) = ($line =~ / id=[\'\"](.+?)[\'\"]/);

	if (!defined $id) {
		print "WARNING reading osm file, line follows (expecting id, lon, lat and user for node):\n", $line, "\n" ; 
	}
	else {
		$propRef = getProperties($line, "node", $id, $attrsRequired);
		if ((grep (/"\s*>/, $line)) or (grep (/'\s*>/, $line))) { # more lines, get tags
			nextLine($fileIn) ;
			while (!grep(/<\/node>/, $line)) {
				my ($k, $v) = ($line =~ /^\s*\<tag k=[\'\"](.+)[\'\"]\s*v=[\'\"](.+)[\'\"]/);
				if ((defined ($k)) and (defined ($v))) {
					$nodeTags{$k} = $v;
				}
				else {
					#print "WARNING tag not recognized: ", $line, "\n";
				}
				nextLine($fileIn);
			}
			nextLine($fileIn);
		}
		else {
			nextLine($fileIn);
		}
	}
	return ($propRef, \%nodeTags);
}

sub getProperties {
	my ($line, $type, $id, $attrsRequired) = @_;
	my $version; my $timestamp; my $uid; my $lon; my $lat; my $u; my $cs; my $visible;
	my %properties = ();
	($u) = ($line =~ / user=[\'\"](.+?)[\'\"]/);
	($version) = ($line =~ / version=[\'\"](.+?)[\'\"]/);
	($timestamp) = ($line =~ / timestamp=[\'\"](.+?)[\'\"]/);
	($uid) = ($line =~ / uid=[\'\"](.+?)[\'\"]/);
	($cs) = ($line =~ / changeset=[\'\"](.+?)[\'\"]/);
	($visible) = ($line =~ / visible=[\'\"](.+?)[\'\"]/);

	if ($attrsRequired) {	# fill missing attributes
		if (!defined $u) { $u = "undefined"; }
		if (!defined $version) { $version = "0"; }
		if (!defined $uid) { $uid = 0; }
		if (!defined $timestamp) { $timestamp = ""; }
		if (!defined $cs) { $cs = ""; }
		if (!defined $visible) { $visible = "true"; }
	}
	$properties{"id"} = $id;
	if (defined $u) { $properties{"user"} = $u; }
	if (defined $uid) { $properties{"uid"} = $uid; }
	if (defined $version) { $properties{"version"} = $version; }
	if (defined $timestamp) { $properties{"timestamp"} = $timestamp; }
	if (defined $cs) { $properties{"changeset"} = $cs; }
	if (defined $visible) { $properties{"visible"} = $visible; }
	if ($type eq "node") {
		($lon) = ($line =~ / lon=[\'\"](.+?)[\'\"]/);
		($lat) = ($line =~ / lat=[\'\"](.+?)[\'\"]/);
		if (!defined $lon) { $lon = 0; }
		if (!defined $lat) { $lat = 0; }
		$properties{"lon"} = $lon;
		$properties{"lat"} = $lat;
	}
	return (\%properties);
}

########
# WAYS #
########
sub getWay3 {
	my ($fileIn, $attrsRequired) = @_;
	my $ref0; my $ref1; my $ref3;
	if ($line =~ /^\s*\<way/) {
		($ref0, $ref1, $ref3) = readWay($fileIn, $attrsRequired);
	}
	else {
		return (undef, undef, undef);
	}
	return ($ref0, $ref1, $ref3);
}

sub readWay {
	my ($fileIn, $attrsRequired) = @_;
	my @gNodes = (); my %gTags = ();
	my $propRef;

	my ($id) = ($line =~ / id=[\'\"](.+?)[\'\"]/);
	if (!defined $id) {
		print "WARNING reading osm file, line follows :\n", $line, "\n";
	}
	else {
		$propRef = getProperties($line, "way", $id, $attrsRequired);

		if (!grep /\/>/, $line) {
			nextLine($fileIn);
			while (not($line =~ /\/way>/)) { # more way data
				#get nodes and type
				my ($node) = ($line =~ /^\s*\<nd ref=[\'\"]([\d\-]+)[\'\"]/); # get node id
				my ($k, $v) = ($line =~ /^\s*\<tag k=[\'\"](.+)[\'\"]\s*v=[\'\"](.+)[\'\"]/);

				if (!(($node) or ($k and defined($v)))) {
					#print "WARNING tag not recognized", $line, "\n";
				}

				if ($node) {
					push @gNodes, $node;
				}

				#get tags
				if ($k and defined($v)) {
					$gTags{$k} = $v;
				}
				nextLine($fileIn);
			}
		}
		nextLine($fileIn);
	}
	return ($propRef, \@gNodes, \%gTags);
}

#############
# RELATIONS #
#############

sub getRelation3 {
	my ($fileIn, $attrsRequired) = @_;
	my $ref0; my $ref1; my $ref2;
	if ($line =~ /^\s*\<relation/) {
		($ref0, $ref1, $ref2) = readRelation($fileIn, $attrsRequired);
	}
	else {
		return (undef, undef, undef);
	}
	return ($ref0, $ref1, $ref2);
}

sub readRelation {
	my ($fileIn, $attrsRequired) = @_;
	my $propRef; my %gTags; my @gMembers;

	my ($id) = ($line =~ / id=[\'\"](.+?)[\'\"]/);

	if (!defined $id) {
		print "ERROR: $line\n";
	}
	else {
		$propRef = getProperties($line, "relation", $id, $attrsRequired);
		if (!grep /\/>/, $line) {
			nextLine($fileIn);
			while (not($line =~ /\/relation>/)) { # more data
				if ($line =~ /<member/) {
					my ($memberType) = ($line =~ /^\s*\<member type=[\'\"]([\w]*)[\'\"]/);
					my ($memberRef) = ($line =~ /^.+ref=[\'\"]([\d\-]+)[\'\"]/);
					my ($memberRole) = ($line =~ /^.+role=[\'\"](.*)[\'\"]/);
					if (!$memberRole) { $memberRole = "none"; }
					my @member = [$memberType, $memberRef, $memberRole];
					push @gMembers, @member;
				}
				if ($line =~ /<tag/) {
					my ($k, $v) = ($line =~ /^\s*\<tag k=[\'\"](.+)[\'\"]\s*v=[\'\"](.+)[\'\"]/);
					if (!($k and defined($v))) {
						$k = "unknown";
						$v = "unknown";
					}
					$gTags{$k} = $v;
				}
				nextLine($fileIn);
			}
		}
		nextLine($fileIn);
	}
	return ($propRef, \@gMembers, \%gTags);
}

#######
# API #
#######
sub APIget {
    my ($osmType, $osmId) = @_;

    my $content;
    my $try = 0;

    my $url = $apiUrl . $osmType . "/" . $osmId;
    while ((!defined($content)) and ($try < 4)) {
        $content = get $url;
        $try++;
    }

    #print "API result:\n$content\n\n";

    if (!defined $content) {
        print "ERROR: error receiving OSM query result for $osmType with ID: $osmId\n";
		return (undef, undef, undef, undef, undef);
    }
    if (grep(/<error>/, $content)) {
        print "ERROR: invalid OSM query result for $osmType with ID: $osmId\n" ;
		return (undef, undef, undef, undef, undef);
    }
    return readOsmData(encode('UTF-8', $content));
}

# -------------------------------------------------------------------------------

1;

