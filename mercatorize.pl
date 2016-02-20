#!/usr/bin/perl -w
use Math::Trig;
use Getopt::Long;

my $VERSION ="mercatorize.pl (C)2011 Jozef Vince, Freemap Slovakia";

#project lat lon values into mlat mlon values, using mercator projection

 #lon_map = lon * 20037508.34 / 180;
 #lat_map = Math.log(Math.tan( (90 + lat) * PI / 360)) / (PI / 180);
 #lat_map = lat_map * 20037508.34 / 180;

our $DEG_TO_RAD = (pi/180.0);
our $RAD_TO_DEG = (180.0/pi);
our $R_MAJOR = 6378137.000000000;
#our $R_MINOR = 6356752.314245179;
our $R_MINOR = 6378137.000; # using spherical merctor ! :)
our $PI_OVER_2 = (pi/2);
our $RATIO = $R_MINOR / $R_MAJOR;
our $ECCENT = sqrt(1.0 - ($RATIO**2));
our $ECCENTH = 0.5 * $ECCENT;

sub ProjectLat2Merc($) {
  #my ($lat) = @_;
  my $lat = shift();

	my $phi = $DEG_TO_RAD * (
		($lat > 89.5) ? 89.5
		: ($lat < -89.5) ? -89.5
		: $lat);
    my $sinphi = sin($phi);
    my $con = $ECCENT * $sinphi;
    $con = ((1.0 - $con)/(1.0 + $con)) ** $ECCENTH;
    my $ts = tan(0.5 * ($PI_OVER_2 - $phi))/$con;
    return 0 - $R_MAJOR * log($ts);
}

sub ProjectLon2Merc($) {
	my $lon = shift();
	return( $R_MAJOR * $DEG_TO_RAD * $lon);
}


sub ProjectMerc2Lon($) {
	my $x = shift();
    return $RAD_TO_DEG * $x / $R_MAJOR;
}

sub ProjectMerc2Lat($) {
    my $y = shift();
    my $ts = exp(-$y / $R_MAJOR);
    my $phi = $PI_OVER_2 - 2 * atan($ts);
	my $dphi = 1.0;
    $i = 0;
    while ((abs($dphi) > 0.000000001) && ($i < 15))
        {
            my $con = $ECCENT * sin($phi);
            $dphi = $PI_OVER_2 - 2 * atan($ts * (((1.0 - $con) / (1.0 + $con)) ** $ECCENTH)) - $phi;
            $phi += $dphi;
            $i++;
        }
        return ($RAD_TO_DEG * $phi);
    }

sub ProjectXY2Merc {
    my ( $X, $Y, $Zoom ) = @_;
	my ( $La1, $La2, $Lo1, $Lo2 ) = ProjectXY($X, $Y, $Zoom);
 	return ( ProjectLat2Merc($La1), ProjectLat2Merc($La2), ProjectLon2Merc($Lo1), ProjectLon2Merc($Lo2)  );
}

sub ProjectXY {
    my ( $X, $Y, $Zoom ) = @_;

 # Setup map projection
 	#my $LimitY  = ProjectLat2Merc(85.0511);
	#my $LimitY2 = ProjectLat2Merc(-85.0511);
	#my $LimitY  = ProjectLat2Merc(85.0840590501104);
	#my $LimitY2 = ProjectLat2Merc(-85.0840590501104);
    my $LimitY  = ProjectLon2Merc(180);
	my $LimitY2 = ProjectLon2Merc(-180);
	my $RangeY  = $LimitY - $LimitY2;

    my $Unit  = 1 / ( 2**$Zoom );
    my $relY1 = $Y * $Unit;
    my $relY2 = $relY1 +$Unit;

    my $La1 = ProjectMerc2Lat($LimitY - $RangeY * $relY1);
    my $La2 = ProjectMerc2Lat($LimitY - $RangeY * $relY2);

    my $Lo1 = - 180 + 360 * $X * $Unit ;
	my $Lo2 =  $Lo1 + 360 * $Unit;

    return ( $La2, $La1, $Lo1, $Lo2  );
}


our $in_file; # The complete osm Filename (including path)
our $out_file;
our $z;
our $x;
our $y;
our $s;
our $trans=0;

# Set defaults and get options from command line
Getopt::Long::Configure('no_ignore_case');
GetOptions ( 
	     'in-file=s'           => \$in_file,
	     'out-file=s'          => \$out_file,
		 'z=i'          => \$z,
    	 'x=i'          => \$x,
		 'y=i'          => \$y,
		 's=i'          => \$s,
	     );

if (!defined($in_file)) {
	die "No in-file defined \n";
}
die "No existing osm File $in_file\n"
    unless -s $in_file;

if (!defined($out_file)) {
	$out_file = $in_file;
	$out_file =~ s/\.osm(\.gz|\.bz2)?$/-merc.osm/;
}

if (!defined($s)) {
	$s =256;
} else {
	$s= 256 * (2 **($s));
}
our ( $Lat1, $Lat2, $Lon1, $Lon2 );
our $x0;
our $y0;
our $xs;
our $ys;

	#print (ProjectLat2Merc(-85.0840590501798)." ".ProjectLat2Merc(85.0840590501798)."\n");
    #print (ProjectLon2Merc(-180)." ".ProjectLon2Merc(180)."\n");
    #print (ProjectMerc2Lat(-20037508.3427892)." ".ProjectMerc2Lat( 20037508.3427892)."\n");
    #print (ProjectLon2Merc(-180)." ".ProjectLon2Merc(180)."\n");


if (defined($x) && defined($y) && defined($z) && defined($s)) {
	$trans=1;
	( $Lat1, $Lat2, $Lon1, $Lon2 ) = ProjectXY($x, $y, $z);
	#print (" $Lat1, $Lat2, $Lon1, $Lon2 \n");
	( $Lat1, $Lat2, $Lon1, $Lon2 ) = ProjectXY2Merc($x, $y, $z);
	#print (" $Lat1, $Lat2, $Lon1, $Lon2 \n");

	$x0 = $Lat1;
	$xs = ($Lat2- $Lat1)/ $s;
	$y0 = $Lon1;
	$ys = ($Lon2- $Lon1)/ $s;
	#print (" $x0, $xs, $y0, $ys \n");

} else {
	$trans=0;
}


# Make sure we can create the output file before we start processing data
open(OUTFILE, ">$out_file") or die "Can’t write to $out_file: $!";
close OUTFILE;

my $start_time=time();

die "No OSM file specified\n" unless $in_file;

#-----------------------------------------------------------------------------
# Transform lat/lon to mercator coordinates (in preprocess)
#-----------------------------------------------------------------------------
open( my $fo, ">", $out_file);
open( my $fi, "<", $in_file );
while (<$fi>) {
    my $line = $_;

	if ($trans==0) {
		 # perform classical mercator
	     if ($line =~ /^(\s*<node.*id=["']-*\d+['"].*lat=["'])([0-9.-]+)(["'].*lon=['"])([0-9.-]+)(["'].*$)/) {
	         $line = $1.ProjectLat2Merc($2).$3.ProjectLon2Merc($4).$5."\n";
	     }

	     if ($line =~ /^(\s*<bounds.*minlat=["'])([0-9.-]+)(['"].*minlon=["'])([0-9.-]+)(['"].*maxlat=["'])([0-9.-]+)(['"].*maxlon=["'])([0-9.-]+)(['"].*$)/) {
	         $line = $1.ProjectLat2Merc($2).$3.ProjectLon2Merc($4).$5.ProjectLat2Merc($6).$7.ProjectLon2Merc($8).$9."\n";
	     }
	 } else {
     		# do some magic for osmarender
	 	     if ($line =~ /^(\s*<node.*id=["']-*\d+['"].*lat=["'])([0-9.-]+)(["'].*lon=['"])([0-9.-]+)(["'].*$)/) {
	         $line = $1.($s-(ProjectLat2Merc($2)-$x0)/$xs).$3.((ProjectLon2Merc($4)-$y0)/$ys).$5."\n";
	     }

	     if ($line =~ /^(\s*<bounds.*minlat=["'])([0-9.-]+)(['"].*minlon=["'])([0-9.-]+)(['"].*maxlat=["'])([0-9.-]+)(['"].*maxlon=["'])([0-9.-]+)(['"].*$)/) {
	         $line = $1.($s-(ProjectLat2Merc($2)-$x0)/$xs).$3.((ProjectLon2Merc($4)-$y0)/$ys).$5.($s-(ProjectLat2Merc($6)-$x0)/$xs).$7.((ProjectLon2Merc($8)-$y0)/$ys).$9."\n";
	     }
	}
    print $fo $line;
    }

close($fi);
close($fo);

