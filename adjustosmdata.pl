#!/usr/bin/perl

use strict;
use warnings;

use Geo::OSM::Freemap;
use Getopt::Long qw(:config no_ignore_case);

my $actions = "";
my $debug = 0;
my $inFile = "";
my $outFile = "";

my @allowedHikingSymbols = qw(cave edu education interesting_object local major none peak roundtrip ruin shelter spring stripe yes);

# read the input parameters
GetOptions (
	"actions=s" => \$actions,
	"debug" => \$debug,
	"in-file=s" => \$inFile,
	"out-file=s" => \$outFile)
or die("Error in command line arguments!\n");

# define actions
my $addFmRelTags = 0;
my $joinMpMembers = 0;
my $cropToBbox = 0;
my $isolateMpMembers = 0;

# verify the specified actions
for my $action (split(/,/, $actions)) {
	if ($action eq "addfmrel") { $addFmRelTags = 1; }
	elsif ($action eq "joinmpmembers") { $joinMpMembers = 1; }
	elsif ($action eq "crop") { $cropToBbox = 1; }
	elsif ($action eq "isolatempmembers") { $isolateMpMembers = 1; }
	else { die("Unknown action: \"$action\"\n"); }
}

# verify the input/output file
if ($inFile eq "") { die("Input file not specified!\n"); }
elsif (! -s $inFile) { die("Input file \"$inFile\" does not exist or is empty!\n"); }
if ($outFile eq "") { die("Output file not specified!\n"); }

# global variable
my $newWayIdValue = -1;
# read OSM file
my ($nodesAll, $waysAll, $relsAll, $header, $bounds, $attrsRequired) = readOsmFile($inFile);

if ($addFmRelTags) {
	print("##### Adding FmRel tags from relations to ways #####\n") if ($debug);
	addFmRelTags($waysAll, $relsAll);
}
if ($joinMpMembers) {
	print("##### Joining Multipolygons members #####\n") if ($debug);
	joinMultipolygonMembers($nodesAll, $waysAll, $relsAll);
}
if ($cropToBbox) {
	print("##### Cropping data to the BBOX #####\n") if ($debug);
	cropToArea($nodesAll, $waysAll, $relsAll, $bounds);
}
if ($isolateMpMembers) {
	print("##### Isolating inner from outer members #####\n") if ($debug);
	isolateMultipolygonMembers($waysAll, $relsAll);
}
# write OSM file
writeOsmFile($outFile, $nodesAll, $waysAll, $relsAll, $header, $attrsRequired);

################################################################################
####################           ADDING FMREL TAGS            ####################
################################################################################
sub addFmRelTags {
	my ($ways, $rels) = @_;
	my ($fmRelTags) = collectFmRelTags($rels);
	deleteOldFmRelTags($ways);
	addFmRelTagsToWays($fmRelTags, $ways);
}

sub addFmRelTagsToWays {
	my ($tags, $ways) = @_;
	for my $wayId (keys(%$tags)) {
		if (defined($ways->{$wayId})) {	# add all fmrel* tags
			for my $key (keys(%{$tags->{$wayId}})) {
				$ways->{$wayId}->{tg}->{$key} = $tags->{$wayId}->{$key};
			}
		}
	}
}

sub addNewTags2Cache {
	my ($destTags, $newTags, $relItems) = @_;

	for my $itemArr (@$relItems) {
		if ($itemArr->[0] eq "way") {
			my $wayId = $itemArr->[1];
			if (!defined($destTags->{$wayId})) { $destTags->{$wayId} = {}; }
			my $wayTags = $destTags->{$wayId};
			for my $tag (keys(%$newTags)) {
				if (index($tag, "ref") != -1) {	# add Ref to an array
					if (!defined($wayTags->{$tag})) { $wayTags->{$tag} = (); }
					push @{$wayTags->{$tag}}, $newTags->{$tag};
				}
				else { $wayTags->{$tag} = $newTags->{$tag}; }
			}
		}
	}
}

sub collectFmRelAdminTags {
	my ($destTags, $rel) = @_;

	if (hasTagWithValue($rel, "boundary", "administrative") and hasTag($rel, "admin_level")) {
		my $relTags = $rel->{tg};
		my $admName = "";
		my $admLevel = $relTags->{"admin_level"};
		if (defined($relTags->{"name"})) { $admName = $relTags->{"name"}; }
		for my $itemArr (@{$rel->{mb}}) {
			if ($itemArr->[0] eq "way") {
				my $wayId = $itemArr->[1];
				if (!defined($destTags->{$wayId})) { $destTags->{$wayId} = {}; }
				my $wayTags = $destTags->{$wayId};
				if (!defined($wayTags->{"fmreladminlevel"}) or
						($wayTags->{"fmreladminlevel"} > $admLevel)) {
					$wayTags->{"fmreladminlevel"} = $admLevel;
					if ($admName ne "") { $wayTags->{"fmreladminname"} = $admName; }
				}
			}
		}
	}
}

sub collectFmRelRouteTags {
	my ($destTags, $rel) = @_;
	our $dispatchTable ||= {
		bicycle => \&getFmRelBicycleTags,
		bus		=> \&getFmRelBusTags,
		foot	=> \&getFmRelFootTags,
		hiking	=> \&getFmRelHikingTags,
		horse	=> \&getFmRelHorseTags,
		mtb		=> \&getFmRelMtbTags,
		ski		=> \&getFmRelSkiTags,
		tram	=> \&getFmRelTramTags,
		trolleybus => \&getFmRelTrolleybusTags
	};

	my $relTags = $rel->{tg};
	#print $rel->{pr}->{id} . "\n";

	my $action = $relTags->{"route"};
	if (defined($dispatchTable->{$action})) {
		my $newTags = $dispatchTable->{$action}->($relTags);
		addNewTags2Cache($destTags, $newTags, $rel->{mb});
	}
}

sub collectFmRelTags {
	my ($rels) = @_;
	my $tags = {};

	for my $relId (keys(%$rels)) {
		my $tmpRel = $rels->{$relId};
		if (hasTagWithValue($tmpRel, "type", "route") and hasTag($tmpRel, "route")) {
			print("Collecting Route tags for relation " . $relId . "\n") if ($debug);
			collectFmRelRouteTags($tags, $tmpRel);
		} elsif (hasTagWithValue($tmpRel, "type", "boundary")) {
			print("Collecting Admin tags for relation " . $relId . "\n") if ($debug);
			collectFmRelAdminTags($tags, $tmpRel);
		}
	}
	convertArrayToString($tags);
	return $tags;
}

sub	convertArrayToString {
	my ($tags) = @_;

	for my $wayId (keys(%$tags)) {
		my $wayTags = $tags->{$wayId};
		for my $tag (keys(%$wayTags)) {
			if (index($tag, "ref") != -1) {	# convert Ref from array to plain string
				if (scalar(@{$wayTags->{$tag}}) > 1) {
					$wayTags->{$tag} = join(",", sort(uniq(@{$wayTags->{$tag}})));
				}
				else { $wayTags->{$tag} = $wayTags->{$tag}->[0]; }
			}
		}
	}
}

sub deleteOldFmRelTags {
	my ($ways) = @_;

	for my $wayId (keys(%$ways)) {
		if (defined($ways->{$wayId}->{tg})) {
			my $wayTags = $ways->{$wayId}->{tg};
			for my $key (keys(%$wayTags)) {
				if ($key =~ /^fmrel/) { delete($wayTags->{$key}); }
			}
		}
	}
}

sub getColour {
	my ($relTags) = @_;
	my $colour = "";
	our @colours = ("red", "blue", "green", "yellow", "black", "white");

	if (defined($relTags->{"osmc:symbol"})) { # get the colour from the osmc:symbol
		my $osmc = $relTags->{"osmc:symbol"};
		for my $tmpColour (@colours) {
			if (index($osmc, $tmpColour . ":") == 0) {
				$colour = $tmpColour;
				last;
			}
		}
	}
	if ($colour eq "") {	# get the colour from the tag of the relation itself
		if (defined($relTags->{"colour"})) { $colour = $relTags->{"colour"}; }
		elsif (defined($relTags->{"color"})) { $colour = $relTags->{"color"}; }
	}
	if (!grep(/^$colour$/, @colours)) { $colour = "default"; }

	return $colour;
}

sub getFmRelBicycleTags {
	my ($relTags) = @_;
	my $fmRelTags = {};
	my $colour = getColour($relTags);
	my $symbol = getSymbol($relTags);

	if (defined($relTags->{"ref"})) { $fmRelTags->{"fmrelbicycleref"} = $relTags->{"ref"}; }
	$fmRelTags->{"fmrelbicycle" . $colour} = $symbol;

	return $fmRelTags;
}

sub getFmRelBusTags {
	my ($relTags) = @_;
	my $fmRelTags = {};

	$fmRelTags->{"fmrelbus"} = "yes";
	if (defined($relTags->{"ref"})) { $fmRelTags->{"fmrelbusref"} = $relTags->{"ref"}; }

	return $fmRelTags;
}

sub getFmRelFootTags {
	my ($relTags) = @_;
	my $fmRelTags = {};
	my @colours = ("red", "blue", "green", "yellow");

	my $key = "";
	for my $colour (@colours) {
		if (defined($relTags->{"kct_" . $colour})) {
			$key = $colour;
			last;
		}
	}
	if ($key ne "") {
		$fmRelTags->{"fmrelhiking" . $key} = $relTags->{"kct_" . $key};
	}
	return $fmRelTags;
}

sub getFmRelHikingTags {
	my ($relTags) = @_;
	my $fmRelTags = {};
	my $symbol = getSymbol($relTags);

	if (!isValidOsmcSymbol($relTags)) {	# avoid strange relations
		if (!isValidHikingSymbol($symbol)) {
			return $fmRelTags;
		}
	}
	my $colour = getColour($relTags);
	my $ref = undef;

	if (defined($relTags->{"ref"})) { $ref = $relTags->{"ref"}; }
	if (($symbol eq "edu") or ($symbol eq "education")) { # education trails
		$fmRelTags->{"fmreleducation"} =  $symbol;
		if (defined($ref)) { $fmRelTags->{"fmreleducationref"} = $ref; }
	} else {	# hiking trails
		my $network = "";	# distinguish the official trail from the local/unknown trails
		if (defined($relTags->{"network"})) { $network = $relTags->{"network"}; }
		if ($network eq "lwn") { $network = "local"; }
		elsif (($network eq "rwn") or ($network eq "nwn") or ($network eq "iwn")) { $network = ""; }
		else { $network = "unknown"; }
		$fmRelTags->{"fmrelhiking" . $network . $colour} = $symbol;
		$fmRelTags->{"fmrelhiking" . $colour} = $symbol; # tag duplication, reason unknown :(
		if (defined($ref)) {
			$fmRelTags->{"fmrelhikingref"} = $ref;
			$fmRelTags->{"fmrelhiking" . $network . $colour . "ref"} = $ref;
			$fmRelTags->{"fmrelhiking" . $colour . "ref"} = $ref; # tag duplication
		}
	}
	return $fmRelTags;
}

sub getFmRelHorseTags {
	my ($relTags) = @_;

	my $fmRelTags = {};
	my $colour = getColour($relTags);
	my $symbol = getSymbol($relTags);

	if (defined($relTags->{"ref"})) { $fmRelTags->{"fmrelhorseref"} = $relTags->{"ref"}; }
	$fmRelTags->{"fmrelhorse" . $colour} = $symbol;

	return $fmRelTags;
}

sub getFmRelMtbTags {
	my ($relTags) = @_;
	my $fmRelTags = {};
	my $colour = getColour($relTags);
	my $symbol = getSymbol($relTags);

	if (defined($relTags->{"ref"})) { $fmRelTags->{"fmrelmtbref"} = $relTags->{"ref"}; }
	$fmRelTags->{"fmrelmtb" . $colour} = $symbol;

	return $fmRelTags;
}

sub getFmRelSkiTags {
	my ($relTags) = @_;
	my $fmRelTags = {};
	my $colour = getColour($relTags);
	my $symbol = getSymbol($relTags);

	if (defined($relTags->{"ref"})) { $fmRelTags->{"fmrelskiref"} = $relTags->{"ref"}; }
	$fmRelTags->{"fmrelski" . $colour} = $symbol;

	return $fmRelTags;
}

sub getFmRelTramTags {
	my ($relTags) = @_;
	my $fmRelTags = {};

	$fmRelTags->{"fmreltram"} = "yes";
	if (defined($relTags->{"ref"})) { $fmRelTags->{"fmreltramref"} = $relTags->{"ref"}; }

	return $fmRelTags;
}

sub getFmRelTrolleybusTags {
	my ($relTags) = @_;
	my $fmRelTags = {};

	$fmRelTags->{"fmreltrolleybus"} = "yes";
	if (defined($relTags->{"ref"})) { $fmRelTags->{"fmreltrolleybusref"} = $relTags->{"ref"}; }

	return $fmRelTags;
}

sub getSymbol {
	my ($relTags) = @_;
	my $symbol = "";

	if (defined($relTags->{"symbol"})) { $symbol = $relTags->{"symbol"}; }
	if ($symbol eq "") { $symbol = "none"; }

	return $symbol;
}

sub isValidHikingSymbol {
	my ($symbol) = @_;

	return grep(/^$symbol$/, @allowedHikingSymbols);	
}

sub isValidOsmcSymbol {
	my ($relTags) = @_;
	
	if (!defined($relTags->{"osmc:symbol"})) { return 0; }
	my $osmcSymbol = $relTags->{"osmc:symbol"};
	return (verifyOsmcSymbol($osmcSymbol) eq "OK");
}

sub uniq {
	my %seen;
	return grep { !$seen{$_}++ } @_;
}

sub verifyOsmcSymbol {
	my ($symb) = @_;	

	our @wayColor = ("blue", "yellow", "green", "red", "black");
	our @background = ("", "black", "white", "blue", "yellow", "green", "red",
			"purple", "brown", "orange", "blue_round", "green_round", "red_round",
			"white_round", "black_circle", "blue_circle", "yellow_circle", "red_circle",
			"white_circle", "yellow_frame", "green_frame", "red_frame", "blue_frame");
	our @foreground = ("", "blue_dot", "blue_bowl", "blue_circle", "blue_bar", "blue_stripe", "blue_cross", "blue_x", "blue_slash", "blue_backslash", "blue_triangle", "blue_triangle_turned", "blue_diamond", "blue_rectangle", "blue_pointer", "blue_fork", "blue_turned_T", "blue_L", "blue_arch", "blue_lower", "blue_corner", "yellow_dot", "yellow_bowl", "yellow_circle", "yellow_bar", "yellow_stripe", "yellow_cross", "yellow_x", "yellow_slash", "yellow_backslash", "yellow_triangle", "yellow_diamond", "yellow_pointer", "yellow_rectangle", "yellow_fork", "yellow_turned_T", "yellow_L", "yellow_arch", "yellow_lower", "yellow_corner", "yellow_rectangle_line", "red_dot", "red_bowl", "red_circle", "red_bar", "red_stripe", "red_cross", "red_x", "red_slash", "red_backslash", "red_triangle", "red_triangle_turned", "red_diamond", "red_pointer", "red_crest", "red_rectangle", "red_fork", "red_turned_T", "red_L", "red_arch", "red_drop_line", "red_drop", "red_lower", "red_corner", "green_dot", "green_bowl", "green_circle", "green_bar", "green_stripe", "green_cross", "green_x", "green_backslash", "green_slash", "green_rectangle", "green_triangle", "green_triangle_turned", "green_triangle_line", "green_diamond", "green_pointer", "green_fork", "green_turned_T", "green_L", "green_arch", "green_drop_line", "green_corner", "green_lower", "green_horse", "black_dot", "black_circle", "black_bar", "black_x", "black_cross", "black_crest", "black_triangle", "black_rectangle", "black_diamond", "black_pointer", "black_fork", "black_horse", "black_arch", "black_rectangle_line", "black_triangle_line", "black_corner", "black_red_diamond", "white_circle", "white_cross", "white_stripe", "white_x", "white_dot", "white_triangle", "white_rectangle_line", "white_rectangle", "white_triangle_line", "white_diamond_line", "white_diamond", "white_arch", "white_lower", "white_bar", "white_turned_T", "white_pointer", "white_corner", "white_red_diamond", "white_hiker", "orange_bar", "orange_diamond_line", "orange_dot", "wolfshook", "shell_modern", "shell", "ammonit", "mine", "hiker", "heart", "tower", "bridleway");
	our @textColor = ("black", "white", "gray", "blue", "yellow", "green",
			"red", "purple", "orange", "brown");
	my @symbArr = split(':', $symb, -1);
	my $symbCnt = @symbArr;
	if ($symbCnt < 2) { return "At least one colon expected (2 fields)"; }
	elsif ($symbCnt > 6) { return "Too many colons: " . ($symbCnt - 1) . " (max 5)"; }
	if (!grep(/^$symbArr[0]$/, @wayColor)) { return "Invalid waycolor: " . $symbArr[0]; }
	if (!grep(/^$symbArr[1]$/, @background)) { return "Invalid background: " . $symbArr[1]; }
	if ($symbCnt != 4) {
		if (!grep(/^$symbArr[2]$/, @foreground)) { return "Invalid foreground: " . $symbArr[2]; }
	}
	if ($symbCnt > 3) {
		if (!grep(/^$symbArr[-1]$/, @textColor)) { return "Invalid textcolor: " . $symbArr[-1]; }
	}
	if ($symbCnt == 6) {
		if (!grep(/^$symbArr[3]$/, @foreground)) { return "Invalid foreground2: " . $symbArr[3]; }
	}
	return "OK";
}

################################################################################
####################      PROCESSING THE MULTIPOLYGONS      ####################
################################################################################
sub joinMultipolygonMembers {
	my ($nodes, $ways, $rels) = @_;
	# process all relations with type=multipolygon
	for my $relId (keys %$rels) {
		if (hasTagWithValue($rels->{$relId}, "type", "multipolygon")) {
			print("Processing relation $relId\n") if ($debug);
			my $members;
			$members = processMembers($rels->{$relId}, "outer", $nodesAll, $waysAll);
			copyTagsToClosedMembers($rels->{$relId}, $members, $waysAll);
			processMembers($rels->{$relId}, "inner", $nodesAll, $waysAll);
		}
	}
}

sub processMembers {
	my ($relRef, $membRole, $nodes, $ways) = @_;
	my ($relMembers) = getMembers($relRef, $membRole);
	print("\t=> found " . scalar(@$relMembers) . " $membRole member(s)\n") if ($debug);
	my ($newMembers) = joinWays($relMembers, $nodes, $ways);
	if (scalar(@$relMembers) == scalar(@$newMembers)) {	# no ways joined, do nothing
		if ($debug) {
			print("\tNo ways can be joined together, final list: ");
			for my $tmpWayId (@$newMembers) { print("$tmpWayId "); }
			print("\n");
		}
		return ($relMembers);
	}
	# convert arrays to hashes, to simplify access to the new/old members IDs
	my %relMembersMap = map { $_ => 1 } @$relMembers;
	my %newMembersMap = map { $_ => 1 } @$newMembers;

	my $relMembRef = $relRef->{mb};

	for (my $from = 0; $from < @$relMembRef; $from++) {	# remove ways, which were joined
		# member may have been deleted during the previous execution of this function
		if (defined($relMembRef->[$from])) {
			my $tmpMembId = $relMembRef->[$from]->[1];	# get the wayId
			if (defined($tmpMembId) and defined($relMembersMap{$tmpMembId}) 
					and !defined($newMembersMap{$tmpMembId})) {
				if (defined($ways->{$tmpMembId}) and (!defined($ways->{$tmpMembId}->{tg}) or
					!keys(%{$ways->{$tmpMembId}->{tg}}))) {
					print("Way $tmpMembId does not have tags, marking for deletion\n") if ($debug);
					$ways->{$tmpMembId}->{_delete} = 1;
				}
				print("\tRemoving $tmpMembId from members\n") if ($debug);
				delete($relMembRef->[$from]);
			}
		}
	}
	for my $newMembId (@$newMembers) {
		if ($newMembId < 0) {	# new way was created as combination of other existing ways
			print("\tAdding $newMembId to members\n") if ($debug);
			push @$relMembRef, ['way', $newMembId, $membRole];
		}
	}
	return ($newMembers);
}

################################################################################
####################          CROPPING DATA TO BBOX         ####################
################################################################################
sub cropToArea {
    my ($nodes, $ways, $rels, $bbox) = @_;
	markInsideNodes($nodes, $bbox);
	markWaysNotInBbox($nodes, $ways, $bbox);
	cropSelectedWays($nodes, $ways, $bbox);
	verifyMarkedNodes($nodes, $ways);
	removeMarkedData($nodes, $ways, $rels);
}

sub markInsideNodes {
	# mark all nodes in the bbox as important
	my ($nodes, $bbox) = @_;

	my $startTime = time;
	for my $nodeId (keys %$nodes) {
		$nodes->{$nodeId}->{_inside} = 1 if (isInArea($nodes->{$nodeId},$bbox));
	}
	if ($debug) {
		my $duration = time - $startTime;
		my @keys = keys %$nodes;
		my $total = @keys;
		my $cnt = 0;
		for my $tmpId (@keys) {
			$cnt++ if ($nodes->{$tmpId}->{_inside});
		}
		print("There are $cnt inside nodes of $total total inside bbox @$bbox\n");
		print("TIME: Marking inside nodes took $duration seconds\n");
	}
}

sub markWaysNotInBbox {
	# mark all ways, which have no nodes in the bbox
	# ways, which surrounds the bbox => keep them
	my ($nodes, $ways, $bbox) = @_;

	my $startTime = time;
	for my $wayId (keys %$ways) {
		my $wayNdRefs = getWayNdRefs($wayId, $ways);
		my $canMark = 1;
		my $minLon = undef;
		my $minLat = undef;
		my $maxLon = undef;
		my $maxLat = undef;
		for my $nodeId (@$wayNdRefs) {
			next unless (defined($nodeId) and defined($nodes->{$nodeId}));
			if ($nodes->{$nodeId}->{_inside}) {
				$canMark = 0;
				last;
			}
			$minLon = getMinimum($nodes->{$nodeId}->{pr}->{lon}, $minLon);
			$minLat = getMinimum($nodes->{$nodeId}->{pr}->{lat}, $minLat);
			$maxLon = getMaximum($nodes->{$nodeId}->{pr}->{lon}, $maxLon);
			$maxLat = getMaximum($nodes->{$nodeId}->{pr}->{lat}, $maxLat);
		}
		if ($canMark) {
			if (areaOverlap($minLon, $minLat, $maxLon, $maxLat, $bbox)) {
				print("Cannot mark way $wayId for deletion, as it is overlapping the Bbox\n") if ($debug);
			} else {
				print("Marking way $wayId for deletion, as it is completely outside Bbox\n") if ($debug);
				if (defined($ways->{$wayId})) { $ways->{$wayId}->{_delete} = 1; }
				for my $tmpNodeId (@$wayNdRefs) {
					next unless (defined($tmpNodeId) and defined($nodes->{$tmpNodeId}));
					print("Marking node $tmpNodeId for deletion, as it is completely outside Bbox\n")
						 if ($debug);
					$nodes->{$tmpNodeId}->{_delete} = 1;
				}
			}
		}
	}
    if ($debug) {
        my $duration = time - $startTime;
        my $cnt = 0;
        for my $tmpWayId (keys %$ways) {
            $cnt++ if ($ways->{$tmpWayId}->{_delete});
        }
        print("$cnt ways are outside Bbox, therefore they are marked for deletion\n");
        print("TIME: Marking ways outside Bbox took $duration seconds\n");
    }
}

sub cropSelectedWays {
	# remove all insignificant nodes, that are not inside bbox and also not the border-nodes
	# border-node is first node outside bbox, and is directly connected with the inside-node
	my ($nodes, $ways, $bbox) = @_;

	my $startTime = time;
	my %rules = loadCroppingRules("croprules.dat");
	my $cornerNodes = createCornerNodes($nodes, $bbox);
	my @ruleNames = keys %rules;
	if (scalar(@ruleNames) == 0) { return; }	# no rules specified, nothing to do
	for my $wayId (keys %$ways) {	# examine all ways
		for my $ruleName (@ruleNames) {
			my $ruleValue = $rules{$ruleName};
			my $doCrop = 0;
			if ($ruleValue eq "") { $doCrop = hasTag($ways->{$wayId},$ruleName); }
			else { $doCrop = hasTagWithValue($ways->{$wayId}, $ruleName, $ruleValue); }
			# crop also untagged ways, as they are usually an inner members of multipolygons
			if ($doCrop or !defined($ways->{$wayId}->{tg}) or !keys(%{$ways->{$wayId}->{tg}})) {
				print("Cropping way $wayId, rule name \"$ruleName\", value \"$ruleValue\"\n") 
					if ($debug);
				cropWay($nodes, $ways->{$wayId}, $bbox, $cornerNodes);
			}
		}
	}
    if ($debug) {
        my $duration = time - $startTime;
        my @keys = keys %$nodes;
        my $total = @keys;
        my $cnt = 0;
        for my $tmpId (@keys) {
            $cnt++ if ($nodes->{$tmpId}->{_delete});
        }
        print("There are $cnt nodes of $total total marked for deletion\n");
        print("TIME: Cropping all ways took $duration seconds\n");
    }
}

sub verifyMarkedNodes {
	my ($nodes, $ways) = @_;

	my $cnt = 0;
	# if a node marked for deletion is used by another way, remove the mark
	for my $wayId (keys %$ways) {
		next if (!defined($ways->{$wayId}) or $ways->{$wayId}->{_delete});
		for my $nodeId (@{getWayNdRefs($wayId, $ways)}) {
			if (defined($nodeId) and defined($nodes->{$nodeId})
					 and $nodes->{$nodeId}->{_delete}) {
				$nodes->{$nodeId}->{_delete} = 0;
				$cnt++;
			}
		}
	}
	if ($debug) { print("Undeleting $cnt nodes\n"); }
}

sub removeMarkedData {
	my ($nodes, $ways, $rels) = @_;

	removeMarkedWaysFromRelations($ways, $rels);
	print("Ways: ") if ($debug);
	removeMarkedObjects($ways);
	print("Nodes: ") if ($debug);
	removeMarkedObjects($nodes);
}

sub removeMarkedWaysFromRelations {
	my ($ways, $rels) = @_;

	my $cnt = 0;
	for my $relId (keys %$rels) {
		my $relMembRef = $rels->{$relId}->{mb};
		for (my $i = 0; $i < @$relMembRef; $i++) {
			if (defined($relMembRef->[$i]) and ($relMembRef->[$i]->[0] eq "way")) {
				my $wayId = $relMembRef->[$i]->[1];
				if (defined($ways->{$wayId}) and $ways->{$wayId}->{_delete}) {
					delete($relMembRef->[$i]);
					$cnt++;
				}
			}
		}
	}
	if ($debug) { print("Removed $cnt ways from relation members\n"); }
}

sub removeMarkedObjects {
	my ($objs) = @_;

	my $cnt = 0;
	for my $objId (keys %$objs) {
		if ($objs->{$objId}->{_delete}) {
			delete($objs->{$objId});
			$cnt++;
		}
	}
	if ($debug) { print("$cnt deleted\n"); }
}

sub cropWay {
	my ($nodes, $wayRef, $bbox, $cornerNodes) = @_;

	if (!defined($wayRef->{nd})) { return; }	# way has no nodes?!
	my $wayNdRefs = $wayRef->{nd};
	my $isClosed = isClosed($wayNdRefs);
	my $idx = 0;
	my $previousNodeRef = undef;
	my $intersectWeight = 0;
	my $cornerNodeRef;

	if ($isClosed) {	# find the previous node
		delete($wayNdRefs->[$#$wayNdRefs]);	# remove the last node, because it is already the first one
		for (my $i = $#$wayNdRefs; $i >= 0; $i--) {
			next unless defined($nodes->{$wayNdRefs->[$i]});
			$previousNodeRef = $nodes->{$wayNdRefs->[$i]};
			last;
		}
	}
	while ($idx < scalar(@$wayNdRefs)) {	# examine each node
		my $nodeId = $wayNdRefs->[$idx];
		next unless defined($nodeId);
		my $nodeRef = $nodes->{$nodeId};
		next unless defined($nodeRef);
		if ($nodeRef->{_inside}) {	# node already marked as important
			$previousNodeRef = $nodeRef;	# remember for calculating the intersection
			next;
		}
		if (defined($previousNodeRef) and $previousNodeRef->{_inside}) {
			$previousNodeRef = $nodeRef;
			next;
		}
		my $nextNodeRef = undef;
		for (my $i = $idx + 1; $i < @$wayNdRefs; $i++) {
			next unless (defined($wayNdRefs->[$i]) and defined($nodes->{$wayNdRefs->[$i]}));
			$nextNodeRef = $nodes->{$wayNdRefs->[$i]};
			last;
		}
		if (defined($nextNodeRef) and $nextNodeRef->{_inside}) {
			$previousNodeRef = $nodeRef;
			next;
		}
		if (defined($previousNodeRef) and defined($nextNodeRef)) {
			$intersectWeight = intersectLineSectionWithBbox($previousNodeRef, $nextNodeRef, $bbox);
			if ($intersectWeight) {
				if (defined($cornerNodes->{$intersectWeight})) {
					# intersecting the bbox corner => check, if we can use corner-node instead
					$cornerNodeRef = $nodes->{$cornerNodes->{$intersectWeight}};
					if (!intersectLineSectionWithBbox($previousNodeRef, $cornerNodeRef, $bbox) and
							!intersectLineSectionWithBbox($cornerNodeRef, $nextNodeRef, $bbox)) {
						# it is safe to replace the current node with the corner-node
						$nodeRef->{_delete} = 1;
						$wayNdRefs->[$idx] = $cornerNodes->{$intersectWeight};
						$previousNodeRef = $cornerNodeRef;
						next;
					}
				} else {	# intersecting the bbox opposite sides => find the closest corner nodes
					my $closestCornerNodes = closestCornerNodes($previousNodeRef, $nodeRef,
						$cornerNodes, $intersectWeight, $nodes);
					if (!intersectLineSectionWithBbox($previousNodeRef,
							$nodes->{$closestCornerNodes->[0]}, $bbox) and
							!intersectLineSectionWithBbox($nodes->{$closestCornerNodes->[1]},
							 $nextNodeRef, $bbox)) {
						splice(@$wayNdRefs, $idx, 1, @$closestCornerNodes);
						$idx++;	# because the two nodes were inserted
						$nodeRef->{_delete} = 1;
						$previousNodeRef = $nodes->{$closestCornerNodes->[1]};
						next;
					}
					print("Undefined intersection weight $intersectWeight, current node " .
							$nodeRef->{pr}->{id} . ", previous node " . $previousNodeRef->{pr}->{id} .
							", next node " . $nextNodeRef->{pr}->{id} . "\n");
				}
				# cannot remove the node, because the line (from previous node to the next node)
				# is crossing the bbox
				$previousNodeRef = $nodeRef;
			} else {
				# mark the current node for deletion and delete the reference from the current way
				$nodeRef->{_delete} = 1;
				delete($wayNdRefs->[$idx]);
			}
		} else {
			# this is the first/last node, mark for deletion
			if (!defined($nextNodeRef) and $isClosed) {
				# make sure, that removing the last node of a closed way will not intersect
				# with the edge of bbox

				# if current node is going to be removed, then the "next" node is the first
				# "not-marked" node used by this way
				for (my $i = 0; $i < @$wayNdRefs; $i++) {
					next unless defined($wayNdRefs->[$i]);
					next if ($i == $idx);	# avoid getting the same node as is the current one
					$nextNodeRef = $nodes->{$wayNdRefs->[$i]};
					last;
				}
				$intersectWeight = 0;
				if (defined($nextNodeRef)) {
					$intersectWeight = intersectLineSectionWithBbox($previousNodeRef, $nextNodeRef,
											 $bbox);
					if ($intersectWeight) {
						if (defined($cornerNodes->{$intersectWeight})) {
							# intersecting the bbox corner => check, if we can use corner-node instead
							$cornerNodeRef = $nodes->{$cornerNodes->{$intersectWeight}};
							if (!intersectLineSectionWithBbox($previousNodeRef, $cornerNodeRef, $bbox)
								and !intersectLineSectionWithBbox($cornerNodeRef, $nextNodeRef, $bbox)) {
								# it is safe to replace the current node with the corner-node
								$nodeRef->{_delete} = 1;
								$wayNdRefs->[$idx] = $cornerNodes->{$intersectWeight};
								next;
							}
						}
					}
				}
				if (!defined($nextNodeRef) or !$intersectWeight) {
						$nodeRef->{_delete} = 1;
						delete($wayNdRefs->[$idx]);
				}
			} else {
				$nodeRef->{_delete} = 1;
				delete($wayNdRefs->[$idx]);
			}
		}
	} continue { $idx++; }
	if (@$wayNdRefs) {	# some nodes remained, close the way if needed
		if ($isClosed) {
			my $firstNodeRef = undef;
			for (my $i = 0; $i < @$wayNdRefs; $i++) {
				next unless defined($wayNdRefs->[$i]);
				$firstNodeRef = $wayNdRefs->[$i];
				last;
			}
			push @$wayNdRefs, $firstNodeRef;
		}
	} else {	# if all nodes are removed, mark also the way for deletion
		if ($debug) { print("Marking way $wayRef->{pr}->{id} for deletion\n"); }
		$wayRef->{_delete} = 1;
	}
}

sub intersectLineSectionWithBbox {
    my ($nd1Ref, $nd2Ref, $bbox) = @_;  # bbox is already in format: minLon, minLat, maxLon, maxLat

	return 0 unless areaByNodesOverlap($nd1Ref, $nd2Ref, $bbox);

    my $x1 = $nd1Ref->{pr}->{lon};
    my $y1 = $nd1Ref->{pr}->{lat};
    my $x2 = $nd2Ref->{pr}->{lon};
    my $y2 = $nd2Ref->{pr}->{lat};
	my $intersectWeight = 0;

	# line/nodes weights:      line at the top of bbox = weight 1
	#   9      1      3        line at the right side = weight 2
	#    +-----------+         line at the bottom of bbox = weight 4
	#    |           |         line at the left side = weight 8
	#    |           |
	#   8|    bbox   |2        nodes weight are calculated as "sum of intersecting lines":
	#    |           |         top-right node = weight 3 (=1+2)
	#    |           |         bottom-right node = weight 6 (=2+4)
	#    +-----------+         bottom-left node = weight 12 (=4+8)
	#  12      4      6        top-left node = weight 9 (=8+1)

	if (intersectLineSections($x1, $y1, $x2, $y2, $bbox->[0], $bbox->[3], $bbox->[2], $bbox->[3])) {
		$intersectWeight += 1; # top side of bbox
	}
	if (intersectLineSections($x1, $y1, $x2, $y2, $bbox->[2], $bbox->[3], $bbox->[2], $bbox->[1])) {
		$intersectWeight += 2; # right side of bbox
	}
	if (intersectLineSections($x1, $y1, $x2, $y2, $bbox->[2], $bbox->[1], $bbox->[0], $bbox->[1])) {
		$intersectWeight += 4; # bottom side of bbox
	}
	if (intersectLineSections($x1, $y1, $x2, $y2, $bbox->[0], $bbox->[1], $bbox->[0], $bbox->[3])) {
		$intersectWeight += 8; # left side of bbox
	}
    return $intersectWeight;
}

sub intersectLineSections {
	# 1st line SECTION: (x1,y1) -> (x2,y2)
	# 2nd line SECTION: (x3,y3) -> (x4,y4)
    my ($x1, $y1, $x2, $y2, $x3, $y3, $x4, $y4) = @_;

	# from: http://www.perlmonks.org/bare/?node_id=253974
	# all of the points on a line can be parameterized as linear combination 
	# of two points defining the line segment: P = (p-1)*A + p*B

	# For p:
	# =0: A
	# =1: B
	# <0: points past A
	# >1: points past B
	
	# Intersection of the lines:
	# P = p*A + (1-p)*B
	# Q = q*C + (1-p)*D

	# Find p,q such that P=Q:

	# [ p*ax + (1-p)*bx, p*ay + (1-p)*by ] = 
	# [ q*cx + (1-q)*dx, q*cy + (1-q)*dy ]

	# p*ax + (1-p)*bx = q*cx + (1-q)*dx
	# p*ay + (1-p)*by = q*cy + (1-q)*dy

	# p*(ax-bx) + bx = q*(cx-dx) + dx
	# p*(ay-by) + by = q*(cy-dy) + dy

	# ( p*(ax-bx) + bx-dx ) / (cx-dx) = q
	# ( p*(ay-by) + by-dy ) / (cy-dy) = q

	# ( p*(ax-bx) + bx-dx ) / (cx-dx) = ( p*(ay-by) + by-dy ) / (cy-dy)
	# ( p*(ax-bx) + bx-dx ) * (cy-dy) = ( p*(ay-by) + by-dy ) * (cx-dx)
	# p*(ax-bx)*(cy-dy) + (bx-dx)*(cy-dy) = p*(ay-by)*(cx-dx) + (by-dy)*(cx-dx)
	# p*( (ax-bx)*(cy-dy) - (ay-by)*(cx-dx) ) = (by-dy)*(cx-dx) - (bx-dx)*(cy-dy)

	# Result:
	# p = ( (by-dy)*(cx-dx) - (bx-dx)*(cy-dy) ) / ( (ax-bx)*(cy-dy) - (ay-by)*(cx-dx) )
	# px= p*ax + (1-p)*bx
	# py= p*ay + (1-p)*by

	# The same way:
	# q = ( (dy-by)*(ax-bx) - (dx-bx)*(ay-dy) ) / ( (cx-dx)*(ay-by) - (cy-dy)*(ax-bx) )

	my $d = ($x1 - $x2) * ($y3 - $y4) - ($y1 - $y2) * ($x3 - $x4);
	return 0 if ($d == 0);	# parallel lines
	my $p = (($y2 - $y4) * ($x3 - $x4) - ($x2 - $x4) * ($y3 - $y4)) / $d;
	return 0 unless (($p >= 0) and ($p <= 1));
	my $q = (($y4 - $y2) * ($x1 - $x2) - ($x4 - $x2) * ($y1 - $y2)) /
				(($x3 - $x4) * ($y1 - $y2) - ($y3 - $y4) * ($x1 - $x2));
	return (($q >= 0) and ($q <= 1));
}

sub loadCroppingRules {
	my $cropDataFile = shift;
	my %cropRules;
	my $lineNo = 0;

	if (-f $cropDataFile) {
		open(my $fp, "<$cropDataFile") or return %cropRules;
		while (my $line = <$fp>) {
			chomp($line);
			$lineNo++;
			next if ($line =~ /^\s*$/);	#only white spaces on the line
			next if ($line =~ /^\s*#.*$/);	# comment on the whole line
			if ($line =~ /^\s*([^=#\s]+)\s*=?\s*(\w*)\s*#?.*$/) { $cropRules{$1} = $2; }
			else { print STDERR "Wrong line #$lineNo: \"$line\"\n" if ($debug) }
		}
		close($fp);
	}
	my $cnt = keys %cropRules;
	print("Number of cropping rules: $cnt\n") if ($debug);
	return %cropRules;
}

sub createCornerNodes {
	# create virtual nodes near the corners of bbox, but still outside of it
	my ($nodes, $bbox) = @_;  # bbox is already in format: minLon, minLat, maxLon, maxLat
	my $nodeId = -1;
	my @nodeWeight = (3, 6, 12, 9);	# see function intersectLineSectionWithBbox for more information
	my $delta = 0.00001;
	my $cornerNodes = {};
	for (my $i = 0; $i < 4; $i++) {
		while (defined($nodes->{$nodeId})) { $nodeId--; }
		my ($lat, $lon);
		if ( $i < 2 ) { $lon = $bbox->[2] + $delta; }
		else { $lon = $bbox->[0] - $delta; }
		if ( $i > 0 and $i < 3) { $lat = $bbox->[1] - $delta; }
		else { $lat = $bbox->[3] + $delta; }
		# set properties for node
		$nodes->{$nodeId}->{pr}->{id} = $nodeId;
		$nodes->{$nodeId}->{pr}->{lat} = $lat;
		$nodes->{$nodeId}->{pr}->{lon} = $lon;
		# mark node as unnecessary, if it will be used, then it will be unmarked before deletion
		$nodes->{$nodeId}->{_delete} = 1;
		# create mapping "node weight" -> "node ID"
		$cornerNodes->{$nodeWeight[$i]} = $nodeId;
		if ($debug) {
			print("Created corner node: weight=$nodeWeight[$i], id=$nodeId, lat=$lat, lon=$lon\n");
		}
	}
	return $cornerNodes;
}
 
sub closestCornerNodes {
	# find the two closest nodes and return them in the correct order
	my ($prevNodeRef, $currNodeRef, $cornerNodes, $intersectWeight, $nodes) = @_;
	my $tlNodeRef = $nodes->{$cornerNodes->{9}};
	my $trNodeRef = $nodes->{$cornerNodes->{3}};
	my $blNodeRef = $nodes->{$cornerNodes->{12}};
	my $brNodeRef = $nodes->{$cornerNodes->{6}};
	my $cornerNodesOrderRef;
	if ($intersectWeight % 2 == 0) {	# crossing top and bottom side of bbox
		$cornerNodesOrderRef = [$tlNodeRef, $trNodeRef, $blNodeRef, $brNodeRef];
	} else {	# crossing left and right side of bbox
		$cornerNodesOrderRef = [$tlNodeRef, $blNodeRef, $trNodeRef, $brNodeRef];
	}
	return closestCornerNodesByNodeOrder($prevNodeRef, $currNodeRef, $cornerNodesOrderRef);
}

sub closestCornerNodesByNodeOrder {
	my ($prevNodeRef, $currNodeRef, $nodesOrderRef) = @_;
	my $minArrRef = [-1, undef, undef];
	closestCornerNodesWithMinimalDistance($minArrRef, $prevNodeRef, $currNodeRef, $nodesOrderRef->[0],
			$nodesOrderRef->[1]);
	closestCornerNodesWithMinimalDistance($minArrRef, $prevNodeRef, $currNodeRef, $nodesOrderRef->[1],
			$nodesOrderRef->[0]);
	closestCornerNodesWithMinimalDistance($minArrRef, $prevNodeRef, $currNodeRef, $nodesOrderRef->[2],
			$nodesOrderRef->[3]);
	closestCornerNodesWithMinimalDistance($minArrRef, $prevNodeRef, $currNodeRef, $nodesOrderRef->[3],
			$nodesOrderRef->[2]);
	shift(@$minArrRef);
	my @cornerNodesId = map { $_->{pr}->{id} } @$minArrRef;
	return \@cornerNodesId;
}

sub closestCornerNodesWithMinimalDistance {
	my ($minArrRef, $prevNodeRef, $currNodeRef, $firstCornerNode, $lastCornerNode) = @_;
	my $distanceWeight = distanceWeightSum($prevNodeRef, $firstCornerNode, $currNodeRef,
			$lastCornerNode);
	if (($minArrRef->[0] < 0) or ($distanceWeight < $minArrRef->[0])) {
		$minArrRef->[0] = $distanceWeight;
		$minArrRef->[1] = $firstCornerNode;
		$minArrRef->[2] = $lastCornerNode;
	}
}

sub distanceWeightSum {
	my ($prevNodeRef, $firstNode, $currNodeRef, $lastNode) = @_;
	return distanceWeight($prevNodeRef, $firstNode) + distanceWeight($currNodeRef, $lastNode);
}

sub distanceWeight {
	my ($node1, $node2) = @_;
	# no need to do a sqrt, as we don't need the exact value, just some value for comparing
	return ($node1->{pr}->{lat} - $node2->{pr}->{lat}) ** 2 +
			($node1->{pr}->{lon} - $node2->{pr}->{lon}) ** 2;
}

################################################################################
####################   ISOLATING INNER FROM OUTER MEMBERS   ####################
################################################################################
sub isolateMultipolygonMembers {
	my ($ways, $rels) = @_;
	my $waysInRels = {};
	# collect all ways, which are used as members in the relations
	for my $relId (keys(%$rels)) {
		my $rel = $rels->{$relId};
		if (defined($rel->{mb})) {
			for my $membArr (@{$rel->{mb}}) {
				if (defined($membArr)) {
					if ($membArr->[2] eq "outer") {
						$waysInRels->{$membArr->[1]}->{"out"} = $relId;
					} elsif ($membArr->[2] eq "inner") {
						$waysInRels->{$membArr->[1]}->{"in"} = $relId;
					}
				}
			}
		}
	}
	# if way is inner member of one relation and outer member of another relation, duplicate it
	# with the new ID (this is workaround, as osmarender.xsl cannot solve this situation correctly)
	for my $wayId (keys(%$waysInRels)) {
		my $way = $waysInRels->{$wayId};
		if (defined($way->{"out"}) and defined($way->{"in"})) {
			my $newWayId = $newWayIdValue;
			$newWayIdValue--;
			print("Adding way $newWayId as copy of $wayId\n") if ($debug);
			addNewWayWithData($ways, $newWayId, getWayNdRefs($wayId, $ways), getObjProps($wayId, $ways));
			my $innerInRelId = $way->{"in"};
			my $tmpRel = $rels->{$innerInRelId};
			for my $membArr (@{$tmpRel->{mb}}) {	# find the old way between relation members
				if (defined($membArr) and ($membArr->[1] eq $wayId)) {
					$membArr->[1] = $newWayId;	# replace old way with the ID of its duplicate
				}
			}
		}
	}
}

################################################################################
####################                 GENERAL                ####################
################################################################################
sub isClosed {
	my ($wayNdRefs) = @_;
	if (defined($wayNdRefs) and scalar(@$wayNdRefs)) {	# report ways without nodes as not closed
		my $first = $wayNdRefs->[0];
		if (!defined($first)) {	# way was modified, skip all "undef" items to find the first node
			for (my $i = 1; $i < @$wayNdRefs; $i++) {
				next unless defined($wayNdRefs->[$i]);
				$first = $wayNdRefs->[$i];
				last;
			}
		}
		my $last = $wayNdRefs->[-1];
		return ($first eq $last);
	}
	return 0;
}

sub hasTag {
	my ($osmObj, $tag) = @_;
	return (defined($osmObj->{tg}) and defined($osmObj->{tg}->{$tag}));
}

sub hasTagWithValue {
	my ($osmObj, $tag, $val) = @_;
	return (hasTag($osmObj, $tag) and ($osmObj->{tg}->{$tag} eq $val));
}

sub getMembers {
	my ($osmObj, $membRole) = @_;
	my @members;

	if (defined($osmObj->{mb})) {
		for my $membArr (@{$osmObj->{mb}}) {
			if (defined($membArr) and ($membArr->[2] eq $membRole)) {
				# membArr could be empty, if the member was deleted from the relation
				# (=joined with another way)
				push @members, $membArr->[1];
			}
		}
	}
	return \@members;
}

sub joinWays {
	my ($wayIds, $nodes, $ways) = @_;
	if ((scalar @$wayIds) == 0) { return ($wayIds); }	# nothing to do

	my @tmpWayIds = ();
	my @finalWayIds = ();
	for my $wayId (@$wayIds) {
		if (!defined($ways->{$wayId})) {	# download missing data from API
			if ($wayId > 0) {
				print("\t=> downloading way $wayId from API\n") if ($debug);
				my ($ndApi, $wayApi, $relApi, $headApi, $boundApi) = APIget("way", $wayId);
				if (defined $wayApi->{$wayId}) {	# copy data from API response
					addNewNodes($nodes, $ndApi);
					addNewWays($ways, $wayApi);
				}
				else {
					print("\tError downloading way $wayId from API!\n") if ($debug);
				}
			}
			else {
				print("Error before joining ways: temporary way $wayId have no data in <way> structure!\n") if ($debug);
			}
		}
		# process only ways with nodes
		if (defined($ways->{$wayId})) {
			if (isClosed(getWayNdRefs($wayId, $ways))) {
				print("\t=> way $wayId is closed, adding it directly to the result\n") if ($debug);
				push @finalWayIds, $wayId;	# way is already closed
			}
			else {
				push @tmpWayIds, $wayId;	# create a list with wayIds, that should be combined together
			}
		}
		else {	# put ways without nodes directly to the result
			push @finalWayIds, $wayId;	# way is already closed
		}
	}

	my $tmpWayIndex = 0;
	while ($tmpWayIndex < scalar(@tmpWayIds)) {
		# copy the current way into a temporary way
		my $newWayId = $newWayIdValue;
		my $orgWayId = $tmpWayIds[$tmpWayIndex];
		my @tmpNdRefs = ();
		for my $tmpNdRef (@{getWayNdRefs($orgWayId, $ways)}) {
			push @tmpNdRefs, $tmpNdRef;
		}
		my $lastNdRef = $tmpNdRefs[-1];	# reference to the last node of the current way
		my @removeWayIds = ();	# Ids of the ways, which are combined to a new way
		print("\t=> join[$tmpWayIndex]: temporary way based on wayId ". $tmpWayIds[$tmpWayIndex] .
			", last node $lastNdRef\n") if ($debug);

		my $joined;
		do {	# ways could be unsorted (e.g. 1st is connected to 3rd, then 2nd,...
				# => repeat while some ways were joined together)
			$joined = 0;
			for my $index (($tmpWayIndex+1) .. $#tmpWayIds) {
				my $tmpWayId = $tmpWayIds[$index];
				next if (grep /^$tmpWayId$/, @removeWayIds);	# way already joined in the previos loop
				print("\t=> join[$tmpWayIndex]: index=$index, wayId=$tmpWayId\n") if ($debug);
				my $wayNdRefs = getWayNdRefs($tmpWayId, $ways);
				if ($wayNdRefs->[0] eq $lastNdRef) {	# add all node references except the first one
					$joined = 1;
					addNdRefs(\@tmpNdRefs, $wayNdRefs);
					$lastNdRef = $tmpNdRefs[-1];
					print("\t=> join: adding nodes from way $tmpWayId, new last node $lastNdRef\n")
						 if ($debug);
					push @removeWayIds, $tmpWayId;	# mark wayId for delete
				} elsif ($wayNdRefs->[-1] eq $lastNdRef) {
					# reverse all node references and add them except the first one
					$joined = 1;
					addNdRefsReversed(\@tmpNdRefs, $wayNdRefs);
					$lastNdRef = $tmpNdRefs[-1];
					print("\t=> join: adding reversed nodes from way $tmpWayId, new last node $lastNdRef\n") if ($debug);
					push @removeWayIds, $tmpWayId;	# mark wayId for delete
				}
			}
		} while ($joined and !(isClosed(\@tmpNdRefs)));
		if (scalar(@removeWayIds)) {	# some ways were combined, remove the original way IDs
			$tmpWayIds[$tmpWayIndex] = $newWayId;	# replace old wayId with the ID of a combined way
			$newWayIdValue--;	# generate ID for the next new way
			my %removeIdsMap = map { $_ => 1 } @removeWayIds;
			my @nextWayIds = ();
			for my $id (@tmpWayIds) {
				push @nextWayIds, $id if (!defined($removeIdsMap{$id}));
			}
			@tmpWayIds = @nextWayIds;
			addNewWayWithData($ways, $newWayId, \@tmpNdRefs, getObjProps($orgWayId, $ways));
			unshift @removeWayIds, $orgWayId;	# array now contains IDs of all original ways
			mergeCommonTags($newWayId, \@removeWayIds, $ways);
		}
		$tmpWayIndex++;
	}
	for my $finWayId (@tmpWayIds) {	# copy remaining wayIds to the result
		push @finalWayIds, $finWayId;
	}
	return (\@finalWayIds);
}

sub addNewNodes {
	my ($destNodes, $srcNodes) = @_;
	for my $id (keys %$srcNodes) {
		if (!defined $destNodes->{$id}) { $destNodes->{$id} = $srcNodes->{$id}; }
	}
}

sub addNewWays {
	my ($destWays, $srcWays) = @_;
	for my $id (keys %$srcWays) {
		if (!defined $destWays->{$id}) { $destWays->{$id} = $srcWays->{$id}; }
	}
}

sub addNewWayWithData {
	my ($destWays, $wayId, $wayNdRefs, $wayProps) = @_;
	for my $tag (keys %$wayProps) {
		if (!($tag eq "id") and (($wayId > 0) or !($tag eq "changeset"))) {	# no changeset for wayId < 0
			$destWays->{$wayId}->{pr}->{$tag} = $wayProps->{$tag};
		}
	}
	$destWays->{$wayId}->{pr}->{id} = $wayId;
	$destWays->{$wayId}->{nd} = $wayNdRefs;
}

sub copyTags {
	my ($srcRel, $destWay) = @_;
	if (defined $srcRel->{tg}) {
		for my $tag (keys %{$srcRel->{tg}}) {
			if (!(($tag eq "type") and ($srcRel->{tg}->{$tag} eq "multipolygon"))) {
				$destWay->{tg}->{$tag} = $srcRel->{tg}->{$tag};
			}
		}
	}
}

sub getWayNdRefs {
	my ($wayId, $ways) = @_;
	if ((defined $ways->{$wayId}) and (defined $ways->{$wayId}->{nd})) {
		return $ways->{$wayId}->{nd};
	}
	return [];	# empty array reference
}

sub getObjProps {
	my ($objId, $objs) = @_;
	if (defined($objs->{$objId}) and defined($objs->{$objId}->{pr})) {
		return $objs->{$objId}->{pr};
	}
	return {};	# empty hash reference
}

sub addNdRefs {
	my ($destRefs, $srcRefs) = @_;
	if ((scalar @$srcRefs) > 1) {	# copy reference to a node, except the first one
		for my $index (1 .. $#$srcRefs) {
			push @$destRefs, $srcRefs->[$index];
		}
	}
}

sub addNdRefsReversed {
	my ($destRefs, $srcRefs) = @_;
	my @reversed = reverse @$srcRefs;
	addNdRefs($destRefs, \@reversed);
}

sub mergeCommonTags {
	my ($wayId, $oldWayIds, $ways) = @_;
	my ($tags) = getObjProps($oldWayIds->[0], $ways);	# take the tags from the first old way
	for my $k (keys %$tags) {
		my $v = $tags->{$k};
		my $copyTag = 1;
		for my $tmpWayId (@$oldWayIds) {
			if (!hasTagWithValue($ways->{$tmpWayId}, $k, $v)) { $copyTag = 0; }
		}
		if ($copyTag) {
			$ways->{$wayId}->{tg}->{$k} = $v;
		}
	}
}

sub copyTagsToClosedMembers {
	my ($relRef, $wayIds, $ways) = @_;
	for my $wayId (@$wayIds) {
		if (isClosed(getWayNdRefs($wayId, $ways))) {
			print("\tCopying tags from relation to the way $wayId\n") if ($debug);
			copyTags($relRef, $ways->{$wayId});
		}
	}
}

sub isInArea {
	my ($ndRef, $bbox) = @_;

	my $x = $ndRef->{pr}->{lon};
	my $y = $ndRef->{pr}->{lat};

	return (($x >= $bbox->[0]) and ($x <= $bbox->[2]) and
			($y >= $bbox->[1]) and ($y <= $bbox->[3]));
}

sub areaByNodesOverlap {
	my ($nd1Ref, $nd2Ref, $bbox) = @_;	# bbox is already in format: minLon, minLat, maxLon, maxLat

	my $x1 = $nd1Ref->{pr}->{lon};
	my $y1 = $nd1Ref->{pr}->{lat};
	my $x2 = $nd2Ref->{pr}->{lon};
	my $y2 = $nd2Ref->{pr}->{lat};
	# sort the X,Y to simplify the comparing of the areas
	my $minX = ($x1 < $x2) ? $x1 : $x2;
	my $minY = ($y1 < $y2) ? $y1 : $y2;
	my $maxX = ($x1 < $x2) ? $x2 : $x1;
	my $maxY = ($y1 < $y2) ? $y2 : $y1;

	return areaOverlap($minX, $minY, $maxX, $maxY, $bbox);
}

sub areaOverlap {
	my ($minX, $minY, $maxX, $maxY, $bbox) = @_;

	if ($minX > $bbox->[2]) { return 0; }
	if ($maxX < $bbox->[0]) { return 0; }
	if ($minY > $bbox->[3]) { return 0; }
	if ($maxY < $bbox->[1]) { return 0; }

	return 1;	
}

sub getMinimum {
	my ($value1, $value2) = @_;

	if (!defined($value1)) { return $value2; }
	if (!defined($value2)) { return $value1; }

	return ($value1 < $value2) ? $value1 : $value2;
}

sub getMaximum {
	my ($value1, $value2) = @_;

	if (!defined($value1)) { return $value2; }
	if (!defined($value2)) { return $value1; }

	return ($value1 > $value2) ? $value1 : $value2;
}
