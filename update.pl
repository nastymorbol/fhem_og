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
@filenames = getFiles("www/pgm2",);
writeUpdateFile($filehandle, "www/pgm2/", @filenames);
@filenames = getFiles("www/pgm2/images/",);
writeUpdateFile($filehandle, "www/pgm2/images/", @filenames);
@filenames = getFiles("www/images",);
writeUpdateFile($filehandle, "www/images/", @filenames);
@filenames = getFiles("www/images/default/",);
writeUpdateFile($filehandle, "www/images/default/", @filenames);

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
    next if $filename =~ /.DS_Store/;

    next if $filename !~ $regex;
    next if -d $folder . "/" . $filename;
    
    push @results, $folder."/".$filename;
  }

  for my $filepath (@results) {
    next if $filepath !~ /.*.pm/;
    open my $handle, '<', $filepath;
    chomp(my @lines = <$handle>);
    close $handle;

    my $id = @lines[1];
    my $filename = basename($filepath);

    if($id !~ /# \$Id: /) {
      print "ID Comment error > " . $id . " < in file $filename";
      exit 0;
    }
    
    my @statOutput = stat($filepath);
    
    if (scalar @statOutput != 13)
    {
      printf("error: stat has unexpected return value for ".$filepath."/".$filename."\n");
      next;
    }
    
    my $mtime = $statOutput[9];
    my $date = POSIX::strftime("%Y-%m-%d", localtime($mtime));
    my $time = POSIX::strftime("%H:%M:%S", localtime($mtime));
    #my $filetime = $date."_".$time;
    my $size = $statOutput[7];

    # $Id: 00_OPENgate.pm 20665 2020-06-19 11:05:35Z sschulze $
    my ($filesize, $filedate, $filetime, $username) = (split(/ /, $id))[3, 4, 5, 6];
    
    if($size eq $filesize) {
      next;
    }

    my $index=0;
    foreach (@lines)
    {
        #   $hash->{VERSION}     = "2020-11-24_04:52:47";
        if($_ =~ /\$hash->{VERSION}/)
        {
          my $fmttime = '"' . $date."_".$time .'";';
          my $newversion = s/(.*)(\$hash->{VERSION})(.*)/$1$2 = $fmttime/r;
          @lines[$index] = $newversion;
          print "$_ --> $newversion\n"; # Print each entry in our array to the file
          last;
        }
        $index++;
    }

    my $revision = int($size);

    $id = "# \$Id: $filename $revision $date $time"."Z sschulze \$";
    @lines[1] = $id;

    # Open a file named "output.txt"; die if there's an error
    open my $fh, '>', $filepath or die "Cannot open $filepath: $!";

    # Loop over the array
    foreach (@lines)
    {
        print $fh "$_\n"; # Print each entry in our array to the file
    }
    close $fh; # Not necessary, but nice to do
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

    if($filename =~ /01_BACnetDevice/)
    {
      print "MOV FHEM/00_BACnetDevice.pm unused"."\n";
      print $fh "MOV FHEM/00_BACnetDevice.pm unused"."\n";
    }
    elsif($filename =~ /02_BACnetDatapoint/)
    {
      print "MOV FHEM/00_BACnetDatapoint.pm unused"."\n";
      print $fh "MOV FHEM/00_BACnetDatapoint.pm unused"."\n";
    }
  }
}

