package ACH::Builder;

use strict;
use warnings;

use POSIX qw( ceil strftime );
use Carp qw( carp croak );

our $VERSION = '0.10';

=pod

=head1 NAME

ACH::Builder - Tools for building ACH (Automated Clearing House) files

=head1 SYNOPSIS

  use ACH::Builder;

  my $ach = ACH::Builder->new( {
      # Required
      company_id        => '11-111111',
      company_name      => 'MY COMPANY',
      entry_description => 'TV-TELCOM',
      destination       => '123123123',
      destination_name  => 'COMMERCE BANK',
      origination       => '12312311',
      origination_name  => 'MYCOMPANY',

      # Optional
      company_note      => 'BILL',
      effective_date    => '130903',
  } );

  # load some sample records
  my @samples = $ach->sample_detail_records;

  # build file header record
  $ach->make_file_header_record;

  # build batch for web entries
  $ach->set_entry_class_code( 'WEB' );
  $ach->make_batch( \@samples );

  # build batch for telephone entries
  $ach->set_entry_class_code( 'TEL' );
  $ach->make_batch( \@samples );

  # build file control record
  $ach->make_file_control_record;

  print $ach->to_string;

=head1 DESCRIPTION

This module is tool to help construct ACH files, which are fixed-width
formatted files accpected by most banks. ACH (Automated Clearing House)
is an electronic banking network operating system in the United States.
ACH processes large volumes of both credit and debit transactions which
are originated in batches. Rules and regulations governing the ACH network
are established by the National Automated Clearing House Association
(NACHA) and the Federal Reserve (Fed).

ACH credit transfers include direct deposit payroll payments and payments
to contractors and vendors. ACH debit transfers include consumer payments
on insurance premiums, mortgage loans, and other kinds of bills.

=head1 CONFIGURATION

The parameters below can be passed to the constructor C<new> in a hashref.

=head2 company_id

Required. Your 10-digit company number; usually your federal tax ID.

=head2 company_name

Required. Your company name to appear on the receiver's statement; up to 16
characters.

=head2 entry_description

Required per batch. A brief description of the nature of the transactions.
This will appear on the receiver's bank statement. Maximum of 10 characters.

=head2 destination

Required per file. The 9-digit routing number for the destination bank.

=head2 destination_name

Optional per file. A 23-character string identifying the destination bank.

=head2 origination

Required per file. This will usually be the same as the C<company_id>.

=head2 origination_name

Required per file. This will usually be the same as the C<company_name>,
but note that it can be up to 23 characters long.

=head2 company_note

Optional per batch. For your own internal use. Maximum 20 characters.

=head2 effective_date

Optional per batch. Date in C<yymmdd> format that the transactions should be posted.

=head1 DETAIL RECORD FORMAT

The C<make_batch> function expects entry detail records in this format:

 {
   customer_name    => 'JOHN SMITH',   # Maximum of 22 characters
   customer_acct    => '0000-0111111', # Maximum of 15 characters
   amount           => '2501',         # In whole cents; this is $25.01
   routing_number   => '10010101',     # 9 digits
   bank_account     => '103030030',    # Maximum of 17 characters
   transaction_code => '27',
   entry_trace      => 'ABCDE0000000001', # Optional trace number
 }

Only the following transaction codes are supported:

 22 - Deposit to checking account
 27 - Debit from checking account
 32 - Deposit to savings account
 37 - Debit from savings account

Rules for the C<entry_trace> may vary. An example institution requires the
first 8 characters be the destination bank's routing number (excluding the
final checksum digit), and the next 7 characters be a zero-filled number
incrementing sequentially for each record.

=head1 METHODS

=head2 new({ company_id => '...', company_note ... })

See above for configuration details. Note that the configuration parameter
names do not always match the names of the setter methods below.

=cut

sub new {
    my ( $class, $vars ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->{__BATCH_COUNT__}           = 0;
    $self->{__ENTRY_COUNT__}           = 0;
    $self->{__ENTRY_HASH__}            = 0;
    $self->{__FILE_TOTAL_DEBIT__}      = 0;
    $self->{__FILE_TOTAL_CREDIT__}     = 0;
    $self->{__ACH_DATA__}              = [];

    # Collapse given and default values
    $self->set_service_class_code(      $vars->{service_class_code} || 200);
    $self->set_immediate_dest_name(     $vars->{destination_name});
    $self->set_immediate_origin_name(   $vars->{origination_name});
    $self->set_immediate_dest(          $vars->{destination});
    $self->set_immediate_origin(        $vars->{origination});

    $self->set_entry_class_code(        $vars->{entry_class_code} || 'PPD');
    $self->set_entry_description(       $vars->{entry_description});
    $self->set_company_id(              $vars->{company_id});
    $self->set_company_name(            $vars->{company_name});
    $self->set_company_note(            $vars->{company_note});
    $self->set_effective_date(          $vars->{effective_date} || strftime( "%y%m%d", localtime( time + 86400 ) ));

    $self->set_origin_status_code(      $vars->{origin_status_code} || 1);
    $self->set_file_id_modifier(        $vars->{file_id_modifier}   || 'A');
    $self->set_record_size(             $vars->{record_size}        || 94);
    $self->set_blocking_factor(         $vars->{blocking_factor}    || 10);
    $self->set_format_code(             $vars->{format_code}        || 1);

    return( $self );
}

=pod

=head2 make_file_header_record( )

Adds the file header record. This can only be called once and must be
called before any batches are added with C<make_batch>.

=cut

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

=pod

=head2 sample_detail_records( )

Returns a list of sample records ready for C<make_batch>. See above for format details.

=cut

sub sample_detail_records {
    return {
            customer_name       => 'JOHN SMITH',
            customer_acct       => '1234-0123456',
            amount              => '2501',
            routing_number      => '010010101',
            bank_account        => '103030030',
            transaction_code    => '27',
        },
        {
            customer_name       => 'ALICE VERYLONGNAMEGETSTRUNCATED',
            customer_acct       => 'verylongaccountgetstruncated',
            amount              => '2501',
            routing_number      => '010010401',
            bank_account        => '440030030',
            transaction_code    => '32',
        },
    ;
}

=pod

=head2 make_batch( @$records )

Adds a batch of records to the file. You must have called
C<make_file_header_record> before adding a batch to the file.

=cut

sub make_batch {
    my ( $self, $records ) = @_;

    croak "Invalid or empty records for batch" unless ref $records eq 'ARRAY' && @$records;

    ++$self->{__BATCH_COUNT__};

    # reset the batch variables
    $self->{__BATCH_TOTAL_DEBIT__}  = 0;
    $self->{__BATCH_TOTAL_CREDIT__} = 0;
    $self->{__BATCH_ENTRY_COUNT__}  = 0;
    $self->{__BATCH_ENTRY_HASH__}   = 0;

    $self->_make_batch_header_record();

    foreach my $record ( @$records ) {
        croak 'Amount cannot be negative' if $record->{amount} < 0;

        if ($record->{transaction_code} =~ /^(27|37)$/) {
            croak "Debits cannot be used with service_class_code 220" if $self->{__SERVICE_CLASS_CODE__} eq '220';
            $self->{__BATCH_TOTAL_DEBIT__} += $record->{amount};
            $self->{__FILE_TOTAL_DEBIT__} += $record->{amount};
        } elsif ($record->{transaction_code} =~ /^(22|32)$/ ) {
            croak "Credits cannot be used with service_class_code 220" if $self->{__SERVICE_CLASS_CODE__} eq '225';
            $self->{__BATCH_TOTAL_CREDIT__} += $record->{amount};
            $self->{__FILE_TOTAL_CREDIT__} += $record->{amount};
        } else {
            croak "Unsupported transaction_code '$record->{transaction_code}'";
        }

        # modify batch values
        # Hash is calculated without the checksum digit
        $self->{__BATCH_ENTRY_HASH__} += substr $record->{routing_number}, 0, 8;
        ++$self->{__BATCH_ENTRY_COUNT__};

        # modify file values
        $self->{__ENTRY_HASH__} += substr $record->{routing_number}, 0, 8;
        ++$self->{__ENTRY_COUNT__};

        $self->_make_detail_record( $record )
    }

    $self->_make_batch_control_record();
}

# For internal use only. Formats a detail record and adds it to the ACH data.
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
        discretionary_data
        addenda
        entry_trace
    );

    # default values for some fields
    $record->{record_type}          ||= 6;
    $record->{discretionary_data}   ||= '';
    $record->{entry_trace}          ||= '';
    $record->{addenda}              ||= 0;

    # stash detail record
    push( @{ $self->ach_data() },
        fixedlength( $self->format_rules(), $record, \@def )
    );
}

# For internal use only. Starts a batch of detail records.
sub _make_batch_header_record {
    my( $self ) = @_;

    my @def    = qw(
        record_type
        service_class_code
        company_name
        company_note
        company_id
        entry_class_code
        entry_description
        date
        effective_date
        settlement_date
        origin_status_code
        origin_dfi_id
        batch_number
    );

    my $data = {
        record_type         => 5,
        service_class_code  => $self->{__SERVICE_CLASS_CODE__},
        company_name        => $self->{__COMPANY_NAME__},
        company_note        => $self->{__COMPANY_NOTE__},
        company_id          => $self->{__COMPANY_ID__},
        entry_class_code => $self->{__ENTRY_CLASS_CODE__},
        entry_description => $self->{__ENTRY_DESCRIPTION__},
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

# For internal use only. Closes out a batch of detail records.
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
        entry_hash          => $self->{__BATCH_ENTRY_HASH__},
        entry_count         => $self->{__BATCH_ENTRY_COUNT__},
        total_debit_amount  => $self->{__BATCH_TOTAL_DEBIT__},
        total_credit_amount => $self->{__BATCH_TOTAL_CREDIT__},
    };

    # Truncate leftmost digits of entry hash
    $data->{entry_hash} = substr($data->{entry_hash}, length($data->{entry_hash}) - 10, 10) if length($data->{entry_hash}) > 10;

    push( @{ $self->ach_data() },
        fixedlength( $self->format_rules(), $data, \@def )
    );
}

=pod

=head2 make_file_control_record( )

Adds the file control record, finishing the file. This can only be called
once. Afterward, the ACH file can be retrieved in its entirety with C<to_string>.

=cut

sub make_file_control_record {
    my( $self ) = @_;

    croak "Detail records have unbalanced debits ($self->{__FILE_TOTAL_DEBIT__}) and credits ($self->{__FILE_TOTAL_CREDIT__})!"
        unless $self->{__FILE_TOTAL_DEBIT__} eq $self->{__FILE_TOTAL_CREDIT__};

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
        block_count            => ceil(scalar(@{ $self->{__ACH_DATA__} })/$self->{__BLOCKING_FACTOR__}),
        file_entry_count       => $self->{__ENTRY_COUNT__},
        entry_hash             => $self->{__ENTRY_HASH__},
        total_debit_amount     => $self->{__FILE_TOTAL_DEBIT__},
        total_credit_amount    => $self->{__FILE_TOTAL_CREDIT__},
        bank_39                => '',
    };

    # Truncate leftmost digits of entry hash
    $data->{entry_hash} = substr($data->{entry_hash}, length($data->{entry_hash}) - 10, 10) if length($data->{entry_hash}) > 10;

    push( @{ $self->ach_data() },
        fixedlength( $self->format_rules(), $data, \@def )
    );
}

=pod

=head2 format_rules( )

Returns a hash of ACH format rules. Used internally to generate the
fixed-width format required for output.

=cut

sub format_rules {
    my( $self ) = @_;

    return( {
        customer_name       => '%-22.22s',
        customer_acct       => '%-15.15s',
        amount              => '%010.10s',
        discretionary_data  => '%-2.2s',
        entry_trace         => '%-15.15s',
        addenda             => '%01.1s',
        trace_num           => '%-15.15s',
        transaction_code    => '%-2.2s',
        record_type         => '%1.1s',
        bank_account        => '%-17.17s',
        routing_number      => '%09.9s',

        record_type         => '%1.1s',

        priority_code       => '%02.2s',
        immediate_dest      => '%10.10s',
        immediate_origin    => '%10.10s',
        date                => '%-6.6s',
        time                => '%-4.4s',
        file_id_modifier    => '%1.1s',
        record_size         => '%03.3s',
        blocking_factor     => '%02.2s',
        format_code         => '%1.1s',
        immediate_dest_name => '%-23.23s',
        immediate_origin_name => '%-23.23s',
        reference_code        => '%-8.8s',

        service_class_code    => '%-3.3s',
        company_name          => '%-16.16s',
        company_note          => '%-20.20s',
        company_id            => '%-10.10s',
        entry_class_code      => '%-3.3s',
        entry_description     => '%-10.10s',
        effective_date        => '%-6.6s',
        settlement_date       => '%-3.3s',  # for bank
        origin_status_code    => '%-1.1s',  # for bank
        origin_dfi_id         => '%-8.8s',  # for bank
        batch_number          => '%07.7s',

        entry_count           => '%06s',
        entry_hash            => '%010s',
        total_debit_amount    => '%012s',
        total_credit_amount   => '%012s',
        authen_code           => '%-19.19s',
        bank_6                => '%-6.6s',

        batch_count            => '%06s',
        block_count            => '%06s',
        file_entry_count       => '%08s',
        bank_39                => '%-39.39s',
    } );
}

# For internal use only. Formats a record according to format_rules.
sub fixedlength {
    my( $format, $data, $order ) = @_;

    my $fmt_string;
    foreach my $field ( @$order ) {
        croak "Format for the field $field was not defined"
            unless defined $format->{$field};

        carp "data for $field is not defined"
            unless defined $data->{$field};

        $data->{$field} ||= "";

        $fmt_string .= sprintf $format->{$field}, $data->{$field};
    }

    return $fmt_string;
}

=pod

=head2 to_string( )

Returns the built ACH file.

=cut

sub to_string {
    my $self = shift;
    return( join( "\n", @{ $self->{__ACH_DATA__} } ) );
}

=pod

=head2 ach_data( )

Returns as an arrayref the formatted lines that will be turned into the ACH file.

=cut

sub ach_data {
    my ( $self ) = shift;
    $self->{__ACH_DATA__};
}

=pod

=head2 set_origin_status_code( $value )

The code must be either:

 1 - Originator is a financial institution bound by the NACHA rules (the default)
 2 - Originator is a federal agency not bound by the NACHA rules

=cut

sub set_origin_status_code {
    my ( $self, $p ) = @_;
    croak "Invalid origin_status_code" unless $p eq '1' || $p eq '2';
    $self->{__ORIGIN_STATUS_CODE__} = $p;
}

=pod

=head2 set_format_code( $value )

Of limited value. The only valid format code is I<1>, the default.

=cut

sub set_format_code {
    my ( $self, $p ) = @_;
    croak "format_code other than 1 is not supported" unless $p eq '1';
    $self->{__FORMAT_CODE__} = $p;
}

=pod

=head2 set_blocking_factor( $value )

Of limited value. The only valid blocking factor is I<10>, the default.

=cut

sub set_blocking_factor {
    my ( $self, $p ) = @_;
    croak "blocking_factor other than 10 is not supported" unless $p == 10;
    $self->{__BLOCKING_FACTOR__} = $p;
}

=pod

=head2 set_record_size( $value )

Of limited value. The only valid record size (characters per line) is I<94>, the default.

=cut

sub set_record_size {
    my ( $self, $p ) = @_;
    croak "record_size other than 94 is not supported" unless $p == 94;
    $self->{__RECORD_SIZE__} = $p;
}

=pod

=head2 set_file_id_modifier( $value )

A sequential alphanumeric value used to distinguish files submitted on the same day. The default is I<A>.

=cut

sub set_file_id_modifier {
    my ( $self, $p ) = @_;
    check_length($p, 'file_id_modifier');
    $self->{__FILE_ID_MODIFIER__} = $p;
}

=pod

=head2 set_immediate_origin_name( $value )

The same as the C<origination_name> described above. This will usually be
your company name and is limited to 23 characters.

=cut

sub set_immediate_origin_name {
    my ( $self, $p ) = @_;
    check_length($p, 'immediate_origin_name');
    $self->{__IMMEDIATE_ORIGIN_NAME__} = $p;
}

=pod

=head2 set_immediate_origin( $value )

The same as the C<origination> described above. This will usually be your
federal tax ID number, in I<##-#######> format.

=cut

sub set_immediate_origin {
    my ( $self, $p ) = @_;
    check_length($p, 'immediate_origin');
    $self->{__IMMEDIATE_ORIGIN__} = $p;
}

=pod

=head2 set_immediate_dest_name( $value )

The same as the C<destination_name> described above. This identifies the
destination bank that will be processing this file. Limited to 23
characters.

=cut

sub set_immediate_dest_name {
    my ( $self, $p ) = @_;
    check_length($p, 'immediate_dest_name');
    $self->{__IMMEDIATE_DEST_NAME__} = $p;
}

=pod

=head2 set_immediate_dest( $value )

The same as the C<destination> described above. This is the 9-digit routing
number of the destination bank.

=cut

sub set_immediate_dest {
    my ( $self, $p ) = @_;
    check_length($p, 'immediate_dest');
    $self->{__IMMEDIATE_DEST__} = $p;
    $self->{__ORIGINATING_DFI__} = substr $p, 0, 8;
}

=pod

=head2 set_entry_description( $value )

A brief description of the nature of the transactions. This will appear on
the receiver's bank statement. Maximum of 10 characters. This can be set
separately for each batch before C<make_batch> is called.

=cut

sub set_entry_description {
    my ( $self, $p ) = @_;
    check_length($p, 'entry_description');
    $self->{__ENTRY_DESCRIPTION__} = $p;
}

=pod

=head2 set_entry_class_code( $value )

The code must be one of:

 PPD - Prearranged Payments and Deposit entries for consumer items (the default)
 CCD - Cash Concentration and Disbursement entries
 CTX - Corporate Trade Exchange entries for corporate transactions
 TEL - Telephone initiated entries
 WEB - Authorization received via the Internet

=cut

sub set_entry_class_code {
    my ( $self, $p ) = @_;
    check_length($p, 'entry_class_code');
    $self->{__ENTRY_CLASS_CODE__} = $p;
}

=pod

=head2 set_company_id( $value )

Your 10-digit company number; usually your federal tax ID. This can be set
separately for each batch.

=cut

sub set_company_id {
    my ( $self, $p ) = @_;
    check_length($p, 'company_id');
    $self->{__COMPANY_ID__} = $p;
}

=pod

=head2 set_company_name( $value )

Required. Your company name to appear on the receiver's statement; up to 16
characters.

=cut

sub set_company_name {
    my ( $self, $p ) = @_;
    check_length($p, 'company_name');
    $self->{__COMPANY_NAME__} = $p;
}

=pod

=head2 set_company_note( $value )

An optional parameter for your internal use, limited to 20 characters.

=cut

sub set_company_note {
    my ( $self, $p ) = @_;
    check_length($p, 'company_note');
    $self->{__COMPANY_NOTE__} = $p;
}

=pod

=head2 set_effective_date( $value )

The date that transactions in this batch will be posted. The date should be
in I<YYMMDD> format. Defaults to tomorrow.

=cut

sub set_effective_date {
    my ( $self, $p ) = @_;
    croak "Invalid effective_date" unless $p =~ /^\d{6}$/;
    $self->{__EFFECTIVE_DATE__} = $p;
}

=pod

=head2 set_service_class_code( $value )

The code must be one of:

 200 - Mixed credits and debits (the default)
 220 - Credits only
 225 - Debits only

=cut

sub set_service_class_code {
    my ( $self, $p ) = @_;
    croak "Invalid service_class_code" unless $p =~ /^(200|220|225)$/;
    $self->{__SERVICE_CLASS_CODE__} = $p;
}

# For internal use only. Checks that the value for a field fits and warns if not.
sub check_length {
    my ($p, $field) = @_;
    my $rules = format_rules();
    carp "Field '$field' not found in format rules!" and return unless $rules->{$field};
    (my $length = $rules->{$field}) =~ s/^%-?0*(\d+).*/$1/;
    carp "Value '$p' for field $field will be truncated to '".sprintf($rules->{$field}, $p)."'!"
        and return 0 if length $p > $length;
    return 1;
}

=pod

=head1 NOTES

The ACH record format is officially documented in the NACHA I<Operating
Rules & Guidelines> publication, which is not freely available. It can
be purchased at: https://www.nacha.org/achrules

ACH file structure:

 File Header
   Batch Header
     Entries
   Batch Control
   Batch Header
     Entries
   Batch Control
  File Control

=head1 LIMITATIONS

Only certain types of ACH transactions are supported (see the detail
record format above).

=head1 AUTHOR

Tim Keefer <tkeefer@gmail.com>

=head1 CONTRIBUTORS

=over 4

=item *

Cameron Baustian <camerb@cpan.org>

=item *

Steven N. Severinghaus <sns-perl@severinghaus.org>

=back

=head1 COPYRIGHT

Tim Keefer, Cameron Baustian

=cut

1;
