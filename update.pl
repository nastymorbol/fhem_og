#!/usr/bin/perl

use File::Basename;
use POSIX qw(strftime);
use strict;


opendir my $dir, "FHEM" or die "Cannot open directory: $!";
my @filenames = readdir $dir;
closedir $dir;

my $prefix = "FHEM";
my $filename = "";

open(FH, '>', "update_mods.txt") or die $!;

foreach $filename (@filenames)
{
  my @statOutput = stat($prefix."/".$filename);
  
  next if $filename eq ".";
  next if $filename eq "..";

  if (scalar @statOutput != 13)
  {
    printf("error: stat has unexpected return value for ".$prefix."/".$filename."\n");
    next;
  }

  my $mtime = $statOutput[9];
  my $date = POSIX::strftime("%Y-%m-%d", localtime($mtime));
  my $time = POSIX::strftime("%H:%M:%S", localtime($mtime));
  my $filetime = $date."_".$time;

  my $filesize = $statOutput[7];

  print FH "UPD ".$filetime." ".$filesize." ".$prefix."/".$filename."\n";
}

close(FH);