##############################################
# $Id: 00_BACnetNetwork.pm 7863 2023-04-19 12:46:24Z sschulze $
# History
# 2021-04-12 DriverReq wurde immer wieder neu getriggert
#            Get für ScanNetwork entfernt
# 2021-03-10 DriverRes wird nicht mehr getrieggert

package main;

use strict;
use warnings;
use SetExtensions;

sub
BACnetNetwork_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "BACnetNetwork_Get";
  $hash->{SetFn}     = "BACnetNetwork_Set";
  $hash->{DefFn}     = "BACnetNetwork_Define";
  $hash->{AttrList}  = "readingList setList " .
                       "disable disabledForIntervals " .
                       "ip port deviceInstance autocreateDevices " .                       
                       $readingFnAttributes;
}

###################################
sub
BACnetNetwork_Get($$$)
{
  my ( $hash, $name, $opt, @args ) = @_;
  
  return "\"get $name\" needs at least one argument" unless(defined($opt));
  
  if($opt eq "urn")
  {
    return OPENgate_UpdateInternalUrn($hash, @args);
  }
  
  return undef;
  #return "unknown argument choose one of ScanNetwork:noArg";

}

###################################
sub
BACnetNetwork_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "no set value specified" if(int(@a) < 1);
  
  my $cmd = shift @a;
  my @setList = ();
  
  if($cmd eq "ScanNetwork")
	{    
    $hash->{DriverReq} = "CMD:GetScanNetwork";
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return undef;
  }

  if($cmd eq "ip") {
    my $ip = shift @a;
  
    if (index($ip, ':') == -1) {
      $ip .= ":47808";
    }          
    $hash->{IP} = $ip;
    
    return undef;
  } 
  
  if($cmd eq "instance") {
    $hash->{Instance} = shift @a;    
    return undef;
  }   
  
  if($cmd eq "autocreateDevices") {
    $attr{$name}{autocreateDevices} = 1;
    return undef;
  }   
  
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
    return undef;
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

    #if($rcmd eq "Write" and $rerr eq "OK")
    #{
    #  my $bacProp = "prop_" . $rprop;
    #  readingsSingleUpdate($hash, $bacProp, $rval, 1);
    #}

    
    DoTrigger($name, "DriverRes: " . $hash->{DriverRes});
  
    return undef;
  }

  if(not defined AttrVal($name,"autocreateDevices",undef) ) {
    push @setList, "autocreateDevices";
  }
    
  push @setList, "ScanNetwork:noArg";
  return join ' ', @setList;

  #readingsSingleUpdate($hash,"state",$v,1);
  return undef;
}

sub
BACnetNetwork_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $name = shift @a;

  return "Wrong syntax: use define <name> BACnetNetwork DeviceInstance IP[:Port]" if(int(@a) != 3);

  $hash->{VERSION} = "2023-04-19_12:46:24";

  if(AttrVal($name,"room",undef)) {
    
  } else {
    $attr{$name}{room} = 'BACnet,BACnet->Networks';
  }

  my $type = shift @a;
  my $instance = shift @a;
  my $ip = shift @a;
  
  if (index($ip, ':') == -1) {
    $ip .= ":47808";
  }  
  
  $hash->{Instance} = $instance;
  $hash->{IP} = $ip;
  $hash->{ObjectId} = "device:$instance";
  $hash->{DriverReq} = "N/A";
  $hash->{DriverRes} = "N/A";

  OPENgate_InitializeInternalUrn($hash);

  return undef;
}

1;

=pod
=item helper
=item summary    BACnetNetwork device
=item summary_DE BACnetNetwork Ger&auml;t
=begin html

<a name="BACnetNetwork"></a>
<h3>BACnetNetwork</h3>
<ul>

  Define a BACnetNetwork. A BACnetNetwork can take via <a href="#set">set</a>.
  Used for programming.
  <br><br>

  <a name="dummydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; BACnetNetwork DeviceInstance IP[:Port]</code>
    <br><br>

    Example:
    <ul>
      <code>define MyBACnetNetwork BACnetNetwork 6378 192.168.178.54:47808</code><br>
      <code>set myvar 7</code><br>
    </ul>
  </ul>
  <br>

  <a name="dummyset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt</code><br>
    Set any value.
  </ul>
  <br>

  <a name="dummyget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="dummyattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
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

<a name="dummy"></a>
<h3>dummy</h3>
<ul>

  Definiert eine Pseudovariable, der mit <a href="#set">set</a> jeder beliebige
  Wert zugewiesen werden kann.  Sinnvoll zum Programmieren.
  <br><br>

  <a name="dummydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; dummy</code>
    <br><br>

    Beispiel:
    <ul>
      <code>define myvar dummy</code><br>
      <code>set myvar 7</code><br>
    </ul>
  </ul>
  <br>

  <a name="dummyset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt</code><br>
    Weist einen Wert zu.
  </ul>
  <br>

  <a name="dummyget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="dummyattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a name="readingList">readingList</a><br>
      Leerzeichen getrennte Liste mit Readings, die mit "set" gesetzt werden
      k&ouml;nnen.</li>

    <li><a name="setList">setList</a><br>
      Liste mit Werten durch Leerzeichen getrennt. Diese Liste wird mit "set
      name ?" ausgegeben.  Damit kann das FHEMWEB-Frontend Auswahl-Men&uuml;s
      oder Schalter erzeugen.<br> Beispiel: attr dummyName setList on off </li>

    <li><a name="useSetExtensions">useSetExtensions</a><br>
      Falls gesetzt, und setList enth&auml;lt on und off, dann die <a
      href="#setExtensions">set extensions</a> Befehle sind auch aktiv.  In
      diesem Fall werden nur die Befehle aus setList und die set exensions
      akzeptiert.</li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html_DE

=cut
