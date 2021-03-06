#!/usr/bin/perl

use lib '.';

use LWP::Simple;
use LWP::UserAgent;
use Math::Trig;
use File::Copy;
use Digest::MD5 qw(md5_hex);
use File::Temp qw(tempfile);
use FindBin qw($Bin);
use tahconfig;
use tahlib;
use English '-no_match_vars';
use GD qw(:DEFAULT :cmp);
use strict;
use POSIX qw(locale_h);

#-----------------------------------------------------------------------------
# OpenStreetMap tiles@home
#
# Contact OJW on the Openstreetmap wiki for help using this program
#-----------------------------------------------------------------------------
# Copyright 2006, Oliver White, Etienne Cherdlu, Dirk-Lueder Kreie,
# Sebastian Spaeth and others
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#-----------------  ------------------------------------------------------------
# Read the config file
my %Config = ReadConfig(
    "freemapdiskclient.conf", "general.conf",
    "authentication.conf",    "layers.conf",
    "freemapdisk.conf"
);
$Config{"LowZoom"} = 1 unless defined( $Config{"LowZoom"} );

# detect the current system locale: comma (,) => SK, dot (.) => EN
my ($decimalSep) = @{localeconv()}{"mon_decimal_point"};

printf STDERR "-- Running as PID: %d\n", $PID;
my %EnvironmentInfo = CheckConfig(%Config);

# Get version number from version-control system, as integer
my $Version = '$Revision: 5175 $';
my $VerifyHash;
$Version =~ s/\$Revision:\s*(\d+)\s*\$/$1/;

printf STDERR "This is version %d (%s) of tilesgen running on %s\n", $Version,
  $Config{ClientVersion}, $^O;

# check GD
eval GD::Image->trueColor(1);
if ( $@ ne '' ) {
    print STDERR "please update your libgd to version 2 for TrueColor support";
    exit(3);
}

# Setup GD options
# currently unused (GD 2 truecolor mode)
#
#   my $numcolors = 256; # 256 is maximum for paletted output and should be used
#   my $dither = 0; # dithering on or off.
#
# dithering off should try to find a good palette, looks ugly on
# neighboring tiles with different map features as the "optimal"
# palette is chosen differently for different tiles.

# create a comparison blank image
my $EmptyLandImage = new GD::Image( 256, 256 );
my $MapLandBackground = $EmptyLandImage->colorAllocate( 248, 248, 248 );
$EmptyLandImage->fill( 127, 127, $MapLandBackground );
my $EmptySeaImage = new GD::Image( 256, 256 );
my $MapSeaBackground = $EmptySeaImage->colorAllocate( 181, 214, 241 );
$EmptySeaImage->fill( 127, 127, $MapSeaBackground );

# Some broken versions of Inkscape occasionally produce totally black
# output. We detect this case and throw an error when that happens.
my $BlackTileImage = new GD::Image( 256, 256 );
my $BlackTileBackground = $BlackTileImage->colorAllocate( 0, 0, 0 );
$BlackTileImage->fill( 127, 127, $BlackTileBackground );

# set the progress indicator variables
my $currentSubTask;
my $progress        = 0;
my $progressJobs    = 0;
my $progressPercent = 0;

# Check the on disk image tiles havn't been corrupted
if ( -s "emptyland.png" != 67 ) {
    print STDERR
"Corruption detected in emptyland.png. Trying to redownload from svn automatically.\n";
    statusMessage( "Downloading: emptyland.png",
        $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent, 0 );
    DownloadFile(
"http://svn.openstreetmap.org/applications/rendering/tilesAtHome/emptyland.png"
        ,    # TODO: should be svn update, instead of http get...
        "emptyland.png",
        0
    );       ## 0=delete old file from disk first
}
if ( -s "emptysea.png" != 69 ) {
    print STDERR
"Corruption detected in emptysea.png. Trying to redownload from svn automatically.\n";
    statusMessage( "Downloading: emptysea.png",
        $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent, 0 );
    DownloadFile(
"http://svn.openstreetmap.org/applications/rendering/tilesAtHome/emptysea.png"
        ,    # TODO: should be svn update, instead of http get...
        "emptysea.png",
        0
    );       ## 0=delete old file from disk first
}

# Check the on disk image tiles are now in order
if (   -s "emptyland.png" != 67
    or -s "emptysea.png" != 69 )
{
    print STDERR "\nAutomatic fix failed. Exiting.\n";
    cleanUpAndDie( "init.emptytile_template_check", "EXIT", 4, $PID );
}

# Setup map projection
my $LimitY  = ProjectF(85.0511);
my $LimitY2 = ProjectF(-85.0511);
my $RangeY  = $LimitY - $LimitY2;

# Create the working directory if necessary
mkdir $Config{WorkingDirectory} if ( !-d $Config{WorkingDirectory} );

# keep track of time running
my $progstart = time();
my $dirent;

# keep track of the server time for current job
my $JobTime;

# Handle the command-line
my $Mode = shift();
my $ConfigName;

if ( $Mode eq "config" ) {

    my $ConfigName = shift();

    if ( not defined $ConfigName ) {
        die "Must specify config file name \n";
    }
    AppendConfig($ConfigName);

    # precitam dalsi prikaz
    $Mode = shift();
}
if ( $Mode eq "xy" ) {

    # ----------------------------------
    # "xy" as first argument means you want to specify a tileset to render
    # ----------------------------------
    my $X = shift();
    my $Y = shift();

    if ( not defined $X or not defined $Y ) {
        die "Must specify tile coordinates\n";
    }
    my $Zoom = shift();
    GenerateTileset( $X, $Y, $Zoom );
}
elsif ( $Mode eq "loop" ) {

    # create PID file...  loop until PID file exists
    if ( open( FAILFILE, ">", "./$PID.pid" ) ) {
        print FAILFILE $PID;
        close FAILFILE;
    }

    # ----------------------------------
    # Continuously process requests from server
    # ----------------------------------

    # if this is a re-exec, we want to capture some of our status
    # information from the command line. this feature allows setting
    # any numeric variable by specifying "variablename=value" on the
    # command line after the keyword "reexec". Currently unsuitable
    # for alphanumeric variables.

    if ( shift() eq "reexec" ) {
        while ( my $evalstr = shift() ) {
            die unless $evalstr =~ /^[A-Za-z]+=\d+/;
            eval( '$' . $evalstr );
        }
    }

    # this is the actual processing loop

    while ( -e "./$PID.pid" ) {
        reExecIfRequired();
        my ( $did_something, $message ) = ProcessRequestsFromServer();
        uploadIfEnoughTiles();
        if ( $did_something == 0 ) {
            talkInSleep( $message, 300 );
        }
        else {
            setIdle( 0, 0 );
        }

    }
    print("endless loop terminated :)");
    exit(1);
}
elsif ( $Mode eq "" ) {

    # ----------------------------------
    # Normal mode downloads request from server
    # ----------------------------------
    my ( $did_something, $message ) = ProcessRequestsFromServer();

    talkInSleep( $message, 300 ) unless ($did_something);

}

else {

    # ----------------------------------
    # "help" as first argument tells how to use the program
    # ----------------------------------
    my $Bar = "-" x 78;
    print "\n$Bar\nOpenStreetMap tiles\@home client\n$Bar\n";
    print "Usage: \n";
    print "Specific area:\n  \"$0 xy [x] [y] [zoom]\"\n  (x and y coordinates of a zoom-zoom tile in the slippy-map coordinate system)\n  See [[Slippy Map Tilenames]] on wiki.openstreetmap.org for details\n";
    print "Other modes:\n";
    print "  $0 loop - runs continuously\n";
    print "  $0 version - prints out version string and exits\n";
    print "\nGNU General Public license, version 2 or later\n$Bar\n";

}

sub uploadIfEnoughTiles {
    my $Count = 0;

    # compile a list of the "Prefix" values of all configured layers,
    # separated by |
    my $allowedPrefixes = join( "|",
        map( $Config{"Layer.$_.Prefix"}, split( /,/, $Config{"LowLayers"} ) ) );

    opendir( my $dp, $Config{WorkingDirectory} ) || return;
    while ( my $File = readdir($dp) ) {
        $Count++ if ( $File =~ /($allowedPrefixes)_.*\.png/ );
    }
    closedir($dp);

    if ( $Count < 1 ) {

        # print "Not uploading yet, only $Count tiles\n";
    }
    else {
        upload();
    }
}

sub upload {
    ## Run upload directly because it uses same messaging as tilesGen.pl,
    ## no need to hide output at all.

    my $UploadScript = "perl $Bin/lowzoomupload.pl $progressJobs";
    if ( defined $ConfigName ) {
        $UploadScript = "perl $Bin/lowzoomupload.pl config $ConfigName $progressJobs";
    }
    my $retval = system($UploadScript);
    return $retval;
}

#-----------------------------------------------------------------------------
# Ask the server what tileset needs rendering next
#-----------------------------------------------------------------------------
sub ProcessRequestsFromServer {
    my $LocalFilename = $Config{WorkingDirectory} . "request-" . $PID . ".txt";

    if ( $Config{"LocalSlippymap"} ) {
        print "Config option LocalSlippymap is set. Downloading requests\n";
        print "from the server in this mode would take them from the tiles\@home\n";
        print "queue and never upload the results. Program aborted.\n";
        cleanUpAndDie( "ProcessRequestFromServer:LocalSlippymap set, exiting",
            "EXIT", 1, $PID );
    }

    # ----------------------------------
    # Download the request, and check it
    # Note: to find out exactly what this server is telling you,
    # add ?help to the end of the URL and view it in a browser.
    # It will give you details of other help pages available,
    # such as the list of fields that it's sending out in requests
    # ----------------------------------
    killafile($LocalFilename);
    my $RequestUrlString =
        $Config{DiSKRequestLowURL}
      . "&Email="
      . $Config{DiSKUsername}
      . "&ClientVersion="
      . $Config{DiSKAPIVersion}
      . "&PasswordMD5="
      . md5_hex( $Config{DiSKPassword} );

    print ("using URL " . $RequestUrlString . "\n") if ( $Config{Debug} );
    DownloadFile( $RequestUrlString, $LocalFilename, 0 );

    if ( !-f $LocalFilename ) {
        return ( 0, "Error reading request from server" );
    }

    # Read into memory
    open( my $fp, "<", $LocalFilename ) || return;
    my $Request = <$fp>;
    chomp $Request;
    close $fp;

    # Parse the request
    my ( $ValidFlag, $ClientVersion, $X, $Y, $Z, $ModuleName, $VerifyString, $StylesheetVersion) =
      split( /\|/, $Request );

    # Check what format the results were in
    # If you get this message, please do check for a new version, rather than
    # commenting-out the test - it means the field order has changed and this
    # program no longer makes sense!
    if ( $ClientVersion != $Config{DiSKAPIVersion} ) {
        #print STDERR "\n";
        #print STDERR "Server is speaking a different version of the protocol to us.\n";
        #print STDERR "Check to see whether a new version of this program was released!\n";
        #cleanUpAndDie("ProcessRequestFromServer:Request API version mismatch, exiting",
        #              "EXIT", 1, $PID );
        return ( 0, "Server has some difficulties, waiting for a while" );
    }

    if ( $StylesheetVersion != $Config{StylesheetVersion} ) {
        if ( $ValidFlag eq "OK" ) {
            PutRequestBackToServer( $X, $Y, $Z, "OldStyleSheets" );
            }
        print STDERR "\n";
        print STDERR "Server has a different version of stylesheets.\n";
        print STDERR "You should update your client to render consistent map!\n";
        cleanUpAndDie("ProcessRequestFromServer:Stylesheet version mismatch, exiting",
                      "EXIT", 1, $PID );
        ## No need to return, we exit the program at this point
    }

    # First field is always "OK" if the server has actually sent a request
    if ( $ValidFlag eq "XX" ) {
        return ( 0, "Server has no work for us ($ModuleName)" );
    }
    elsif ( $ValidFlag ne "OK" ) {
        return ( 0, "Server dysfunctional ($ModuleName)" );
    }

    # Information text to say what's happening
    statusMessage("Got work from the \"$ModuleName\" server module");

    $VerifyHash = $VerifyString;

    # DEBUG: print "$VerifyHash\n";
    # Create the tileset requested
    GenerateTileset( $X, $Y, $Z );
    return ( 1, "" );
}

sub PutRequestBackToServer {
    ## TODO: will not be called in some libGD abort situations
    my ( $X, $Y, $Z, $Cause ) = @_;

    ## do not do this if called in xy mode!
    return if ( $Mode eq "xy" );

    my $Prio = $Config{ReRequestPrio};

    my $LocalFilename =
      $Config{WorkingDirectory} . "requesting-" . $PID . ".txt";

    killafile($LocalFilename) if ( !$Config{Debug} );    # maybe not necessary if DownloadFile is called correctly?

    my $RequestUrlString =
      $Config{DiSKReRequestURL} . "&TileX=" . $X . "&TileY=" . $Y . "&Zoom=" .$Z ."&Verify=&Message=" . $Cause;

    statusMessage( "Putting Job " . $X . "," . $Y . "@" . $Z . " back to server",
        $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent, 0 );
    DownloadFile( $RequestUrlString, $LocalFilename, 0 );

    if ( !-f $LocalFilename ) {
        return ( 0, "Error reading response from server" );
    }

    # Read into memory
    open( my $fp, "<", $LocalFilename ) || return;
    my $Request = <$fp>;
    chomp $Request;
    close $fp;

    ## TODO: Check response for "OK" or "Duplicate Entry" (which would be OK, too)

    killafile($LocalFilename) if ( !$Config{Debug} );    # don't leave old files laying around

}

#-----------------------------------------------------------------------------
# Render a tile (and all subtiles, down to a certain depth)
#-----------------------------------------------------------------------------
sub GenerateTileset {
    my ( $X, $Y, $Zoom ) = @_;

    my ( $N, $S ) = Project( $Y, $Zoom );
    my ( $W, $E ) = ProjectL( $X, $Zoom );
    
    printf "Source  (%s,%s): Lat %1.3f,%1.3f, Long %1.3f,%1.3f\n",
       $X, $Y, $N, $S, $W, $E
      if ( $Config{"Debug"} );

    $progress        = 0;
    $progressPercent = 0;
    $progressJobs++;
    $currentSubTask = "jobinit";

    my $maxCoords = ( 2**$Zoom - 1 );

    statusMessage(
        sprintf(
            "Doing tileset $X,$Y z%d (area around %f,%f) from Freemap TRAPI",
            $Zoom,
            ( $N + $S ) / 2,
            ( $W + $E ) / 2
        ),
        $Config{Verbose},
        $currentSubTask,
        $progressJobs,
        $progressPercent,
        1
    );

    if (   ( $X < 0 )
        or ( $X > $maxCoords )
        or ( $Y < 0 )
        or ( $Y > $maxCoords ) )
    {

        #maybe do something else here
        die("\n Coordinates out of bounds (0..$maxCoords)\n");
    }

    $currentSubTask = "Preproc";

    # Adjust requested area to avoid boundary conditions
    my $N1 = $N + ( $N - $S ) * $Config{BorderNLow};
    my $S1 = $S - ( $N - $S ) * $Config{BorderSLow};
    my $E1 = $E + ( $E - $W ) * $Config{BorderELow};
    my $W1 = $W - ( $E - $W ) * $Config{BorderWLow};

    # TODO: verify the current system cannot handle segments/ways crossing the
    # 180/-180 deg meridian and implement proper handling of this case, until
    # then use this workaround:

    if ( $W1 <= -180 ) {
        $W1 = -180;    # api apparently can handle -180
    }
    if ( $E1 > 180 ) {
        $E1 = 180;
    }

    $N = ProjectLat2Merc($N1);
    $S = ProjectLat2Merc($S1);
    $W = ProjectLon2Merc($W1);
    $E = ProjectLon2Merc($E1);

    my $bbox = sprintf( "%f,%f,%f,%f", $W1, $S1, $E1, $N1 );

    #------------------------------------------------------
    # Download data
    #------------------------------------------------------
    my $DataFile = $Config{WorkingDirectory} . "data-$PID.osm";

    killafile($DataFile);

    my $URLS;

    $URLS = sprintf( "%s/map?bbox=%s&zoom=%d%s", $Config{DiSKDataLowURL}, $bbox, $Zoom, $Config{DiSKDataLowURLPostfix} );
    printf( "%s\n", $URLS ) if ( $Config{Debug} );

# We only need the bounding box for ways (they will be downloaded completly,
# but need the extended bounding box for places (names from neighbouring tiles)
#   $URLS = sprintf(
#"%s%s/way[natural=*][bbox=%s] %s%s/way[boundary=*][bbox=%s] %s%s/way[landuse=*][bbox=%s] %s%s/way[highway=motorway|motorway_link|trunk|primary|secondary|tertiary][bbox=%s] %s%s/way[waterway=river][bbox=%s] %s%s/way[railway=*][bbox=%s] %s%s/node[place=*][bbox=%s]",
#                $Config{XAPIURL}, $Config{OSMVersion}, $bbox,
#                $Config{XAPIURL}, $Config{OSMVersion}, $bbox,
#                $Config{XAPIURL}, $Config{OSMVersion}, $bbox,
#                $Config{XAPIURL}, $Config{OSMVersion}, $bbox,
#                $Config{XAPIURL}, $Config{OSMVersion}, $bbox,
#                $Config{XAPIURL}, $Config{OSMVersion}, $bbox,
#                $Config{XAPIURL}, $Config{OSMVersion}, $bbox
#            );

    my @tempfiles;
    push( @tempfiles, $DataFile );

    my $filelist = [];
    my $i        = 0;
    foreach my $URL ( split( / /, $URLS ) ) {
        ++$i;

        my $partialFile;
        $partialFile = $Config{WorkingDirectory} . "data-$PID-$i.osm";

        push( @{$filelist}, $partialFile );
        push( @tempfiles,   $partialFile );

        statusMessage( "Downloading: Map data to $partialFile",
            $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent,
            0 );

        DownloadFile( $URL, $partialFile, 0 );

        if ( -s $partialFile == 0 ) {
            printf("No data here...\n");

            # if loop was requested just return  or else exit with an error.
            # (to enable wrappers to better handle this situation
            # i.e. tell the server the job hasn't been done yet)
            PutRequestBackToServer( $X, $Y, $Zoom, "NoData" );

            foreach my $file (@tempfiles) { killafile($file); }
            return 0 if ( $Mode eq "loop" );
            exit(1);
        }
    }

    mergeOsmFiles( $DataFile, $filelist );

# Get the server time for the data so we can assign it to the generated image (for tracking from when a tile actually is)
    $JobTime = [ stat $DataFile ]->[9];

 # Check for correct UTF8 (else inkscape will run amok later)
 # FIXME: This doesn't seem to catch all string errors that inkscape trips over.
    statusMessage( "Checking for UTF-8 errors in $DataFile",
        $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent, 0 );
    open( OSMDATA, $DataFile )
      || die("could not open $DataFile for UTF-8 check");
    my @toCheck = <OSMDATA>;
    close(OSMDATA);
    my $osmtagfound =0;
    while ( my $osmline = shift @toCheck ) {
        if ( utf8::is_utf8($osmline)) {
            # this might require perl 5.8.1 or an explicit use statement
            statusMessage(
                "found incorrect UTF-8 chars in $DataFile, job $X $Y  $Zoom",
                $Config{Verbose},
                $currentSubTask,
                $progressJobs,
                $progressPercent,
                1
            );
            PutRequestBackToServer( $X, $Y, $Zoom, "BadUTF8" );
            return 0 if ( $Mode eq "loop" );
            exit(1);
        }

        if ($osmline  =~ /\<\/osm\>/ ) {
            $osmtagfound=1;
        }


    }
    if ($osmtagfound ==0) {
            PutRequestBackToServer( $X, $Y, $Zoom, "InvalidData" );
            return 0 if ( $Mode eq "loop" );
            exit(1);
        }

    #------------------------------------------------------
    # Adjust OSM data
    #------------------------------------------------------
    my $AdjustCmd = sprintf("%s perl adjustosmdata.pl --in-file %s --out-file %s --actions addfmrel,joinmpmembers",
								$Config{Niceness}, "$DataFile", "$DataFile");
    statusMessage("Running OSM data adjustment", $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent, 0);
    runCommand($AdjustCmd, $PID);

    #------------------------------------------------------
    # Handle all layers, one after the other
    #------------------------------------------------------

    foreach my $layer ( split( /,/, $Config{"LowLayers"} ) ) {

        #reset progress for each layer
        $progress        = 0;
        $progressPercent = 0;
        $currentSubTask  = $layer;

        my $maxzoom = $Config{"Layer.$layer.MaxLowZoom"};
        my $minzoom = $Config{"Layer.$layer.MinLowZoom"};
        my $layerDataFile;

        if ( $minzoom <= $Zoom ) {

            # Faff around
            for ( my $i = $Zoom ; $i <= $maxzoom ; $i++ ) {
                killafile( $Config{WorkingDirectory} . "output-$PID-z$i.svg" );
            }

            my $Margin = " " x ( $Zoom - 8 );

        #printf "%03d %s%d,%d: %1.2f - %1.2f, %1.2f - %1.2f\n", $Zoom, $Margin, $X, $Y, $S,$N, $W,$E;

            #------------------------------------------------------
            # Go through preprocessing steps for the current layer
            #------------------------------------------------------
            my @ppchain = ($PID);

            # force the Mercator preprocessor
            my $LayerPreprocessor = $Config{"LowLayer.$layer.Preprocessor"};
			if (!($LayerPreprocessor =~ /\mercator/)) {
                if ($LayerPreprocessor eq "") {
                    $LayerPreprocessor = "mercator";
				} else {
                    $LayerPreprocessor .= ",mercator";
				}
            }
            
        # config option may be empty, or a comma separated list of preprocessors
            foreach my $preprocessor ( split /,/, $LayerPreprocessor ) {
                my $inputFile = sprintf( "%sdata-%s.osm", $Config{WorkingDirectory}, join( "-", @ppchain ) );
                push( @ppchain, $preprocessor );
                my $outputFile = sprintf( "%sdata-%s.osm", $Config{WorkingDirectory}, join( "-", @ppchain ) );

                if ( -f $outputFile ) {

        # no action; files for this preprocessing step seem to have been created
        # by another layer already!
                }
                elsif ( $preprocessor eq "close-areas" ) {
                    my $Cmd =
                      sprintf( "%s perl close-areas.pl $X $Y $Zoom < %s > %s",
                        $Config{Niceness}, "$inputFile", "$outputFile" );
                    statusMessage( "Running close-areas",
                        $Config{Verbose}, $currentSubTask, $progressJobs,
                        $progressPercent, 0 );
                    runCommand( $Cmd, $PID );
                }
                elsif ( $preprocessor eq "mercator" ) {
                    my $Cmd = sprintf( "%s perl mercatorize.pl -in-file %s -out-file %s -z $Zoom -x $X -y $Y -s 0",
                        $Config{Niceness}, "$inputFile", "$outputFile" );
                    statusMessage( "Running Mercatorization",
                        $Config{Verbose}, $currentSubTask, $progressJobs,
                        $progressPercent, 0 );
                    runCommand( $Cmd, $PID );
                }
                elsif ( $preprocessor eq "simplify" ) {
                    my $sfactor;
                    if ( $Zoom == 5 )  { $sfactor = 0.0439453125; }
                    if ( $Zoom == 6 )  { $sfactor = 0.02197265625; }
                    if ( $Zoom == 7 )  { $sfactor = 0.010986328125; }
                    if ( $Zoom == 8 )  { $sfactor = 0.0054931640625; }
                    if ( $Zoom == 9 )  { $sfactor = 0.00274658203125; }
                    if ( $Zoom == 10 ) { $sfactor = 0.001373291015625; }
                    if ( $Zoom == 11 ) { $sfactor = 0.0006866455078125; }

                    my $Cmd = sprintf("%s perl simplify.pl --osm-file=%s --out=%s --simplify=%f",
                        $Config{Niceness}, "$inputFile",
                        "$outputFile",     $sfactor
                    );
                    statusMessage( "Running Simplification",
                        $Config{Verbose}, $currentSubTask, $progressJobs,
                        $progressPercent, 0 );
                    runCommand( $Cmd, $PID );
            }  elsif ( $preprocessor eq "relation" ) {

                my $Cmd = sprintf("%s perl analyze_missing_relations.pl --url=low --osm-file=%s --out=%s",
                    $Config{Niceness}, "$inputFile",
                    "$outputFile"
                );
                statusMessage( "Running Analyze relations",
                    $Config{Verbose}, $currentSubTask, $progressJobs,
                    $progressPercent, 0 );
                runCommand( $Cmd, $PID );
            } elsif ( $preprocessor eq "simplifyNames" ) {
                    my $Cmd = sprintf( "%s SimplifyNames.exe -s %s -d %s",
                        $Config{Niceness}, "$inputFile", "$outputFile" );
                    statusMessage( "Running simplifyNames",
                        $Config{Verbose}, $currentSubTask, $progressJobs,
                        $progressPercent, 0 );
                    runCommand( $Cmd, $PID );
                }

     #elsif ($preprocessor eq "reduce")
     #{
     #my $Cmd = sprintf(
     #        "%s perl reduce.pl --osm-in=%s --osm-out=%s --layer=%s --zoom=%d",
     #        $Config{Niceness}, "$inputFile",
     #        "$outputFile",     $layer , $Zoom
     #    );
     #    statusMessage(
     #                  "Running Reduction", $Config{Verbose},
     #                  $currentSubTask,          $progressJobs,
     #                  $progressPercent,         0
     #    );
     #    runCommand($Cmd, $PID);
     #
     #}
                else {
                    die "Invalid preprocessing step '$preprocessor'";
                }
                push( @tempfiles, $outputFile );
            }

            #------------------------------------------------------
            # Preprocessing finished, start rendering
            #------------------------------------------------------

            $layerDataFile = sprintf( "%sdata-%s.osm", $Config{WorkingDirectory}, join( "-", @ppchain ) );

            # Add bounding box to osmarender
            # then set the data source
            # then transform it to SVG

            # Create a new copy of rules file to allow background update
            # don't need zoom or layer in name of file as we'll
            # process one after the other
            my $source =$Config{FeaturesPath} . $Config{"Layer.$layer.Rules.$Zoom"};
			my $tmpFeaturesXml = $Config{WorkingDirectory} . "map-features-$PID.xml";
            copy( $source, $tmpFeaturesXml )
              or die "Cannot make copy of $source";

# Update the rules file  with details of what to do (where to get data, what bounds to use)
            #AddBounds( $tmpFeaturesXml, $W, $S, $E, $N );
			print ("Delta Zoom: 0\n")  if ( $Config{Debug} );
            AddBounds2($tmpFeaturesXml, 0);
            SetDataSource( $layerDataFile, $tmpFeaturesXml );

            # Render the file
            if (
                xml2svg(
                    $tmpFeaturesXml,
                    "$Config{WorkingDirectory}output-$PID-z$Zoom.svg",
                    $layer, $Zoom
                )
              )
            {

                # Delete temporary rules file
                killafile($tmpFeaturesXml) if ( !$Config{Debug} );
            }
            else {

                # Delete temporary rules file
                killafile($tmpFeaturesXml);
                foreach my $file (@tempfiles) {
                    killafile($file) if ( !$Config{Debug} );
                }
                return 0;
            }

            # Find the size of the SVG file
            my ( $ImgH, $ImgW, $Valid ) =
              getSize("$Config{WorkingDirectory}output-$PID-z$Zoom.svg");
            print "\nImage Dimension: $ImgH, $ImgW \n\n"  if ( $Config{Debug} );

            # Render it as loads of recursive tiles
            my $empty = RenderTile($layer, $X, $Y, $Zoom, $Zoom, 0, 0, $ImgW, $ImgH, 0);

            # Clean-up the SVG files
            killafile("$Config{WorkingDirectory}output-$PID-z$Zoom.svg") if ( !$Config{Debug} );
        }

    }
    foreach my $file (@tempfiles) {
        killafile($file) if ( !$Config{Debug} );
    }
    return 1;
}

#-----------------------------------------------------------------------------
# Render a tile
#   $X, $Y, $Zoom - which tile
#   $N, $S, $W, $E - bounds of the tile
#   $ImgX1,$ImgY1,$ImgX2,$ImgY2 - location of the tile in the SVG file
#-----------------------------------------------------------------------------
sub RenderTile {
    my (
        $layer, $X, $Y, $Zoom, $ZOrig,
        $X1, $Y1, $X2, $Y2, $empty
    ) = @_;

    return if ( $Zoom > $Config{"Layer.$layer.MaxZoom"} );

    my $AAL = $Config{"AAL"};
    if ( $Config{"Layer.$layer.AAL.$Zoom"} != 0 ) {
        $AAL = $Config{"Layer.$layer.AAL.$Zoom"};
    }

    # no need to render subtiles if empty
    return if ( $empty == 1 );

    # Render it to PNG
    printf "Tilestripe (%s,%s): X %1.1f,%1.1f, Y %1.1f,%1.1f\n",
      $X, $Y, $X1, $X2, $Y1, $Y2
      if ( $Config{"Debug"} );
    my $Width =
      ( $AAL * 256 ) * ( 2**( $Zoom - $ZOrig ) );    # Pixel size of tiles
    my $Height = $Width;                     # Pixel height of tile

    # svg2png returns true if all tiles extracted were empty. this might break
    # if a higher zoom tile would contain data that is not rendered at the
    # current zoom level.
    if (
        svg2png(
            $layer, $X, $Y, $Zoom, $ZOrig,
            $X1, $Y1, $X2, $Y2, $Width, $Height
        )
            and !$Config{"Layer.$layer.RenderFullTileset"}
      )
    {
        $empty = 1;
    }

    # Get progress percentage
    if ( $empty == 1 ) {

# leap forward because this tile and all higher zoom tiles of it are "done" (empty).
        for ( my $j = $Config{"Layer.$layer.MaxZoom"} ; $j >= $Zoom ; $j-- ) {
            $progress += 2**( $Config{"Layer.$layer.MaxZoom"} - $j );
        }
    }
    else {
        $progress += 1;
    }

    if (($progressPercent = $progress * 100 / ($Zoom - $ZOrig + 1)) == 100) {
        statusMessage( "Finished $X,$Y for layer $layer",
            $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent,
            1 );
    }
    else {
        if ( $Config{Verbose} ) {
            printf STDERR "Job No. %d %1.1f %% done.\n", $progressJobs,
              $progressPercent;
        } else {
            statusMessage( "Working", $Config{Verbose}, $currentSubTask,
                $progressJobs, $progressPercent, 0 );
        }
    }

    return $empty;
}

#-----------------------------------------------------------------------------
# Project latitude in degrees to Y coordinates in mercator projection
#-----------------------------------------------------------------------------
sub ProjectF {
    my $Lat = DegToRad( shift() );
    my $Y   = log( tan($Lat) + sec($Lat) );
    return ($Y);
}

#-----------------------------------------------------------------------------
# Project Y to latitude bounds
#-----------------------------------------------------------------------------
sub Project {
    my ( $Y, $Zoom ) = @_;

    my $Unit  = 1 / ( 2**$Zoom );
    my $relY1 = $Y * $Unit;
    my $relY2 = $relY1 + $Unit;

    $relY1 = $LimitY - $RangeY * $relY1;
    $relY2 = $LimitY - $RangeY * $relY2;

    my $Lat1 = ProjectMercToLat($relY1);
    my $Lat2 = ProjectMercToLat($relY2);
    return ( ( $Lat1, $Lat2 ) );
}

#-----------------------------------------------------------------------------
# Convert Y units in mercator projection to latitudes in degrees
#-----------------------------------------------------------------------------
sub ProjectMercToLat($) {
    my $MercY = shift();
    return ( RadToDeg( atan( sinh($MercY) ) ) );
}

#-----------------------------------------------------------------------------
# Project X to longitude bounds
#-----------------------------------------------------------------------------
sub ProjectL {
    my ( $X, $Zoom ) = @_;

    my $Unit = 360 / ( 2**$Zoom );
    my $Long1 = -180 + $X * $Unit;
    return ( ( $Long1, $Long1 + $Unit ) );
}

#-----------------------------------------------------------------------------
# Angle unit-conversions
#-----------------------------------------------------------------------------
sub DegToRad($) { return pi * shift() / 180; }
sub RadToDeg($) { return 180 * shift() / pi; }

#-----------------------------------------------------------------------------
# MERCATOR PROJECTION (deg to merc)
#-----------------------------------------------------------------------------

#lon_map = lon * 20037508.34 / 180;
#lat_map = Math.log(Math.tan( (90 + lat) * PI / 360)) / (PI / 180);
#lat_map = lat_map * 20037508.34 / 180;

sub ProjectLat2Merc($) {

    #my ($lat) = @_;
    my $lat = shift();

    return (
        log( tan( ( 90.0 + $lat ) * pi / 360.0 ) ) /
          ( pi / 180.0 ) * 20037508.34 /
          180.0 );

}

sub ProjectLon2Merc($) {

    #my ($lon) = @_;
    my $lon = shift();

    return ( $lon * 20037508.34 / 180.0 );
}

#-----------------------------------------------------------------------------
# Gets latest copy of osmarender from repository
#-----------------------------------------------------------------------------
sub UpdateFreemapSlovakiaDiSK {
    foreach my $File (
        (
            "freemap/map-features-z10.xml", "freemap/map-features-z11.xml",
            "freemap/map-features-z12.xml", "freemap/map-features-z13.xml",
            "freemap/map-features-z14.xml", "freemap/map-features-z15.xml",
            "freemap/map-features-z16.xml", "freemap/map-features-z17.xml"
        )
      )
    {
        statusMessage( "Downloading: Osmarender ($File)",
            $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent,
            0 );

        DownloadFile(
            "http://freemap/freemap_disk/features/$File"
            , # TODO: should be config option. TODO: should be SVN. TODO: should be called
            $Config{FeaturesPath} . $File,
            1
        );
    }

    # TODO: should be config option.
    # TODO: should be SVN.
    # TODO: should be called at all
    # TODO: should update other aspects of the client as well
}

#-----------------------------------------------------------------------------
# Transform an OSM file (using osmarender) into SVG
#-----------------------------------------------------------------------------
sub xml2svg {
    my ( $MapFeatures, $SVG, $layer, $zoom ) = @_;
    my $TSVG = "$SVG";
    my $NoBezier = $Config{NoBezier} || $zoom <= 11;

    my $Cmd;
    if ( !$NoBezier ) {
        $TSVG = "$SVG-temp.svg";
    }
        if ( $Config{UseOrp} == 1 ) {

        #orp.pl -r rule.xml data.osm -outfile
        $Cmd = sprintf( "%s perl orp/orp.pl -r %s -o %s ",
            $Config{Niceness}, "$MapFeatures", $TSVG );
    }
    else {
		$Cmd = sprintf( "%s %s tr %s %s > \"%s\"",
        $Config{Niceness}, $Config{XmlStarlet}, "osmarender.xsl",
        "$MapFeatures", $TSVG );
    }

    statusMessage( "Transforming zoom level $zoom",
        $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent, 0 );

    printf "\n >> $Cmd \n\n" if ( $Config{"Debug"} );

    runCommand( $Cmd, $PID );

    # look at temporary svg wether it really is a svg or just the
    # xmlstarlet dump and exit if the latter.
    open( SVGTEST, "<", $TSVG ) || return;
    my $TestLine = <SVGTEST>;
    chomp $TestLine;
    close SVGTEST;

    if ( grep( !/</, $TestLine ) ) {
        statusMessage( "File $TSVG doesn't look like svg, exiting",
            $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent,
            1 );
        return cleanUpAndDie( "xml2svg", $Mode, 3, $PID );
    }

  #-----------------------------------------------------------------------------
  # Process way cleanup
  #-----------------------------------------------------------------------------

    my $CSVG = "$TSVG-clean.svg";

    my $Cmd = sprintf( "%s perl waycleanup.pl %s > %s",
        $Config{Niceness}, $TSVG, $CSVG );
    statusMessage( "Running waycleanup",
        $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent, 0 );

    runCommand( $Cmd, $PID );

    my $filesize = -s $CSVG;
    if ($filesize) {
        copy( $CSVG, $TSVG );
    }
    else {
        statusMessage( "Error on WauCleanUp, rendering full svg file",
            $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent,
            0 );
    }
    killafile($CSVG) if ( !$Config{Debug} );

  #-----------------------------------------------------------------------------
  # Process lines to Bezier curve hinting
  #-----------------------------------------------------------------------------
    if ( !$NoBezier ) {    # do bezier curve hinting

        my $Cmd = sprintf( "%s perl lines2curves.pl %s > %s",
            $Config{Niceness}, $TSVG, $SVG );

        statusMessage( "Beziercurvehinting zoom level $zoom",
            $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent,
            0 );
        runCommand( $Cmd, $PID );

 #-----------------------------------------------------------------------------
 # Sanitycheck for Bezier curve hinting, no output = bezier curve hinting failed
 #-----------------------------------------------------------------------------
        my $filesize = -s $SVG;
        if ( !$filesize ) {
            copy( $TSVG, $SVG );
            statusMessage(
"Error on Bezier Curve hinting, rendering without bezier curves",
                $Config{Verbose},
                $currentSubTask,
                $progressJobs,
                $progressPercent,
                0
            );
        }
        killafile($TSVG) if ( !$Config{Debug} );
    }
    else {    # don't do bezier curve hinting
        statusMessage( "Bezier Curve hinting disabled.",
            $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent,
            0 );
    }
    return 1;
}

#-----------------------------------------------------------------------------
# Render a SVG file
# $ZOrig - the lowest zoom level of the tileset
# $X, $Y - tilemnumbers of the z12 tile containing the data we're working on
# $Ytile - the actual tilenumber in Y-coordinate of the zoom we are processing
#-----------------------------------------------------------------------------
sub svg2png {
    my (
        $layer, $X, $Y, $Zoom, $ZOrig,
        $X1, $Y1, $X2, $Y2,
        $Width, $Height
    ) = @_;

    my $TempFile = $Config{WorkingDirectory} . "$PID.png";

    my $stdOut = $Config{WorkingDirectory} . $PID . ".stdout";

    my $Cmd;

    #-------------------------------------
    if ( $Config{UseBatik} == 1 ) {
        my $area = sprintf( "%f:%f:%f:%f", $X1, $Y1, $X2 - $X1, $Y2 - $Y1 );
        $area =~ s/,/\./g;
        $area =~ s/\:/,/g;

        $Cmd = sprintf("%s %s -bg 0.0.0.0 -w %d -h %d -a %s -m image/png -d %s.png %s%s  > %s",
            $Config{Niceness}, $Config{Batik}, $Width, $Height, $area, $TempFile,
            $Config{WorkingDirectory},
            "output-$PID-z$Zoom.svg", $stdOut
        );

        #DEBUG: print ("\n\n$Cmd\n\n");
        #-------------------------------------
    }
    else {
        $Cmd = sprintf("%s %s -w %d -h %d --export-area=%f:%f:%f:%f --export-png=\"%s\" \"%s%s\" > %s",
            $Config{Niceness},
            $Config{Inkscape},
            $Width,
            $Height,
            $X1, $Y1, $X2, $Y2,
            $TempFile,
            $Config{WorkingDirectory},
            "output-$PID-z$Zoom.svg",
            $stdOut
        );

        # Locale SK uses comma (,) as decimal separator, convert the command, to avoid 
        # the error "assertion `!area.hasZeroArea()' failed" in Inkscape
        if( "$decimalSep" eq "," ) {
            $Cmd =~ s/\./,/g;
            $Cmd =~ s/,png_part/\.png_part/g;
            $Cmd =~ s/,png/\.png/g;
            $Cmd =~ s/,stdout/\.stdout/g;
            $Cmd =~ s/,svg/\.svg/g;
            $Cmd =~ s/,exe/\.exe/g;
        }
    }

    # stop rendering the current job when inkscape fails
    statusMessage( "Rendering", $Config{Verbose}, $currentSubTask,
        $progressJobs, $progressPercent, 0 );

    if ( not runCommand( $Cmd, $PID ) ) {
        statusMessage( "$Cmd failed", $Config{Verbose}, $currentSubTask,
            $progressJobs, $progressPercent, 1 );

        ## TODO: check this actually gets the correct coords
        PutRequestBackToServer( $X, $Y, $Zoom, "BadSVG" );
        return 0 if ( $Mode eq "loop" );
        exit(1);
    }

    #-------------------------------------
    if ( $Config{UseBatik} == 1 ) {
        rename( $TempFile . ".png", $TempFile );
    }

    #-------------------------------------

    killafile($stdOut) if ( !$Config{Debug} );

    # returns true if tiles were all empty
    my $ReturnValue = splitImageX($layer, $X, $Y, $Zoom, $ZOrig, $TempFile);

    killafile($TempFile) if ( !$Config{Debug} );

    return $ReturnValue;    #return true if empty

}

sub writeToFile {
    open( my $fp, ">", shift() ) || return;
    print $fp shift();
    close $fp;
}

#-----------------------------------------------------------------------------
# Add bounding-box information to an osm-map-features file
#-----------------------------------------------------------------------------
sub AddBounds {
    my ( $Filename, $W, $S, $E, $N, $Size ) = @_;

    # Read the old file
    open( my $fpIn, "<", "$Filename" );
    my $Data = join( "", <$fpIn> );
    close $fpIn;
    die("no such $Filename") if ( !-f $Filename );

    # Change some stuff
    my $BoundsInfo = sprintf("<bounds minlat=\"%f\" minlon=\"%f\" maxlat=\"%f\" maxlon=\"%f\" />", $S, $W, $N, $E );

    $Data =~s/(<!--bounds_mkr1-->).*(<!--bounds_mkr2-->)/$1\n<!-- Bounds Inserted by tilesGen -->\n$BoundsInfo\n$2/s;

    # Save back to the same location
    open( my $fpOut, ">$Filename" );
    print $fpOut $Data;
    close $fpOut;
}

#-----------------------------------------------------------------------------
# Add bounding-box information to an osm-map-features file
#-----------------------------------------------------------------------------
sub AddBounds2 {
    my ( $Filename, $Size ) = @_;

    my $realSize = 256 * (2**$Size);
    # Read the old file
    open( my $fpIn, "<", "$Filename" );
    my $Data = join( "", <$fpIn> );
    close $fpIn;
    die("no such $Filename") if ( !-f $Filename );

    # Change some stuff
    my $BoundsInfo = sprintf( "<bounds minlat=\"0\" minlon=\"0\" maxlat=\"%d\" maxlon=\"%d\" />",$realSize, $realSize );

    $Data =~s/(<!--bounds_mkr1-->).*(<!--bounds_mkr2-->)/$1\n<!-- Bounds Inserted by tilesGen -->\n$BoundsInfo\n$2/s;

    # Save back to the same location
    open( my $fpOut, ">$Filename" );
    print $fpOut $Data;
    close $fpOut;
}

#-----------------------------------------------------------------------------
# Set data source file name in map-features file
#-----------------------------------------------------------------------------
sub SetDataSource {
    my ( $Datafile, $Rulesfile ) = @_;
    # Convert filename to the file:///dir/file format
    if ( $Config{Slash} =~ /\\/ ) {
        # Win32 specific
        $Datafile =~ s/\\/\//g;
        $Datafile = '/' . $Datafile ;
    }
    $Datafile = 'file://' . $Datafile;

    # Read the old file
    open( my $fpIn, "<", "$Rulesfile" );
    my $Data = join( "", <$fpIn> );
    close $fpIn;
    die("no such $Rulesfile") if ( !-f $Rulesfile );

    #$Data =~ s/(  data=\").*(  scale=\")/$1$Datafile\"\n$2/s;

    $Data =~s/(<!--data_mkr1-->).*(<!--data_mkr2-->)/$1\n<!-- Data File Inserted by tilesGen -->\n<data file=\"$Datafile\" \/>\n$2/s;

    # Save back to the same location
    open( my $fpOut, ">$Rulesfile" );
    print $fpOut $Data;
    close $fpOut;
}

#-----------------------------------------------------------------------------
# Get the width and height (in SVG units, must be pixels) of an SVG file
#-----------------------------------------------------------------------------
sub getSize($) {
    my $SVG = shift();
    open( my $fpSvg, "<", $SVG );
    while ( my $Line = <$fpSvg> ) {
        if ( $Line =~ /height=\"(.*)px\" width=\"(.*)px\"/ ) {
            close $fpSvg;
            return ( ( $1, $2, 1 ) );
        }
    }
    close $fpSvg;
    return ( ( 0, 0, 0 ) );
}

#-----------------------------------------------------------------------------
# Temporary filename to store a tile
#-----------------------------------------------------------------------------
sub tileFilename {
    my ( $layer, $X, $Y, $Zoom ) = @_;

    return (
        sprintf(
            $Config{LocalSlippymap}
            ? "%s%s$Config{Slash}%d$Config{Slash}%d$Config{Slash}%d.png"
            : "%s%s_%d_%d_%d.png",
            $Config{LocalSlippymap} ? $Config{LocalSlippymap} : $Config{WorkingDirectory},
            $Config{"Layer.$layer.Prefix"},
            $Zoom, $X, $Y
        )
    );
}

## sub mergeOsmFiles moved to tahlib.pm

#-----------------------------------------------------------------------------
# Split a tileset image into tiles
#-----------------------------------------------------------------------------
sub splitImageX {
    my ( $layer, $X, $Y, $Z, $ZOrig, $File ) = @_;

    my $AAL = $Config{"AAL"};
    if ( $Config{"Layer.$layer.AAL.$Z"} != 0 ) {
        $AAL = $Config{"Layer.$layer.AAL.$Z"};
    }

    my $ImageSize = 256 * (2 ** ($Z - $ZOrig));
    # Size of tiles
    my $Pixels      = ( $AAL * 256 );
    my $SmallPixels = 256;

    # Number of tiles
    my $Size = 2**( $Z - $ZOrig );

    # Assume the tileset is empty by default
    my $allempty = 1;

  #-----------------------------------------------------------------------------
  # Run mogrify on each split tile, then delete the temporary cut file
  #-----------------------------------------------------------------------------

    if ( $AAL > 1 ) {

        my $MagickFilename = "$File.png";
        copy( $File, $MagickFilename );

        my $Cmd = sprintf("%s $Config{Mogrify} $Config{MogrifyOptions2} -resize x%d %s > $Config{WorkingDirectory}$PID.stdout",
            $Config{Niceness}, $ImageSize, $MagickFilename );

        statusMessage( "Mogrifying", $Config{Verbose}, $currentSubTask,
            $progressJobs, $progressPercent, 0 );
        if ( runCommand( $Cmd, $PID ) ) {
            unlink($File);
            killafile("$Config{WorkingDirectory}$PID.stdout") if ( !$Config{Debug} );
            rename( $MagickFilename, $File );
        }
        else {
            statusMessage( "Mogrifying failed",
                $Config{Verbose}, $currentSubTask, $progressJobs,
                $progressPercent, 1 );
            unlink($MagickFilename);
        }
    }

    # Load the tileset image
    statusMessage( sprintf( "Splitting %s (%d x 1)", $File, $Size ),
        $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent, 0 );
    my $Image = newFromPng GD::Image($File);

    # Use one subimage for everything, and keep copying data into it
    my $SubImage;

    #   if ( $Config{"Layer.$layer.Overlay"} == 0 ) {
    #       $SubImage = new GD::Image( $SmallPixels, $SmallPixels );
    #   }

    # For each subimage
    for (my $xi = 0; $xi < $Size; $xi++) {
        for (my $yi = 0; $yi < $Size; $yi++) {
            if ( $Config{"Layer.$layer.Overlay"} == 1 ) {
                $SubImage = newFromPng GD::Image("transparent.png");
                $SubImage->saveAlpha(1);
            } else {
                $SubImage = new GD::Image( $SmallPixels, $SmallPixels );
            }

            # Get a tiles'worth of data from the main image
            $SubImage->copy(
                $Image,
                0,                     # Dest X offset
                0,                     # Dest Y offset
                $xi * $SmallPixels,    # Source X offset
                $yi * $SmallPixels,    # Source Y offset
                $SmallPixels,    # Copy width
                $SmallPixels     # Copy height
            );                   

            # Decide what the tile should be called
            my $Filename = tileFilename( $layer, $X * $Size + $xi, $Y * $Size + $yi, $Z );
            MagicMkdir($Filename) if ( $Config{"LocalSlippymap"} );

            # Temporary filename
            my $Filename2 = "$Filename.cut.png";
            my $Basename  = $Filename;             # used for statusMessage()
            $Basename =~ s|.*\$Config\{Slash}||;

            # Check for black tile output
            if ( not( $SubImage->compare($BlackTileImage) & GD_CMP_IMAGE ) ) {
                print STDERR "\nERROR: Your inkscape has just produced a totally black tile. This usually indicates a broken Inkscape, please upgrade.\n";
            }

            # Detect empty tile here:
            elsif (
                not( $SubImage->compare($EmptyLandImage) & GD_CMP_IMAGE )
              ) # libGD comparison returns true if images are different. (i.e. non-empty Land tile) so return the opposite (false) if the tile doesn''t look like an empty land tile
            {

                # copy("emptyland.png", $Filename);
                copy( "empty2.png", $Filename );

            }
            elsif (
                not( $SubImage->compare($EmptySeaImage) & GD_CMP_IMAGE )
              )    # same for Sea tiles
            {

                # copy("emptysea.png",$Filename);
                copy( "empty2.png", $Filename );

    #            $allempty = 0; # TODO: enable this line if/when serverside empty tile methods is implemented. Used to make sure we                                     generate all blank seatiles in a tileset.
            }
            else {

                # If at least one tile is not empty set $allempty false:
                $allempty = 0;

    # convert Tile to paletted file This *will* break stuff if different libGD versions are used
    # $SubImage->trueColorToPalette($dither,$numcolors);

                # Store the tile
                statusMessage( " -> $Basename", $Config{Verbose}, 0 )
                  if ( $Config{Verbose}, $currentSubTask, $progressJobs,
                    $progressPercent, 0 );
                WriteImage( $SubImage, $Filename2 );

      #-----------------------------------------------------------------------------
      # Run pngcrush on each split tile, then delete the temporary cut file
      #-----------------------------------------------------------------------------
                my $Cmd = sprintf( "%s $Config{Pngcrush} -q %s %s > $Config{WorkingDirectory}$PID.stdout",
                    $Config{Niceness}, $Filename2, $Filename );

                statusMessage( "Pngcrushing $Basename",
                    $Config{Verbose}, $currentSubTask, $progressJobs,
                    $progressPercent, 0 );
                if ( runCommand( $Cmd, $PID ) ) {
                    unlink($Filename2);
                    killafile("$Config{WorkingDirectory}$PID.stdout") if ( !$Config{Debug} );
                }
                else {
                    statusMessage( "Pngcrushing $Basename failed",
                        $Config{Verbose}, $currentSubTask, $progressJobs,
                        $progressPercent, 1 );
                    rename( $Filename2, $Filename );
                }
            }
        }
    }
    undef $SubImage;

    # tell the rendering queue wether the tiles are empty or not
    return $allempty;
}

#-----------------------------------------------------------------------------
# Write a GD image to disk
#-----------------------------------------------------------------------------
sub WriteImage {
    my ( $Image, $Filename ) = @_;

    # Get the image as PNG data
    my $png_data = $Image->png;

    # Store it
    open( my $fp, ">$Filename" ) || die("Cannot write PNG image \"$Filename\": $!");
    binmode $fp;
    print $fp $png_data;
    close $fp;
}

#-----------------------------------------------------------------------------
# A function to re-execute the program.
#
# This function attempts to detect whether the perl script has changed
# since it was invoked initially, and if so, just runs the new version.
# This can be used to update the program while it is running (as it is
# sometimes hard to hit Ctrl-C at exactly the right moment!)
#-----------------------------------------------------------------------------
sub reExecIfRequired {

    # until proven to work with other systems, only attempt a re-exec
    # on linux.
    return unless ( $^O eq "linux" || $^O eq "cygwin" );

    my (
        $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
        $size, $atime, $mtime, $ctime, $blksize, $blocks
    ) = stat($0);
    my $de = "$size/$mtime/$ctime";
    if ( !defined($dirent) ) {
        $dirent = $de;
        return;
    }
    elsif ( $dirent ne $de ) {
        statusMessage( "tilesGen.pl has changed, re-start new version",
            $Config{Verbose}, $currentSubTask, $progressJobs, $progressPercent,
            1 );
        exec "perl", $0, "loop", "reexec", "progressJobs=$progressJobs",
          "idleSeconds=" . getIdle(1), "idleFor=" . getIdle(0),
          "progstart=$progstart"
          or die;
    }
}

sub AppendConfig {
    my $Filename = shift();

    open( my $fp, "<$Filename" ) || die("Can't open \"$Filename\" ($!)\n");
    while ( my $Line = <$fp> ) {
        $Line =~ s/#.*$//;    # Comments
        $Line =~ s/\s*$//;    # Trailing whitespace

        if (
            $Line =~ m{
	       ^
	        \s*
	        ([A-Za-z0-9._-]+) # Keyword: just one single word no spaces
	        \s*            # Optional whitespace
	        =              # Equals
	        \s*            # Optional whitespace
	        (.*)           # Value
	        }x
          )
        {

            # Store config options in a hash array
            $Config{$1} = $2;
            print "Found $1 ($2)\n" if (0);    # debug option
        }
    }
    close $fp;
}
