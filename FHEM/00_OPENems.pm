##############################################
# $Id: 00_OPENems.pm 7280 2021-11-20 05:08:50Z sschulze $
# History
# 2021-09-11 Initital commit

package main;

use strict;
use warnings;
use SetExtensions;

sub
OPENems_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "OPENems_Get";
  $hash->{SetFn}     = "OPENems_Set";
  $hash->{DefFn}     = "OPENems_Define";
  $hash->{AttrFn}    = "OPENems_Attr";
  $hash->{AttrList}  = "disable slot-[0-9]+-.* " .
                       $readingFnAttributes;
}

###################################
sub
OPENems_Get($$$)
{
  my ( $hash, $name, $opt, @args ) = @_;
  
  return "\"get $name\" needs at least one argument" unless(defined($opt));
  
  if($opt eq "urn")
  {
    return OPENgate_UpdateInternalUrn($hash, @args);
  }

  my @setList = ();
  
  if($opt eq "ScanFupPages")
  {
    $hash->{DriverReq} = "CMD:ScanFupPages";
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return "OK";
  }
  push @setList, "ScanFupPages:noArg";

  if($opt eq "ScanTrendSlots")
  {
    $hash->{DriverReq} = "CMD:ScanTrendSlots";
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return "OK";
  }
  push @setList, "ScanTrendSlots:noArg";

  return "unknown argument choose one of " . join(' ', @setList);
  
}

###################################
sub OPENems_isInt{
	return  ($_[0] =~/^-?\d+$/)?1:0;
}

sub OPENems_isNotInt{
	return  ($_[0] =~/^-?\d+$/)?0:1;
}


sub
OPENems_Set($@)
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
        # DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
      }
    }
    
    DoTrigger($name, "DriverRes: " . $hash->{DriverRes});
  
    return undef;
  }


  if($cmd eq "AddLabelByName")
  {    
    my $labelName = shift @a;
    if(!defined $labelName || $labelName eq '')
    {
        return "Error: Label name must have an value like 'zeit.f:E06'"
    }
    
    my ($fupPage, $label) = split(':', $labelName);
    if(!defined $fupPage || $fupPage eq '')
    {
        return "Error: Label name must have an value like 'zeit.f:E06'. FupPage part is not set"
    }
    if(!defined $label || $label eq '')
    {
        return "Error: Label name must have an value like 'zeit.f:E06'. Label part is not set"
    }
    
    $hash->{DriverReq} = "CMD:AddLabelByName " . $labelName;
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return undef;
  }
  
  push @setList, "AddLabelByName";   
  return join ' ', @setList;
}

sub OPENems_Attr($$$$)
{
	my ( $cmd, $name, $attrName, $attrValue ) = @_;
    
  # $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attrName/$attrValue sind Attribut-Name und Attribut-Wert
    
	if ($cmd eq "set") {
    if ($attrName =~ "slot_.*_name") {
      # json2nameValue('{"Interval":3600, "Controller":1, "Name":"My Receipe name on OPENems"}')
			#my $json = json2nameValue($attrValue);
      #return "Error in 'Name' field ($attrValue)" if (not $json->{Name});
      #return "Error in 'Interval' field ($attrValue)" if (not $json->{Interval});
      #return "Error in 'Controller' field ($attrValue)" if (not $json->{Controller});
		}
	}
	return undef;
}

sub
OPENems_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $name = shift @a;

  return "Wrong syntax: use define <name> OPENems http[s]://ip[:port]" if(int(@a) != 2);

  $hash->{VERSION} = "2021-11-20_05:08:50";

  if(AttrVal($name,"room", undef)) {
    
  } else {
    $attr{$name}{room} = 'OPENems';
  }

  my $type = shift @a;
  my $url = shift @a;

  if (index($url, 'http') == -1) {
    return "Wrong syntax: use define <name> OPENems http[s]://ip[:port]";
  }

  if(substr($url, -1) eq "/")
  {
    $url = substr($url, 0, -1);
  }
  
  my $ipIndex = rindex($url, ':');
  if ($ipIndex < 7) {
    if (index($url, 'https://') == -1) {
      $url .= ":80";
    }
    else {
      $url .= ":443";
    }    
  }
  my $ip = substr($url, index($url, ':') +3);
  
  $hash->{URL} = $url;
  $hash->{IP} = $ip;
  $hash->{DriverReq} = "N/A";
  $hash->{DriverRes} = "N/A";
  $hash->{STATE} = "Init";

  OPENgate_InitializeInternalUrn($hash);

  return undef;
}

1;

=pod
=item helper
=item summary    OPENems device
=item summary_DE OPENems Ger&auml;t
=begin html

<a name="OPENems"></a>
<h3>OPENems</h3>
<ul>

  Define a OPENems. A OPENems can take via <a href="#set">set</a> any values.
  Used for programming.
  <br><br>

  <a name="OPENemsdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OPENems &lt;URL&gt;</code>
    <br><br>

    Example:
    <ul>
      <code>define MyOPENems OPENems http://192.168.123.199</code><br>
      <code>set MyOPENems ScanTrendSlots</code><br>
    </ul>
  </ul>
  <br>

  <b>Set</b>
  <li><a name="ScanTrendSlots"></a>
    <code>set &lt;name&gt; ScanTrendSlots</code><br>
    Scans all Trend Slots Configruations in the OPENems Controller.
    All Slots will be configured threw Attributes
    
  </li>
  <br>

  <a name="OPENemsget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="OPENemsattr"></a>
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
