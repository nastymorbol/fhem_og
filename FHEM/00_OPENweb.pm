##############################################
# $Id: 00_OPENweb.pm 8260 2021-05-20 03:08:42Z sschulze $
# History
# 2021-05-20 Initital commit

package main;

use strict;
use warnings;
use SetExtensions;

sub
OPENweb_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "OPENweb_Get";
  $hash->{SetFn}     = "OPENweb_Set";
  $hash->{DefFn}     = "OPENweb_Define";
  $hash->{AttrFn}    = "OPENweb_Attr";
  $hash->{AttrList}  = "disable " .
                       $readingFnAttributes;
}

###################################
sub
OPENweb_Get($$$)
{
  my ( $hash, $name, $opt, @args ) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));
  
  return undef;
  
}

###################################
sub OPENweb_isInt{
	return  ($_[0] =~/^-?\d+$/)?1:0;
}

sub OPENweb_isNotInt{
	return  ($_[0] =~/^-?\d+$/)?0:1;
}


sub
OPENweb_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "no set value specified" if(int(@a) < 1);
  
  my $cmd = shift @a;
  my @setList = ();
  
  if($cmd eq "ScanReceipes")
	{    
    $hash->{DriverReq} = "CMD:ScanReceipes";
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return undef;
  }
  push @setList, "ScanReceipes:noArg";
  
  if($cmd eq "AddReceipe")
	{    
    my $args = join ' ', @a;
    # Anlage:Interval:Name

    my @receipeData = split(':', $args, 3);
    return "Wrong syntax: use set $name AddReceipe 0001:3600:MyReceipe" if(int(@receipeData) != 3);

    my ($anlage, $interval, $receiptname) = @receipeData;

    return "Wrong syntax: use set $name AddReceipe 0001:3600:My Receipe name on OPENweb\nAnlage is not an integer value ($anlage)" if OPENweb_isNotInt($anlage);
    return "Wrong syntax: use set $name AddReceipe 0001:3600:MyReceipe\nInterval is not an integer value ($interval)" if OPENweb_isNotInt($interval);

    my $attrib = makeReadingName('rec' . int($anlage) . ' ' . $receiptname);    
    addToDevAttrList($name, $attrib);
    my %attrval = (
      Name => $receiptname,
      Interval => int($interval),
      Controller => int($anlage)
    );
    
    my $json = toJSON(\%attrval);
    my $oldVal = AttrVal($name, $attrib, "");

    #readingsSingleUpdate($hash, "my_recipe", "N: $json | O: $oldVal", 1);

    if($json ne $oldVal)
    {
      # Event triggern ... Global global ATTR myOpenWeb rec3_bla
      # $attr{$name}{$attrib} = toJSON(\%attrval);
      my $res = CommandAttr($hash, $name . " " . $attrib . " " . $json);
      #readingsSingleUpdate($hash, "my_CommandAttr", $res, 1);
      CommandSave($hash, undef);# if (AttrVal("global", "autosave", 1));
    }

    return undef;
  }
  push @setList, "AddReceipe";

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
        #$hash->{DriverReq} = $hash->{DriverReq} =~ s/CMD://r;
        $hash->{DriverReq} .= " > exec" ;
        DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
      }
    }
    
    DoTrigger($name, "DriverRes: " . $hash->{DriverRes});
  
    return undef;
  }

  if(not defined AttrVal($name,"autocreateDevices",undef) ) {
    # push @setList, "autocreateDevices";
  }
    
  return join ' ', @setList;

  return undef;
}

sub OPENweb_Attr($$$$)
{
	my ( $cmd, $name, $attrName, $attrValue ) = @_;
    
  # $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attrName/$attrValue sind Attribut-Name und Attribut-Wert
    
	if ($cmd eq "set") {
		if ($attrName eq "Regex") {
			eval { qr/$attrValue/ };
			if ($@) {
				Log3 $name, 3, "X ($name) - Invalid regex in attr $name $attrName $attrValue: $@";
				return "Invalid Regex $attrValue: $@";
			}
		}
    if ($attrName =~ "rec.*") {
      # json2nameValue('{"Interval":3600, "Controller":1, "Name":"My Receipe name on OPENweb"}')
			my $json = json2nameValue($attrValue);
      return "Error in 'Name' field ($attrValue)" if ($json->{Name} eq undef);
      return "Error in 'Interval' field ($attrValue)" if ($json->{Interval} eq undef);
      return "Error in 'Controller' field ($attrValue)" if ($json->{Controller} eq undef);
		}
	}
	return undef;
}

sub
OPENweb_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $name = shift @a;

  return "Wrong syntax: use define <name> OPENweb http[s]://ip[:port]" if(int(@a) != 2);

  $hash->{VERSION} = "2021-05-20_03:08:42";

  if(AttrVal($name,"room", undef)) {
    
  } else {
    $attr{$name}{room} = 'OPENweb';
  }

  my $type = shift @a;
  my $url = shift @a;

  if (index($url, 'http') == -1) {
    return "Wrong syntax: use define <name> OPENweb http[s]://ip[:port]";
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
#  $hash->{ObjectId} = "openweb:$ip";
  $hash->{DriverReq} = "N/A";
  $hash->{DriverRes} = "N/A";
  $hash->{STATE} = "Init";

  my $urn = getKeyValue($name . "_urn");
  if($urn)
  {
    $hash->{urn} = $urn;
  }

  return undef;
}

1;

=pod
=item helper
=item summary    OPENweb device
=item summary_DE OPENweb Ger&auml;t
=begin html

<a name="OPENweb"></a>
<h3>OPENweb</h3>
<ul>

  Define a OPENweb. A OPENweb can take via <a href="#set">set</a> any values.
  Used for programming.
  <br><br>

  <a name="OPENwebdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OPENweb &lt;URL&gt;</code>
    <br><br>

    Example:
    <ul>
      <code>define MyOPENweb OPENweb http://192.168.123.199</code><br>
      <code>set MyOPENweb AddReceipe 1:60:My Receipe</code><br>
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
    Adds or Updates an OPENweb Receipe information. <br/>
    The Receipe Infos are stored in an Attribute named after the Receipe name.
  </li>
  <li><a name="ScanReceipes"></a>
    <code>set &lt;name&gt; ScanReceipes [Interval]</code><br>
    Not implemented yet.
  </li>
  <br>

  <a name="OPENwebget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="OPENwebattr"></a>
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
