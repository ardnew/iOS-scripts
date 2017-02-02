#!/usr/bin/perl5.18

# this script will locate the most recently modified iOS device simulator to determine
# which sqlite database was last modified, which helps hunting down hard-to-find bugs
# in Core Data enabled applications

# NOTE: this script does depend on perl 5.18 for some reason i do not recall. its 
#       possible it will work with other versions, i just haven't had time to identify
#       the reason for this. please feel free to test on you own!

use strict;
use warnings;

use Foundation; # Apple Obj-C lib bindings

my $device_file_path = "$ENV{HOME}/Library/Developer/CoreSimulator/Devices";
my $device_set_plist = "device_set.plist";
my $device_apps_path = "data/Containers/Data/Application";
my $coredata_db_path = "Documents/CoreDataApp.sqlite";

sub desc($) { $_[0]->description->UTF8String }
sub val($$) { $_[0]->objectForKey_($_[1]) }
sub pld($)
{
  if ($_[0] and $_[0]->isKindOfClass_(NSDictionary->class))
  {
    my $desc = desc($_[0]);
    # convert the ObjC syntax to perl hash
    $desc =~ s/=/=>/g;
    $desc =~ s/;/,/g;
    return %{ eval $desc };
  }
  return undef;
}

sub sort_last_modified
{
  # constat "9" is the "last modified time" index of the array returned from stat()
  return map { $_->[0] } sort { $b->[1] <=> $a->[1] } map { [ $_, (stat($_))[9] ] } grep { -e } @_;
}

sub device_type_from_path($$)
{
  my ($href, $path, $pfix) = (@_, $device_file_path);

  $path =~ s/^$pfix\/([^\/]+)(\/.*)?$/$1/;

  my $ostype = ${$$href{$path}}[0];
  my $hwtype = ${$$href{$path}}[1];

  $ostype =~ s/^.+\.([^\.]+)$/$1/;
  $hwtype =~ s/^.+\.([^\.]+)$/$1/;

  return "${hwtype}[$ostype]";
}

# -----------
#  MAIN LINE 
# -----------

my $device_plist = NSDictionary->dictionaryWithContentsOfFile_("$device_file_path/$device_set_plist");

my %device = pld(val($device_plist, "DefaultDevices"));

# discard any non-iOS devices
delete $device{$_} for grep { ! /\.iOS[^.]+$/ } keys %device;
# discard any non-iPad devices
for my $os (keys %device)
{
  delete ${$device{$os}}{$_} for grep { ! /\.iPad[^.]+$/ } keys %{ $device{$os} }
}

my %dev_hash;
while (my ($os, $idl) = each %device)
{
  #for my $hash (values %$idl) { $dev_hash{$hash} = $os }
  while (my ($dev, $hash) = each %$idl) { $dev_hash{$hash} = [ $os, $dev ]; }
}

my @dev_path = grep { -d } 
                map { "$device_file_path/$_" } 
                map { values %$_ } 
             values %device;

my ( $dev_last_modified ) = sort_last_modified(@dev_path);

my %app_path;
for my $dev (@dev_path)
{
  opendir my $dh, "$dev/$device_apps_path" or next;
  $app_path{$dev} = [ grep { -d } 
                       map { "$dev/$device_apps_path/$_" } 
                      grep { ! /^\.\.?$/ } 
                   readdir $dh ];
  closedir $dh;
}

my ( $app_last_modified ) = grep { -f } 
                             map { "$_/$coredata_db_path" } 
              sort_last_modified(map { @$_ } values %app_path);

my $dev_last_modified_type = device_type_from_path(\%dev_hash, $dev_last_modified);
my $app_last_modified_type = device_type_from_path(\%dev_hash, $app_last_modified);

print "most recently modified iPad simulator ($dev_last_modified_type):$/";
print "$dev_last_modified$/";

print "most recently modified iPad app ($app_last_modified_type):$/";
print "$app_last_modified$/";


