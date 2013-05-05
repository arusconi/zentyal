# Copyright (C) 2008-2013 Zentyal S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# Class: EBox::LogObserver
#
#       Those modules FIXME to process logs generated by their
#       daemon or servide must inherit from this class and implement
#       the given interface
#
package EBox::LogObserver;

use strict;
use warnings;

use Perl6::Junction qw(any);

sub new
{
    my $class = shift;
    my $self = {};
    bless($self, $class);
    return $self;
}

# Method: logHelper
#
# Returns:
#
#       An object implementing EBox::LogHelper
sub logHelper
{
    return undef;
}

# Method: enableLog
#
#   This method must be overriden by the class implementing this interface,
#   if it needs to enable or disable logging facilities in the services its
#   managing.
#
# Parameters:
#
#   enable - boolean, true if it's enabled, false it's disabled
#
sub enableLog
{
}

# Method: tableInfo
#
#       This function returns an array of hash ref or a single hash
#       ref with these fields:
#
#        - name: the printable name of the table
#        - tablename: the name of the database table associated with the module.
#        - titles: A hash ref with the table fields and theirs user read
#               translation.
#        - order: An array with table fields ordered.
#
#         - consolidate: instructions for consolidation of information in
#         periodic tables. The instruction is a hash ref (see below)
#
#
#  Consolidate hash specification:
#
#    The hash has as keys the name of the destination consolidation tables (it
#    will be concataned to time periods prefix as daily, hourly).  The values
#    must be another hash ref with the consolidation parameters. The hash ref
#    has those fields:
#       - consolidateColumns:hash ref which a key for each column that should
#           be treated the value is a hash ref with more options:
#             * conversor: reference to a sub to convert the column value. The
#                 function will be called with row value as first argument and
#                 the row as second
#              * accummulate: sginals that the vaule of the column will be
#                   accummulated and in which column will be accummulated.
#                   It may be a string to specif a column or a sub ref which
#                   returns the name of the column to be accummulated. In the
#                   last case it is called with the vaule of the column and
#                   the row as arguments.
#              * destination: for not-accummulate column this will be the column
#                  which wil be store the value. Defaults to a column whith
#                  the same name
#       - accummulateColumns: hash ref to signal which data base columns
#           will be used to accummulate numeric data from other columns.
#           The keys should be the name of the clumn and the values
#           the number will be used to autoincremet the column in each row.
#           Use zero if you don't want autoincrement.
#            The drfault is a column called count which autoincrements one unit
#            each time
#
#       - filter: reference to a method used to filter out rows, the method will
#                 be supplied to a reference to a hash with the row values and
#                 if it returns false the row would be excluded
#       - quote: hash ref which signals which columns should be quoted
#                to protect special string characters. The columns should
#                contain strings.
#                Not present columns default to false.
#
#   Warning:
#    -use lowercase in column names
sub tableInfo
{
    throw EBox::Exceptions::NotImplemented;
}

# Method: humanEventMessage
#
#      Given a row with the table description given by
#      <EBox::LogObserver::tableInfo> it will return a human readable
#      message to inform admin using events.
#
#      To be overriden by subclasses. Default behaviour is showing
#      every field name following by a colon and the value.
#
# Parameters:
#
#      row - hash ref the row returned by <EBox::Logs::search>
#
# Returns:
#
#      String - the i18ned human readable message to send in an event
#
sub humanEventMessage
{
    my ($self, $row) = @_;

    my @tableInfos;
    my $tI = $self->tableInfo();
    if ( ref($tI) eq 'HASH' ) {
        EBox::warn('tableInfo() in ' . $self->name()
                   . ' must return a reference to a '
                   . 'list of hashes not the hash itself');

        @tableInfos = ( $tI );
    } else {
        @tableInfos = @{ $tI };
    }
    my $message = q{};
    foreach my $tableInfo (@tableInfos) {
        next unless (exists($tableInfo->{events}->{$row->{event}}));
        foreach my $field (@{$tableInfo->{order}}) {
            if ( $field eq $tableInfo->{eventcol} ) {
                $message .= $tableInfo->{titles}->{$tableInfo->{eventcol}}
                  . ': ' . $tableInfo->{events}->{$row->{$field}} . ' ';
            } else {
                my $rowContent = $row->{$field};
                # Delete trailing spaces
                $rowContent =~ s{ \s* \z}{}gxm;
                $message .= $tableInfo->{titles}->{$field} . ": $rowContent ";
            }
        }
    }
    return $message;

}

# Method: reportUrls
#
#     this  return the module's rows for the SelectLog table.
sub reportUrls
{
    my ($self) = @_;
#    my $domain = $self->name();

    my @tableInfos;
    my $ti = $self->tableInfo();
    if (ref $ti eq 'HASH') {
            EBox::warn('tableInfo() in ' . $self->name .
                       ' must return a reference to a list of hashes not the hash itself');

            @tableInfos = ( $ti );
          }
    else {
      @tableInfos = @{ $ti };
    }

    my @urls;
    foreach my $tableInfo (@tableInfos) {
      my $index = $tableInfo->{tablename};
      my $rawUrl = "/Logs/Index?selected=$index&refresh=1";

      if (not $tableInfo->{consolidate}) {
          push @urls, { domain => $tableInfo->{name},  raw => $rawUrl, };
          next;
      }

      my @consolidateTables = keys %{ $tableInfo->{consolidate} };

      my @reportComposites = grep {
          ((ref $_) =~ /Report$/) and
              ($self->_compositeUsesDbTable($_, \@consolidateTables) )
      } @{ $self->composites };

      (ref $self) =~  m/::(.*?)$/;;
      my $urlModName= $1;

      my $first = 1;
      foreach my $comp (@reportComposites) {
          my $compName = $comp->name();
          my %compUrls =(
                         domain => $tableInfo->{name},
                         summary => "/$urlModName/Composite/$compName",
                      );
          if ($first) {
              $compUrls{raw} = $rawUrl;
              $first =0;
          }
          else {
              $compUrls{raw} = undef;
          }

          push @urls, \%compUrls;
      }

      if (not @reportComposites) {
          push @urls, { domain => $tableInfo->{name},  raw => $rawUrl } ;

      }

  }

    return \@urls;
}

sub _compositeUsesDbTable
{
    my ($self, $composite, $dbTables_r) = @_;

    my $usesDbTable = 0;
    foreach my $component (@{ $composite->components() } ) {
        if ($component->can('dbTableName')) {
            if ($component->dbTableName() eq any( @{ $dbTables_r } )) {
                $usesDbTable = 1;
            }

            last;
        }
    }

    return $usesDbTable;
}

1;
