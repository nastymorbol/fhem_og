#!/usr/bin/perl

use File::Basename;
use FileHandle;
use POSIX qw(strftime);
use strict;


my @filenames = getFiles("FHEM");

my $prefix = "FHEM";

my $filehandle;
open($filehandle, '>', "update_mods.txt") or die $!;

writeUpdateFile($filehandle, "FHEM/", @filenames);
@filenames = getFiles(".", "entry.sh");
writeUpdateFile($filehandle, "/", @filenames);


close($filehandle);

sub 
getFiles($$) {
  my $folder = shift;
  my $regex = shift;

  $regex = ".*" if not defined $regex;

  opendir my $dir, $folder or die "Cannot open directory: $!";
  my @filenames = readdir $dir;
  closedir $dir;

  my @results = ();
  for my $filename (@filenames) {
    next if $filename eq ".";
    next if $filename eq "..";

    next if $filename !~ $regex;

    push @results, $folder."/".$filename;
  }

  return @results;
}

sub 
writeUpdateFile(@) {
  my ($fh, $destination, @filenames) = @_;

  foreach my $filename (@filenames)
  {
    my @statOutput = stat($filename);
    
    next if $filename eq ".";
    next if $filename eq "..";

    if (scalar @statOutput != 13)
    {
      printf("error: stat has unexpected return value for ".$destination."/".$filename."\n");
      next;
    }

    my $mtime = $statOutput[9];
    my $date = POSIX::strftime("%Y-%m-%d", localtime($mtime));
    my $time = POSIX::strftime("%H:%M:%S", localtime($mtime));
    my $filetime = $date."_".$time;

    my $filesize = $statOutput[7];

    print "UPD ".$filetime." ".$filesize." ".$destination.basename($filename)."\n";
    print $fh "UPD ".$filetime." ".$filesize." ".$destination.basename($filename)."\n";
  }
}

