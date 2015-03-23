#Written by Keith Jolley
#Copyright (c) 2014, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::REST::Routes::Resources;
use strict;
use warnings;
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Resource description routes
any [qw(get post)] => '/' => sub {
	my $self      = setting('self');
	my $resources = $self->get_resources;
	my $values    = [];
	foreach my $resource (@$resources) {
		my $databases = [];
		push @$databases,
		  { name => 'Sequence/profile definitions', href => request->uri_for("/db/$resource->{'seqdef_config'}")->as_string }
		  if defined $resource->{'seqdef_config'};
		push @$databases, { name => 'Isolates', href => request->uri_for("/db/$resource->{'isolates_config'}")->as_string }
		  if defined $resource->{'isolates_config'};
		push @$values, { name => $resource->{'name'}, description => $resource->{'description'}, databases => $databases };
	}
	return $values;
};
any [qw(get post)] => qr{^/db/?+$} => sub {
	redirect '/';
};
any [qw(get post)] => '/db/:db' => sub {
	my $self = setting('self');
	my $db   = params->{'db'};
	if ( !$self->{'system'}->{'db'} ) {
		send_error( "Database '$db' does not exist", 404 );
	}
	my $set_id       = $self->get_set_id;
	my $schemes      = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $loci         = $self->{'datastore'}->get_loci( { set_id => $set_id } );
	my $scheme_route = @$schemes ? request->uri_for("/db/$db/schemes")->as_string : undef;
	my $loci_route   = @$loci ? request->uri_for("/db/$db/loci")->as_string : undef;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $count  = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
		my $routes = {
			records  => int($count),                                       #Force integer output (non-quoted)
			isolates => request->uri_for("/db/$db/isolates")->as_string,
			fields   => request->uri_for("/db/$db/fields")->as_string
		};
		$routes->{'schemes'} = $scheme_route if $scheme_route;
		$routes->{'loci'}    = $loci_route   if $loci_route;
		return $routes;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $routes = {};
		$routes->{'schemes'} = $scheme_route if $scheme_route;
		$routes->{'loci'}    = $loci_route   if $loci_route;
		return $routes;
	} else {
		return { title => 'Database configuration is invalid' };
	}
};
1;
