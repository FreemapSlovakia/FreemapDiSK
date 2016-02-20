package Geo::ShapeFile;
use strict;
use warnings;
use Carp;
use IO::File;
use Geo::ShapeFile::Shape;
use Config;

our $VERSION = '2.52';

# Preloaded methods go here.
sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $self = {};

    $self->{filebase} = shift || croak "Must specify filename!";
    $self->{filebase} =~ s/\.\w{3}$//;

    $self->{_enable_caching} = {
        shp                => 1,
        dbf                => 1,
        shx                => 1,
        shapes_in_area    => 1,
    };

    bless($self, $class);

    $self->{_change_cache} = {
        shape_type    => undef,
        records        => undef,
        shp    => {},
        dbf    => {},
        shx    => {},
    };
    $self->{_object_cache} = {
        shp    => {},
        dbf    => {},
        shx    => {},
        shapes_in_area => {},
    };

    if(-f $self->{filebase}.".shx") {
        $self->read_shx_header();
        $self->{has_shx} = 1;
    } else {
        $self->{has_shx} = 0;
    }

    if(-f $self->{filebase}.".shp") {
        $self->read_shp_header();
        $self->{has_shp} = 1;
    } else {
        $self->{has_shp} = 0;
    }

    if(-f $self->{filebase}.".dbf") {
        $self->read_dbf_header();
        $self->{has_dbf} = 1;
    } else {
        $self->{has_dbf} = 0;
    }

    return $self;
}

sub caching {
    my $self = shift;
    my $what = shift;

    if(@_) {
        $self->{_enable_caching}->{$what} = shift;
    }
    return $self->{_enable_caching}->{$what};
}

sub cache {
    my $self = shift;
    my $type = shift;
    my $obj = shift;

    if($self->{_change_cache}->{$type} && $self->{_change_cache}->{$type}->{$obj}) {
        return $self->{_change_cache}->{$type}->{$obj};
    }

    return unless $self->caching($type);

    if($@) {
        $self->{_object_cache}->{$type}->{$obj} = shift;
    }
    return $self->{_object_cache}->{$type}->{$obj};
}

sub read_shx_header { shift()->read_shx_shp_header('shx',@_); }
sub read_shp_header { shift()->read_shx_shp_header('shp',@_); }
sub read_shx_shp_header {
    my $self = shift;
    my $which = shift;
    my $doubles;

    $self->{$which."_header"} = $self->get_bytes($which,0,100);
    (
        $self->{$which."_file_code"}, $self->{$which."_file_length"},
        $self->{$which."_version"}, $self->{$which."_shape_type"}, $doubles
    ) = unpack("N x20 N V2 a64",$self->{$which."_header"});

    (
        $self->{$which."_x_min"}, $self->{$which."_y_min"},
        $self->{$which."_x_max"}, $self->{$which."_y_max"},
        $self->{$which."_z_min"}, $self->{$which."_z_max"},
        $self->{$which."_m_min"}, $self->{$which."_m_max"},
    ) = (
        unpack( 'b', pack( 'S', 1 ) )
            ? unpack( 'd8', $doubles )
            : reverse( unpack( 'd8', scalar( reverse( $doubles ) ) ) )
    );

    return 1;
}

sub type_is {
    my $self = shift;
    my $type = shift;

    return(lc($self->type($self->shape_type)) eq lc($type));
}

sub read_dbf_header {
    my $self = shift;

    $self->{dbf_header} = $self->get_bytes('dbf',0,12);
    (
        $self->{dbf_version},
        $self->{dbf_updated_year},
        $self->{dbf_updated_month},
        $self->{dbf_updated_day},
        $self->{dbf_num_records},
        $self->{dbf_header_length},
        $self->{dbf_record_length},
    ) = unpack("C4 V v v", $self->{dbf_header});
    # unpack changed from c4 l s s to fix endianess problem
    # reported by Daniel Gildea

    my $ls = $self->{dbf_header_length} +
        ($self->{dbf_num_records}*$self->{dbf_record_length});
    my $li = -s $self->{filebase}.".dbf";

    # some shapefiles (such as are produced by the NOAA NESDIS) don't
    # have a end-of-file marker in their dbf files, Aleksandar Jelenak
    # says the ESRI tools don't have a problem with this, so we shouldn't
    # either
    my $last_byte = $self->get_bytes('dbf',$li-1,1);
    $ls += 1 if (ord $last_byte == 0x1A);

    if($ls != $li) {
        croak "dbf: file wrong size (should be $ls, but found $li)";
    }

    my $header = $self->get_bytes('dbf',32,$self->{dbf_header_length}-32);
    my $count = 0;
    $self->{dbf_header_info} = [];

    while($header) {
        my $tmp = substr($header,0,32,'');
        my $chr = substr($tmp,0,1);

        if(ord $chr == 0x0D) { last; }
        if(length($tmp) < 32) { last; }

        my %tmp = ();
        (
            $tmp{name},
            $tmp{type},
            $tmp{size},
            $tmp{decimals}
        ) = unpack("Z11 Z x4 C2",$tmp);

        $self->{dbf_field_info}->[$count] = {%tmp};
        
        $count++;
    }
    $self->{dbf_fields} = $count;
    if($count < 1) { croak "dbf: Not enough fields ($count < 1)"; }

    my @template = ();
    foreach(@{$self->{dbf_field_info}}) {
        if($_->{size} < 1) {
            croak "dbf: Field $_->{name} too short ($_->{size} bytes)";
        }
        if($_->{size} > 4000) {
            croak "dbf: Field $_->{name} too long ($_->{size} bytes)";
        }

        push(@template,"A".$_->{size});
    }
    $self->{dbf_record_template} = join(' ',@template);

    my @field_names = ();
    foreach(@{$self->{dbf_field_info}}) {
        push(@field_names,$_->{name});
    }
    $self->{dbf_field_names} = [@field_names];

    return 1;
}

sub generate_dbf_header {
    my $self = shift;

    #$self->{dbf_header} = $self->get_bytes('dbf',0,12);
    (
        $self->{dbf_version},
        $self->{dbf_updated_year},
        $self->{dbf_updated_month},
        $self->{dbf_updated_day},
        $self->{dbf_num_records},
        $self->{dbf_header_length},
        $self->{dbf_record_length},
    ) = unpack("C4 V v v", $self->{dbf_header});

    $self->{_change_cache}->{dbf_cache}->{header} = pack("C4 V v v",
        3,
        (localtime)[5],
        (localtime)[4]+1,
        (localtime)[3],
        0, # TODO - num_records,
        0, # TODO - header_length,
        0, # TODO - record_length,
    );

#    my $ls = $self->{dbf_header_length} +
#        ($self->{dbf_num_records}*$self->{dbf_record_length}) +
#        1;
#    my $li = -s $self->{filebase}.".dbf";
#
#    if($ls != $li) {
#        croak "dbf: file wrong size (should be $ls, but found $li)";
#    }
#
#    my $header = $self->get_bytes('dbf',32,$self->{dbf_header_length}-32);
#    my $count = 0;
#    $self->{dbf_header_info} = [];
#
#    while($header) {
#        my $tmp = substr($header,0,32,'');
#        my $chr = substr($tmp,0,1);
#
#        if(ord $chr == 0x0D) { last; }
#        if(length($tmp) < 32) { last; }
#
#        my %tmp = ();
#        (
#            $tmp{name},
#            $tmp{type},
#            $tmp{size},
#            $tmp{decimals}
#        ) = unpack("Z11 Z x4 C2",$tmp);
#
#        $self->{dbf_field_info}->[$count] = {%tmp};
#        
#        $count++;
#    }
#    $self->{dbf_fields} = $count;
#    if($count < 1) { croak "dbf: Not enough fields ($count < 1)"; }
#
#    my @template = ();
#    foreach(@{$self->{dbf_field_info}}) {
#        if($_->{size} < 1) {
#            croak "dbf: Field $_->{name} too short ($_->{size} bytes)";
#        }
#        if($_->{size} > 4000) {
#            croak "dbf: Field $_->{name} too long ($_->{size} bytes)";
#        }
#
#        push(@template,"A".$_->{size});
#    }
#    $self->{dbf_record_template} = join(' ',@template);
#
#    my @field_names = ();
#    foreach(@{$self->{dbf_field_info}}) {
#        push(@field_names,$_->{name});
#    }
#    $self->{dbf_field_names} = [@field_names];
#
#    return 1;
}

sub get_dbf_record {
    my $self = shift;
    my $entry = shift;

    my $dbf = $self->cache('dbf',$entry);
    if(! $dbf) {
        $entry--; # make entry 0-indexed

        my $record = $self->get_bytes(
            'dbf',
            $self->{dbf_header_length}+($self->{dbf_record_length} * $entry),
            $self->{dbf_record_length}+1, # +1 for deleted flag
        );
        my($del,@data) = unpack("c".$self->{dbf_record_template},$record);

        map { s/^\s*//; s/\s*$//; } @data;

        my %record = ();
        @record{@{$self->{dbf_field_names}}} = @data;
        $record{_deleted} = (ord $del == 0x2A);
        $dbf = {%record};
        $self->cache('dbf',$entry+1,$dbf);
    }

    if(wantarray) {
        return %{$dbf};
    } else {
        return $dbf;
    }
}

sub set_dbf_record {
    my $self = shift;
    my $entry = shift;
    my %record = @_;

    $self->{_change_cache}->{dbf}->{$entry} = {%record};
}

sub get_shp_shx_header_value {
    my $self = shift;
    my $val = shift;

    unless($self->{"shx_".$val} || $self->{"shp_".$val}) {
        $self->read_shx_header();
    }

    return $self->{"shx_".$val} || $self->{"shp_".$val} || undef;
}

sub x_min { shift()->get_shp_shx_header_value('x_min'); }
sub x_max { shift()->get_shp_shx_header_value('x_max'); }
sub y_min { shift()->get_shp_shx_header_value('y_min'); }
sub y_max { shift()->get_shp_shx_header_value('y_max'); }
sub z_min { shift()->get_shp_shx_header_value('z_min'); }
sub z_max { shift()->get_shp_shx_header_value('z_max'); }
sub m_min { shift()->get_shp_shx_header_value('m_min'); }
sub m_max { shift()->get_shp_shx_header_value('m_max'); }

sub upper_left_corner {
    my $self = shift;

    return new Geo::ShapeFile::Point(X => $self->x_min, Y => $self->y_min);
}
sub upper_right_corner {
    my $self = shift;

    return new Geo::ShapeFile::Point(X => $self->x_max, Y => $self->y_min);
}
sub lower_right_corner {
    my $self = shift;

    return new Geo::ShapeFile::Point(X => $self->x_max, Y => $self->y_max);
}
sub lower_left_corner {
    my $self = shift;

    return new Geo::ShapeFile::Point(X => $self->x_min, Y => $self->y_max);
}

sub height {
    my $self = shift;

    return $self->x_max - $self->x_min;
}
sub width {
    my $self = shift;

    return $self->y_max - $self->y_min;
}

sub corners {
    my $self = shift;

    return(
        $self->upper_left_corner,
        $self->upper_right_corner,
        $self->lower_right_corner,
        $self->lower_left_corner,
    );
}

sub area_contains_point {
    my $self = shift;
    my $point = shift;
    my ($x_min,$y_min,$x_max,$y_max) = @_;

    return (
        ($point->X >= $x_min) &&
        ($point->X <= $x_max) &&
        ($point->Y >= $y_min) &&
        ($point->Y <= $y_max)
    );
}

sub bounds_contains_point {
    my $self = shift;
    my $point = shift;

    return $self->area_contains_point(
        $point, $self->x_min, $self->y_min, $self->x_max, $self->y_max,
    );
}

sub file_version {
    shift()->get_shp_shx_header_value('file_version');
}

sub shape_type {
    my $self = shift;

    if(defined $self->{_change_cache}->{shape_type}) {
        return $self->{_change_cache}->{shape_type};
    } else {
        return $self->get_shp_shx_header_value('shape_type');
    }
}

sub shapes {
    my $self = shift;

    if(defined $self->{_change_cache}->{records}) {
        return $self->{_change_cache}->{records};
    }
    unless($self->{shx_file_length}) { $self->read_shx_header(); }

    my $filelength = $self->{shx_file_length};
    $filelength -= 50; # don't count the header
    return ($filelength/4);
}

sub records {
    my $self = shift;

    if(defined $self->{_change_cache}->{records}) {
        return $self->{_change_cache}->{records};
    }

    if($self->{shx_file_length}) {
        my $filelength = $self->{shx_file_length};
        $filelength -= 50; # don't count the header
        return ($filelength/4);
    } elsif($self->{dbf_num_records}) {
        return $self->{dbf_num_records};
    }
}

sub shape_type_text {
    my $self = shift;

    return $self->type($self->shape_type());
}

sub get_shx_record_header { shift()->get_shx_record(@_); }
sub get_shx_record {
    my $self = shift;
    my $entry = shift;

    croak "must specify entry index" unless $entry;

    my $shx = $self->cache('shx',$entry);
    unless($shx) {
        my $record = $self->get_bytes('shx',(($entry - 1) * 8) + 100,8);
        $shx = [unpack("N N",$record)];
        $self->cache('shx',$entry,$shx);
    }
    return(@{$shx});
}

sub get_shp_record_header {
    my $self = shift;
    my $entry = shift;

    my($offset) = $self->get_shx_record($entry);

    my $record = $self->get_bytes('shp',$offset*2,8);
    my($number,$content_length) = unpack("N N",$record);

    return($number,$content_length);
}

# TODO - cache this
sub shapes_in_area {
    my $self = shift;
    my @area = @_; # x_min,y_min,x_max,y_max,

    my @results = ();
    for(1 .. $self->shapes) {
        my($offset,$content_length) = $self->get_shx_record($_);
        my $type = unpack("V",$self->get_bytes('shp',($offset*2)+8,4));

        if($self->type($type) eq 'Null') {
            next;
        } elsif($self->type($type) =~ /^Point/) {
            my $bytes = $self->get_bytes('shp',($offset*2)+12,16);
            my($x,$y) = (
                unpack( 'b', pack( 'S', 1 ) )
                    ? unpack( 'dd', $bytes )
                    : reverse( unpack( 'dd', scalar( reverse( $bytes ) ) ) )
            );
            my $pt = new Geo::ShapeFile::Point(X => $x, Y => $y);
            if($self->area_contains_point($pt,@area)) {
                push(@results,$_);
            }
        } elsif($self->type($type) =~ /^(PolyLine|Polygon|MultiPoint|MultiPatch)/) {
            my $bytes = $self->get_bytes('shp',($offset*2)+12,32);
            my @p = (
                unpack( 'b', pack( 'S', 1 ) )
                    ? unpack( 'd4', $bytes )
                    : reverse( unpack( 'd4', scalar( reverse( $bytes ) ) ) )
            );
            if($self->check_in_area(@p,@area) || $self->check_in_area(@area,@p)) {
                push(@results,$_);
            }
        } else {
            print "type=".$self->type($type)."\n";
        }
    }
    return @results;
}

sub check_in_area {
    my $self = shift;
    my(
        $x1_min,$y1_min,$x1_max,$y1_max,
        $x2_min,$y2_min,$x2_max,$y2_max,
    ) = @_;

    my $lhit = $self->between($x1_min,$x2_min,$x2_max);
    my $rhit = $self->between($x1_max,$x2_min,$x2_max);
    my $thit = $self->between($y1_min,$y2_min,$y2_max);
    my $bhit = $self->between($y1_max,$y2_min,$y2_max);

    return ( # collision
        ($lhit && $thit) || ($rhit && $thit) || ($lhit && $bhit) || ($rhit && $bhit)
    ) || ( # containment
        ($lhit && $thit) && ($rhit && $thit) && ($lhit && $bhit) && ($rhit && $bhit)
    );
}

sub between {
    my $self = shift;

    my $check = shift;

    unless($_[0] < $_[1]) { @_ = reverse @_; }
    return (($check >= $_[0]) && ($check <= $_[1]));
}

sub bounds {
    my $self = shift;

    return($self->x_min,$self->y_min,$self->x_max,$self->y_max);
}

sub extract_ints {
    my $self = shift;
    my $end = shift;
    my @what = @_;

    my $template = ($end =~ /^l/i)?'V':'N';

    $self->extract_and_unpack(4, $template, @what);
    foreach(@what) {
        $self->{$_} = $self->{$_};
    }
}

sub get_shp_record {
    my $self = shift;
    my $entry = shift;

    my $shape = $self->cache('shp',$entry);
    unless($shape) {
        my($offset,$content_length) = $self->get_shx_record($entry);

        my $record = $self->get_bytes('shp',$offset*2,($content_length*2)+8);

        $shape = new Geo::ShapeFile::Shape();
        $shape->parse_shp($record);
        $self->cache('shp',$entry,$shape);
    }

    return $shape;
}

sub shx_handle { shift()->get_handle('shx'); }
sub shp_handle { shift()->get_handle('shp'); }
sub dbf_handle { shift()->get_handle('dbf'); }
sub get_handle {
    my $self = shift;
    my $which = shift;

    my $han = $which."_handle";
    unless($self->{$han}) {
        $self->{$han} = new IO::File;
        my $file = join('.', $self->{filebase},$which);
        unless($self->{$han}->open($file, O_RDONLY | O_BINARY)) {
            croak "Couldn't get file handle for $file: $!";
        }
        binmode($self->{$han}); # fix windows bug reported by Patrick Dughi
    }

    return $self->{$han};
}

sub get_bytes {
    my $self = shift;
    my $file = shift;
    my $offset = shift;
    my $length = shift;

    my $handle = $file."_handle";
    my $h = $self->$handle();
    $h->seek($offset,0) || confess "Couldn't seek to $offset for $file";;
    my $tmp;
    my $res = $h->read($tmp,$length);
    if(defined $res) {
        if($res == 0) {
            confess "EOF reading $length bytes from $file at offset $offset";
        }
    } else {
        confess "Couldn't read $length bytes from $file at offset $offset ($!)";
    }
    return $tmp;
}

sub type {
    my $self = shift;
    my $shape = shift;

    my %shape_types = qw(
        0   Null
        1   Point
        3   PolyLine
        5   Polygon
        8   MultiPoint
        11  PointZ
        13  PolyLineZ
        15  PolygonZ
        18  MultiPointZ
        21  PointM
        23  PolyLineM
        25  PolygonM
        28  MultiPointM
        31  MultiPatch
    );

    return $shape_types{$shape};
}

sub find_bounds {
    my $self = shift;
    my @objects = @_;

    my %bounds = (
        x_min    => undef,
        y_min    => undef,
        x_max    => undef,
        y_max    => undef,
    );

    foreach my $obj (@objects) {
        foreach('x_min','y_min') {
            if((!defined $bounds{$_}) || ($obj->$_() < $bounds{$_})) {
                $bounds{$_} = $obj->$_();
            }
        }
        foreach('x_max','y_max') {
            if((!defined $bounds{$_}) || ($obj->$_() > $bounds{$_})) {
                $bounds{$_} = $obj->$_();
            }
        }
    }
    return(%bounds);
}

1;
__END__
=head1 NAME

Geo::ShapeFile - Perl extension for handling ESRI GIS Shapefiles.

=head1 SYNOPSIS

  use Geo::ShapeFile;

  my $shapefile = new Geo::ShapeFile("roads");

  for(1 .. $shapefile->shapes()) {
    my $shape = $shapefile->get_shp_record($_);
    # see Geo::ShapeFile::Shape docs for what to do with $shape

    my %db = $shapefile->get_dbf_record($_);
  }

=head1 ABSTRACT

The Geo::ShapeFile module reads ESRI ShapeFiles containing GIS mapping
data, it has support for shp (shape), shx (shape index), and dbf (data
base) formats.

=head1 DESCRIPTION

The Geo::ShapeFile module reads ESRI ShapeFiles containing GIS mapping
data, it has support for shp (shape), shx (shape index), and dbf (data
base) formats.

=head1 METHODS

=over 4

=item new($filename_base)

Creates a new shapefile object, the only argument it takes is the basename
for your data (don't include the extension, the module will automatically
find the extensions it supports).  For example if you have data files called
roads.shp, roads.shx, and roads.dbf, use 'new Geo::ShapeFile("roads");' to
create a new object, and the module will load the data it needs from the
files as it needs it.

=item type_is($numeric_type)

Returns true if the major type of this data file is the same as the type
passed to type_is().

=item get_dbf_record($record_index)

Returns the data from the dbf file associated with the specified record index
(shapefile indexes start at 1).  If called in a list context, returns a hash,
if called in a scalar context, returns a hashref.

=item x_min() x_max() y_min() y_max()

=item m_min() m_max() z_min() z_max()

Returns the minimum and maximum values for x, y, z, and m fields as indicated
in the shp file header.

=item upper_left_corner() upper_right_corner()

=item lower_left_corner() lower_right_corner()

Returns a Geo::ShapeFile::Point object indicating the respective corners.

=item height() width()

Returns the height and width of the area contained in the shp file.  Note that
this likely does not return miles, kilometers, or any other useful measure, it
simply returns x_max - x_min, or y_max - y_min.  Whether this data is a useful
measure or not depends on your data.

=item corners()

Returns a four element array consisting of the corners of the area contained
in the shp file.  The corners are listed clockwise starting with the upper
left.
(upper_left_corner, upper_right_corner, lower_right_corner, lower_left_corner)

=item area_contains_point($point,$x_min,$y_min,$x_max,$y_max)

Utility function that returns true if the Geo::ShapeFile::Point object in
point falls within the bounds of the rectangle defined by the area
indicated.  See bounds_contains_point() if you want to check if a point falls
within the bounds of the current shp file.

=item bounds_contains_point($point)

Returns true if the specified point falls within the bounds of the current
shp file.

=item file_version()

Returns the ShapeFile version number of the current shp/shx file.

=item shape_type()

Returns the shape type contained in the current shp/shx file.  The ESRI spec
currently allows for a file to contain only a single type of shape (null
shapes are the exception, they may appear in any data file).  This returns
the numeric value for the type, use type() to find the text name of this
value.

=item shapes()

Returns the number of shapes contained in the current shp/shx file.  This is
the value that allows you to iterate through all the shapes using
'for(1 .. $obj->shapes()) {'.

=item records()

Returns the number of records contained in the current data.  This is similar
to shapes(), but can be used even if you don't have shp/shx files, so you can
access data that is stored as dbf, but does not have shapes associated with it.

=item shape_type_text()

Returns the shape type of the current shp/shx file (see shape_type()), but
as the human-readable string type, rather than an integer.

=item get_shx_record($record_index)
=item get_shx_record_header($record_index)

Get the contents of an shx record or record header (for compatibility with
the other get_* functions, both are provided, but in the case of shx data,
they return the same information).  The return value is a two element array
consisting of the offset in the shp file where the indicated record begins,
and the content length of that record.

=item get_shp_record_header($record_index)

Retrieve an shp record header for the specified index.  Returns a two element
array consisting of the record number and the content length of the record.

=item get_shp_record($record_index)

Retrieve an shp record for the specified index.  Returns a
Geo::ShapeFile::Shape object.

=item shapes_in_area($x_min,$y_min,$x_max,$y_max)

Returns an array of integers, consisting of the indices of the shapes that
overlap with the area specified.  Currently this is a very oversimplified
function that actually finds shapes that have any point that falls within
the specified bounding box.  Currently it may miss some shapes that actually
do overlap with the specified area, if there are two points outside the area
that cause an edge to pass through the area, but neither of the end points
of that edge actually fall within the area specified.  Patches to make this
function more useful would be welcome.

=item check_in_area($x1_min,$y1_min,$x1_max,$y1_max,$x2_min,$x2_max,$y2_min,$y2_max)

Returns true if the two specified areas overlap.

=item bounds()

Returns the bounds for the current shp file.
(x_min, y_min, x_max, y_max)

=item shx_handle() shp_handle() dbf_handle()

Returns the file handles associated with the respective data files.

=item type($shape_type_number)

Returns the name of the type associated with the given type id number.

=item find_bounds(@shapes)

Takes an array of Geo::ShapeFile::Shape objects, and returns a hash, with
keys of x_min,y_min,x_max,y_max, with the values for each of those ranges.

=back

=head1 REPORTING BUGS

Please send any bugs, suggestions, or feature requests to
  E<lt>geo-shapefile-bugs@jasonkohles.comE<gt>.

=head1 SEE ALSO

Geo::ShapeFile::Shape
Geo::ShapeFile::Point

=head1 AUTHOR

Jason Kohles, E<lt>email@jasonkohles.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002,2003 by Jason Kohles

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
