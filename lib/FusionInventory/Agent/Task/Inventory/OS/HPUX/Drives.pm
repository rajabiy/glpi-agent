package FusionInventory::Agent::Task::Inventory::OS::HPUX::Drives;

use strict;
use warnings;

use English qw(-no_match_vars);
use POSIX qw(strftime);

use FusionInventory::Agent::Tools;

sub isInventoryEnabled  {
    return
        can_run('fstyp') &&
        can_run('bdf');
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    # get filesystem types
    my @types = getAllLines(
        command => 'fstyp -l',
        logger  => $logger
    );

    # get filesystems for each type
    foreach my $type (@types) {

        my $handle = getFileHandle(
            command => "bdf -t $type",
            logger  => $logger
        );

        my $device;
        while (my $line = <$handle>) {
            next if $line =~ /Filesystem/;

            if ($line =~ /^(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+%)\s+(\S+)/) {
                $device = $1;

                my $ctime = $type eq 'vxfs' ?
                    _getVxFSctime($device, $logger) : undef;

                $inventory->addEntry(
                    section => 'DRIVES',
                    entry   => {
                        FREE       => $3,
                        FILESYSTEM => $type,
                        TOTAL      => $2,
                        TYPE       => $6,
                        VOLUMN     => $device,
                        CREATEDATE => $ctime
                    }
                );
                next;
            }

            if ($line =~ /^(\S+)\s/) {
                $device = $1;
                next;
            }
            
            if ($line =~ /(\d+)\s+(\d+)\s+(\d+)\s+(\d+%)\s+(\S+)/) {
                my $ctime = $type eq 'vxfs' ?
                    _getVxFSctime($device, $logger) : undef;

                $inventory->addEntry(
                    section => 'DRIVES',
                    entry   => {
                        FREE       => $3,
                        FILESYSTEM => $type,
                        TOTAL      => $1,
                        TYPE       => $5,
                        VOLUMN     => $device,
                        CREATEDATE => $ctime
                    }
                );
                next;
            }
        }
        close $handle;
    }
}

# get filesystem creation time by reading binary value directly on the device
sub _getVxFSctime {
    my ($device, $logger) = @_;

    # compute version-dependant read offset

    # Output of 'fstyp' should be something like the following:
    # $ fstyp -v /dev/vg00/lvol3
    #   vxfs
    #   version: 5
    #   .
    #   .
    my $version = getFirstMach(
        command => "fstyp -v $device",
        logger  => $logger,
        pattern => /^version:\s+(\d+)$/
    );

    my $offset =
        $version == 5 ? 8200 :
        $version == 6 ? 8208 :
                        undef;

    if (!$offset) {
      $logger->error("unable to compute offset from fstyp output");
      return;
    }

    # read value
    open (my $handle, "<:raw:bytes", $device)
        or die "Can't open $device in raw mode: $ERRNO";
    seek($handle, $offset, 0) 
        or die "Can't seek offset $offset on device $device: $ERRNO";
    my $raw;
    read($handle, $raw, 4)
        or die "Can't read 4 bytes on device $device: $ERRNO";
    close($handle);

    # Convert the 4-byte raw data to long integer and
    # return a string representation of this time stamp
    return strftime("%Y/%m/%d %T", localtime(unpack('L', $raw)));
}

1;
