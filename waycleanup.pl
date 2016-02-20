#!/usr/bin/perl -w
#-----------------------------------------------------------------------------
#
#  waycleanup.pl
#
#  Call it as follows:
#
#    waycleanup.pl YourSVGFile.svg >SVGFileWithCurves.svg
#
#-----------------------------------------------------------------------------
#
#  Copyright 2007 by Barry Crabtree, Jozef Vince
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA
#
#-----------------------------------------------------------------------------

use strict;
use Carp;

#
# clean up unused ways (i.e. ways and areas which are not rendered)
#
# Globals...
my $line_position = 0;     # current line position in the svg file
my @svg_lines     = ();    # the lines from the svg file
my %defs;                  # ways and areas found in svg

# first pass, read in the svg lines, build the @svg_lines, %defs structures.

while (<>) {
    my $line = $_;
    $svg_lines[$line_position] = $line;
    if ( $line =~ m{<path\s+id=\"((?:way|area|x_way|x_area)_\S+)\" }x ) {
        my $path_prefix = $1;

        $defs{$path_prefix} = [ $line_position, 0 ];    # 0 mean not referenced

    }
    $line_position++;
}

foreach my $line (@svg_lines) {
    if ( $line =~
        m{<use\s+xlink\:href=\"\#((?:way|area|x_way|x_area)_\S+)\" }x )
    {                                                   # found a path
        my $path_ref = $1;

        $defs{$path_ref}->[1] = 1;
    }
    elsif ( $line =~
        m{<textPath\s+xlink\:href=\"\#((?:way|area|x_way|x_area)_\S+)\" }x )
    {                                                   # found a path
        my $path_ref = $1;

        $defs{$path_ref}->[1] = 1;
    }
    $line_position++;
}

foreach my $path_id ( keys %defs ) {
    my $path_info_ref   = $defs{$path_id};
    my $line_index      = $path_info_ref->[0];
    my $path_referenced = $path_info_ref->[1];

    if ( $path_referenced == 0 ) {
        $svg_lines[$line_index] = "";
    }
}

# print out the transformed svg file.
foreach my $line (@svg_lines) {
    print $line;
}
