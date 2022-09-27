##############################################
# $Id: 01_FupMacro.pm 20859 2022-07-21 16:46:23Z sschulze $
# History
# 2021-11-05 Initial commit
# 2021-11-20 Changed command structure
# 2021-11-20 New Command read label values
# 2021-11-22 FUP Page Name max Length corrected
# 2022-05-09 Changed JSON Interpreter

package main;

use strict;
use warnings;
use SetExtensions;
use JSON::PP;

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
FupMacro_Get($$$@)
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
        
        my $searchPattern = shift(@args);

        my @entries = split(/[,\n]/, $attrValue);
        my @labelDatas;
        foreach (@entries) {
            next if (length($_) < 3);
            my ($label, $reading) = split '\|', $_, 2;
            if (not defined($reading) or length($_) < 1) {
                next;
            }
            my %labelData=();
            # check for FupPage name in Label name
            if(index($label, ':') == -1)
            {
                $label = uc($hash->{FupPageName}) . ':' . $label;
            }
            $labelData{name} = $label;
            $labelData{reading} = $reading;
            if($searchPattern)
            {
                my $isReading = ReadingsVal($name, $searchPattern, undef);
                if(defined($isReading))
                {
                    if($reading eq $searchPattern)
                    {
                        return(encode_json(\%labelData));
                    }
                }
                else {
                    my $colonIndex = index($searchPattern, ':');
                    if ($colonIndex == -1) {
                        $searchPattern = uc($hash->{FupPageName}) . ':' . $searchPattern;
                    }
                    else {
                        $searchPattern = uc(substr($searchPattern, 0, $colonIndex)) . ':' . substr($searchPattern, $colonIndex + 1);
                    }

                    if($label eq $searchPattern)
                    {
                        return(encode_json(\%labelData));
                    }
                }
            }
            push(@labelDatas, \%labelData);
        }
        
        return(encode_json(\@labelDatas));
    }
    #push @setList, "LabelData:noArg";
    push @setList, "LabelData";

    if($opt eq 'LabelValues')
    {
        my $ioDev = $hash->{IODev};
        my $devHash = $defs{$ioDev};
        $devHash->{DriverReq} = "CMD:$opt $name";
        DoTrigger($ioDev, "DriverReq: " . $devHash->{DriverReq});
        $hash->{DriverReq} = "CMD:Delegate $opt $name to $ioDev";
        DoTrigger($hash, "DriverReq: " . $hash->{DriverReq});
        return undef;
    }
    push @setList, "LabelValues:noArg";
    
    return "unknown argument choose one of " . join(' ', @setList);
}

###################################



sub
FupMacro_Set($@)
{
    my ($hash, @a) = @_;
    my $name = shift @a;
    
    return "no set value specified" if(int(@a) < 1);
    
    my $cmd = shift @a;

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

    if($cmd eq 'AddLabel')
    {
        my $value = join '|', @a;
        return fhem("attr -a $name labels ,$value");
    }

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
    
    if($cmd eq 'WriteLabel')
    {
        $cmd = shift @a;
    }

    # If setter is Reading, then send write Label Command
    my $currentValue = ReadingsVal($name, $cmd, undef);
    my $json = undef;
    if(not defined $currentValue)
    {
        # Try to pars Reading name if Label is given ...
        $json = FupMacro_Get($hash, $name, "LabelData", $cmd);
        if(index($json, '{') == 0 && index($json, '}') > 2)
        {
            $cmd = decode_json($json)->{reading};
            $currentValue = ReadingsVal($name, $cmd, undef);
        }
    }
    if(defined $currentValue)
    {
        # set ISPHS26_system scan_C1ERRO_ULI_4 33
        # set ISPHS26_system C1ERRO 33
        # setreading ISPHS26_system scan_C1ERRO_ULI_4 33
        my $newValue = shift(@a);
    
        if(defined $newValue)
        {
            $json = FupMacro_Get($hash, $name, "LabelData", $cmd) if not defined $json;
            # check for empty array
            if(index($json, '{') == 0 && index($json, '}') > 2) {
                my $label = decode_json($json)->{name};
                if($label)
                {
                    my $ioDev = $hash->{IODev};
                    my $devHash = $defs{$ioDev};
                    $devHash->{DriverReq} = "CMD:WriteLabel $name $label $newValue";
                    DoTrigger($ioDev, "DriverReq: " . $devHash->{DriverReq});
                    $hash->{DriverReq} = "CMD:Delegate WriteLabel $label [$newValue] to $ioDev";
                    DoTrigger($hash, "DriverReq: " . $hash->{DriverReq});
                    #return "Write Label Reading: $cmd CurrentValue: $currentValue NewValue: $newValue";
                    return(undef);
                }
            }
            else {
                readingsSingleUpdate($hash, $cmd, $newValue, 1);
                #return($currentValue . " -> " . $newValue . " --> " .  $json);
                return(undef);
            }
            return "ERROR: JSON empty [$json] " . index($json, '[') . " : " . index($json, ']') ;
        }
        return "ERROR: No value in set command [$newValue]";
    }
    
    my @setList = ();
    push @setList, "pollInterval";
    push @setList, "AddLabel";
    push @setList, "ScanLabel:noArg";
    push @setList, "RemoveLabel";
    push @setList, "WriteLabel";
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
                # 2022-01-13 FupPage Name can be length 8.3 ...
                if(defined($fupPage) and length($fupPage) > 12)
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
    
    $hash->{VERSION} = "2022-07-21_16:46:23";
    
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
    if(length($fupPageName) > 12)
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

###### HELPER FUNCTIONS
sub FupMacro_isInt{
    return  ($_[0] =~/^-?\d+$/)?1:0;
}

sub FupMacro_isNotInt{
    return  ($_[0] =~/^-?\d+$/)?0:1;
}
######

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
  <br/><br/>

  <a name="FupMacrodefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FupMacro &lt;OPENems&gt;</code>
    <br/><br/>

    Example:
    <ul>
      <code>define MyFupMacro FupMacro myOPENemsController</code><br/>
      <code>set MyFupMacro ScanLabel</code><br/>
    </ul>
  </ul>
  <br/>

  <b>Set</b>
  <ul>
      <li><a name="WriteLabel">WriteLabel</a><br/>
        <code>set [$NAME] ReadingName Value </code><br/>
        <code>set [$NAME] WriteLabel ReadingName Value </code><br/>
        Writes the Value to the Label, which is assigned to the given ReadingName        
      </li>
      
      <li><a name="AddLabel">AddLabel</a><br/>
        <code>set <$NAME> AddLabel E06 ReadingName </code><br/>
        Adds an Label Configuration to the <a href="#labelsAttr">labels Attribute</a>        
      </li>
      <li><a name="RemoveLabel">RemoveLabel</a><br/>
        <code>set <$NAME> RemoveLabel E06 </code><br/>
        Removes an Label Configuration from the <a href="#labelsAttr">labels Attribute</a>
      </li>
      <li><a name="ScanLabel">ScanLabel</a> (see also <a href="#ClearScanResults">ClearScanResult</a>)<br/>
        <code>set <$NAME> ScanLabel</code><br/>
        Scans all Labels within this FupPage. This can take some time! <br/>
        After successful Label scanning, all found Label will be added to the <a href="#labelsAttr">labels Attribute</a>. <br/>
        After reaching the poll interval, all scanned Labels will be updated.<br/><br/>
        The Readingname will have the following format.        
        <ul>
            scan_&lt;LABELNAME&gt;_&lt;DATATYPE&gt;_&lt;LEN&gt;[_USTBDFTEXT] <br/>
            scan_C1ERRO_ULI_4_MaybeSomeText
        </ul>
        
      </li>
  </ul><br/>

  <a name="FupMacroget"></a>
  <b>Get</b>
  <ul>
      </li>
        <li><a name="ClearScanResult">ClearScanResult</a><br/>
        <code>
        get &lt;$NAME&gt; ClearScanResult    
        </code><br/><br/>
        Clears all Label readings, that are added threw an automated Label Scan. <br/>
        
      </li>
      <li><a name="LabelData">LabelData</a><br/>
        <code>
        get &lt;$NAME&gt; LabelData [searchPattern]    
        </code><br/><br/>
        Returns Label informations as json object. If the given search pattern is empty, or not found, then the returned json object
        is a list of all label infos.
        <br/>
        The Searchpattern can be Labelname only or an FQDN Labelname. <br/>
        In case of Labelname only, the Searchpattern will be expanded threw 
        the FupPageName internal in this FupMacro. <br/>
        E06 will be expanded to zeit.f:E06 <br/>
        <br/>Example:<br/>
        <ul>
        <code>
            get &lt;$NAME&gt; LabelData E06 <br/>
            {"reading":"scan_C1ERRO_ULI_4","name":"SYSTEM:C1ERRO"} <br/>
            <br/>
            get &lt;$NAME&gt; LabelData <br/>
            [{"reading":"scan_C1ERRO_ULI_4","name":"SYSTEM:C1ERRO"}] <br/>
        </code></ul><br/>
      </li>
        <li><a name="LabelValues">LabelValues</a><br/>
        <code>
        get &lt;$NAME&gt; LabelValues    
        </code><br/><br/>
        Reads all Label Values and Updates the Corresponding Readings. If the reading doesn't exists, it will be created. <br/>
        <br/>
        This is in delegate command. The Command will be delegated to the corresponding OPENems in the IODev Internal. The
        OPENems Device will then asynchronously update the values. <br/>
        <br/>Example:<br/>
        <code>
            get &lt;$NAME&gt; LabelValues <br/>
        </code><br/>
      </li>
    </ul>
  <br/>

  <a name="FupMacroattr"></a>
  <b>Attributes</b>
  <ul>    
    <li><a name="labelsAttr">labels</a><br/>
      Comma separated list of readings, which will be updated threw an Label value.
      <p>
      C1ERRO|scan_C1ERRO_ULI_4, C1SENT|scan_C1SENT_ULI_4
      </p>
    </li>

    <li><a name="setList">setList</a><br/>
      Space separated list of commands, which will be returned upon "set name
      ?", so the FHEMWEB frontend can construct a dropdown and offer on/off
      switches. Example: attr dummyName setList on off </li>

    <li><a name="useSetExtensions">useSetExtensions</a><br/>
      If set, and setList contains on and off, then the
      <a href="#setExtensions">set extensions</a> are supported.
      In this case no arbitrary set commands are accepted, only the setList and
      the set exensions commands.</li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br/>

</ul>

=end html

=begin html_DE

=end html_DE

=cut
