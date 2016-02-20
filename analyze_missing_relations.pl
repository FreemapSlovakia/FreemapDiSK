#!/usr/bin/perl


my $VERSION ="analyze_missing_relations.pl (c)2012 Jozef Vince, Freemap Slovakia";

my $TRAPI_URL = "http://dev.freemap.sk/trapi/api/0.6/map/?way=";
my $TRAPI_LOW_URL = "http://dev.freemap.sk/trapi/apilow/0.6/map/?way=";

BEGIN {
    my $dir = $0;
    $dir =~s,[^/]+/[^/]+$,,;
    unshift(@INC,"perl_lib");
    
}


use strict;
use warnings;

use File::Basename;
use File::Copy;
use File::Path;
use Getopt::Long;
use HTTP::Request;
use IO::File;
use Geo::OSM::Planet;
use Geo::OSM::Write;
use Utils::Debug;
use Utils::LWP::Utils;
use Utils::File;
use Data::Dumper;
use XML::Parser;

my ($man,$help);

our $osm_file; # The complete osm Filename (including path)
my ($tmpfile, $tmpdir);	# first is not used, second is the path, where the temporary files will be created

my $OSM_BOUNDS     = {};

my $OSM_NODES     = {};
my $OSM_WAYS      = {};
my $OSM_RELATIONS = {};
my $OSM_OBJ       = undef; # OSM Object currently read

my $count_node=0;
my $count_node_all=0;
my $count_way=0;
my $count_way_all=0;
my $count_relation=0;
my $count_relation_all=0;
my $output;

my $missing_ways={};
my $previous_nd =0;
my $count_downloaded =0;
my $used_url = 'mid';
my $mode = 'multipolygon';
# -------------------------------------------------------------------

# Remove duplicate node entries.
# Duplicate nodes are references to the original node so look like they have the wrong ID
sub delete_duplicate_nodes_data() {
    for my $node_id ( keys %{$OSM_NODES} ) {
	if ($OSM_NODES->{$node_id}->{id} != $node_id) {
		delete $OSM_NODES->{$node_id};
	}
    }
}

sub bounds_ {
    $OSM_OBJ = undef;
}

sub bounds {
    my($p, $tag, %attrs) = @_;
    my $minlat = delete $attrs{minlat};
	my $minlon = delete $attrs{minlon};
    my $maxlat = delete $attrs{maxlat};
    my $maxlon = delete $attrs{maxlon};
 	
 	$OSM_BOUNDS->{minlat} = $minlat;
	$OSM_BOUNDS->{minlon} = $minlon;
	$OSM_BOUNDS->{maxlat} = $maxlat;
	$OSM_BOUNDS->{maxlon} = $maxlon;
}

sub node_ {
    $OSM_OBJ = undef;
}

sub node {
    my($p, $tag, %attrs) = @_;  
    my $id = delete $attrs{id};
    $OSM_OBJ = {};
    $OSM_OBJ->{element}="node";

    my $lat = delete $attrs{lat};
    my $lon = delete $attrs{lon};
    delete $attrs{timestamp} if defined $attrs{timestamp};

    if ( keys %attrs ) {
	warn "node $id has extra attrs: ".Dumper(\%attrs);
    }

	# Create initial data for this unique node, more duplicates may come along later.
	$OSM_OBJ->{id} = $id;
	$OSM_OBJ->{lat} = $lat;
	$OSM_OBJ->{lon} = $lon;
	$OSM_OBJ->{dupes} = 1;
	$OSM_NODES->{$id} = $OSM_OBJ;

    $count_node_all++;
    if ( $VERBOSE || $DEBUG ) {
		if (!($count_node_all % 1000) ) {
		    printf("node %d (%d) \n\r",$count_node,$count_node_all);
		}
    }
}

# --------------------------------------------
sub relation_ {
    my $id = $OSM_OBJ->{id};

    if ( @{$OSM_OBJ->{member}} > 0 ) {
	$OSM_RELATIONS->{$id} = $OSM_OBJ;
	$count_relation++;
    }
    $OSM_OBJ = undef;
}

sub relation {
    my($p, $tag, %attrs) = @_;
    my $id = delete $attrs{id};
    
    $OSM_OBJ = {};
    $OSM_OBJ->{element}="relation";
	$OSM_OBJ->{id} = $id;
    	
    delete $attrs{timestamp} if defined $attrs{timestamp};

    print "\n" if !$count_relation_all && ($VERBOSE || $DEBUG);
    $count_relation_all++;
    printf("relation %d(%d)\n\r",$count_relation,$count_relation_all)
	if !( $count_relation_all % 1000 ) && ($VERBOSE || $DEBUG);
    }

#<member type="way" ref="25048339" role=""/>
sub member {
    my($p, $tag, %attrs) = @_;

    my $type = $attrs{type};
    my $id = $attrs{ref};
    my $role = $attrs{role};

#    if ($type eq "way") {
#
#	    if ($role eq "outer") {
#
#	        if (!defined($missing_ways->{$id})) {
#				#bud vyrobim zoznam toho co treba stiahnut
#				#alebo to stiahnem hned
#				# treba stihanut way :)
#				#$result = mirror_file($url,$current_file);
#				#$OSM_OBJ = {};
#    			#$OSM_OBJ->{element} = "way";
#    			#$OSM_OBJ->{id} = $id;
#				push(@{$missing_ways->{$id}},$id );
#			}
#		}
#    }
    
    if ($type eq "node") {
        #return if (!defined($OSM_NODES->{$id}));
    }

    if (($OSM_OBJ->{element}) eq "relation") {
        my $OSM_MEMBER = {};
        $OSM_MEMBER->{type}=$type;
        $OSM_MEMBER->{role}=$role;
        $OSM_MEMBER->{ref}=$id;
        push(@{$OSM_OBJ->{member}},$OSM_MEMBER );
        $OSM_MEMBER= undef;
    }
}


sub member_ {
# nothing
}
# --------------------------------------------
sub way_ {
    my $id = $OSM_OBJ->{id};
     
    if ( @{$OSM_OBJ->{nd}} > 1 ) {
	$OSM_WAYS->{$id} = $OSM_OBJ;
	$count_way++;
    }
    $OSM_OBJ = undef;
}

sub way {
    my($p, $tag, %attrs) = @_;  
    my $id = delete $attrs{id};
    $OSM_OBJ = {};
    $OSM_OBJ->{element} = "way";
    $OSM_OBJ->{id} = $id;
    
    #reset $previous_nd
    $previous_nd=0;
    
    delete $attrs{timestamp} if defined $attrs{timestamp};

    if ( keys %attrs ) {
	warn "way $id has extra attrs: ".Dumper(\%attrs);
    }

    print "\n" if !$count_way_all && ($VERBOSE || $DEBUG);
    $count_way_all++;
    printf("way %d(%d)\n\r",$count_way,$count_way_all)
	if !( $count_way_all % 1000 ) && ($VERBOSE || $DEBUG);
}

sub nd {
    my($p, $tag, %attrs) = @_;
    
    my $id = $attrs{ref};

    delete $attrs{timestamp} if defined $attrs{timestamp};
    #return if (!defined($OSM_NODES->{$id}));

    if (($OSM_OBJ->{element}) eq "way")
    {

        # do not make 2 or more duplicate nd in one chain
        if ($previous_nd ne $id) {
            push(@{$OSM_OBJ->{nd}},$id);
            $previous_nd =$id;
        }
    }
}
# --------------------------------------------
sub tag {
    my($p, $tag, %attrs) = @_;  
    #print "Tag - $tag: ".Dumper(\%attrs);
    my $k = delete $attrs{k};
    my $v = delete $attrs{v};
    delete $attrs{timestamp};

    return if $k eq "created_by";

    if ( keys %attrs ) {
		print "Unknown Tag value for ".Dumper($OSM_OBJ)."Tags:".Dumper(\%attrs);
    }

    my $id = $OSM_OBJ->{id};
    if ( defined( $OSM_OBJ->{tag}->{$k} ) &&
	 	$OSM_OBJ->{tag}->{$k} ne $v
	 ) {
	printf "Tag %8s already exists for obj(id=$id) tag '$OSM_OBJ->{tag}->{$k}' ne '$v'\n",$k ;
    }
    $OSM_OBJ->{tag}->{$k} = $v;
    if ( $k eq "alt" ) {
	$OSM_OBJ->{alt} = $v;
    }
}

############################################
# -----------------------------------------------------------------------------
sub read_osm_file($) { 
    my $file_name = shift;


	my $p = XML::Parser->new( Style => 'Subs' , ErrorContext => 10);
	if (-s $file_name > 200) {
	    print STDERR "Parsing file: $file_name\n" if $DEBUG;
	    


	    my $fh = data_open($file_name);
	    die "Cannot open OSM File $file_name\n" unless $fh;
	    #eval {
		$p->parse($fh);
	    #};
	    print "\n" if $DEBUG || $VERBOSE;
	    #if ( $VERBOSE) {
	    #    printf "Read and parsed $file_name in %.0f sec\n",time()-$start_time;
	    #}
    }
	if ( $@ ) {
	warn "$@Error while parsing\n $file_name\n";
	return;
    }
    if (not $p) {
	warn "WARNING: Could not parse osm data\n";
	return;
    }
    return;
}

sub analyze_missing_relations() {
		print "processing relations (mode $mode)\n" if ($VERBOSE || $DEBUG);
	for my $relation_id ( sort {$a <=> $b} keys %{$OSM_RELATIONS} ) {
		next unless $relation_id;
        my $relation = $OSM_RELATIONS->{$relation_id};
		if ( defined( $relation->{tag}->{type} ) &&
		 	$relation->{tag}->{type} eq "multipolygon" &&
			 ( !defined($relation->{tag}->{layer}) || $relation->{tag}->{layer} ne "-5" )  ||
			(defined( $relation->{tag}->{type} ) &&
		 	$relation->{tag}->{type} eq "boundary" && $mode eq "boundary" ) ) {
			print "in $relation_id\n" if ($VERBOSE || $DEBUG);

            for my $relation_member ( @{$relation->{member}} ) {
			    next unless $relation_member;
		        my $ref =$relation_member->{ref};
		        my $role =$relation_member->{role};
		        my $type =$relation_member->{type};

				if ($type eq "way" && $role eq "outer") {
					if (!defined $OSM_WAYS->{$ref}) {
					print " $ref" if ($VERBOSE || $DEBUG);
                    push(@{$missing_ways->{$ref}},$ref );
					my $tmpwayfile = $tmpdir . "way_" . $ref . ".osm";
					my $result = mirror_file($TRAPI_URL. $ref,$tmpwayfile);
                    read_osm_file($tmpwayfile);
					unlink($tmpwayfile) if !$DEBUG;
					$count_downloaded ++;
					}

				}
				
			}
            print " \n\n" if ($VERBOSE || $DEBUG);
		}
	}
}


########################################################################################
########################################################################################
########################################################################################
#
#                     Main
#
########################################################################################
########################################################################################
########################################################################################


# Set defaults and get options from command line
Getopt::Long::Configure('no_ignore_case');
GetOptions ( 
	     'debug+'              => \$DEBUG,      
	     'd+'                  => \$DEBUG,      
	     'verbose+'            => \$VERBOSE,
	     'MAN'                 => \$man, 
	     'man'                 => \$man, 
	     'h|help|x'            => \$help, 

	     'no-mirror'           => \$Utils::LWP::Utils::NO_MIRROR,
	     'proxy=s'             => \$Utils::LWP::Utils::PROXY,

	     'osm-file=s'          => \$osm_file,
	     'out=s'               => \$output,
	     'url=s'               => \$used_url,
	     'mode=s'               => \$mode
	     );

die "No existing osm File $osm_file\n" 
    unless -s $osm_file;
# Store downloaded files in the same directory, as $osm_file"
($tmpfile, $tmpdir) = fileparse($osm_file);

if (!defined($output)) {
	$output = $osm_file;
	$output =~ s/\.osm(\.gz|\.bz2)?$/-amr.osm/;
}

if ($used_url eq 'mid') {
	$used_url = $TRAPI_URL;
	} elsif ($used_url eq 'low') {
    	$used_url = $TRAPI_LOW_URL;
	} else {
    die "invalid URL parameter definition\n"
	}

if ($mode eq 'boundary') {
	} elsif ($mode eq 'multipolygon') {
	} else {
    die "invalid mode parameter definition\n"
	}


my $OSM = {};
$OSM->{tool}     	= 'analyze_missing_relations.pl';
$OSM->{bounds}   	= $OSM_BOUNDS;
$OSM->{nodes}    	= $OSM_NODES;
$OSM->{ways}     	= $OSM_WAYS;
$OSM->{relations}   = $OSM_RELATIONS;


# Make sure we can create the output file before we start processing data
open(OUTFILE, ">$output") or die "Can't write to $output: $!";
close OUTFILE;

my $start_time=time();

die "No OSM file specified\n" unless $osm_file;

print "Unpack and Read OSM Data from file $osm_file\n" if $VERBOSE || $DEBUG;
print "$osm_file:	".(-s $osm_file)." Bytes\n" if $DEBUG;


read_osm_file($osm_file);
analyze_missing_relations();
write_osm_file($output, $OSM);

print " Downloaded additional '$count_downloaded' ways\n ";

printf "$output produced from $osm_file in %.0f sec\n\n",time()-$start_time;

exit 0;

##################################################################
# Usage/manual

__END__

=head1 NAME

B<simplify.pl> Version 0.02

=head1 DESCRIPTION

B<simplify.pl> is a program to download the planet.osm
Data from Openstreetmap and reduce shrink the data set
by removing data of less than a given size (in degrees).

This Programm is completely experimental, but some Data 
can already be retrieved with it.

So: Have Fun, improve it and send me fixes :-))

=head1 SYNOPSIS

B<Common usages:>

simplify.pl [-d] [-v] [-h] --simplify=<Degrees> [--osm-file=planet.osm] [--out=<filename>]

=head1 OPTIONS

=over 2

=item B<--man> Complete documentation

Complete documentation

=item B<--no-mirror>

Do not try mirroring the files from the original Server. Only use
files found on local Filesystem.

=item B<--proxy>

use proxy for download

=item B<--osm-file=path/planet.osm>

Select the "path/planet.osm" file to use for the checks

=item B<--simplify=0.1>

Remove all features of less then "0.1" degrees

=back
