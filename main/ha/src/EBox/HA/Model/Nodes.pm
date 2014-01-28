# Copyright (C) 2014 Zentyal S. L.
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

use strict;
use warnings;

package EBox::HA::Model::Nodes;

# Class: EBox::HA::Model::Nodes
#
#     Model to show the nodes from the cluster
#

use base 'EBox::Model::DataTable';

use EBox::Gettext;
use EBox::HA::CRMWrapper;
use EBox::HA::NodeList;
use EBox::Types::Host;
use EBox::Types::HostIP;
use EBox::Types::MultiStateAction;
use EBox::Types::Port;

# Group: Public methods

# Constructor: new
#
#    To store the list
#
sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    $self->{list} = new EBox::HA::NodeList($self->parentModule());

    return $self;
}

# Method: ids
#
#     Return the current list of node names
#
# Overrides:
#
#     <EBox::Model::DataTable::ids>
#
sub ids
{
    my ($self)  = @_;

    my @names = map { $_->{name} } @{$self->{list}->list()};
    return \@names;
}

# Method: row
#
#     Return a node names
#
# Overrides:
#
#     <EBox::Model::DataTable::row>
#
sub row
{
    my ($self, $id)  = @_;

    my $node = $self->{list}->node($id);

    my $row = new EBox::Model::Row(dir => $self->directory(), confmodule => $self->parentModule());
    $row->setId($id);
    $row->setModel($self);
    $row->setReadOnly(1);

    my $tableDesc = $self->table()->{tableDescription};
    foreach my $type (@{$tableDesc}) {
        my $element = $type->clone();
        $element->setValue($node->{$element->fieldName()});
        $row->addElement($element);
    }

    return $row;
}

# Method: printableModelName
#
#     Showing the dynamic cluster name
#
# Overrides:
#
#     <EBox::Model::DataTable.:printableModelName>
#
sub printableModelName
{
    my ($self) = @_;

    my $clusterName = $self->parentModule()->model('Cluster')->nameValue();
    return __x('Node list for {name} cluster', name => $clusterName);
}

# Group: Protected methods

# Method: _table
#
# Overrides:
#
#       <EBox::Model::DataTable::_table>
#
sub _table
{
    my ($self) = @_;

    my @fields = (
        new EBox::Types::Host(
            fieldName     => 'name',
            printableName => __('Hostname'),
           ),
        new EBox::Types::HostIP(
            fieldName     => 'addr',
            printableName => __('IP address'),
       ),
        new EBox::Types::Port(
            fieldName     => 'webAdminPort',  # FIX the name?
            printableName => __('Port'),
           ),
       );
    my $customActions = [
        new EBox::Types::MultiStateAction(
            acquirer  => \&_acquireActive,
            model     => $self,
            states    => {
                'active'  => {
                    name           => 'demote',
                    printableValue => __('Demote'),
                    handler        => \&_doDemote,
                    message        => __('Node demoted'),
                    enabled        => \&_anyResource,
                },
                'passive' => {
                    name           => 'promote',
                    printableValue => __('Promote'),
                    handler        => \&_doPromote,
                    message        => __('Node promoted'),
                    enabled        => \&_anyResource,
                }
               },
           ),
       ];

    my $dataTable =
    {
        tableName => 'Nodes',
        printableTableName => __('Node list for cluster'),
        defaultActions => [ 'changeView' ],
        customActions  => $customActions,
        modelDomain => 'HA',
        tableDescription => \@fields,
        help => undef,
    };

    return $dataTable;
}

# Group: Subroutines handlers

# Knowing if I'm the active/passive
sub _acquireActive
{
    my ($self, $id) = @_;

    unless ($self->{activeNode}) {
        # Calculate and cache the active node
        $self->{activeNode} = EBox::HA::CRMWrapper::activeNode();
    }

    return ($self->{activeNode} eq $id ? 'active' : 'passive');
}

# Knowing if any resource is available
sub _anyResource
{
    return (EBox::HA::CRMWrapper::resourceNum() > 0);
}

# Do promote by moving all resources to the given node
sub _doPromote
{
    my ($self, $actionType, $id, %params) = @_;

    EBox::HA::CRMWrapper::promote($id);
}

# Do demote by moving out all resources from the given node
sub _doPromote
{
    my ($self, $actionType, $id, %params) = @_;

    EBox::HA::CRMWrapper::demote($id);
}

1;
