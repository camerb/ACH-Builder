package ACH::Builder;

use strict;
use warnings;

use POSIX qw( strftime );

our $VERSION = '0.09';

#-------------------------------------------------
# new( $file ? )
#-------------------------------------------------
sub new {
	my ( $class, $vars ) = @_;

	my $self = {};
	bless( $self, $class );

	# set default values
    $self->{__BATCH_COUNT__}           = 0;
    $self->{__BLOCK_COUNT__}           = 0;
	$self->{__ENTRY_COUNT__}           = 0;
	$self->{__ENTRY_HASH__}	           = 0;
	$self->{__DEBIT_AMOUNT__}          = 0;
	$self->{__CREDIT_AMOUNT__}         = 0;

    $self->{__BATCH_TOTAL_DEBIT__}     = 0;
    $self->{__BATCH_TOTAL_CREDIT__}    = 0;
    $self->{__BATCH_ENTRY_COUNT__}     = 0;
    $self->{__BATCH_ENTRY_HASH__}      = 0;

	$self->{__SERVICE_CLASS_CODE__}    = $vars->{service_class_code} || 200;
	$self->{__IMMEDIATE_DEST_NAME__}   = $vars->{destination_name};
	$self->{__IMMEDIATE_ORIGIN_NAME__} = $vars->{origination_name};
	$self->{__IMMEDIATE_DEST__}        = $vars->{destination};
	$self->{__IMMEDIATE_ORIGIN__}      = $vars->{origination};
	$self->{__ORIGIN_STATUS_CODE__}    = $vars->{origin_status_code};
	$self->{__ORIGINATING_DFI__}       = $vars->{originating_dfi} || substr $vars->{destination}, 0, 8;

	$self->{__ENTRY_CLASS_CODE__}      = $vars->{entry_class_code} || 'PPD';
	$self->{__ENTRY_DESCRIPTION__}     = $vars->{entry_description};
	$self->{__COMPANY_ID__}            = $vars->{company_id};
	$self->{__COMPANY_NAME__}          = $vars->{company_name};
	$self->{__COMPANY_NOTE__}          = $vars->{company_note};

	$self->{__FILE_ID_MODIFIER__}      = $vars->{file_id_modifier} || 'A';
	$self->{__RECORD_SIZE__}           = $vars->{record_size}      || 94;
	$self->{__BLOCKING_FACTOR__}       = $vars->{blocking_factor}  || 10;
	$self->{__FORMAT_CODE__}           = $vars->{format_code}      || 1;
	$self->{__EFFECTIVE_DATE__}        = $vars->{effective_date}   || strftime( "%y%m%d", localtime( time + 86400 ) );

	$self->{__ACH_DATA__}              = [];

	# populate self with data from site
	return( $self );

} # END new

#-------------------------------------------------
# to_string()
#-------------------------------------------------
sub to_string {
    my $self = shift;
    return( join( "\n", @{ $self->{__ACH_DATA__} } ) );

}

#-------------------------------------------------
# set_format_code() setter
#-------------------------------------------------
sub set_format_code {
    my ( $self, $p ) = @_;
    $self->{__FORMAT_CODE__} = $p;
}

#-------------------------------------------------
# set_blocking_factor() setter
#-------------------------------------------------
sub set_blocking_factor {
    my ( $self, $p ) = @_;
    $self->{__BLOCKING_FACTOR__} = $p;
}

#-------------------------------------------------
# set_record_size() setter
#-------------------------------------------------
sub set_record_size {
    my ( $self, $p ) = @_;
    $self->{__RECORD_SIZE__} = $p;
}

#-------------------------------------------------
# set_file_id_modifier() setter
#-------------------------------------------------
sub set_file_id_modifier {
    my ( $self, $p ) = @_;
    $self->{__FILE_ID_MODIFIER__} = $p;
}

#-------------------------------------------------
# set_immediate_origin_name() setter
#-------------------------------------------------
sub set_immediate_origin_name {
    my ( $self, $p ) = @_;
    $self->{__IMMEDIATE_ORIGIN_NAME__} = $p;
}

#-------------------------------------------------
# set_immediate_origin() setter
#-------------------------------------------------
sub set_immediate_origin {
    my ( $self, $p ) = @_;
    $self->{__IMMEDIATE_ORIGIN__} = $p;
}

#-------------------------------------------------
# set_immediate_dest_name() setter
#-------------------------------------------------
sub set_immediate_dest_name {
    my ( $self, $p ) = @_;
    $self->{__IMMEDIATE_DEST_NAME__} = $p;
}

#-------------------------------------------------
# set_immediate_dest() setter
#-------------------------------------------------
sub set_immediate_dest {
    my ( $self, $p ) = @_;
    $self->{__IMMEDIATE_DEST__} = $p;
}

#-------------------------------------------------
# set_entry_desription() setter
#-------------------------------------------------
sub set_entry_description {
    my ( $self, $p ) = @_;
    $self->{__ENTRY_DESCRIPTION__} = $p;
}

#-------------------------------------------------
# set_entry_class_code() setter
#-------------------------------------------------
sub set_entry_class_code {
    my ( $self, $p ) = @_;
    $self->{__ENTRY_CLASS_CODE__} = $p;
}

#-------------------------------------------------
# set_company_id() setter
#-------------------------------------------------
sub set_company_id {
    my ( $self, $p ) = @_;
    $self->{__COMPANY_ID__} = $p;
}

#-------------------------------------------------
# set_company_note() setter
#-------------------------------------------------
sub set_company_note {
    my ( $self, $p ) = @_;
    $self->{__COMPANY_NOTE__} = $p;
}

#-------------------------------------------------
# set_service_class_code() setter
#-------------------------------------------------
sub set_service_class_code {
    my ( $self, $p ) = @_;
    $self->{__SERVICE_CLASS_CODE__} = $p;
}

#-------------------------------------------------
# ach_data() accessor
#-------------------------------------------------
sub ach_data {
    my ( $self ) = shift;
    $self->{__ACH_DATA__};
}

#-------------------------------------------------
# make_batch( @$records )
#-------------------------------------------------
sub make_batch {
    my( $self, $records ) = @_;

    return if scalar( @{ $records } ) <= 0;

    # bump the batch count
    ++$self->{__BATCH_COUNT__};

    # inititalize the batch variables
    $self->{__BATCH_TOTAL_DEBIT__}  = 0;
    $self->{__BATCH_TOTAL_CREDIT__} = 0;
    $self->{__BATCH_ENTRY_COUNT__}  = 0;
    $self->{__BATCH_ENTRY_HASH__}   = 0;

    # get batch header
    $self->_make_batch_header_record();

    # loop over the detail records
    foreach my $record ( @{ $records } ) {

        die 'amount cannot be negative' if $record->{amount} < 0;

        if ($record->{transaction_code} =~ /^(27|37)$/) {
           #if it is a debit
           $self->{__BATCH_TOTAL_DEBIT__} += $record->{amount};
           $self->{__DEBIT_AMOUNT__} += $record->{amount};
           $self->{__TOTAL_DEBIT__} += $record->{amount};

        } elsif ($record->{transaction_code} =~ /^(22|32)$/ ) {
           #if it is a credit
           $self->{__BATCH_TOTAL_CREDIT__} += $record->{amount};
           $self->{__CREDIT_AMOUNT__} += $record->{amount};
           $self->{__TOTAL_CREDIT__} += $record->{amount};
        } else {
           die 'unsupported transaction_code';
        }

        # modify batch values
        $self->{__BATCH_ENTRY_HASH__}  += $record->{routing_number};
        ++$self->{__BATCH_ENTRY_COUNT__};

        # modify file values
        $self->{__ENTRY_HASH__}  += $record->{routing_number};
        ++$self->{__ENTRY_COUNT__};

        # get detail record
        $self->_make_detail_record( $record )
    }

    # get batch control record
    $self->_make_batch_control_record();

}

#-------------------------------------------------
# make_file_control_record(  )
#-------------------------------------------------
sub make_file_control_record {
    my( $self ) = @_;

    my @def = qw(
       record_type
       batch_count
       block_count
       file_entry_count
       entry_hash
       total_debit_amount
       total_credit_amount
       bank_39
    );

    my $data = {
        record_type            => 9,
        batch_count            => $self->{__BATCH_COUNT__},
        block_count            => $self->{__BLOCK_COUNT__},
        file_entry_count       => $self->{__ENTRY_COUNT__},
        entry_hash             => $self->{__ENTRY_HASH__},
        total_debit_amount     => $self->{__DEBIT_AMOUNT__},
        total_credit_amount    => $self->{__CREDIT_AMOUNT__},
        bank_39                => '',
    };

    # stash line
    push( @{ $self->ach_data() },
        fixedlength( $self->format_rules(), $data, \@def )
    );
}

#-------------------------------------------------
# make_file_header_record()
#-------------------------------------------------
sub make_file_header_record {
    my( $self ) = @_;

    # ach file header definition
    my @def = qw(
        record_type
        priority_code
        immediate_dest
        immediate_origin
        date
        time
        file_id_modifier
        record_size
        blocking_factor
        format_code
        immediate_dest_name
        immediate_origin_name
        reference_code
    );

    my $data = {
        record_type         => 1,
        priority_code       => 1,
        immediate_dest      => $self->{__IMMEDIATE_DEST__},
        immediate_origin    => $self->{__IMMEDIATE_ORIGIN__},
        date                => strftime( "%y%m%d", localtime(time) ),
        time                => strftime( "%H%M", localtime(time) ),
        file_id_modifier    => $self->{__FILE_ID_MODIFIER__},
        record_size         => $self->{__RECORD_SIZE__},
        blocking_factor     => $self->{__BLOCKING_FACTOR__},
        format_code         => $self->{__FORMAT_CODE__},
        immediate_dest_name   => $self->{__IMMEDIATE_DEST_NAME__},
        immediate_origin_name => $self->{__IMMEDIATE_ORIGIN_NAME__},
        reference_code        => '',
    };

    push( @{ $self->ach_data() },
        fixedlength( $self->format_rules, $data,  \@def  )
    );
}

#-------------------------------------------------
# sample_detail_records()
#-------------------------------------------------
sub sample_detail_records {
    my( $self ) = shift;

    my @records;

    push( @records, {
        customer_name       => 'JOHN SMITH',
        customer_acct       => sprintf( "%010d", '6124' )
            . sprintf( "%08d", '2882282' ),
        amount              => '2501',
        routing_number      => '010010101',
        bank_account        => '103030030',
    } );

    push( @records, {
        customer_name       => 'JOHN SMITHSTIMTIMSTIMSIMSIMS',
        customer_acct       => sprintf( "%010d", '4124' )
                . sprintf( "%08d", '4882282' ),
        amount              => '40801',
        routing_number      => '010010401',
        bank_account        => '440030030',
    } );

    return @records;
}

#-------------------------------------------------
# format_rules()
#-------------------------------------------------
sub format_rules {
    my( $self ) = @_;

    return( {
        customer_name       => '22L',
        customer_acct       => '15L',
        amount              => '10R*D',
        bank_2              => '2L',
        transaction_type    => '2L',
        bank_15             => '15L',
        addenda             => '1L',
        trace_num           => '15L',
        transaction_code    => '2L',
        record_type         => '1L',
        bank_account        => '17L',
        routing_number      => '9R*D',

        record_type         => '1L',

        priority_code       => '2R*D',
        immediate_dest      => '10R',
        immediate_origin    => '10R',
        date                => '6L',
        time                => '4L',
        file_id_modifier    => '1L',
        record_size         => '3R*D',
        blocking_factor     => '2R*D',
        format_code         => '1L',
        immediate_dest_name => '23L',
        immediate_origin_name => '23L',
        reference_code        => '8L',

        service_class_code    => '3L',
        company_name          => '16L',
        company_note_data     => '20L',
        company_id            => '10L',
        standard_entry_class_code => '3L',
        company_entry_descr   => '10L',
        effective_date        => '6L',
        settlement_date       => '3L',  # for bank
        origin_status_code    => '1L',  # for bank
        origin_dfi_id         => '8L',  # for bank
        batch_number          => '7R*D',

        entry_count           => '6R*D',
        entry_hash            => '10R*D',
        total_debit_amount    => '12R*D',
        total_credit_amount   => '12R*D',
        authen_code           => '19L',
        bank_6                => '6L',

        batch_count            => '6R*D',
        block_count            => '6R*D',
        file_entry_count       => '8R*D',
        bank_39                => '39L',
    } );
}

#-------------------------------------------------
# _make_batch_control_record(  )
#-------------------------------------------------
sub _make_batch_control_record {
    my( $self ) = @_;

    my @def = qw(
        record_type
        service_class_code
        entry_count
        entry_hash
        total_debit_amount
        total_credit_amount
        company_id
        authen_code
        bank_6
        origin_dfi_id
        batch_number
    );

    my $data = {
        record_type         => 8,
        service_class_code  => $self->{__SERVICE_CLASS_CODE__},
        company_id          => $self->{__COMPANY_ID__},
        origin_dfi_id       => $self->{__ORIGINATING_DFI__},
        batch_number        => $self->{__BATCH_COUNT__},
        authen_code         => '',
        bank_6              => '',
        entry_hash          => substr( $self->{__BATCH_ENTRY_HASH__}, 0, 9 ),
        entry_count         => $self->{__BATCH_ENTRY_COUNT__},
        total_debit_amount  => $self->{__BATCH_TOTAL_DEBIT__},
        total_credit_amount => $self->{__BATCH_TOTAL_CREDIT__},
    };

    push( @{ $self->ach_data() },
        fixedlength( $self->format_rules(), $data, \@def )
    );
}

#-------------------------------------------------
# _make_detail_record(  )
#-------------------------------------------------
sub _make_detail_record {
    my( $self, $record ) = @_;

    my @def = qw(
        record_type
        transaction_code
        routing_number
        bank_account
        amount
        customer_acct
        customer_name
        transaction_type
        addenda
        bank_15
    );

    # add to record unless already defined
    $record->{record_type}      ||= 6;
    $record->{transaction_code} ||= 27;
    $record->{transaction_type} ||= 'S';
    $record->{bank_15}          ||= '';
    $record->{addenda}          ||= 0;

    # stash detail record
    push( @{ $self->ach_data() },
        fixedlength( $self->format_rules(), $record, \@def )
    );
}

#-------------------------------------------------
# _make_batch_header_record(  )
#-------------------------------------------------
sub _make_batch_header_record {
    my( $self ) = @_;

    my @def    = qw(
        record_type
        service_class_code
        company_name
        company_note_data
        company_id
        standard_entry_class_code
        company_entry_descr
        date
        effective_date
        settlement_date
        origin_status_code
        origin_dfi_id
        batch_number
    );

    my $data = {
        record_type         => 5,
        service_class_code  => 200,
        company_name        => $self->{__COMPANY_NAME__},
        company_note_data   => $self->{__COMPANY_NOTE__},
        company_id          => $self->{__COMPANY_ID__},
        standard_entry_class_code => $self->{__ENTRY_CLASS_CODE__},
        company_entry_descr => $self->{__ENTRY_DESCRIPTION__},
        date                => strftime( "%y%m%d", localtime(time) ),
        effective_date      => $self->{__EFFECTIVE_DATE__},
        settlement_date     => '',
        origin_status_code  => $self->{__ORIGIN_STATUS_CODE__},
        origin_dfi_id       => $self->{__ORIGINATING_DFI__},
        batch_number        => $self->{__BATCH_COUNT__},
        authen_code         => '',
        bank_6              => '',
    };

    push( @{ $self->ach_data() },
        fixedlength( $self->format_rules(), $data, \@def )
    );
}

#-------------------------------------------------
# _is_credit(  )
#-------------------------------------------------
#sub _is_credit {
    #my( $self ) = @_;
    #return true/false
#}

sub fixedlength {
    my( $format, $data, $order ) = @_;

    my $int_re = '([*])?(D)';
    my $flt_re = '([*])?(F)(\d+)?';
    my $numfmt_re = "($int_re|$flt_re)";
    my $format_re =<<RE;
        (\\d+)       # width
        (R|L)?       # optional justification
        (            # optional numerical formatting
         $numfmt_re
        )?
RE

    my $debug=0;
    my $fmt_string;

    foreach my $field ( @{ $order } ) {

        if ( ! defined $format->{$field} ) {
            die( "Format for the field $field was not defined\n" );
        }

        if ( ! defined $data->{$field} ) {
            warn( "data for $field is not defined" );
            $data->{$field} = "";
        }

        if ( $format->{$field} =~ /$format_re/x ) {
            my $width = $1;

            my $just  = $2 || 'L';
            $just = $just eq 'L' ? '-' : '';

            my $text  = ( $3 || '' );

            if ( $text =~ /$int_re/i or $text =~ /$flt_re/ ) {
                my $zero_fill = $1 ? '0' : '';
                my $d_or_f    = lc $2;

                warn "d_of_f: $d_or_f" if $debug;
                $d_or_f = ".$3$d_or_f" if ($d_or_f eq 'f');

                my $fmt = "%${just}${zero_fill}${width}${d_or_f}";

                warn "num sprintf :$fmt" if $debug;

                my $dta = $data->{$field};

                # crop text
                if ( length($dta) > $width ) {
                    $dta = substr( $dta, 0, $width );
                }

                $fmt_string .= sprintf( $fmt, $dta );
            }
            else {
                my $fmt = "%${just}${width}s";
                warn "str sprintf: $fmt" if $debug;

                my $dta = $data->{$field};

                # crop text
                if ( length($dta) > $width ) {
                    $dta = substr( $dta, 0, $width );
                }

                $fmt_string .= sprintf( $fmt, $dta );
            }

        } # end if match format

    } # end foreach fields

    return $fmt_string;
}
# EOF
1;

__END__

=head1 NAME

ACH::Builder - Tools for Building ACH (Automated Clearing House) Files

=head1 SYNOPSIS

  use ACH::Builder;

  my $ach = ACH::Builder->new( {

      # (required) Company Identification, Fed Tax ID
      company_id        => '11-111111',

      # (required) This will appear on the receiver's bank statement
      company_name      => 'MY COMPANY',

      # (required) a brief description of the nature of the
      # payments this will apper on the receiver's bank statement
      entry_description => 'TV-TELCOM',

      # (required)
      destination       => '123123123',
      destination_name  => 'COMMERCE BANK',

      # (required)
      origination            => '12312311',
      origination_name       => 'MYCOMPANY',

      # (optional)
      company_note      => 'BILL',

      # (optional)
      effective_date    => 'yymmdd',

  } );

  # I've included some sample detail records
  my @samples = $ach->sample_detail_records();

  # build file header record
  $ach->make_file_header_record();

  # build batch for web entries
  $ach->set_entry_class_code( 'WEB' );
  $ach->make_batch( \@samples );

  # build batch for telephone entries
  $ach->set_entry_class_code( 'TEL' );
  $ach->make_batch( \@samples );

  # build file control record
  $ach->make_file_control_record();

  print $ach->to_string;

=head1 DESCRIPTION

ACH File Structure

This module is tool to help construct ACH files, which are fixed width
formatted files accpected by most banks. ACH (Automated Clearing House)
is an electronic banking network operating system in the United States.
ACH processes large volumes of both credit and debit transactions which
are originated in batches. Rules and regulations governing the ACH network
are established by the National Automated Clearing House Association
(NACHA) and the Federal Reserve (Fed).

ACH credit transfers include direct deposit payroll payments and payments
to contractors and vendors. ACH debit transfers include consumer payments
on insurance premiums, mortgage loans, and other kinds of bills.

=head1 DETAIL RECORD FORMAT

Detail Record Format

=over 4

 { customer_name    => 'JOHN SMITH',
   customer_acct    => '0000-0111111',
   amount           => '2501',
   routing_number   => '010010101'
   bank_account     => '103030030' }

=back

=head1 METHODS

=over 4

=item new (constructor)

params: Hash Ref { company_id => '...', company_note ... }

** set methods are also provided for these parameters

=over 4

 service_class_code
 destination_name
 origination_name
 destination
 origination
 entry_class_code
 entry_description
 company_id
 company_name
 company_note
 file_id_modifier
 record_size
 blocking_factor
 format_code

=back

=item make_file_header_record

Called to create the File Header record. This should be called before
"make_batch".

=item make_file_control_record

Called to create the File Control Record. This should be called after
"make_batch".

=item make_batch

params: AoH Records

Called the create and stash a batch of ACH entries. This method requires
an AoH records. See "sample_detail_records" from record specifications.

=item format_rules

Hash of ACH format rules.

=item sample_detail_records

AoH of sample detail records

Detail Record Format

=over 4

 { customer_name    => 'JOHN SMITH',
   customer_acct    => '0000-0111111',
   amount           => '2501',
   routing_number   => '010010101'
   bank_account     => '103030030' }

=back

=item to_string

returns the built ACH file

=back

=head1 METHOD Setters

=over 4

=item set_service_class_code

=item set_destination_name

=item set_destination

=item set_origination_name

=item set_origination

=item set_entry_class_code

=item set_entry_description

=item set_company_id

=item set_company_name

=item set_company_note

=item set_file_id_modifier

=item set_record_size

=item set_format_code

=back

=head1 NOTES

ACH File structure.

 File Header
   Batch Header
     Entries
   Batch Control
   Batch Header
     Entries
   Batch Control
  File Control

=head1 LIMITATIONS

Only supports the ACH format.

=head1 AUTHOR

Tim Keefer <tkeefer@gmail.com>

=head1 CONTRIBUTOR

Cameron Baustian <camerb@cpan.org>

=head1 COPYRIGHT

Tim Keefer
Cameron Baustian

=cut
