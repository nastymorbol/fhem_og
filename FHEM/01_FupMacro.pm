##############################################
# $Id: 01_FupMacro.pm 5902 2021-11-05 20:11:50Z sschulze $
# History
# 2021-11-05 Initital commit

package main;

use strict;
use warnings;
use SetExtensions;

sub
FupMacro_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "FupMacro_Get";
  $hash->{SetFn}     = "FupMacro_Set";
  $hash->{DefFn}     = "FupMacro_Define";
  $hash->{AttrFn}    = "FupMacro_Attr";
  $hash->{AttrList}  = "disable labels " .
                       "pollIntervall " .
                       $readingFnAttributes;
}

###################################
sub
FupMacro_Get($$$)
{
  my ( $hash, $name, $opt, @args ) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));
  
  return undef;
  
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

  if($cmd eq 'pollIntervall')
  {
    my $value = join ' ', @a;
    
    fhem("attr $name $cmd $value");
    
    return undef;
  }
  push @setList, "pollIntervall";

  return join ' ', @setList;

  return undef;
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
    if ($attrName eq "pollIntervall") {
      $_[3] = 300 if(FupMacro_isInt($attrValue)==0);
      $_[3] = 300 if($attrValue > 0 && $attrValue < 30);
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

  return "Wrong syntax: use define <name> FupMacro <OPENems>" if(int(@a) != 2);

  $hash->{VERSION} = "2021-11-05_20:11:50";

  my $type = shift @a;
  my $iodev = shift @a;

  if(!defined($defs{$iodev})) 
  {
    return "Wrong syntax: use define <name> FupMacro <OPENems>. The Device '$iodev' doesn't exist";
  }

  if(!defined(AttrVal($name,"room", undef))) {
    $attr{$name}{room} = "FupMacros->" . $iodev;
  }

  $hash->{DriverReq} = "N/A";
  $hash->{DriverRes} = "N/A";
  $hash->{STATE} = "Init";
  $hash->{IODev} = $iodev;
  
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
