#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
package BIGSdb::Locus;
use strict;
use warnings;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Locus');

sub new {    ## no critic (RequireArgUnpacking)
	my $class = shift;
	my $self  = {@_};
	$self->{'sql'} = {};
	if ( !$self->{'id'} ) {
		throw BIGSdb::DataException('Invalid locus');
	}
	$self->{'dbase_id_field'}  = 'id'       if !$self->{'dbase_id_field'};
	$self->{'dbase_seq_field'} = 'sequence' if !$self->{'dbase_seq_field'};
	bless( $self, $class );
	$logger->info("Locus $self->{'id'} set up.");
	return $self;
}

sub DESTROY {
	my ($self) = @_;
	foreach ( keys %{ $self->{'sql'} } ) {
		eval {
			if ( $self->{'sql'}->{$_} && $self->{'sql'}->{$_}->isa('UNIVERSAL') )
			{
				$self->{'sql'}->{$_}->finish;
				$logger->info("Locus $self->{'id'} statement handle '$_' finished.");
			}
		};
	}
	$logger->info("Locus $self->{'id'} destroyed.");
	return;
}

sub get_allele_id_from_sequence {
	my ( $self, $seq_ref ) = @_;
	if ( !$self->{'db'} ) {
		throw BIGSdb::DatabaseConnectionException("No connection to locus $self->{'id'} database");
	}
	if ( !$self->{'sql'}->{'lookup_sequence'} ) {
		my $qry;
		if ( $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'} ) {
			$qry =
			    "SELECT $self->{'dbase_id_field'} FROM $self->{'dbase_table'} WHERE "
			  . "(md5($self->{'dbase_seq_field'}),$self->{'dbase_id2_field'})=(md5(?),?)";
		} else {
			$qry = "SELECT $self->{'dbase_id_field'} FROM $self->{'dbase_table'} "
			  . "WHERE md5($self->{'dbase_seq_field'})=md5(?)";
		}
		$self->{'sql'}->{'lookup_sequence'} = $self->{'db'}->prepare($qry);
	}
	my @args = ($$seq_ref);
	push @args, $self->{'dbase_id2_value'} if $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'};
	eval { $self->{'sql'}->{'lookup_sequence'}->execute(@args) };
	if ($@) {
		$logger->error( q(Cannot execute 'lookup_sequence' query handle. Check database attributes in the )
			  . qq (locus table for locus '$self->{'id'}'! Statement was )
			  . qq('$self->{'sql'}->{lookup_sequence}->{Statement}'. $@ )
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException('Locus configuration error');
	} else {
		my ($allele_id) = $self->{'sql'}->{'lookup_sequence'}->fetchrow_array;

		#Prevent table lock on long offline jobs
		$self->{'db'}->commit;
		return $allele_id;
	}
}

sub get_allele_sequence {
	my ( $self, $id ) = @_;
	if ( !$self->{'db'} ) {
		throw BIGSdb::DatabaseConnectionException("No connection to locus $self->{'id'} database");
	}
	if ( !$self->{'sql'}->{'sequence'} ) {
		my $qry;
		if ( $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'} ) {
			$qry =
			    "SELECT $self->{'dbase_seq_field'} FROM $self->{'dbase_table'} WHERE "
			  . "($self->{'dbase_id_field'},$self->{'dbase_id2_field'})=(?,?)";
		} else {
			$qry = "SELECT $self->{'dbase_seq_field'} FROM $self->{'dbase_table'} WHERE $self->{'dbase_id_field'}=?";
		}
		$self->{'sql'}->{'sequence'} = $self->{'db'}->prepare($qry);
		$logger->debug("Locus $self->{'id'} statement handle 'sequence' prepared ($qry).");
	}
	my @args = ($id);
	push @args, $self->{'dbase_id2_value'} if $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'};
	eval { $self->{'sql'}->{'sequence'}->execute(@args) };
	if ($@) {
		$logger->error( q(Cannot execute 'sequence' query handle. Check database attributes in the locus table for )
			  . qq(locus '$self->{'id'}'! Statement was '$self->{'sql'}->{sequence}->{Statement}'. id='$id'  $@ )
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException('Locus configuration error');
	} else {
		my ($sequence) = $self->{'sql'}->{'sequence'}->fetchrow_array;
		$self->{'db'}->commit;    #Prevent table lock on long offline jobs
		return \$sequence;
	}
}

sub get_all_sequences {
	my ( $self, $options ) = @_;
	if ( !$self->{'db'} ) {
		$logger->info("No connection to locus $self->{'id'} database");
		return;
	}
	$options = {} if ref $options ne 'HASH';

	#It can be quicker, on large databases, to create a temporary table of
	#all alleles for a locus, and then to return all of this, than to simply return
	#the values from the sequences table directly.
	my $temp_table = "temp_locus_$self->{'id'}";
	$temp_table =~ s/'/_/gx;
	my $qry;
	if ( $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'} ) {
		$qry = "SELECT $self->{'dbase_id_field'},$self->{'dbase_seq_field'} FROM $self->{'dbase_table'} WHERE "
		  . "$self->{'dbase_id2_field'}=?";
		$qry .= ' AND exemplar' if $options->{'exemplar'};
	} else {
		$qry = "SELECT $self->{'dbase_id_field'},$self->{'dbase_seq_field'} FROM $self->{'dbase_table'}";
		$qry .= ' WHERE exemplar' if $options->{'exemplar'};
	}
	my @args;
	push @args, $self->{'dbase_id2_value'} if $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'};
	my $sql;
	eval {
		if ( $options->{'no_temp_table'} )
		{
			$sql = $self->{'db'}->prepare($qry);
			$sql->execute(@args);
		} else {
			$self->{'db'}->do( "CREATE TEMP TABLE $temp_table AS $qry", undef, @args );
			$sql = $self->{'db'}->prepare("SELECT * FROM $temp_table");
			$sql->execute;
		}
	};
	if ($@) {
		$logger->error( q(Cannot query all sequence temporary table. Check database attributes in the )
			  . qq(locus table for locus '$self->{'id'}'!. $@)
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException('Locus configuration error');
	}
	my $data = $sql->fetchall_arrayref;
	if ( !$options->{'no_temp_table'} ) {

		#Explicitly drop temp table as some offline jobs can be long-running and we
		#shouldn't call this method multiple times anyway.
		$self->{'db'}->do("DROP TABLE $temp_table");
	}
	my %seqs = map { $_->[0] => $_->[1] } @$data;
	delete $seqs{$_} foreach qw(N 0);

	#Prevent table lock on long offline jobs
	$self->{'db'}->commit;
	return \%seqs;
}

sub get_sequence_count {
	my ($self) = @_;
	if ( !$self->{'db'} ) {
		$logger->info("No connection to locus $self->{'id'} database");
		return;
	}
	my $qry;
	if ( $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'} ) {
		$qry = "SELECT COUNT(*) FROM $self->{'dbase_table'} WHERE $self->{'dbase_id2_field'}=?";
	} else {
		$qry = "SELECT COUNT(*) FROM $self->{'dbase_table'}";
	}
	my $sql = $self->{'db'}->prepare($qry);
	my @args;
	push @args, $self->{'dbase_id2_value'} if $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'};
	eval { $sql->execute(@args) };
	if ($@) {
		$logger->error($@);
		throw BIGSdb::DatabaseConfigurationException('Locus configuration error');
	}
	return $sql->fetchrow_array;
}

sub get_flags {
	my ( $self, $allele_id ) = @_;
	if ( !$self->{'db'} ) {
		$logger->info("No connection to locus $self->{'id'} database");
		return [];
	}
	if ( !$self->{'dbase_id2_value'} ) {
		$logger->error('You can only get flags from a BIGSdb seqdef database.');
		return [];
	}
	if ( !$self->{'sql'}->{'flags'} ) {
		$self->{'sql'}->{'flags'} =
		  $self->{'db'}->prepare('SELECT flag FROM allele_flags WHERE (locus,allele_id)=(?,?)');
	}
	my $flags;
	eval {
		$flags =
		  $self->{'db'}->selectcol_arrayref( $self->{'sql'}->{'flags'}, undef, $self->{'dbase_id2_value'}, $allele_id );
	};
	if ($@) {
		$logger->error($@) if $@;
		throw BIGSdb::DatabaseConfigurationException('Locus configuration error');
	}
	$self->{'db'}->commit;    #Stop idle in transaction table lock.
	return $flags;
}

sub get_description {
	my ($self) = @_;
	if ( !$self->{'db'} ) {
		$logger->info("No connection to locus $self->{'id'} database");
		return \%;;
	}
	my $sql = $self->{'db'}->prepare('SELECT * FROM locus_descriptions WHERE locus=?');
	eval { $sql->execute( $self->{'id'} ) };
	if ($@) {
		$logger->info("Can't access locus_description table for locus $self->{'id'}") if $@;

		#Not all locus databases have to have a locus_descriptions table.
		return {};
	}
	return $sql->fetchrow_hashref;
}
1;
