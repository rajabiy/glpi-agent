package FusionInventory::Agent::Task::Inventory::Win32::Controllers;

use strict;
use warnings;

use parent 'FusionInventory::Agent::Task::Inventory::Module';

use FusionInventory::Agent::Tools::Generic;
use FusionInventory::Agent::Tools::Win32;

sub isEnabled {
    my (%params) = @_;
    return 0 if $params{no_category}->{controller};
    return 1;
}

sub isEnabledForRemote {
    my (%params) = @_;
    return 0 if $params{no_category}->{controller};
    return 1;
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};

    foreach my $controller (_getControllers(
        logger  => $params{logger},
        datadir => $params{datadir}
    )) {
        $inventory->addEntry(
            section => 'CONTROLLERS',
            entry   => $controller
        );

        if ( $controller->{NAME} =~ /QEMU/i ) {
            $inventory->setHardware ({
                VMSYSTEM => 'QEMU'
            });
        }
    }
}

sub _getControllers {
    my @controllers;
    my %seen;

    foreach my $controller (_getControllersFromWMI(@_)) {

        if ($controller->{deviceid} =~ /PCI\\VEN_(\S{4})&DEV_(\S{4})/) {
            $controller->{VENDORID} = lc($1);
            $controller->{PRODUCTID} = lc($2);
        }

        if ($controller->{deviceid} =~ /&SUBSYS_(\S{4})(\S{4})/) {
            $controller->{PCISUBSYSTEMID} = lc($2 . ':' . $1);
        }

        # only devices with a PCIID sounds resonable
        next unless $controller->{VENDORID} && $controller->{PRODUCTID};

        # avoid duplicates
        next if $seen{$controller->{VENDORID}}->{$controller->{PRODUCTID}}++;

        delete $controller->{deviceid};

        my $vendor_id    = lc($controller->{VENDORID});
        my $device_id    = lc($controller->{PRODUCTID});
        my $subdevice_id = lc($controller->{PCISUBSYSTEMID});

        my $vendor = getPCIDeviceVendor(id => $vendor_id, @_);
        if ($vendor) {
            $controller->{MANUFACTURER} = $vendor->{name};

            if ($vendor->{devices}->{$device_id}) {
                my $entry = $vendor->{devices}->{$device_id};
                $controller->{CAPTION} = $entry->{name};

                $controller->{NAME} =
                    $subdevice_id && $entry->{subdevices}->{$subdevice_id} ?

                    $entry->{subdevices}->{$subdevice_id}->{name} :
                    $entry->{name};
            }
        }

        push @controllers, $controller;
    }

    return @controllers;
}

sub _getControllersFromWMI {
    my @controllers;

    foreach my $class (qw/
        Win32_FloppyController Win32_IDEController Win32_SCSIController
        Win32_VideoController Win32_InfraredDevice Win32_USBController
        Win32_1394Controller Win32_PCMCIAController CIM_LogicalDevice
    /) {

        foreach my $object (getWMIObjects(
            class      => $class,
            properties => [ qw/
                Name Manufacturer Caption DeviceID
            /]
        )) {

            push @controllers, {
                NAME         => $object->{Name},
                MANUFACTURER => $object->{Manufacturer},
                CAPTION      => $object->{Caption},
                TYPE         => $object->{Caption},
                deviceid     => $object->{DeviceID},
            };
        }
    }

    return @controllers;
}

1;
