##############################################
# $Id: 00_BACnetDatapoint.pm 10366 2020-12-02 03:44:40 sschulze $
package main;

use strict;
use warnings;
use SetExtensions;
use Scalar::Util qw(looks_like_number);

sub
BACnetDatapoint_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "BACnetDatapoint_Get";
  $hash->{SetFn}     = "BACnetDatapoint_Set";
  $hash->{DefFn}     = "BACnetDatapoint_Define";
  $hash->{AttrList}  = "readingList " .
                       "disable disabledForIntervals " .
                       "pollIntervall " .
                       $readingFnAttributes;
}

###################################
sub
BACnetDatapoint_Get($$$)
{
  my ( $hash, $name, $opt, @args ) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));

  # CMD: Get Notification Classes
  if($opt eq "AllProperties")
  {    
    $hash->{DriverReq} = "CMD:Get$opt";
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    return undef;
  }

  return "unknown argument choose one of AllProperties:noArg";
}

###################################
sub
BACnetDatapoint_Set($$)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "no set value specified" if(int(@a) < 1);
  
  my $cmd = shift @a;  

  if($cmd =~ /prop_lowLimit|prop_highLimit|prop_presentValue|prop_covIncrement|prop_notificationClass/)
  {
    my $value = join ' ', @a;
    $hash->{DriverReq} = "Write Property $cmd -> $value";
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    readingsSingleUpdate($hash, $cmd, $value, 1);
    return undef;
  }
  elsif($cmd =~ /prop_outOfService|prop_alarmValue/)
  {
    my $value = shift @a;
    $hash->{DriverReq} = "Write Property $cmd -> $value";
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    readingsSingleUpdate($hash, $cmd, $value, 1);
    return undef;
  }  
  elsif($cmd eq "prop_limitEnable")
  {
    my $value = join ' ', @a;
    my $le = "";

    $hash->{DriverReq} = "Write Property $cmd -> $value";
    DoTrigger($name, "DriverReq: " . $hash->{DriverReq});

    if($value =~ /low-limit/) 
    {
      $le .= "1";
    }
    else
    {
      $le .= "0";
    }

    if($value =~ /high-limit/) 
    {
      $le .= "1";
    }
    else
    {
      $le .= "0";
    }

    readingsSingleUpdate($hash, $cmd, $value, 1);
    return undef;
  }
  elsif($cmd eq "pollIntervall")
  {
    my $value = join ' ', @a;
    
    fhem("attr $name $cmd $value");
    
    return undef;
  }
  elsif($cmd =~ /DriverRes/)
  {
    my ($rcmd, $rprop, $rval, $rerr) = @a;
    #my $value = join ' ', @a;
    $hash->{DriverRes} = join ' ', @a;
    if($rcmd eq "Write" and $rerr eq "OK")
    {
      my $bacProp = "prop_" . $rprop;
      readingsSingleUpdate($hash, $bacProp, $rval, 1);
    }

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
      if($hash->{DriverReq} !~ "exec")
      {
        $hash->{DriverReq} .= " exec" ;
      }
      DoTrigger($name, "DriverReq: " . $hash->{DriverReq});
    }

    DoTrigger($name, "DriverRes: " . $hash->{DriverRes});
  }
  elsif($cmd =~ /urn/)
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

  my @setList = ();

  push @setList, "prop_outOfService:uzsuToggle,true,false";
  push @setList, "prop_notificationClass";
  push @setList, "pollIntervall";

  if($hash->{ObjectType} =~ /analog-.*/) 
  {      
    push @setList, "prop_limitEnable:multiple-strict,low-limit,high-limit";
    push @setList, "prop_covIncrement";
    push @setList, "prop_lowLimit";
    push @setList, "prop_highLimit";
    push @setList, "prop_presentValue";
  }
  elsif($hash->{ObjectType} =~ /binary-.*/) 
  {      
    push @setList, "prop_presentValue:uzsuToggle,true,false";
    push @setList, "prop_alarmValue:uzsuToggle,true,false";
  }

  return join ' ', @setList;
  
  return undef;
}

sub
BACnetDatapoint_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  

#  Log3 $hash, 1, "Get irgendwas " . join(" ", @{$a}) . " -> " . @{$a};
  return "Wrong syntax: use define <name> BACnetDatapoint BACnetDevice ObjectId" if(int(@a) != 4);


  $hash->{VERSION} = "2020-12-02_03:44:40"

  my $name = shift @a;
  my $type = shift @a;
  my $deviceName = shift @a;
  my $objectId = shift @a;

  $objectId =~ s/AV/analog-value/;
  $objectId =~ s/AI/analog-input/;
  $objectId =~ s/AO/analog-output/;
  $objectId =~ s/BV/binary-value/;
  $objectId =~ s/BI/binary-input/;
  $objectId =~ s/BO/binary-output/;
  $objectId =~ s/MSV/multi-state-value/;
  $objectId =~ s/MSI/multi-state-input/;
  $objectId =~ s/MSO/multi-state-output/;


  my $dev_hash = $defs{$deviceName};

  return "Unknown BACnetDevice $deviceName. Please define BACnetDevice" until($dev_hash);

  $hash->{IODev} = $deviceName;
  $hash->{ObjectId} = $objectId;
  $hash->{IP} = $dev_hash->{IP};

  return "Unknown BACnetInstance in ObjectId $objectId. Please set ID:INSTANCE" if( index($objectId, ':') == -1 );
  return "Unknown BACnetObjectType in ObjectId $objectId. Please set ID:INSTANCE" if( index($objectId, ':') == -1 );

  my ($btype, $instance) = split ':', $objectId;

  return "Unknown BACnetObjectInstance in ObjectId $objectId. Please set ID:INSTANCE" until( looks_like_number($instance) );

  $hash->{Instance} = $instance;
  $hash->{ObjectType} = $btype;
  $hash->{DriverReq} = "N/A";
  $hash->{DriverRes} = "N/A";

  my $urn = getKeyValue($name . "_urn");
  if($urn)
  {
    $hash->{urn} = $urn;
  }

  if(AttrVal($name,"room",undef)) {
    
  } else {
    $attr{$name}{room} = 'BACnet,BACnet->Datapoints->' . $dev_hash->{Instance};
  }
  
  readingsSingleUpdate($hash,"state", "defined",1);
    
  return undef;
}

1;

=pod
=item BACnet
=item summary    BACnetDatapoint
=item summary_DE BACnetDatapoint Ger&auml;t
=begin html

<a name="BACnetDatapoint"></a>
<h3>BACnetDatapoint</h3>
<ul>

  Define a BACnetDatapoint. A BACnetDatapoint can take via <a href="#set">set</a> any values.
  Used for programming.
  <br><br>

  <a name="dummydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; dummy</code>
    <br><br>

    Example:
    <ul>
      <code>define myvar BACnetDatapoint BACnetDevice ObjectId</code><br>
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

<a name="BACnetDatapoint"></a>
<h3>BACnetDatapoint</h3>
<ul>

  Definiert eine BACnetDatapoint Instanz
  <br><br>

  <a name="BACnetDatapointdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; BACnetDatapoint BACnetDevice ObjectId;</code>
    <br><br>

    Beispiel:
    <ul>
      <code>define myDp BACnetDatapoint myBACnetDevice AV:10</code><br>
      <code></code><br>
    </ul>
  </ul>
  <br>

  <a name="BACnetDatapointset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;Register_For_NCO&gt; &lt;64&gt;</code><br>
    Regsitriert sich bei der NCO 64 als Empfänger <br>
    Diese Set Befehle werden erst angezeigt, wenn die vorhandenen NCO ermittelt werden konnten <br>
    Hierfür den Befehl get notificationClasses ausführen.
  </ul>
  <br>

  <a name="BACnetDatapointget"></a>
  <b>Get</b> 
    <ul>
      <li><a href="#notificationClasses">notificationClasses</a><br>
      Liest alle vorhandenen NCO aus dem Device aus</li>
      <li><a href="#alarmSummary">alarmSummary</a><br>
      Liest alle anliegenden Meldungen aus dem Gerät aus und aktualisiert die entsprechenden Readings</li>

    </ul>
    <br>

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
