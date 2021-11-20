##############################################
# $Id: 01_FupMacro.pm 14076 2021-11-20 08:57:56Z sschulze $
# History
# 2021-11-05 Initital commit
# 2021-11-20 Changed command structure

package main;

use strict;
use warnings;
use SetExtensions;
use JSON;

sub
FupMacro_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "FupMacro_Get";
  $hash->{SetFn}     = "FupMacro_Set";
  $hash->{DefFn}     = "FupMacro_Define";
  $hash->{AttrFn}    = "FupMacro_Attr";
  $hash->{AttrList}  = "disable labels:textField-long " .
                       "pollInterval " .
                       $readingFnAttributes;
}

###################################
sub
FupMacro_Get($$$)
{
    my ( $hash, $name, $opt, @args ) = @_;

    return "\"get $name\" needs at least one argument" unless(defined($opt));

    my @setList = ();

    if($opt eq "urn")
    {
        return OPENgate_UpdateInternalUrn($hash, @args);
    }
    
    if($opt eq 'ClearScanResult')
    {
        my @toDelete;
        my $count = 0;
        my $readings = $hash->{READINGS};
        readingsBeginUpdate($hash);
        foreach my $a ( keys %{$readings} ) {
            if(index($a, "scan_") == 0 or $a eq "urn")
            {
                readingsBulkUpdate($hash, $a, "undef" );
                push(@toDelete, $a);
                $count++;
            }
        }
        readingsEndUpdate($hash, 1);
        
        foreach(@toDelete){
            readingsDelete($hash, $_);
        }
        
        return "OK - Removed $count reading(s)";
    }
    push @setList, "ClearScanResult:noArg";
    
    if($opt eq 'LabelData')
    {
        my $attrValue = AttrVal($name, 'labels', undef);
        if(not defined($attrValue) or length($attrValue) < 2)
        {
            return '[]';
        }
        
        my @entries = split(/[,\n]/, $attrValue);
        my @labelDatas;
        foreach (@entries) {
            next if (length($_) < 3);
            my ($label, $reading) = split '\|', $_, 2;
            if (not defined($reading) or length($_) < 1) {
                next;
            }
            my %labelData=();
            $labelData{name} = $label;
            $labelData{reading} = $reading;
            push(@labelDatas, \%labelData);
        }
        
        return(to_json(\@labelDatas));
    }
    push @setList, "LabelData:noArg";
    
    return "unknown argument choose one of " . join(' ', @setList);
}

###################################
sub FupMacro_isInt{
	return  ($_[0] =~/^-?\d+$/)?1:0;
}

sub FupMacro_isNotInt{
	return  ($_[0] =~/^-?\d+$/)?0:1;
}


sub
FupMacro_Set($@)
{
    my ($hash, @a) = @_;
    my $name = shift @a;
    
    return "no set value specified" if(int(@a) < 1);
    
    my $cmd = shift @a;
    my @setList = ();

    if($cmd =~ /DriverRes/)
    {
        my ($rcmd, $rprop, $rval, $rerr) = @a;
        #my $value = join ' ', @a;
        $hash->{DriverRes} = join ' ', @a;
    
        # Der Treiber schickt nach efolgter Ausführung eines Befehls eine Respons welche mit 
        # done endet
        if($hash->{DriverRes} =~ /done/)
        {
          if($hash->{DriverReq} ne "done")
          {
            $hash->{DriverReq} = "done" ;
            DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
          }
        }
    
        # Der Treiber schickt unmittelbar nach empfang eines Commandos auf dem DriverReq
        # eine Empfangsbestätigung auf DriverRes mit dem Commando + exec
        # In dem Fall muss der Request um exec erweitert werden, damit befehle nicht doppelt gestartet werden
        if($hash->{DriverRes} =~ /exec/)
        {
          if($hash->{DriverReq} !~ /exec/)
          {
            $hash->{DriverReq} .= " > exec" ;
            DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
          }
        }
    
        DoTrigger($name, "DriverRes: " . $hash->{DriverRes});
        
        return undef;
    }

    if($cmd eq 'pollInterval')
    {
        my $value = join ' ', @a;
        fhem("attr $name $cmd $value");
        return undef;
    }
    push @setList, "pollInterval";

    if($cmd eq 'AddLabel')
    {
        my $value = join '|', @a;
        return fhem("attr -a $name labels ,$value");
    }
    push @setList, "AddLabel";

    if($cmd eq 'ScanLabel')
    {
        my $ioDev = $hash->{IODev};
        my $devHash = $defs{$ioDev};
        $devHash->{DriverReq} = "CMD:$cmd $name";
        DoTrigger($ioDev, "DriverReq: " . $devHash->{DriverReq});
        $hash->{DriverReq} = "CMD:Delegate $cmd $name to $ioDev";
        DoTrigger($hash, "DriverReq: " . $hash->{DriverReq});
        return undef;
    }
    push @setList, "ScanLabel:noArg";

    if($cmd eq 'RemoveLabel')
    {
        my $value = join '|', @a;
        my $labelAttr = AttrVal($name, 'labels', undef);
        if(not defined($labelAttr)) {
            return(undef);
        }
        my @labels = split ',\n', $labelAttr;
        foreach(@labels)
        {
            if(index($_, $value) > -1)
            {
                return fhem("attr -r $name labels $_");
            }
        }
        
        return(undef);
    }
    push @setList, "RemoveLabel";
    
    return join ' ', @setList;
}

sub FupMacro_Attr($$$$)
{
	my ( $cmd, $name, $attrName, $attrValue ) = @_;
    
    # $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attrName/$attrValue sind Attribut-Name und Attribut-Wert
    
	if ($cmd eq "set") {
        if ($attrName =~ "rec.*") {
            # json2nameValue('{"Interval":3600, "Controller":1, "Name":"My Receipe name on FupMacro"}')
            my $json = json2nameValue($attrValue);
            return "Error in 'Name' field ($attrValue)" if (not $json->{Name});
            return "Error in 'Interval' field ($attrValue)" if (not $json->{Interval});
            return "Error in 'Controller' field ($attrValue)" if (not $json->{Controller});
        }
        if ($attrName eq "pollInterval") {
            $_[3] = 300 if(FupMacro_isInt($attrValue)==0);
            $_[3] = 300 if($attrValue > 0 && $attrValue < 30);
            return undef;
        }
        if ($attrName eq "labels") 
        {
            #$attrValue =~ s/\s+/ /gs;
            if(length($attrValue) < 2)
            {
                $_[3] = '[]';
                return (undef);
            }
            
            my @entries = split(/,|\n/, $attrValue);
            my @attributes;
            my @labels;
            my @readings;
            foreach (@entries) {
            	next if( length($_) < 3 );
            	my ($fullLabelName, $reading) = split '\|', $_, 2;
                my ($part0, $part1) = split ':', $fullLabelName, 2;
                my $fupPage = $part0;
                my $label = $part1;
                if(not defined($label))
                {
                    $label = $part0;
                    undef($fupPage);
                }
                if( not defined($reading) or length($_) < 1 )
                {
                    return "Error no label name given, or reading name not valid [$_]."
                }
                if ( grep( /^$fullLabelName$/, @labels ) ) 
                {
                    return "Error label names have to be unique. $fullLabelName is already defined."
                }
                if ( grep( /^$reading$/, @readings ) )
                {
                    return "Error reading names have to be unique. $reading is already defined."
                }
                if($fullLabelName =~ /^[0-9]/)
                {
                    return "Error label name [$fullLabelName] is not valid. Label name shouldn't start with a number"
                }
                if(length($label)<2)
                {
                    # attribute removed ?!
                    next;
                }
                if(not goodReadingName($label))
                {
                    return "Error label name [$fullLabelName] is not valid."
                }
                if(defined($fupPage) and length($fupPage)>8)
                {
                    return "Error FupPage name [$fupPage] is to long."
                }
                if(length($label) > 4)
                {
                    if(index(uc $fupPage, "SYSTEM") == -1)
                    {
                        #return "Error label name [$label] is to long."
                    }
                }
                
                push(@labels, $fullLabelName);
                push(@readings, $reading);
                if(not goodReadingName($reading))
                {
                    $reading = makeReadingName($reading);
                }

                if(defined($fupPage))
                {
                    push(@attributes, $fupPage . ":" . $label . "|" . $reading);
                }
                else {
                    push(@attributes, $label . "|" . $reading);
                }
            }

            $_[3] = join(",\n", @attributes);

            return undef;
        }
                
	}
	return undef;
}

sub
FupMacro_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    
    my $name = shift @a;
    
    return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName]" if(int(@a) < 2);
    
    $hash->{VERSION} = "2021-11-20_08:57:56";
    
    my $type = shift @a;
    my $iodev = shift @a;
    my $fupPageName = shift @a;

    my $devHash = $defs{$iodev};
    if(!defined($devHash))
    {
        return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName].\nThe Device '$iodev' doesn't exist";
    }

    if($devHash->{TYPE} ne "OPENems")
    {
        return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName].\nThe Device '$iodev' is not from TYPE OPENems [$devHash->{TYPE}].";
    }
    
    if(not defined($fupPageName) or length($fupPageName) < 3)
    {
        # if name is shorter then the ioDev name, the the fupPage may be the name of this device
        if(length($name) < length($iodev))
        {
            $fupPageName = $name;
        }
        else
        {
            $fupPageName = (split('_', $name, 2))[-1];   
        }
    }

    if(not goodReadingName($fupPageName))
    {
        return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName]. The FupPageName '$fupPageName' has illegal character's";
    }

    my ($fupPart, $extPart) = split('\.[fF]', $fupPageName, 2);
    if(not defined($fupPart))
    {
        return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName]. The FupPageName '$fupPageName' doesn't have an dot f syntax (const.f).";
    }
    if(lc($fupPageName) eq "system")
    {
        $fupPart = "system";
        $extPart = "-";
    }
    if(not defined($extPart))
    {
        return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName]. The Extension '$extPart' doesn't have an dot f syntax (const.f).";
    }
    if(length($fupPart) > 8)
    {
        return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName]. The FupPageName '$fupPageName' is to long (max 12 character's)";
    }
    if(length($extPart) > 2)
    {
        return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName]. The Extension '$extPart' is to long (max 2 character's)";
    }
    if(length($fupPageName) > 11)
    {
        return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName]. The FupPageName '$fupPageName' is to long (max 12 character's)";
    }
    if($fupPart =~ /^[0-9]/)
    {
        return "Wrong syntax: use define <name> FupMacro <OPENems> [FupPageName]. The FupPageName '$fupPageName' can't start with an number";
    }

    $hash->{FupPageName} = $fupPageName;

    
    if(!defined(AttrVal($name,"room", undef))) {
        $attr{$name}{room} = "FupMacros->" . $iodev;
    }
    
    $hash->{DriverReq} = "N/A";
    $hash->{DriverRes} = "N/A";
    $hash->{IODev} = $iodev;

    OPENgate_InitializeInternalUrn($hash);
    
    return undef;
}

1;

=pod
=item helper
=item summary    FupMacro device
=item summary_DE FupMacro Ger&auml;t
=begin html

<a name="FupMacro"></a>
<h3>FupMacro</h3>
<ul>

  Define a FupMacro. A FupMacro can take via <a href="#set">set</a> any values.
  Used for programming.
  <br><br>

  <a name="FupMacrodefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FupMacro &lt;URL&gt;</code>
    <br><br>

    Example:
    <ul>
      <code>define MyFupMacro FupMacro http://192.168.123.199</code><br>
      <code>set MyFupMacro AddReceipe 1:60:My Receipe</code><br>
    </ul>
  </ul>
  <br>

  <b>Set</b>
  <li><a name="AddReceipe"></a>
    <code>set &lt;name&gt; AddReceipe &lt;1:60:My Receipe&gt</code><br>
    Format for ReceipeInfo:<br/>
    <p>
      PlantIndex:UptateInterval[s]:ReceipeName <br/>
      1:60:AHU001 <br/>
    </p>
    Adds or Updates an FupMacro Receipe information. <br/>
    The Receipe Infos are stored in an Attribute named after the Receipe name.
  </li>
  <li><a name="ScanReceipes"></a>
    <code>set &lt;name&gt; ScanReceipes [Interval]</code><br>
    Not implemented yet.
  </li>
  <br>

  <a name="FupMacroget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="FupMacroattr"></a>
  <b>Attributes</b>
  <ul>    
    <li><a name="readingList">readingList</a><br>
      Space separated list of readings, which will be set, if the first
      argument of the set command matches one of them.</li>

    <li><a name="setList">setList</a><br>
      Space separated list of commands, which will be returned upon "set name
      ?", so the FHEMWEB frontend can construct a dropdown and offer on/off
      switches. Example: attr dummyName setList on off </li>

    <li><a name="useSetExtensions">useSetExtensions</a><br>
      If set, and setList contains on and off, then the
      <a href="#setExtensions">set extensions</a> are supported.
      In this case no arbitrary set commands are accepted, only the setList and
      the set exensions commands.</li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html

=begin html_DE

=end html_DE

=cut
