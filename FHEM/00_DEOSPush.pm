##############################################
# $Id: 98_dummy.pm 16965 2018-07-09 07:59:58Z rudolfkoenig $
package main;

use HttpUtils;
#use JSON::Create 'create_json';
use JSON;
use boolean;
use strict;
use warnings;
#use utf8;
use Encode;

sub
DEOSPush_Initialize($)
{
  my ($hash) = @_;
    
  $hash->{NOTIFYDEV} =  "TYPE=BACnetDevice";
  $hash->{NotifyFn}  =  "DEOSPush_Notify";
  $hash->{SetFn}     =  "DEOSPush_Set";
  $hash->{DefFn}     =  "DEOSPush_Define";
  $hash->{AttrList}  =  "disable disabledForIntervals " .
                        "reporterId token serverId serverName " .
                       $readingFnAttributes;
}

###################################
sub
DEOSPush_Set($@)
{
  my ( $hash, $name, $cmd, @args ) = @_;
	my $cmdList = "message message_payload";

	return "\"set $name\" needs at least one argument" unless(defined($cmd));

  my $reporterId = AttrVal($name, "reporterId", undef);
  my $token = AttrVal($name, "token", undef);
  my $serverId = AttrVal($name, "serverId", undef);
  my $serverName = AttrVal($name, "serverName", undef);
  
  if($cmd eq "token")
  {
    $attr{$name}{token} = $args[0];
    return undef;
  }
  elsif($cmd eq "reporterId")
  {
    $attr{$name}{reporterId} = $args[0];
    return undef;
  }
  elsif($cmd eq "serverId")
  {
    $attr{$name}{serverId} = join ' ', @args;
    return undef;
  }
    elsif($cmd eq "serverName")
  {
    $attr{$name}{serverName} = join ' ', @args;
    return undef;
  }

  return "reporterId" unless(defined($reporterId));
  return "token" unless(defined($token));
  return "serverId" unless(defined($serverId));
  return "serverName" unless(defined($serverName));
  
  my %payload = 
    (
      reporterId => $reporterId,
      token => $token,
      events => []
    );

	if($cmd eq "message")
	{    
		# Sende Nachricht ...
    return "Es müssen wenigstens StateText und Nachricht angeben werden (Normal Pumpe)" if(int(@args) < 2);
      
    my $stateText = shift @args;
    my $msg = join( ' ', @args );

    readingsSingleUpdate($hash,"state", "Send Message ..." ,1);

    my $event = {
          dateTime => time() * 1000,
          state => false,
          stateText => $stateText,
          message => $msg,
          serverId => "0000",
          controllerId => "0",
          controllerGroupId => "0",
          serverName => "DEOS BACnet Push Gateway",
          controllerGroupName => "TestDeviceGroup",
          controllerName => "TestDevice"
        };
    
    # Perl halt ....
    push( (@{$payload{events}}) , $event);

    #my $JSON = JSON->new->utf8(1);
    my $JSON = JSON->new->latin1(1);
    $JSON->convert_blessed(1);
    #my $data = encode_json(%payload); #
    my $data = $JSON->encode (\%payload); #
    #$data = encode("cp1252", $data);    
    # $data = encode("UTF-8", $data);
    # from_to($data, "UTF-8", "cp1252", Encode::FB_QUIET);

    #return "JSON Daten (): " . $data;

    my $param = {
                  url         => "https://push01.deos-ag.com/pushEvents",
                  timeout     => 5,
                  hash        => $hash,                                          # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                  method      => "POST",                                         # Lesen von Inhalten
                  header      => "Content-Type:application/json;charset=UTF-8",                # ;charset=utf-8
                  data        => $data,
                  httpversion => "1.1",
                  callback   => \&DeosPush_Callback
                };

    HttpUtils_NonblockingGet($param);                               # Starten der HTTP Abfrage. Es gibt keinen Return-Code. 

	}
	elsif($cmd eq "message_payload")
	{
		# Nachrichten werden als JSON Objekt entgegen genommen ...
    readingsSingleUpdate($hash,"state", "Send JSON Message ..." ,1);

    my $json_text = join(' ', @args);

    #my $JSON = JSON->new->utf8(1);
    my $JSON = JSON->new->latin1(1);
    $JSON->convert_blessed(1);

    my @events = ();

    eval {
      @events = $JSON->decode ($json_text);
      1;
    } or do {
      Log3 $hash, 3, "Error beim parsen des JSON-Objektes > " . $json_text;
      return "Error beim parsen des JSON-Objektes > " . $json_text ;
    };

    %payload = 
    (
      reporterId => $reporterId,
      token => $token,
      events => @events
    );

    $json_text = $JSON->encode (\%payload);
    
    readingsSingleUpdate($hash, "lastMessage", $json_text, 0);
    #$hash->{READINGS}{lastMessage}{VAL} = "Message:\n" . $json_text;

    # Keine Meldungen versenden!!!
    if( IsDisabled($name) )
    {
      readingsSingleUpdate($hash,"state", "Send JSON Message ... disabled" ,1);
      return undef;
    }

    my $param = {
                  url         => "https://push01.deos-ag.com/pushEvents",
                  timeout     => 5,
                  hash        => $hash,                                          # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                  method      => "POST",                                         # Lesen von Inhalten
                  header      => "Content-Type:application/json;charset=UTF-8",
                  data        => $json_text,
                  httpversion => "1.1",
                  callback   => \&DeosPush_Callback
                };

    Log3 $hash, 2, "JSON Text > " . $json_text;

    HttpUtils_NonblockingGet($param);                               # Starten der HTTP Abfrage. Es gibt keinen Return-Code. 

	}
  else 
  {
    return $cmdList;
  }
	
  return undef;
}

########################## Notify BACnet Messages
sub 
DEOSPush_Notify($$)
{
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME}; # own name / hash

  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled

  my $devName = $dev_hash->{NAME}; # Device that created the events

  my $events = deviceEvents($dev_hash,1);
  return if( !$events );

  my @events = [];

  foreach my $event (@{$events}) {
    next if(!defined($event));
    next if( $dev_hash->{TYPE} ne "BACnetDevice");

    # Examples:
    # $event = "readingname: value" 
    # or
    # $event = "INITIALIZED" (for $devName equal "global")
    #
    # processing $event with further code

    # readingsSingleUpdate($own_hash, "notifyData", $event, 1);
    my @args = split ' ', $event;

    my $reading = shift @args;
    next if($reading !~ '.*_event');

    
    # Log3 $own_hash, 1, "Device: $devName Event: " . join ' ', @args;
    # fhem("set $ownName message " . join ' ', @args);
  }
}

sub 
DeosPush_Callback($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    
    if($err ne "")                                                                                                      # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        Log3 $name, 3, "error while requesting ".$param->{url}." - $err";                                               # Eintrag fürs Log
        readingsSingleUpdate($hash, "state", "ERROR " . $err, 1);                                                       # Readings erzeugen
    }
    elsif($data ne "")                                                                                                  # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
    {
        Log3 $name, 3, "url ".$param->{url}." returned: $data";                                                         # Eintrag fürs Log

        # An dieser Stelle die Antwort parsen / verarbeiten mit $data
        readingsSingleUpdate($hash, "state", $data, 1);                                                          # Readings erzeugen
    }
    else
    {
        Log3 $name, 4, "url ".$param->{url}." returned: OK";                                                         # Eintrag fürs Log
        readingsSingleUpdate($hash, "state", "Message send OK ". FmtDateTime(time()), 1);                                                     # Readings erzeugen
    }

    # Damit ist die Abfrage zuende.
    # Evtl. einen InternalTimer neu schedulen
}

sub
DEOSPush_Define($$)
{
  my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

  return "Wrong syntax: use define <name> DEOSPush" if(int(@a) != 2);

  my $name = $hash->{NAME};

  if(AttrVal($name,"room",undef)) {
    
  } else {
    $attr{$name}{room} = 'BACnet';
  }

  return undef;
}

1;

=pod
=item helper
=item summary    dummy device
=item summary_DE dummy Ger&auml;t
=begin html

<a name="dummy"></a>
<h3>dummy</h3>
<ul>

  Define a dummy. A dummy can take via <a href="#set">set</a> any values.
  Used for programming.
  <br><br>

  <a name="dummydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; dummy</code>
    <br><br>

    Example:
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
