##############################################
# $Id: 04_MbusDevice.pm 12351 2022-07-11 16:35:06Z sschulze $
# History
# 2022-07-11 New Attribute bacnetIndex for Instance Number calculation
# 2022-07-07 mapToBacnet can now hold multiple records
# 2022-06-30 frameCount Attribute added
# 2022-05-29 mapToBacnet Attribute added
# 2022-01-25 Initial commit

package main;

use strict;
use warnings;

sub
MbusDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "MbusDevice_Get";
  $hash->{SetFn}     = "MbusDevice_Set";
  $hash->{DefFn}     = "MbusDevice_Define";
  $hash->{AttrFn}    = "MbusDevice_Attr";
  $hash->{AttrList}  = "disable useSecondaryAddress retries retryPause timeout pollInterval mapToBacnet frameCount bacnetIndex";
}

sub
MbusDevice_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $name = shift @a;

  return "Wrong syntax: use define <name> MbusDevice <MbusNetwork> <PRIMARY_ADDRESS|SECONDARY_ADDRESS>" if(int(@a) < 2);

  $hash->{VERSION} = "2022-07-11_16:35:06";

  if(not defined AttrVal($name,"room", undef)) {
    $attr{$name}{room} = 'MbusDevice';
  }

  my $type = shift @a;
  my $ioDev = shift @a;
  my $primaryAddress = shift @a;
  my $secondaryAddress = shift @a;
  
  
  if ( !defined($ioDev) ) {
    return "Wrong syntax: use define <name> MbusDevice <MbusNetwork> <PRIMARY_ADDRESS|SECONDARY_ADDRESS>";
  }

  my $devHash = $defs{$ioDev};
  if(!defined($devHash))
  {
    return "Wrong syntax: use define <name> MbusDevice <MbusNetwork> <PRIMARY_ADDRESS|SECONDARY_ADDRESS>.\nThe Device '$ioDev' doesn't exist";
  }

  if($devHash->{TYPE} ne "MbusNetwork")
  {
    return "Wrong syntax: use define <name> MbusDevice <MbusNetwork> <PRIMARY_ADDRESS|SECONDARY_ADDRESS>.\nThe Device '$ioDev' isn't a MbusNetwork [$devHash->{TYPE}].";
  }

  $hash->{IODev} = $ioDev;
  $hash->{PrimaryAddress} = $primaryAddress;
  $hash->{SecondaryAddress} = $secondaryAddress;
  $hash->{DriverReq} = "N/A";
  $hash->{DriverRes} = "N/A";
  $hash->{STATE} = "Init";

  OPENgate_InitializeInternalUrn($hash);

  return undef;
}

###################################
sub
MbusDevice_Get($$$)
{
  my ( $hash, $name, $opt, @args ) = @_;
  
  return "\"get $name\" needs at least one argument" unless(defined($opt));
  
  if($opt eq "urn")
  {
    return OPENgate_UpdateInternalUrn($hash, @args);
  }

  my @setList = ();
  
  if($opt eq "ReadMeter")
  {
    $hash->{DriverReq} = "CMD:ReadMeter";
    if(@args)
    {
      $hash->{DriverReq} .= " " . join(' ', @args);
    }
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    my $devHash = $defs{$hash->{IODev}};
    if(!defined($devHash))
    {
      return "The Device '$hash->{IODev}' doesn't exist";
    }

    return MbusNetwork_Get($devHash, $devHash->{NAME}, "ReadMeter", ($name));
  }
  push @setList, "ReadMeter";

  
  return "unknown argument choose one of " . join(' ', @setList);
}

sub
MbusDevice_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "no set value specified" if(int(@a) < 1);
  
  my $cmd = shift @a;
  my @setList = ();

  if($cmd =~ /urn/)
  {
    my $value = join ' ', @a;
    if(defined($hash->{urn}))
    {
      if($hash->{urn} ne $value)
      {
        setKeyValue($name . "_urn", $value);
        $hash->{urn} = $value;
      }
    }
    else
    {
      setKeyValue($name . "_urn", $value);
      $hash->{urn} = $value;
    }
    return "OK";
  }

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
        DoTrigger($name, "DriverReq: done");
      }
    }

    # Der Treiber schickt unmittelbar nach empfang eines Commandos auf dem DriverReq
    # eine Empfangsbestätigung auf DriverRes mit dem Commando + exec
    # In dem Fall muss der Request um exec erweitert werden, damit befehle nicht doppelt gestartet werden
    if($hash->{DriverRes} =~ /exec/)
    {
      if($hash->{DriverReq} !~ /exec/)
      {
        #$hash->{DriverReq} = $hash->{DriverReq} =~ s/CMD://r;
        $hash->{DriverReq} .= " > exec" ;
        #DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
      }
    }
    
    DoTrigger($name, "DriverRes: " . $hash->{DriverRes});
  
    return undef;
  }


  if($cmd eq "UseSecondaryAddress")
  {
    my $value = join ' ', @a;
    if($value eq "" || $value eq "0")
    {
      fhem("deleteattr $name useSecondaryAddress");
      return(undef);
    }
    fhem("attr $name useSecondaryAddress 1");
    return(undef);
  }
  
  if($cmd eq "Retries")
  {
    my $value = (join ' ', @a) + 0;
    if($value < 1)
    {
      fhem("deleteattr $name retries");
      return(undef);
    }
    fhem("attr $name retries $value");
    return(undef);
  }
  
  if($cmd eq "Timeout")
  {
    my $value = (join ' ', @a) + 0;
    if($value < 1)
    {
      fhem("deleteattr $name timeout");
      return(undef);
    }
    fhem("attr $name timeout $value");
    return(undef);
  }
  
  if($cmd eq "RetryPause")
  {
    my $value = (join ' ', @a) + 0;
    if($value < 1)
    {
      fhem("deleteattr $name retryPause");
      return(undef);
    }
    fhem("attr $name retryPause $value");
    return(undef);
  }
  
  if($cmd eq "PollInterval")
  {
    my $value = join ' ', @a;
    if($value eq "")
    {
      fhem("deleteattr $name pollInterval");
      return(undef);
    }
    fhem("attr $name pollInterval $value");
    return(undef);
  }
  
  if($cmd eq "MapToBacnet")
  {
    my $value = join ' ', @a;
    if($value eq "")
    {
      fhem("deleteattr $name mapToBacnet");
      return(undef);
    }
    fhem("attr $name mapToBacnet $value");
    return(undef);
  }

  if($cmd eq "FrameCount")
  {
    my $value = join ' ', @a;
    if($value eq "")
    {
      fhem("deleteattr $name frameCount");
      return(undef);
    }
    fhem("attr $name frameCount $value");
    return(undef);
  }
  
  
  push @setList, "UseSecondaryAddress Retries RetryPause Timeout PollInterval MapToBacnet FrameCount";   
  return join ' ', @setList;
}

sub MbusDevice_Attr($$$$)
{
	my ( $cmd, $name, $attrName, $attrValue ) = @_;
    
    # $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attrName/$attrValue sind Attribut-Name und Attribut-Wert
    
	if ($cmd eq "set") {
      if ($attrName eq "useSecondaryAddress") 
      {
        if($attrValue ne "1")
        {
          $_[3] = "1";
        }
      }
      elsif ($attrName eq "retries")
      {
        my $number = $attrValue + 0;
        if($number < 1)
        {
          $number = 3;
        }
        $_[3] = $number;
      }
      elsif ($attrName eq "timeout")
      {
        my $number = $attrValue + 0;
        if($number < 100)
        {
          $number = 2500;
        }
        $_[3] = $number;
      }
      elsif ($attrName eq "retryPause")
      {
        my $number = $attrValue + 0;
        if($number < 1)
        {
          $number = 5000;
        }
        $_[3] = $number;
      }
	}
	return undef;
}

###################################
sub MbusDevice_isInt{
  return  ($_[0] =~/^-?\d+$/)?1:0;
}

sub MbusDevice_isNotInt{
  return  ($_[0] =~/^-?\d+$/)?0:1;
}

1;

=pod
=item helper
=item summary    MbusDevice device
=item summary_DE MbusDevice Ger&auml;t
=begin html

<a name="MbusDevice"></a>
<h3>MbusDevice</h3>
<ul>

  Define a MbusDevice. The Mbus Device connects threw an MbusNetwork (IODev) to the Mbus. 
  
  <br/><br/>

  <a name="MbusDevicedefine"></a>
  <b>Define</b>
  <ul>
    <code>
    define &lt;name&gt; MbusDevice &lt;IODev&gt; [PRIMARY_ADDRESS|SECONDARY_ADDRESS]
    </code>
    <br/><br/>

    Example:
    <ul>      
      <code>
      define MyMbusNetwork MbusNetwork 192.168.123.199:5000 TCP <br/>
      define MyMbusDevice1 MyMbusNetwork 42 <br/>
      define MyMbusDevice2 MyMbusNetwork #FF12345678 <br/>
      </code>    
    </ul>
  </ul>
  <br/>

  <a name="MbusDeviceset"></a>
  <b>Set</b>
    <ul>
      <li><a name="UseSecondaryAddress">UseSecondaryAddress 1</a><br/>
        If activated, the Attribute useSecondaryAddress will be set. Otherwise the Attribute will be deleted.<br/>
      </li>
      <li><a name="MapToBacnet">MapToBacnet 1</a><br/>
        Set the Attribute mapToBacnet will be set.<br/>
        <ul>Ranges: 1,2,1-10,12-15 (Page Ranges ;-))</ul>
      </li>
      <li><a name="Retries">Retries 3</a><br/>
        The Attribute retries will be set.<br/>
        If an Readout fails after given timeout, the Request will be Retried for X times.
      </li>
      <li><a name="RetryPause">RetryPause 5000</a><br/>
        The Attribute retryPause will be set.<br/>
        Pause for X ms after an failed Readout.
      </li>
      <li><a name="Timeout">Timeout 3000</a><br/>
        The Attribute timeout will be set.<br/>
        The Maximum Timeout in [ms] for an TimeOutException.
      </li>
      <li><a name="PollInterval">PollInterval 900</a><br/>
        The Attribute pollInterval will be set.<br/>
        To align the Interval, the popular CRON Format can be used.<br/>
        <pre><code>
                                            Allowed values    Allowed special characters   Comment

          ┌───────────── second (optional)       0-59              * , - /                     
          │ ┌───────────── minute                0-59              * , - /                     
          │ │ ┌───────────── hour                0-23              * , - /                     
          │ │ │ ┌───────────── day of month      1-31              * , - / L W ?               
          │ │ │ │ ┌───────────── month           1-12 or JAN-DEC   * , - /                     
          │ │ │ │ │ ┌───────────── day of week   0-6  or SUN-SAT   * , - / # L ?    Both 0 and 7 means SUN
          │ │ │ │ │ │
          * * * * * *
        </code></pre>
      </li>
    </ul>
  <br/>

  <a name="MbusDeviceget"></a>
  <b>Get</b> 
    <ul>  
        <li><a name="ReadMeter">ReadMeter [NAME|ADDRESS|SEC_ADDRESS] &lt;timeout=1500&gt; &lt;retries=3&gt; </a><br/>
        Reads one MBUS-Meter Records. The Default Timeout ist 1500ms.<br/>
        All running Scans on this network will be cancelled !!! <br/>
        <ul>primary address: 1</ul>
        <ul>primary address: 1 2500</ul>
        <ul>
            name    address: MyMbusMeter_1 <br/>
            If the primary address of the Meter is unique, then the Primary Addressing is used. Otherwise
            the a SlaveSelect with the secondary address is used.
        </ul>
        <br/>
      </li>
    </ul>
  <br/>
  
  <a name="MbusDevicereading"></a>
  <b>Readings</b>
  <ul>    
    <li><a name="last-scan-result">last-scan-result</a><br/>
      Contains the result of the last Scan result. On Scan start, this reading will be erased.<br/>
      The Scan result will be stored as an JsonObject string.<br/>
      <code>
      [ 
        {
          "adr": 1,
          "id": 5544332211,
          "mnf": "MBE",
          "dvt": "Energy",
          "rcc": 12
        }
      ]
      </code>
    </li>
  </ul><br/>
  
  <a name="MbusDeviceattr"></a>
  <b>Attributes</b>
  <ul>    
    <li><a name="readingList">readingList</a><br/>
      Space separated list of readings, which will be set, if the first
      argument of the set command matches one of them.</li>

    <li><a name="bacnetIndex">bacnetIndex</a><br/>
      Index for BACnet Instance number calculation. The BACnet Datapoint Instance is
      calculated with an static prefix of 2E6 + bacbetIndex*10e2 + recordNumber.
      
    </li>
      
    <li><a name="setList">setList</a><br/>
      Space separated list of commands, which will be returned upon "set name
      ?", so the FHEMWEB frontend can construct a dropdown and offer on/off
      switches. Example: attr dummyName setList on off </li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br/>

</ul>

=end html

=begin html_DE

=end html_DE

=cut
