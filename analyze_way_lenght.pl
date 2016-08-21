#!/usr/bin/perl


my $VERSION ="analyze_way_lenght.pl (C)2011 Jozef Vince, Freemap Slovakia";

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

use constant PI => 4 * atan2 1, 1;
use constant DEGRAD => PI / 180;
#use constant RADIUS => 6367000.0;
use constant RADIUS => 6378135.618;


my ($man,$help);

our $osm_file; # The complete osm Filename (including path)


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
our $mode; 
my $previous_nd =0;
my $count_downloaded =0;
my $used_url = 'mid';

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

sub analyze_way_length() {

	for my $way_id ( sort {$a <=> $b} keys %{$OSM_WAYS} ) {
		next unless $way_id;

		my $way = $OSM_WAYS->{$way_id};
    	next unless scalar( @{$way->{nd}} )>1;

#	print $fh "  <way id=\'$way_id\'";
#	print $fh " timestamp=\'".$way->{timestamp}."\'"
#	    if defined $way->{timestamp};
#	print $fh ">\n";
        my $way_nd_counter = 0;
	    my $lat = 0;
	    my $lon = 0;
	    my $way_length = 0;

		for my $way_nd ( @{$way->{nd}} ) {
		    next unless $way_nd;
            
			my $node = $OSM_NODES->{$way_nd};
			if ($node){
				$way_nd_counter++;

				if ($way_nd_counter != 1) {
					if ($mode eq "merc") {
						$way_length += calc_distance_merc($lat, $lon, $node->{lat}, $node->{lon});
					} else {
						$way_length += calc_distance($lat, $lon, $node->{lat}, $node->{lon});
                    }
				}
                $lat = $node->{lat};
				$lon = $node->{lon};
			}

		}
		$way->{tag}{length} =$way_length;

	}
}

sub calc_distance {
    my ($lat1, $lon1, $lat2, $lon2) = @_;

    ($lat1, $lon1, $lat2, $lon2) = ($lat1 * DEGRAD, $lon1 * DEGRAD, $lat2 * DEGRAD, $lon2 * DEGRAD);

    my $dlon = ($lon2 - $lon1);
    my $dlat = ($lat2 - $lat1);
    my $a = (sin($dlat/2))**2 + cos($lat1) * cos($lat2) * (sin($dlon/2))**2;
    my $c = 2 * atan2(sqrt($a), sqrt(1-$a)) ;
    return RADIUS * $c;
}

sub calc_distance_merc {
    my ($lat1, $lon1, $lat2, $lon2) = @_;

    my $dlon = ($lon2 - $lon1);
    my $dlat = ($lat2 - $lat1);

    return (sqrt($dlon**2 + $dlat**2));
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
	     'no-mirror'           => \$Utils::LWP::Utils::NO_MIRROR,
	     'proxy=s'             => \$Utils::LWP::Utils::PROXY,

	     'in-file=s'          => \$osm_file,
	     'out-file=s'               => \$output,
         'mode=s'               => \$mode,
	     );

die "No existing osm File $osm_file\n" 
    unless -s $osm_file;

if (!defined($output)) {
	$output = $osm_file;
	$output =~ s/\.osm(\.gz|\.bz2)?$/-awl.osm/;
}

my $OSM = {};
$OSM->{tool}     = 'analyze_way_lenght.pl';
$OSM->{nodes}    = $OSM_NODES;
$OSM->{ways}     = $OSM_WAYS;
$OSM->{relations}     = $OSM_RELATIONS;

# Make sure we can create the output file before we start processing data
open(OUTFILE, ">$output") or die "Cant write to $output: $!";
close OUTFILE;

my $start_time=time();

die "No OSM file specified\n" unless $osm_file;

print "Unpack and Read OSM Data from file $osm_file\n" if $VERBOSE || $DEBUG;
print "$osm_file:	".(-s $osm_file)." Bytes\n" if $DEBUG;


read_osm_file($osm_file);
analyze_way_length();
write_osm_file($output, $OSM);

printf "$output produced from $osm_file in %.0f sec\n\n",time()-$start_time if $VERBOSE ;

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
