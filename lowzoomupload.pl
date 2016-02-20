#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use File::Copy;
use Digest::MD5 qw(md5_hex);
use English '-no_match_vars';
use tahconfig;
use tahlib;

#-----------------------------------------------------------------------------
# OpenStreetMap tiles@home, upload module
# Takes any tiles generated, adds them into ZIP files, and uploads them
#
# Contact OJW on the Openstreetmap wiki for help using this program
#-----------------------------------------------------------------------------
# Copyright 2006, Oliver White
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
#-----------------------------------------------------------------------------

# conf file, will contain username/password and environment info
my %Config = ReadConfig(
    "freemapdiskclient.conf", "general.conf",
    "authentication.conf",    "layers.conf",
    "freemapdisk.conf"
);

# Handle the command-line
my $Mode = shift();
my $ConfigName;
if ( $Mode eq "config" ) {
    my $ConfigName = shift();

    if ( not defined $ConfigName ) {
        die "Must specify config file name \n";
    }
    AppendConfig ($ConfigName);
    # precitam dalsi prikaz
} else {
    unshift(@_,$Mode);
}

my $ZipFileCount = 0;

my $ZipDir = $Config{WorkingDirectory} . "uploadable";

my @sorted;

# when called from tilesGen, use these for nice display
my $progress        = 0;
my $progressPercent = 0;
my $progressJobs    = $ARGV[0] or 1;
my $currentSubTask;

my $lastmsglen;

my $tileCount;

my @tiles;

# Upload any ZIP files which are still waiting to go
if (opendir(ZIPDIR, $ZipDir))
{
    $currentSubTask = "uploadZ";
    $progress       = 0;
    my @zipfiles = grep { /\.zip$/ } readdir(ZIPDIR);
    close ZIPDIR;
    @sorted = sort { $a cmp $b }
      @zipfiles
      ;    # sort by ASCII value (i.e. upload oldest first if timestamps used)
    my $zipCount = scalar(@sorted);
    statusMessage(scalar(@sorted) . " zip files to upload",
                  $Config{Verbose}, $currentSubTask, $progressJobs,
                  $progressPercent, 0);
    while (my $File = shift @sorted)
    {

        if ($File =~ /\.zip$/i)
        {
            upload("$ZipDir$Config{Slash}$File");
        }
        $progress++;
        $progressPercent = $progress * 100 / $zipCount;
        statusMessage(
                      scalar(@sorted) . " zip files left to upload",
                      $Config{Verbose},
                      $currentSubTask,
                      $progressJobs,
                      $progressPercent,
                      0
        );
    }
}

$currentSubTask = " upload";

# We calculate % differently this time so we don't need "progress"
# $progress = 0;

$progressPercent = 0;

my $TileDir = $Config{WorkingDirectory};

# Group and upload the tiles
statusMessage("Searching for tiles in $TileDir",
              $Config{Verbose}, $currentSubTask, $progressJobs,
              $progressPercent, 0);

# compile a list of the "Prefix" values of all configured layers,
#     # separated by |
my $allowedPrefixes = join(
                           "|",
                           map($Config{"Layer.$_.Prefix"},
                           split(/,/, $Config{"LowLayers"}))
);

opendir(my $dp, $TileDir) or die("Can't open directory $TileDir\n");

my @dir = readdir($dp);
@tiles = grep { /($allowedPrefixes)_\d+_\d+_\d+\.png$/ } @dir;
closedir($dp);

$tileCount = scalar(@tiles);

exit if ($tileCount == 0);

while (uploadTileBatch($TileDir, $TileDir . "gather", $ZipDir, $allowedPrefixes)) {
}

#-----------------------------------------------------------------------------
# Moves tiles into a "gather" directory until a certain size is reached,
# then compress and upload those files
#-----------------------------------------------------------------------------
sub uploadTileBatch
{
    my ($TileDir, $TempDir, $OutputDir, $allowedPrefixes) = @_;
    my ($Size, $Count) = (0, 0);
    my $MB         = 1024 * 1024;
    my $SizeLimit  = $Config{"UploadChunkSize"} * $MB;
    my $CountLimit = $Config{"UploadChunkCount"};

    #prevent too small zips, 683=half a tileset
    $CountLimit = 683 if ($CountLimit < 100);

    mkdir $TempDir   if !-d $TempDir;
    mkdir $OutputDir if !-d $OutputDir;

    $progressPercent = ($tileCount - scalar(@tiles)) * 100 / $tileCount;
    statusMessage(scalar(@tiles) . " tiles to process",
                  $Config{Verbose}, $currentSubTask, $progressJobs,
                  $progressPercent, 0);

    while (   ($Size < $SizeLimit)
           && ($Count < $CountLimit)
           && (my $file = shift @tiles))
    {
        my $Filename1 = "$TileDir$Config{Slash}$file";
        my $Filename2 = "$TempDir$Config{Slash}$file";
        if ($file =~ /($allowedPrefixes)_\d+_\d+_\d+\.png$/i)
        {
            $Size += -s $Filename1;
            $Count++;

            rename($Filename1, $Filename2);
        }
    }

    if ($Count)
    {
        statusMessage(
                      sprintf(
                              "Got %d files (%d bytes), compressing",
                              $Count, $Size
                      ),
                      $Config{Verbose},
                      $currentSubTask,
                      $progressJobs,
                      $progressPercent,
                      0
        );
        return compressTiles($TempDir, $OutputDir);
    }
    else
    {
        $progressPercent = ($tileCount - scalar(@tiles)) * 100 / $tileCount;
        statusMessage("upload finished",
                      $Config{Verbose}, $currentSubTask, $progressJobs,
                      $progressPercent, 0);
        return 0;
    }
}

#-----------------------------------------------------------------------------
# Compress all PNG files from one directory, creating
#-----------------------------------------------------------------------------
sub compressTiles
{
    my ($Dir, $OutputDir) = @_;

    my $Filename;

    my $epochtime = time;

    if ($Config{UseHostnameInZipname})
    {
        my $hostname = `hostname` . "XXX";
        $Filename = sprintf("%s$Config{Slash}%s_%d_%d.zip",
                            $OutputDir, substr($hostname, 0, 3),
                            $$, $ZipFileCount++);
    }
    else
    {
        $Filename = sprintf("%s$Config{Slash}%d_%d_%d.zip",
                            $OutputDir, $epochtime, $$, $ZipFileCount++);
    }

    # ZIP all the tiles into a single file
    my $stdOut   = $Config{WorkingDirectory} . "/" . $PID . ".stdout";
    my $Command1 = sprintf("%s %s %s > %s",
                           " $Config{Zip} $Config{ZipAdd}", $Filename,
                           "$Dir$Config{Slash}*.png",       $stdOut);

    # ZIP filename is currently our process ID - change this if one process
    # becomes capable of generating multiple zip files

    ## FIXME: this is one of the things that make upload.pl not multithread safe
    # Delete files in the gather directory
    opendir(GATHERDIR, $Dir);
    my @zippedFiles = grep { /.png$/ } readdir(GATHERDIR);
    closedir(GATHERDIR);

    # Run the two commands
    if (runCommand($Command1, $PID))
    {
        while (my $File = shift @zippedFiles)
        {
            killafile($Dir . "$Config{Slash}" . $File);
        }
    }
    else
    {
        while (my $File = shift @zippedFiles)
        {
            rename($Dir . "$Config{Slash}" . $File,
                   $Config{WorkingDirectory} . $File);
        }
    }
    killafile($stdOut)  if ( !$Config{Debug} );
    return upload($Filename);
}

#-----------------------------------------------------------------------------
# Upload a ZIP file
#-----------------------------------------------------------------------------
sub upload()
{
    my ($File) = @_;

    my $ua = LWP::UserAgent->new(keep_alive => 1, timeout => 360);

    $ua->protocols_allowed(['http']);
    $ua->agent("FreemapDiSK/2011.05.11");
    $ua->env_proxy();

    my $URL = $Config{"DiSKUploadURL"};

    #print $URL;

    statusMessage("Uploading $File", $Config{Verbose}, $currentSubTask, $progressJobs,$progressPercent, 0);
    my $res = $ua->post( $URL,
    Content_Type => 'form-data',
    Content => [ File => [$File],
                 Email =>  $Config{DiSKUsername} ,
                 PasswordMD5 => md5_hex($Config{DiSKPassword}),
                 ClientVersion => $Config{DiSKAPIVersion}
               ]);

    if (!$res->is_success())
    {
        print STDERR "ERROR\n";
        print STDERR "  Error uploading $File to $URL:\n";
        print STDERR "  " . $res->status_line . "\n";
        return 0;
    }
    else
    {

        print $res->content."\n";
    }

    if ($Config{DeleteZipFilesAfterUpload})
    {
        unlink($File);
    }
    else
    {
        rename($File, $File . "_uploaded");
    }

    return 1;
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
