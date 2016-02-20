# Einlesen der GpsDrive Track Daten und schreiben in die geoinfo Datenbank von 
# gpsdrive
#
# $Log$
# Revision 1.2  2005/10/11 08:28:35  tweety
# gpsdrive:
# - add Tracks(MySql) displaying
# - reindent files modified
# - Fix setting of Color for Grid
# - poi Text is different in size depending on Number of POIs shown on
#   screen
#
# geoinfo:
#  - get Proxy settings from Environment
#  - create tracks Table in Database and fill it
#    this separates Street Data from Track Data
#  - make geoinfo.pl download also Opengeodb Version 2
#  - add some poi-types
#  - Split off Filling DB with example Data
#  - extract some more Funtionality to Procedures
#  - Add some Example POI for Kirchheim(Munich) Area
#  - Adjust some Output for what is done at the moment
#  - Add more delayed index generations 'disable/enable key'
#  - If LANG=*de_DE* then only impert europe with --all option
#  - WDB will import more than one country if you wish
#  - add more things to be done with the --all option
#
# Revision 1.1  2005/08/15 13:54:22  tweety
# move scripts/POI --> scripts/Geo/Gpsdrive to reflect final Structure and make debugging easier
#
# Revision 1.8  2005/08/14 09:47:17  tweety
# seperate tracks into it own table in geoinfo database
# move Info's from TODO abaout geoinfo DB to Man Page
# rename poi.pl to geoinfo.pl
#
# Revision 1.7  2005/08/09 01:08:30  tweety
# Twist and bend in the Makefiles to install the DataDirectory more apropriate
# move the perl Functions to Geo::Gpsdrive in /usr/share/perl5/Geo/Gpsdrive/POI
# adapt icons.txt loading according to these directories
#
# Revision 1.6  2005/07/07 06:45:23  tweety
# Autor: Blake Swadling <blake@swadling.com>
# Autor: John Hay <jhay@icomtek.csir.co.za>
# Honor Makefile src
# honor +- in import track
# update TODO
#
# Revision 1.5  2005/04/13 19:58:30  tweety
# renew indentation to 4 spaces + tabstop=8
#
# Revision 1.4  2005/04/10 00:15:58  tweety
# changed primary language for poi-type generation to english
# added translation for POI-types
# added some icons classifications to poi-types
# added LOG: Entry for CVS to some *.pm Files
#

package Geo::Gpsdrive::GpsDrive;

use strict;
use warnings;

use IO::File;
use File::Basename;
use File::Path;
use Date::Manip;
use Time::Local;

#use Data::Dumper;

use Geo::Gpsdrive::DBFuncs;
use Geo::Gpsdrive::Utils;
use Geo::Gpsdrive::Gps;

use Geo::Gpsdrive::DB_tracks;

my $multi_insert=1; # Insert with a multicommand all segments of a sub-track at once
                    # 0=insert each segment of track as it is processed
$|=1;

##########################################################################

sub import_GpsDrive_track_file($$){
    my $full_filename = shift;
    my $source_id     = shift;

    print "Reading Track File $full_filename\n";

    my $fh = IO::File->new("<$full_filename");

    my ($lat1,$lon1,$alt1,$time1) = (0,0,0,0);
    my ($lat2,$lon2,$alt2,$time2) = (0,0,0,0);

    my $track_nr=0;
    my $segments_in_track=0;
    my $segments=[];
    while ( my $line = $fh->getline() ) {
	my $valid=0;
	my $tracks_type_id = 2;

	chomp $line;
#	print "line: $line\n";
	#48.175667  11.754383        561 Tue May 18 18:28:04 2004

	( $lat1,$lon1,$alt1,$time1 ) = ( $lat2,$lon2,$alt2,$time2 );

	( $lat2,$lon2,$alt2,$time2 ) = (0,0,0,0);

        if ($line =~ m/^\s*(-?\d{1,3}\.\d+)\s+(-?\d{1,3}\.\d+)\s+(-?[\d\.]+)\s+(\S+\s+\S+\s+\d+\s+[\d\:]+\s+\d+)/ ) {
            $lat2  = $1;
            $lon2  = $2;
            $alt2  = $3;
            my $date = ParseDate($4);
	    #       Wed Dec 10 09:38:24 2003
	    $time2 = UnixDate($date,"%s");
	    $valid=1;
	} elsif ( $line =~ m/^\s*$/)  {
        } elsif ( $line =~ m/^\s*nan\s*nan\s*/)  {
        } elsif ( $line =~ m/^\s*1001.000000 1001.000000\s*/)  {           
        } else {
            print "Unparsed Line '$line'";
        }

	next unless $valid;


	my $dist = Geo::Gpsdrive::Gps::earth_distance($lat1,$lon1,$lat2,$lon2);;
	my $time_delta = $time2 - $time1;
	my $speed      = $valid&&$time_delta ? $dist / $time_delta * 3.600 : -1;
	#printf "Dist: %.4f/%.2f =>  %.2f\n",$dist,$time_delta,$speed;
	$tracks_type_id = 1 if ( $speed >0 );
	$tracks_type_id = 2 if ( $speed >30 );
	$tracks_type_id = 3 if ( $speed >60 );
	$tracks_type_id = 4 if ( $speed >100 );

	if ( $alt2 == 1001 ) { # Otherwise I assume it was POS Mode
	    debug("Altitude = 1001");
	    $valid=0;
	}

	if ( $time_delta >300 ) {
	    debug( "Time diff = $time_delta");
	    $valid = 0;
	}

	if ( $speed >400 ) {
	    debug("Speed = $speed");
	    debug("But ignoring, because time accuracy =1 sec ==> speed not accurate");
	    $valid = 0;
	}

	if ( $dist > 1000  ) {
	    debug(sprintf("earth_distance($lat1,$lon1,$lat2,$lon2) => %.2f\n",$dist));
	    $valid = 0;
	}

	if ( $lat2 > 500 ||
	     $lon2 > 500 
	     ) {
	    print "lat/lon >500\n";
	    $valid = 0;
	}
	
	if ( $valid ) {
	    if ( ! $multi_insert ) {
		Geo::Gpsdrive::DBFuncs::track_add(
				  { lat1 => $lat1, lon1 => $lon1, alt1 => $alt1,
				    lat2 => $lat2, lon2 => $lon2, alt2 => $alt2,
				    level_min => 0, level_max => 99,
				    tracks_type_id => $tracks_type_id, 
				    name => "$dist $full_filename",
				    source_id => $source_id
				    }
				      );
		} else {
		    push(@{$segments},[$lat2,$lon2,$alt2,$time2]);
		}
	    $segments_in_track++;
	} else {
	    if ( $segments_in_track ) {
		$track_nr ++;
		print "Tracks: $track_nr ($segments_in_track Segments)\n"
		    	if $debug;
		if ( $multi_insert ) {
		    # Check for pos mode
		    my $pos_mode=1;
		    for my $segment ( @{$segments} ) {
			if ( $segment->[2] != 0 ) { 
			    $pos_mode=0; # I assume it was not POS Mode
			    last;
			}
		    }
		    
		    if ( $pos_mode ) {
			print "pos mode\n";
		    } else {
			tracks_add(
			       { segments => $segments,
				 level_min => 0, level_max => 99,
				 tracks_type_id => $tracks_type_id, 
				 name => "$dist $full_filename",
				 source_id => $source_id
				 }
				   );
			};
		    $segments=[];
		}
	    }
	    $segments_in_track=0;
	}
    }
}




# *****************************************************************************
sub import_Data(){

    my $gpsdrive_dir = "$main::CONFIG_DIR/";
    my $source = "Gpsdrive Tracks";

    print "\n";
    print "Reading and importing Gpsdrive Tracks\n";

    delete_all_from_source($source);

    my $source_id = Geo::Gpsdrive::DBFuncs::source_name2id($source);

    unless ( $source_id ) {
	my $source_hash = {
	    'source.url'     => "",
	    'source.name'    => $source ,
	    'source.comment' => 'My own Tracks' ,
	    'source.licence' => "It's up to myself"
	    };
	Geo::Gpsdrive::DBFuncs::insert_hash("source", $source_hash);
	$source_id = Geo::Gpsdrive::DBFuncs::source_name2id($source);
    }
    

    
    disable_keys('tracks');

    debug("$gpsdrive_dir/{tracks}/*.sav");
    foreach  my $full_filename ( glob("$gpsdrive_dir/*.sav"),
				 glob("$gpsdrive_dir/tracks/*.sav") ) {
	import_GpsDrive_track_file($full_filename,$source_id);
    }

    enable_keys('tracks');
    print "Finished reading and importing Gpsdrive Tracks\n";
}

1;
