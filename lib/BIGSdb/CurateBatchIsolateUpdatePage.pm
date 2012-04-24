#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
package BIGSdb::CurateBatchIsolateUpdatePage;
use strict;
use warnings;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Batch isolate update</h1>\n";
	if ( !$self->can_modify_table('isolates') || !$self->can_modify_table('allele_designations') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update "
		  . "either isolate records or allele designations.</p></div>\n";
		return;
	}
	if ( $q->param('update') ) {
		$self->_update;
	} elsif ( $q->param('data') ) {
		$self->_check;
	} else {
		print <<"HTML";
<div class="box" id="queryform">
<p>This page allows you to batch update provenance fields or allele designations for multiple isolates.</p>
<ul><li>  The first line, containing column headings, will be ignored.</li>
<li> The first column should be the isolate id (or unique field that you are selecting isolates on).  If a 
secondary selection field is used (so that together the combination of primary and secondary fields are unique), 
this should be entered in the second column.</li>
<li>The next column should contain the field/locus name and then the 
final column should contain the value to be entered, e.g.<br />
<pre style="font-size:1.2em">
id	field	value
2	country	USA
2	abcZ	5
</pre>
</li>
<li> The columns should be separated by tabs. Any other columns will be ignored.</li>
<li> If you wish to blank a field, enter '&lt;blank&gt;' as the value.</li>
<li>The script is compatible with STARS output files.</li></ul>
<p>Please enter the field(s) that you are selecting isolates on.  Values used must be unique within this field or 
combination of fields, i.e. only one isolate has the value(s) used.  Usually the database id will be used.</p>
HTML
		my $fields = $self->{'xmlHandler'}->get_field_list;
		print $q->start_form;
		print $q->hidden($_) foreach qw (db page);
		print "<fieldset><legend>Options</legend>\n";
		print "<ul><li><label for=\"idfield1\" class=\"filter\">Primary selection field: </label>";
		print $q->popup_menu( -name => 'idfield1', -id => 'idfield1', -values => $fields );
		print "</li><li><label for=\"idfield2\" class=\"filter\">Optional selection field: </label>\n";
		unshift @$fields, '<none>';
		print $q->popup_menu( -name => 'idfield2', -id => 'idfield2', -values => $fields );
		print "</li><li>";
		print $q->checkbox( -name => 'overwrite', -label => 'Overwrite existing data', -checked => 0 );
		print "</li></ul></fieldset>\n";
		print "<p>Please paste in your data below:</p>\n";
		print $q->textarea( -name => 'data', -rows => 15, -columns => 40, -override => 1 );
		print "<span style=\"float:left\">\n";
		print $q->reset( -class => 'reset' );
		print "</span>\n<span style=\"float:right;padding-right:2em\">\n";
		print $q->submit( -label => 'Submit', -class => 'submit' );
		print "</span>\n";
		print $q->endform;
		print "<div style=\"clear:both;padding-top:1em\"><p><a href=\"$self->{'system'}->{'script_name'}"
		  . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
		print "</div>\n";
	}
	return;
}

sub _check {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $data   = $q->param('data');
	my @rows = split /\n/, $data;
	if ( @rows < 2 ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Nothing entered.  Make sure you include a header line.</p>\n";
		print "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchIsolateUpdate\">Back</a></p></div>\n";
		return;
	}
	my $buffer   = "<div class=\"box\" id=\"resultstable\">\n";
	my $idfield1 = $q->param('idfield1');
	my $idfield2 = $q->param('idfield2');
	$buffer .= "<p>The following changes will be made to the database.  Please check that this is what you intend and "
	  . "then press 'Submit'.  If you do not wish to make these changes, press your browser's back button.</p>\n";
	my $extraheader = $idfield2 ne '<none>' ? "<th>$idfield2</th>" : '';
	$buffer .= "<table class=\"resultstable\"><tr><th>Transaction</th><th>$idfield1</th>$extraheader<th>Field</th>"
	  . "<th>New value</th><th>Value currently in database</th><th>Action</th></tr>\n";
	my $i = 0;
	my ( @id, @id2, @field, @value, @update );
	my $td  = 1;
	my $qry = "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE $idfield1=?";
	$qry .= " AND $idfield2=?" if $idfield2 ne '<none>';
	my $sql = $self->{'db'}->prepare($qry);
	$qry =~ s/COUNT\(\*\)/id/;
	my $sql_id = $self->{'db'}->prepare($qry);

	foreach my $row (@rows) {
		if ( $idfield2 eq '<none>' ) {
			( $id[$i], $field[$i], $value[$i] ) = split /\t/, $row;
		} else {
			( $id[$i], $id2[$i], $field[$i], $value[$i] ) = split /\t/, $row;
		}
		$id[$i] =~ s/%20/ /g;
		$id2[$i] ||= '';
		$id2[$i] =~ s/%20/ /g;
		$value[$i] =~ s/\s*$//g if defined $value[$i];
		my $displayvalue = $value[$i];
		my $badField     = 0;
		my $is_locus     = $self->{'datastore'}->is_locus( $field[$i] );

		if ( !( $self->{'xmlHandler'}->is_field( $field[$i] ) || $is_locus ) ) {
			$badField = 1;
		}
		$update[$i] = 0;
		my ( $oldvalue, $action );
		if ( $i && defined $value[$i] && $value[$i] ne '' ) {
			if ( !$badField ) {
				my $count;
				my @args;
				push @args, $id[$i];
				push @args, $id2[$i] if $idfield2 ne '<none>';

				#check if allowed to edit
				my $error;
				eval { $sql_id->execute(@args) };
				if ($@) {
					if ( $@ =~ /integer/ ) {
						print "<div class=\"box\" id=\"statusbad\"><p>Your id field(s) contain text characters but the "
						  . "field can only contain integers.</p></div>\n";
						$logger->debug($@);
						return;
					}
				}
				my @not_allowed;
				while ( my ($id) = $sql_id->fetchrow_array ) {
					if ( !$self->is_allowed_to_view_isolate($id) ) {
						push @not_allowed, $id;
					}
				}
				if (@not_allowed) {
					local $" = ', ';
					print "<div class=\"box\" id=\"statusbad\"><p>You are not allowed to edit the following isolate "
					  . "records: @not_allowed.</p></div>\n";
					return;
				}

				#Check if id exists
				eval {
					$sql->execute(@args);
					($count) = $sql->fetchrow_array;
				};
				if ( $@ || $count == 0 ) {
					$oldvalue = "<span class=\"statusbad\">no editable record with $idfield1='$id[$i]'";
					$oldvalue .= " and $idfield2='$id2[$i]'"
					  if $idfield2 ne '<none>';
					$oldvalue .= "</span>";
					$action = "<span class=\"statusbad\">no action</span>";
				} elsif ( $count > 1 ) {
					$oldvalue = "<span class=\"statusbad\">duplicate records with $idfield1='$id[$i]'</span>";
					$action   = "<span class=\"statusbad\">no action</span>";
				} else {
					my $qry;
					my @args;
					if ($is_locus) {
						$qry = "SELECT allele_id FROM allele_designations LEFT JOIN $self->{'system'}->{'view'} ON "
						  . "$self->{'system'}->{'view'}.id=isolate_id WHERE locus=? AND $idfield1=?";
						push @args, $field[$i];
					} else {
						$qry = "SELECT $field[$i] FROM $self->{'system'}->{'view'} WHERE $idfield1=?";
					}
					$qry .= " AND $idfield2=?" if $idfield2 ne '<none>';
					my $sql2 = $self->{'db'}->prepare($qry);
					push @args, $id[$i];
					push @args, $id2[$i] if $idfield2 ne '<none>';
					eval { $sql2->execute(@args) };
					$logger->error($@) if $@;
					$oldvalue = $sql2->fetchrow_array;

					if (   !defined $oldvalue
						|| $oldvalue eq ''
						|| $q->param('overwrite') )
					{
						$oldvalue = "-"
						  if !defined $oldvalue || $oldvalue eq '';
						my $problem = $self->is_field_bad( $self->{'system'}->{'view'}, $field[$i], $value[$i], 'update' );
						if ($is_locus) {
							my $locus_info = $self->{'datastore'}->get_locus_info( $field[$i] );
							if ( $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int( $value[$i] ) ) {
								$problem = "invalid allele id (must be an integer)";
							}
						}
						if ($problem) {
							$action = "<span class=\"statusbad\">no action - $problem</span>";
						} else {
							if ( $value[$i] eq $oldvalue ) {
								$action = "<span class=\"statusbad\">no action - new value unchanged</span>";
								$update[$i] = 0;
							} else {
								$action = "<span class=\"statusgood\">update field with new value</span>";
								$update[$i] = 1;
							}
						}
					} else {
						$action = "<span class=\"statusbad\">no action - value already in db</span>";
					}
				}
			} else {
				$oldvalue = "<span class=\"statusbad\">field not recognised</span>";
				$action   = "<span class=\"statusbad\">no action</span>";
			}
			$displayvalue =~ s/<blank>/&lt;blank&gt;/;
			if ( $idfield2 ne '<none>' ) {
				$buffer .= "<tr class=\"td$td\"><td>$i</td><td>$id[$i]</td><td>$id2[$i]</td><td>$field[$i]</td>"
				  . "<td>$displayvalue</td><td>$oldvalue</td><td>$action</td></tr>\n";
			} else {
				$buffer .= "<tr class=\"td$td\"><td>$i</td><td>$id[$i]</td><td>$field[$i]</td><td>$displayvalue</td>"
				  . "<td>$oldvalue</td><td>$action</td></tr>\n";
			}
			$td = $td == 1 ? 2 : 1;
		}
		$value[$i] =~ s/<blank>// if defined $value[$i];
		$i++;
	}
	print $buffer;
	print "</table>";
	print "<p />\n";
	print $q->start_form;
	$q->param( 'idfield1',  $idfield1 );
	$q->param( 'idfield2',  $idfield2 );
	$q->param( 'id',        @id );
	$q->param( 'id2',       @id2 );
	$q->param( 'updaterec', @update );
	$q->param( 'field',     @field );
	$q->param( 'value',     @value );
	$q->param( 'update',    1 );
	print $q->hidden($_) foreach qw (db page idfield1 idfield2 id id2 updaterec field value update);
	print $q->submit( -label => 'Submit', -class => 'submit' );
	print $q->endform;
	print "<p /><p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p>\n";
	print "</div>\n";
	return;
}

sub _update {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my @id       = $q->param("id");
	my @id2      = $q->param("id2");
	my $idfield1 = $q->param('idfield1');
	my $idfield2 = $q->param('idfield2');
	my @update   = $q->param("updaterec");
	my @field    = $q->param("field");
	my @value    = $q->param("value");
	print "<div class=\"box\" id=\"resultsheader\">\n";
	print "<h2>Updating database ...</h2>";
	my $nochange     = 1;
	my $curator_id   = $self->get_curator_id;
	my $curator_name = $self->get_curator_name;
	print "User: $curator_name<br />\n";
	my $datestamp = $self->get_datestamp;
	print "Datestamp: $datestamp<br />\n";
	my $tablebuffer;
	my $td = 1;

	for my $i ( 0 .. @update - 1 ) {
		my ( $isolate_id, $old_value );
		if ( $update[$i] ) {
			$nochange = 0;
			my ( $qry, $qry2 );
			my $is_locus = $self->{'datastore'}->is_locus( $field[$i] );
			my ( @args, @args2 );
			if ($is_locus) {
				my @id_args;
				my $id_qry = "SELECT id FROM $self->{'system'}->{'view'} WHERE id IN (SELECT id FROM "
				  . "$self->{'system'}->{'view'}) AND $idfield1=?";
				push @id_args, $id[$i];
				if ( $idfield2 ne '<none>' ) {
					$id_qry .= " AND $idfield2=?";
					push @id_args, $id2[$i];
				}
				my $sql_id = $self->{'db'}->prepare($id_qry);
				eval { $sql_id->execute(@id_args) };
				$logger->error($@) if $@;
				($isolate_id) = $sql_id->fetchrow_array;

				#if existing designation set, demote it to pending
				my $existing_ref = $self->{'datastore'}->get_allele_designation( $isolate_id, $field[$i] );
				if ( ref $existing_ref eq 'HASH' ) {
					$old_value = $existing_ref->{'allele_id'};

					#make sure existing pending designation with same allele_id, sender and method doesn't exit
					my $pending_designations = $self->{'datastore'}->get_pending_allele_designations( $isolate_id, $field[$i] );
					my $exists;
					foreach (@$pending_designations) {
						if (   $_->{'allele_id'} eq $existing_ref->{'allele_id'}
							&& $_->{'sender'} eq $existing_ref->{'sender'}
							&& $_->{'method'} eq 'manual' )
						{
							$exists = 1;
						}
					}
					if ( !$exists ) {
						my $pending_sql =
						  $self->{'db'}->prepare( "INSERT INTO pending_allele_designations (isolate_id,locus,allele_id,"
							  . "sender,method,curator,date_entered,datestamp,comments) VALUES (?,?,?,?,?,?,?,?,?)" );
						eval {
							$pending_sql->execute(
								$isolate_id,                     $field[$i],                   $existing_ref->{'allele_id'},
								$existing_ref->{'sender'},       'manual',                     $existing_ref->{'curator'},
								$existing_ref->{'date_entered'}, $existing_ref->{'datestamp'}, $existing_ref->{'comments'}
							);
						};
						$logger->error($@) if $@;
					}
					my $delete_sql = $self->{'db'}->prepare("DELETE FROM allele_designations WHERE isolate_id=? and locus=?");
					eval { $delete_sql->execute( $isolate_id, $field[$i] ) };
					$logger->error($@) if $@;
				}
				my $isolate_ref =
				  $self->{'datastore'}->run_simple_query( "SELECT sender FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id );
				$qry = "INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,date_entered,datestamp) "
				  . "VALUES (?,?,?,?,?,?,?,?,?)";
				push @args, ( $isolate_id, $field[$i], $value[$i], $isolate_ref->[0], 'confirmed', 'manual', $curator_id, 'now', 'now' );

				#delete from pending if it matches the new designation
				$qry2 .=
				  ";DELETE FROM pending_allele_designations WHERE isolate_id=? AND locus=? AND " . "allele_id=? AND sender=? AND method=?";
				push @args2, ( $isolate_id, $field[$i], $value[$i], $isolate_ref->[0], 'manual' );
			} else {
				if ( $value[$i] eq '' ) {
					$qry = "UPDATE isolates SET $field[$i]=null,datestamp=?,curator=? WHERE id IN (SELECT id FROM "
					  . "$self->{'system'}->{'view'}) AND $idfield1=?";
					push @args, ( 'now', $curator_id, $id[$i] );
				} else {
					$qry = "UPDATE isolates SET $field[$i]=?,datestamp=?,curator=? WHERE id IN "
					  . "(SELECT id FROM $self->{'system'}->{'view'}) AND $idfield1=?";
					push @args, ( $value[$i], 'now', $curator_id, $id[$i] );
				}
				my @id_args = ( $id[$i] );
				if ( $idfield2 ne '<none>' ) {
					$qry .= " AND $idfield2=?";
					push @args,    $id2[$i];
					push @id_args, $id2[$i];
				}
				my $id_qry = $qry;
				$id_qry =~ s/UPDATE isolates .* WHERE/SELECT id,$field[$i] FROM isolates WHERE/;
				my $sql_id = $self->{'db'}->prepare($id_qry);
				eval { $sql_id->execute(@id_args) };
				$logger->error($@) if $@;
				( $isolate_id, $old_value ) = $sql_id->fetchrow_array;
			}
			$tablebuffer .= "<tr class=\"td$td\"><td>$idfield1='$id[$i]'";
			$tablebuffer .= " AND $idfield2='$id2[$i]'"
			  if $idfield2 ne '<none>';
			$tablebuffer .= "</td><td>$field[$i]</td><td>$value[$i]</td>";
			my $update_sql = $self->{'db'}->prepare($qry);
			eval {
				$update_sql->execute(@args);
				if ($qry2) {
					my $delete_sql = $self->{'db'}->prepare($qry2);
					$delete_sql->execute(@args2);
				}
			};
			if ($@) {
				$logger->error($@);
				$tablebuffer .= "<td class=\"statusbad\">can't update!</td></tr>\n";
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				$tablebuffer .= "<td class=\"statusgood\">done!</td></tr>\n";
				$old_value ||= '';
				$self->update_history( $isolate_id, "$field[$i]: '$old_value' -> '$value[$i]'" );
			}
			$td = $td == 1 ? 2 : 1;
		}
	}
	if ($nochange) {
		print "<p>No changes to be made.</p>\n";
	} else {
		print "<p /><table class=\"resultstable\"><tr><th>Condition</th><th>Field</th><th>New value</th>"
		  . "<th>Status</th></tr>$tablebuffer</table>\n";
	}
	print "<p /><p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p>\n";
	print "</div>\n";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch Isolate Update - $desc";
}
1;
