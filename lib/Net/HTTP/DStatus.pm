# low-level HTTP client, with deferrable status code support

package Net::HTTP::DStatus;
use base Net::HTTP;

use Class::InsideOut qw(id private);
use Contextual::Return;
use Data::Dumper;

my $defer_code = "208";
my $trailing_status_header = 'X-Deferred-Status';

private scode_deferred => my %scode_deferred;
private scode => my %scode;
private smess => my %smess;

sub read_response_headers {
    my ($self, %opts) = @_;
    my $id = id $self;

    my ($initial_code, $mess, @headers) = 
        $self->SUPER::read_response_headers(%opts);

    if( $initial_code eq $defer_code ) {
        $scode_deferred{$id} = 1;
        return undef, undef, @headers;
    }

    $scode{$id} = $initial_code;
    $smess{$id} = $mess;
    return $initial_code, $mess, @headers;
}

sub get_trailers {
    my ($self) = @_;
    my $id = id $self;

    my @trl = $self->SUPER::get_trailers;
    @trl % 2 == 0 or die "odd number of trailers in @trl";

    if( exists $scode_deferred{$id} ) {
        my $seen;
        for (my $i = 0; $i < $#trl; $i += 2) {
           if($trl[$i] eq $trailing_status_header) {
               $seen++;

               ( $scode{$id}, $smess{$id} )
                   = Net::HTTP::DStatus::_status_line($trl[$i+1]);
           }
        }

        if( ! $seen ) {
            die "no trailing status";
        }
    }
    return @trl;
}

# undef means not yet known
sub get_status_code {
    my ($self) = @_;
    my $id = id $self;

    if( exists $scode{$id} ) {
        return(
            LIST    { return $scode{$id}, $smess{$id} }
            DEFAULT { return $scode{$id}              }
        );
    }
    elsif( exists $scode_deferred{$id} ) {
        return(
            LIST    { return undef, undef }
            DEFAULT { return undef        }
        );
    }
    else {
        die "get_status_code can not be called before read_response_headers";
    }
}

sub Net::HTTP::DStatus::_status_line {
    my ($line) = @_;

    my ($code, $txt) = $line =~ m,(\d{3})(.*),;
    $code or die "invalid status line: $line\n";
    return $code, $txt;
}


1;