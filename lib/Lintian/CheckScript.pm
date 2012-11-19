# Copyright (C) 2012 Niels Thykier <niels@thykier.net>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, you can find it on the World Wide
# Web at http://www.gnu.org/copyleft/gpl.html, or write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.

package Lintian::CheckScript;

use strict;
use warnings;

use Cwd qw(realpath);
use File::Basename qw(dirname);
use base 'Class::Accessor';

use Carp qw(croak);

use Lintian::Tag::Info ();
use Lintian::Util qw(read_dpkg_control);

=head1 NAME

Lintian::CheckScript - Check script meta data

=head1 SYNOPSIS

 use Lintian::CheckScript;
 
 my $cs = Lintian::CheckScript->new ("$ENV{'LINTIAN_ROOT'}/checks/",
                                     'files');
 my $name = $cs->name;
 foreach my $tag ($cs->tags) {
    # $ti is an instance of Lintian::Tag::Info
    my $ti = $cs->get_tag ($tag);
    print "$tag is a part of the check $name\n";
    # Do something with $ti / $tag
 }
 foreach my $needs ($cs->needs_info) {
    print "$name needs $needs\n";
 }
 if ($cs->is_check_type ('binary') && $cs->is_check_type ('source')) {
    # Check applies to binary pkgs AND source pkgs
 }

=head1 DESCRIPTION

Instances of this class represents the data in the check ".desc"
files.  It allows access to the tags (as Lintian::Tag::Info) and the
common meta data of the check (such as Needs-Info).

=head1 CLASS METHODS

=over 4

=item Lintian::CheckScript->new ($basedir, $checkname)

Parses the $file as a check desc file.

=cut

sub new {
    my ($class, $basedir, $checkname) = @_;
    my ($header, @tags) = read_dpkg_control ("$basedir/${checkname}.desc");
    my $self;
    my $dir;
    unless ($header->{'check-script'}) {
        croak "Missing Check-Script field in $basedir/${checkname}.desc";
    }
    $dir = realpath ($basedir)
        or croak "Cannot resolve $basedir: $!";

    $self = {
        'name' => $header->{'check-script'},
        'type' => $header->{'type'}, # lintian.desc has no type
        'abbrev' => $header->{'abbrev'},
        'needs_info' => [split /\s*,\s*/, $header->{'needs-info'}//''],
    };

    $self->{'script_pkg'} = $self->{'name'};
    $self->{'script_pkg'} =~ s,/,::,go;
    $self->{'script_pkg'} =~ s,[-.],_,go;

    $self->{'script_path'} = $dir . '/' . $self->{'name'};

    if ($self->{'type'}//'ALL' ne 'ALL') {
        $self->{'type-table'} = {};
        for my $t (split /\s*,\s*/o, $self->{'type'}) {
            $self->{'type-table'}->{$t} = 1;
        }
    }

    for my $pg (@tags) {
        my $ti;
        croak "Missing Tag field for tag in $basedir/${checkname}.desc"
            unless $pg->{'tag'};
        $ti = Lintian::Tag::Info->new($pg, $self->{'name'}, $self->{'type'});
        $self->{'tag-table'}->{$ti->tag} = $ti;
    }

    bless $self, $class;

    return $self;
}

=item $cs->name

Returns the "name" of the check script.  This is the value in the
Check-Script field in the file.

=item $cs->type

Returns the value stored in the "Type" field of the file.  For the
purpose of testing if the check applies to a given package type, the
L</is_check_type> method can be used instead.

Note in rare cases this may return undef.  This is the case for the
lintian.desc, where this field is simply not present.

=item $cs->abbrev

Returns the value of the Abbrev field from the desc file.

=item $cs->script_path

Returns the (expected) path to the script implementing this check.

=cut

Lintian::CheckScript->mk_ro_accessors (qw(name type abbrev script_path));

=item needs_info

Returns a list of all items listed in the Needs-Info field.  Neither
the list nor its contents should be modified.

=cut

sub needs_info {
    my ($self) = @_;
    return @{ $self->{'needs_info'} };
}

=item $cs->is_check_type ($type)

Returns a truth value if this check can be applied to a $type package.

Note if $cs->type return undef, this will return a truth value for all
inputs.

=cut

sub is_check_type {
    my ($self, $type) = @_;
    return 1 if ($self->{'type'}//'ALL') eq 'ALL';
    return $self->{'type-table'}->{$type};
}

=item $cs->get_tag ($tagname)

Return the L<tag|Lintian::Info::Tag> or undef (if the tag is not in
this check).

=cut

sub get_tag {
    my ($self, $tag) = @_;
    return $self->{'tag-table'}->{$tag};
}

=item $cs->tags

Returns the list of tag names in the check.  The list nor its contents
should be modified.

=cut

sub tags {
    my ($self) = @_;
    return keys %{ $self->{'tag-table'}};
}

=item $cs->run_check ($proc, $group)

Run the check on C<$proc>, which is in the
L<group|Lintian::ProcessableGroup> C<$group>.  C<$proc> should be
a L<lab entry|Lintian::Lab::Entry> and must have the proper
collections run on it prior to calling this method (See
L<Lintian::Unpacker>).

The method may error out if loading the check failed or if the check
itself calls die/croak/fail/etc.

Returns normally on success; the return value has no semantic meaning
and is currently C<undef>.

=cut

sub run_check {
    my ($self, $proc, $group) = @_;
    my $cs_pkg = $self->{'script_pkg'};
    my $cs_path = $self->{'script_path'};

    require $cs_path;

    my @args = ($proc->pkg_name,
                $proc->pkg_type,
                $proc->info,
                $proc,
                $group);
    {
        # minimal "no strict refs" scope.
        no strict 'refs';
        &{'Lintian::' . $cs_pkg . '::run'}(@args);
    }
    return;
}

=back

=head1 AUTHOR

Originally written by Niels Thykier <niels@thykier.net> for Lintian.

=head1 SEE ALSO

lintian(1), Lintian::Profile(3), Lintian::Tag::Info(3)

=cut

1;
__END__

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

