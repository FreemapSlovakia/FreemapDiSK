package Geo::ShapeFile::Point;
# TODO - add dimension operators (to specify if 2 or 3 dimensional point)
use strict;
use warnings;
use Math::Trig;
use Carp;
our $VERSION = '2.52';

use overload
	'=='	=> 'eq',
	'eq'	=> 'eq',
	'""'	=> 'stringify',
	'+'		=> \&add,
	'-'		=> \&subtract,
	'*'		=> \&multiply,
	'/'		=> \&divide,
    fallback    => 1
;

my %config = (
	comp_includes_z		=> 1,
	comp_includes_m		=> 1,
);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $self = {@_};

    bless($self, $class);

    return $self;
}

sub var {
	my $self = shift;
	my $var = shift;

	if(@_) {
		return $self->{$var} = shift;
	} else {
		return $self->{$var};
	}
}

sub X { shift()->var('X',@_); }
sub Y { shift()->var('Y',@_); }
sub Z { shift()->var('Z',@_); }
sub M { shift()->var('M',@_); }

# TODO - document these
sub x_min { shift()->var('X'); }
sub x_max { shift()->var('X'); }
sub y_min { shift()->var('Y'); }
sub y_max { shift()->var('Y'); }
sub z_min { shift()->var('Z'); }
sub z_max { shift()->var('Z'); }
sub m_min { shift()->var('M'); }
sub m_max { shift()->var('M'); }

sub import {
	my $self = shift;
	my %args = @_;

	foreach(keys %args) { $config{$_} = $args{$_}; }
}

sub eq {
	my $left = shift;
	my $right = shift;

	if($config{comp_includes_z} && (defined $left->Z || defined $right->Z)) {
        return 0 unless defined $left->Z && defined $right->Z;
		return 0 unless $left->Z == $right->Z;
	}
	if($config{comp_includes_m} && (defined $left->M || defined $right->M)) {
        return 0 unless defined $left->M && defined $right->M;
		return 0 unless $left->M == $right->M;
	}
	return ($left->X == $right->X && $left->Y == $right->Y);
}

sub stringify {
	my $self = shift;

	my @foo = ();
	foreach(qw/X Y Z M/) {
		if(defined $self->$_()) {
			push(@foo,"$_=".$self->$_());
		}
	}
	my $r = "Point(".join(',',@foo).")";
}

sub distance_from {
	my($p1,$p2) = @_;

	my $dp = $p2->subtract($p1);
	sqrt( ($dp->X ** 2) + ($dp->Y **2) );
}
sub distance_to { distance_from(@_); }

sub angle_to {
	my($p1,$p2) = @_;

	my $dp = $p2 - $p1;
	if($dp->Y && $dp->X) {	# two distinct points
		return rad2deg( atan( $dp->Y / $dp->X ) );
	} elsif($dp->Y) {		# same X value
		return $dp->Y > 0 ? 90 : -90;
	} else {				# same point
		return 0;
	}
}

sub add { mathemagic('add',@_); }
sub subtract { mathemagic('subtract',@_); }
sub multiply { mathemagic('multiply',@_); }
sub divide { mathemagic('divide',@_); }

sub mathemagic {
	my($op,$l,$r,$reverse) = @_;

	if($reverse) { ($l,$r) = ($r,$l); } # put them back in the right order
	my($left,$right);

	if(UNIVERSAL::isa($l,"Geo::ShapeFile::Point")) { $left = 'point'; }
	if(UNIVERSAL::isa($r,"Geo::ShapeFile::Point")) { $right = 'point'; }

	if($l =~ /^[\d\.]+$/) { $left = 'number'; }
	if($r =~ /^[\d\.]+$/) { $right = 'number'; }

	unless($left) { croak "Couldn't identify $l for $op"; }
	unless($right) { croak "Couldn't identify $r for $op"; }

	my $function = join('_',$op,$left,$right);

	unless(defined &{$function}) {
		croak "Don't know how to $op $left and $right";
	} else {
		no strict 'refs';
		return $function->($l,$r);
	}
}

sub add_point_point {
	my($p1,$p2) = @_;

	my $z;
	if(defined($p2->Z) && defined($p1->Z)) { $z = ($p2->Z + $p1->Z); }
	
	new Geo::ShapeFile::Point(
		X => ($p2->X + $p1->X),
		Y => ($p2->Y + $p1->Y),
		Z => $z,
	);
}

sub add_point_number {
	my($p1,$n) = @_;

	my $z;
	if(defined($p1->Z)) { $z = ($p1->Z + $n); }
	
	new Geo::ShapeFile::Point(
		X => ($p1->X + $n),
		Y => ($p1->Y + $n),
		Z => $z,
	);
}
sub add_number_point { add_point_number(@_); }

sub subtract_point_point {
	my($p1,$p2) = @_;

	my $z;
	if(defined($p2->Z) && defined($p1->Z)) { $z = ($p2->Z - $p1->Z); }
	
	new Geo::ShapeFile::Point(
		X => ($p2->X - $p1->X),
		Y => ($p2->Y - $p1->Y),
		Z => $z,
	);
}
sub subtract_point_number {
	my($p1,$n) = @_;

	my $z;
	if(defined($p1->Z)) { $z = ($p1->Z - $n); }
	
	new Geo::ShapeFile::Point(
		X => ($p1->X - $n),
		Y => ($p1->Y - $n),
		Z => $z,
	);
}
sub subtract_number_point { subtract_point_number(reverse @_); }

sub multiply_point_point {
	my($p1,$p2) = @_;

	my $z;
	if(defined($p2->Z) && defined($p1->Z)) { $z = ($p2->Z * $p1->Z); }
	
	new Geo::ShapeFile::Point(
		X => ($p2->X * $p1->X),
		Y => ($p2->Y * $p1->Y),
		Z => $z,
	);
}
sub multiply_point_number {
	my($p1,$n) = @_;

	my $z;
	if(defined($p1->Z)) { $z = ($p1->Z * $n); }
	
	new Geo::ShapeFile::Point(
		X => ($p1->X * $n),
		Y => ($p1->Y * $n),
		Z => $z,
	);
}
sub multiply_number_point { multiply_point_number(reverse @_); }

sub divide_point_point {
	my($p1,$p2) = @_;

	my $z;
	if(defined($p2->Z) && defined($p1->Z)) { $z = ($p2->Z / $p1->Z); }
		
	new Geo::ShapeFile::Point(
		X => ($p2->X / $p1->X),
		Y => ($p2->Y / $p1->Y),
		Z => $z,
	);
}
sub divide_point_number {
	my($p1,$n) = @_;

	my $z;
	if(defined($p1->Z)) { $z = ($p1->Z / $n); }
	
	new Geo::ShapeFile::Point(
		X => ($p1->X / $n),
		Y => ($p1->Y / $n),
		Z => $z,
	);
}
sub divide_number_point { divide_point_number(reverse @_); }

1;
__END__
=head1 NAME

Geo::ShapeFile::Point - Geo::ShapeFile utility class.

=head1 SYNOPSIS

  use Geo::ShapeFile::Point;
  use Geo::ShapeFile;

  my $point = new Geo::ShapeFile::Point(X => 12345, Y => 54321);

=head1 ABSTRACT

  This is a utility class, used by Geo::ShapeFile.

=head1 DESCRIPTION

This is a utility class, used by Geo::ShapeFile to represent point data,
you should see the Geo::ShapeFile documentation for more information.

=head2 EXPORT

Nothing.

=head2 IMPORT NOTE

This module uses overloaded operators to allow you to use == or eq to compare
two point objects.  By default points are considered to be equal only if their
X, Y, Z, and M attributes are equal.  If you want to exclude the Z or M
attributes when comparing, you should use comp_includes_z or comp_includes_m 
when importing the object.  Note that you must do this before you load the
Geo::ShapeFile module, or it will pass it's own arguments to import, and you
will get the default behavior:

  DO:

  use Geo::ShapeFile::Point comp_includes_m => 0, comp_includes_z => 0;
  use Geo::ShapeFile;

  DONT:

  use Geo::ShapeFile;
  use Geo::ShapeFile::Point comp_includes_m => 0, comp_includes_z => 0;
  (Geo::ShapeFile already imported Point for you)

=head1 METHODS

=over 4

=item new(X => $x, Y => $y)

Creates a new Geo::ShapeFile::Point object, takes a has consisting of X, Y, Z,
and/or M values to be assigned to the point.

=item X() Y() Z() M()

Set/retrieve the X, Y, Z, or M values for this object.

=item x_min() x_max() y_min() y_max()

=item z_min() z_max() m_min() m_max()

These methods are provided for compatibility with Geo::ShapeFile::Shape, but
for points simply return the X, Y, Z, or M coordinates as appropriate.

=item distance_from($point)

Returns the distance between this point and the specified point.  Only
considers the two-dimensional distance, altitude is not included in the
calculation.

=item angle_to($point);

Returns the angle (in degress) from this point to some other point.  Returns
0 if the two points are in the same location.

=back

=head1 REPORTING BUGS

Please send any bugs, suggestions, or feature requests to
  E<lt>geo-shapefile-bugs@jasonkohles.comE<gt>.

=head1 SEE ALSO

Geo::ShapeFile

=head1 AUTHOR

Jason Kohles, E<lt>email@jasonkohles.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002,2003 by Jason Kohles

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
