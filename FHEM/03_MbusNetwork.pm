##############################################
# $Id: 03_MbusNetwork.pm 8984 2022-07-09 00:41:45Z sschulze $
# History
# 2022-01-25 Initital commit

package main;

use strict;
use warnings;

sub
MbusNetwork_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "MbusNetwork_Get";
  $hash->{SetFn}     = "MbusNetwork_Set";
  $hash->{DefFn}     = "MbusNetwork_Define";
  $hash->{AttrFn}    = "MbusNetwork_Attr";
  $hash->{AttrList}  = "disable autocreate " . $readingFnAttributes;;
}

sub
MbusNetwork_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $name = shift @a;

  return "Wrong syntax: use define <name> MbusNetwork ip:port [TCP|UDP]" if(int(@a) < 2);

  $hash->{VERSION} = "2022-07-09_00:41:45";

  if(not defined AttrVal($name,"room", undef)) {
    $attr{$name}{room} = 'MbusNetwork';
  }

  my $type = shift @a;
  my $url = shift @a;
  my $protocol = shift @a;
  
  $protocol = "TCP" if(not defined($protocol));
  $protocol = uc $protocol;
  
  my $colonIndex =index($url, ':'); 
  if ($colonIndex == -1) {
    return "Wrong syntax: use define <name> MbusNetwork ip:port";
  }

  $hash->{URL} = $url;
  $hash->{IP} = substr($url, 0, $colonIndex);
  $hash->{PORT} = substr($url, $colonIndex +1);
  $hash->{PROTOCOL} = $protocol;
  $hash->{DriverReq} = "N/A";
  $hash->{DriverRes} = "N/A";
  $hash->{STATE} = "Init";

  OPENgate_InitializeInternalUrn($hash);

  return undef;
}

###################################
sub
MbusNetwork_Get($$$@)
{
  my ( $hash, $name, $opt, @args ) = @_;
  
  #return "$hash -> $name -> $opt, " . join("|", @args);
  
  return "\"get $name\" needs at least one argument" unless(defined($opt));
  
  if($opt eq "urn")
  {
    return OPENgate_UpdateInternalUrn($hash, @args);
  }

  my @setList = ();
  
  if($opt eq "ScanMeter")
  {
    $hash->{DriverReq} = "CMD:ScanMeter";
    if(@args)
    {
      $hash->{DriverReq} .= " " . join(' ', @args);
    }
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return "OK";
  }
  push @setList, "ScanMeter";

  if($opt eq "CreateMeter")
  {
    $hash->{DriverReq} = "CMD:CreateMeter";
    if(@args)
    {
      $hash->{DriverReq} .= " " . join(' ', @args);
    }
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return "OK";
  }
  push @setList, "CreateMeter";
  
  if($opt eq "ReadMeter")
  {
    $hash->{DriverReq} = "CMD:ReadMeter";
    if(@args)
    {
      $hash->{DriverReq} .= " " . join(' ', @args);
    }
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return "OK";
  }
  push @setList, "ReadMeter";
  
  if($opt eq "CancelScanMeter")
  {
    $hash->{DriverReq} = "CMD:CancelScanMeter";
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return "OK";
  }
  push @setList, "CancelScanMeter:noArg";
  
  
  return "unknown argument choose one of " . join(' ', @setList);
}

sub
MbusNetwork_Set($@)
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


  if($cmd eq "AutoCreate")
  {
    my $value = join ' ', @a;
    if($value eq "" || $value eq "0")
    {
      fhem("deleteattr $name autocreate");
      return(undef);
    }
    fhem("attr $name autocreate 1");
    return(undef);
  }
  
  push @setList, "AutoCreate";   
  return join ' ', @setList;
}

sub MbusNetwork_Attr($$$$)
{
	my ( $cmd, $name, $attrName, $attrValue ) = @_;
    
    # $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attrName/$attrValue sind Attribut-Name und Attribut-Wert
    
	if ($cmd eq "set") {
      if ($attrName =~ "autocreate") 
      {
        $_[3] = 1;
      }
	}
	return undef;
}

###################################
sub MbusNetwork_isInt{
  return  ($_[0] =~/^-?\d+$/)?1:0;
}

sub MbusNetwork_isNotInt{
  return  ($_[0] =~/^-?\d+$/)?0:1;
}

1;

=pod
=item helper
=item summary    MbusNetwork device
=item summary_DE MbusNetwork Ger&auml;t
=begin html

<a name="MbusNetwork"></a>
<h3>MbusNetwork</h3>
<ul>

  Define a MbusNetwork. The Network describes the Physical connection to the Mbus Gateway or Interface converter. 
  At the Moment, only TCP or UDP connections are available. Serial Connection is technically implemented but will 
  not be public available.
  <br/><br/>

  <a name="MbusNetworkdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MbusNetwork &lt;URL&gt; [TCP|UDP]</code>
    <br/><br/>

    Example:
    <ul>
      <code>define MyMbusNetwork MbusNetwork 192.168.123.199:5000 TCP</code><br/>
      <code>get MyMbusNetwork ScanMeter</code><br/>
    </ul>
  </ul>
  <br/>

  <a name="MbusNetworkset"></a>
  <b>Set</b>
    <ul>
      <li><a name="AutoCreate">AutoCreate 1</a><br/>
        If activated, all not existing NBUS-Devices will be created on Scan.<br/>
      </li>
    </ul>
  <br/>

  <a name="MbusNetworkget"></a>
  <b>Get</b> 
    <ul>  
      <li><a name="ScanMeter">ScanMeter [timeout] [range]</a><br/>
          Scans all MBUS-Meter. The Default Timeout ist 1500ms.<br/>
          If the value for timeout is smaller then 251, this value will be interpreted as an primary Meter Address<br/>
          <ul>primary   address range: 1,2,1-10,30-40</ul>
          <ul>primary   address range: 2500 1,2,1-10,30-40 (Page Ranges ;-))</ul>
          <ul>secondary address range: #FF000000</ul>
          <br/>
          Secondary Address is the Start Range
      </li>
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
      <li><a name="CreateMeter">AutoCreate 1</a><br/>
        Creates all not existing MBUS-Devices from scan-result.<br/>
        If the primary address of the MBUS-Device ist NOT unique, the attribute useSecondaryAddress will be set to 1.<br/>
      </li>
      <li><a name="CancelScanMeter">CancelScanMeter</a><br/>
          Cancels an running Meter Scan
      </li>
    </ul>
  <br/>
  
  <a name="MbusNetworkreading"></a>
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
  
  <a name="MbusNetworkattr"></a>
  <b>Attributes</b>
  <ul>    
    <li><a name="readingList">readingList</a><br/>
      Space separated list of readings, which will be set, if the first
      argument of the set command matches one of them.</li>

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
