##############################################
# $Id: 00_OPENgate.pm 20491 2021-06-14 10:51:24Z sschulze $
# History
# 2021-06-14 Bug in Gateway Parameter setter
# 2021-05-20 Support for URN set
# 2021-05-03 External MQTT Driver prepare
# 2021-03-16 Perl Warning eliminated
# 2021-03-12 BACnet driver restart - timeout problem resolved
# 2021-03-12 SetCovMessage returns now immidiatialy

package main;

use strict;
use warnings;

sub
OPENgate_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "OPENgate_Set";
  $hash->{DefFn}     = "OPENgate_Define";
#  $hash->{NotifyFn}  = "OPENgate_Notify";
  no warnings 'qw';
  my @attrList = qw(
    disable
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." $readingFnAttributes";
}

###################################
sub
OPENgate_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "no set value specified" if(int(@a) < 1);
  my @setList = qw(
    gatewayId
    username
    password
    log:uzsuDropDown,active,inactive
    covMessage
    bacnetDriver
  );

  return "Unknown argument ?, choose one of " . join(" ", @setList) if($a[0] eq "?");
  
  my $prop = shift @a;

  if($prop =~ /urn/)
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
  
  if($prop eq "covMessage")
  {
    my $payload = join(" ", @a);
    if($payload)
    {
      postMqttPayload("/data/telemetry", $payload);
      readingsSingleUpdate($hash, "lastCovMessage", gettimeofday(), 1);
    }
    return undef;
  }

  if($prop eq "bacnetDriver")
  {
    #my $payload = join(" ", @a);
    return OPENgate_SshCommand($hash, "docker restart runtime_bacnetnf_1", 30, "1");
    #return undef;#$hash->{ShellCommandRes};
  }

  # Execute Shell Command ....
  if($prop eq "sh")
  {
    my $timeout = shift @a;
    if($timeout eq 'timeout') {
      $timeout = shift @a;
    }
    else{
      unshift @a, $timeout;
      $timeout = 10;
    }

    my $payload = join(" ", @a);
    return OPENgate_SshCommand($hash, $payload, $timeout, undef);
  }

  # Execut Shell Command ....
  if($prop eq "sush")
  {
    my $timeout = shift @a;
    if($timeout eq 'timeout') {
      $timeout = shift @a;
    }
    else{
      unshift @a, $timeout;
      $timeout = 10;
    }


    my $payload = join(" ", @a);
    return OPENgate_SshCommand($hash, $payload, $timeout, "1");
  }

  my $value = join(" ", @a);  

  # Konfigurationsparameter als KVP speichern
  if($prop eq $setList[0] || $prop eq $setList[1] || $prop eq $setList[2] )
  {
    my $keyName = $hash->{NAME} . "_" . $prop;
    setKeyValue($keyName, $value);
    
    return OPENgate_InitMqtt($hash);
  }

  if($prop eq "log")
  {
    return "Log driver not supported";

    if($value eq "active")
    {
      notifyRegexpChanged($hash, ".*");
      #$hash->{NOTIFYDEV} = ".*";
      $hash->{Logger} = "Start: ". gettimeofday();
      OPENgate_TimerElapsed($hash);
    }
    else
    {
      notifyRegexpChanged($hash, "global");
      #$hash->{NOTIFYDEV} = "global";
      $hash->{Logger} = "inactive";
      OPENgate_TimerElapsed($hash);
    }
    return undef;
  }

  if($prop eq "BACnetDriverVersion")
  {
    $hash->{VersionBACnetDriver} = $value;
    return undef;
  }

  # {qx(ssh deos\@host.docker.internal "bash -c 'ls /'")}

  return undef;
}

sub
OPENgate_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> OPENgate" if(int(@a) != 2);

  $hash->{NOTIFYDEV} = "global";

  $hash->{VERSION} = "2021-06-14_10:51:24";

  my $urn = getKeyValue($hash->{NAME} . "_urn");
  if($urn)
  {
    $hash->{urn} = $urn;
  }
  return undef;
}

# Notify actions
sub 
OPENgate_Notify(@) {

  my ($own_hash, $dev_hash) = @_;
	my $ownName = $own_hash->{NAME}; # own name / hash
 
	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
 
	my $devName = $dev_hash->{NAME}; # Device that created the events
	my $events = deviceEvents($dev_hash, 1);

	if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
	{
    $own_hash->{MqttClientState} = "Init";
    InternalTimer(gettimeofday() + 5, "OPENgate_TimerElapsed", $own_hash);
    $own_hash->{VersionFrontend} = ReadingsVal("DockerImageInfo", "image.version", undef);
    $own_hash->{SshPublicKey} = ReadingsVal("DockerImageInfo", "ssh-id_ed25519.pub", undef);
	}
  else
  {
    # Fixed Use of uninitialized 2020-09-24
    if($own_hash->{Logger})
    {
      if($own_hash->{Logger} ne "Inactive")
      {      
        foreach my $event (@{$events}) {
          next if(!defined($event));
          my $time = unixTimeMs();
          my $payload = "$time $devName $event";
          postMqttPayload("/data/log", $payload);
        }
      }
    }
  }

  return undef;
}

sub
OPENgate_TimerElapsed($)
{
  my ($hash) = @_;
  
  RemoveInternalTimer($hash);

  OPENgate_InitMqtt($hash);
  
  if($hash->{Logger} && $hash->{Logger} =~ /Start: /)
  {
    InternalTimer(gettimeofday() + 10, "OPENgate_TimerElapsed", $hash);
    my $logTimer = gettimeofday() - int($hash->{Logger} =~ s/Start: (.*)/$1/r);
    if($logTimer > 60)
    {
      $hash->{Logger} = "Inactive";
      $hash->{NOTIFYDEV} = "global";
    }
  }
  else
  {
      InternalTimer(gettimeofday() + 60, "OPENgate_TimerElapsed", $hash);
  }
}

sub
OPENgate_InitMqtt($)
{
  my ($hash) = @_;
  
  $hash->{MqttClientState} = "Init Start";
  readingsSingleUpdate($hash, "state", "Init", 1);

  my $gatewayId = getKeyValue($hash->{NAME} . "_gatewayId");
  my $username = getKeyValue($hash->{NAME} . "_username");
  my $password = getKeyValue($hash->{NAME} . "_password");

  $hash->{gatewayId} = $gatewayId ? "OK" : "ERROR";
  $hash->{username} = $username ? "OK" : "ERROR";
  $hash->{password} = $password ? "OK" : "ERROR";

  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged($hash, "username", $username);
  readingsBulkUpdateIfChanged($hash, "gatewayId", $gatewayId);
  readingsEndUpdate($hash, 1);
  
  readingsSingleUpdate($hash, "state", "Init done", 1);
  $hash->{MqttClientState} = "Init done";
  #return undef;
  #my $gatewayId = AttrVal("MqttClient", "clientId", undef);

  if($gatewayId && $username && $password)
  {
    return $gatewayId . " : " . $username . " : " . $password;
    my $mqttClient = $defs{MqttClient};
    if( not defined ($mqttClient))
    {
      readingsSingleUpdate($hash, "state", "Error MqttClient not found!", 1);
#      fhem("defmod MqttClient MQTT2_CLIENT rmt01.deos-ag.com:8883");
      fhem("attr MqttClient autocreate no");
      fhem("attr MqttClient room MQTT,System");      
    }

    $mqttClient = $defs{MqttClient};
    if($mqttClient)
    {
      my $mstate = ReadingsVal($mqttClient->{NAME}, "state", "0");
      if($mstate ne "opened")
      {
        my $clientId = ReadingsVal($mqttClient->{NAME}, "clientId", undef);
        if(not defined($clientId))
        {
          my $value = "gateway/$gatewayId/command/req/#";
          fhem("attr MqttClient subscriptions $value") if AttrVal("MqttClient", "subscriptions", "0") ne $value;
          
          $value = "gateway/$gatewayId/metric OFFLINE";
          fhem("attr MqttClient lwt $value") if AttrVal("MqttClient", "lwt", "0") ne $value;

          $value = "-r gateway/$gatewayId/metric ONLINE";
          fhem("attr MqttClient msgAfterConnect $value") if AttrVal("MqttClient", "msgAfterConnect", "0") ne $value;

          $value = "-r gateway/$gatewayId/metric GO OFFLINE";
          fhem("attr MqttClient msgBeforeDisconnect $value") if AttrVal("MqttClient", "msgBeforeDisconnect", "0") ne $value;
          
          $value = $gatewayId;
          fhem("attr MqttClient clientId $value") if AttrVal("MqttClient", "clientId", "0") ne $value;

          $value = "1";
          fhem("attr MqttClient SSL $value") if AttrVal("MqttClient", "SSL", "0") ne $value;

          $value = $username;
          fhem("attr MqttClient username $value") if AttrVal("MqttClient", "username", "0") ne "$value";

          fhem("set MqttClient password $password");
#          fhem("modify MqttClient rmt01.deos-ag.com:8883");
          fhem("save") if $init_done;
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged($hash, "state", "OK");
        readingsEndUpdate($hash, 1);
      }
      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged($hash, "username", $username);
      readingsBulkUpdateIfChanged($hash, "gatewayId", $gatewayId);
      readingsEndUpdate($hash, 1);
    }

    my $mqttCli = $defs{MqttCli};
    if( not defined( $mqttCli ))
    {
      readingsSingleUpdate($hash, "state", "Error MqttCli not found!", 1);
      fhem("defmod MqttCli MQTT2_DEVICE MqttClient");
      fhem("attr MqttCli IODev MqttClient");
      fhem("attr MqttCli room MQTT,System");      
    }

    $mqttCli = $defs{MqttCli};
    if($mqttCli)
    {
      # Fixed Use of uninitialized 2020-09-24
      my $attrVal = AttrVal("MqttCli", "readingList", "0");      
      if($attrVal ne "gateway/$gatewayId/command/req.* { mqttCliCommand(\$TOPIC, \$NAME, \$DEVICETOPIC, \$EVENT) }")
      {
  	    fhem("attr MqttCli readingList gateway/$gatewayId/command/req.* { mqttCliCommand(\$TOPIC, \$NAME, \$DEVICETOPIC, \$EVENT) }");
        fhem("save") if $init_done;
        readingsSingleUpdate($hash, "state", "OK", 1);
      }
    }
    else
    {
      readingsSingleUpdate($hash, "state", "Error MqttCli not found!", 1);
      return "Error MqttCli not found!";
    }

    readingsSingleUpdate($hash, "state", "OK", 0);
    $hash->{MqttClientState} = "OK";
    return undef;
  }
  else
  {
    #my $mqttClient = $defs{MqttClient};
    #if($mqttClient)
    #{
    #  $gatewayId = AttrVal($mqttClient->{NAME}, "clientId", undef);
    #  if($gatewayId)
    #  {
    #    Log3($hash->{NAME}, 1, "OPENgate nicht konfiguriert - Versuche gatewayId MQTT zu ermitteln");
    #    setKeyValue($hash->{NAME} . "_gatewayId", $gatewayId);        
    #  }
    #  
    #  $username = AttrVal($mqttClient->{NAME}, "username", undef);
    #  if($username)
    #  {
    #    Log3($hash->{NAME}, 1, "OPENgate nicht konfiguriert - Versuche username MQTT zu ermitteln");
    #    setKeyValue($hash->{NAME} . "_username", $username);        
    #  }
    #  
    #  $password = getKeyValue($mqttClient->{NAME});
    #  if($password)
    #  {
    #    Log3($hash->{NAME}, 1, "OPENgate nicht konfiguriert - Versuche password MQTT zu ermitteln");
    #    setKeyValue($hash->{NAME} . "_password", $password);        
    #  }
    #}
  }

	#fhem("attr MqttClient subscriptions gateway/$gatewayId/command/req/#") if($gatewayId);
	#fhem("attr MqttClient lwt gateway/$gatewayId/metric OFFLINE") if($gatewayId);
	#fhem("attr MqttCli readingList gateway/$gatewayId/command/req.* { mqttCliCommand(\$TOPIC, \$NAME, \$DEVICETOPIC, \$EVENT) }") if($gatewayId);

  readingsSingleUpdate($hash, "state", "Error", 1);

  return "Error - GatewayId not set" if(not defined($gatewayId));
  return "Error - Username not set" if(not defined($username));
  return "Error - Password not set" if(not defined($password));

  return undef;
}

# ------------ SHELL COMMANDS -------------

sub
OPENgate_SshCommand(@)
{
  my ($hash, $command, $timeout, $sudo) = @_;  
  if(defined($sudo))
  {
    my $qxcmd = "ssh -i /opt/fhem/.ssh/id_ed25519 deos\@host.docker.internal \"sudo bash -c \'$command\'\"";
    $hash->{ShellCommand} = $command;
    my @result = exec_safe($qxcmd, $timeout, 3);
    my $ret = pop(@result);
    $hash->{ShellCommandRes} = join("\n", @result); #qx($qxcmd);
    $hash->{ShellCommandRetCode} = $ret;
  }
  else
  {
    my $qxcmd = "ssh -i /opt/fhem/.ssh/id_ed25519 deos\@host.docker.internal \"bash -c \'$command\'\"";
    $hash->{ShellCommand} = $command;    
    my @result = exec_safe($qxcmd, $timeout, 3);
    my $ret = pop(@result);
    $hash->{ShellCommandRes} = join("\n", @result); #qx($qxcmd);
    $hash->{ShellCommandRetCode} = $ret;
  }
  return $hash->{ShellCommandRes};
}

sub exec_safe {
	my ($command, $timeout, $nice_val) = @_;
	my @return_val;
	eval {
		local $SIG{ALRM} = sub { die "Timeout\n" };
		alarm $timeout;
		@return_val= `nice -n $nice_val $command 2>&1`;
		alarm 0;
	};
	if($@) { # If command fails, return non-zero and msg
		die unless $@ eq "Timeout\n";   # propagate unexpected errors
		return ("Command timeout", 1);
	} else {
    my $ret = $?;
    if($ret == -1) {
  		chomp @return_val; push(@return_val, 0);
    }
    else {
  		chomp @return_val; push(@return_val, $? >> 8);
    }
		return @return_val;
	}
}

# ------------ START COMMAND CLI -------------

sub
mqttCliCommand($$$$)
{
	my ($topic, $name, $devicetopic, $event) = @_;
			
	# Die lezten beiden Parts des Topics sind die Session und Command id
	my $session_id = join("/", (split('/', $topic))[-2,-1] );
	my $respTopic = "command/res/$session_id";   #$topic;
		
	my $request = eval { decode_json($event) };
	if ($@)
	{
		return { sessionId=>$session_id, error=>$@, command=>$event, state=>"Error " . FmtDateTime(time()) };
	}
	
	# Requests mit dem Ziel FHEM Enviroment
	if(not exists($request->{type}))
	{
		return { sessionId=>$session_id, error=>"Command has no type field", command=>$event, state=>"Error " . FmtDateTime(time()) };
	}
	
	# ToDo: Prüfen ob Version passt
	if($request->{type} eq "env")
	{
	
		my $response = buildBasicResponse($request);

		executeResponseCommands($response);

		if($request->{ts})
		{
			$response->{ts_req} = $request->{ts};
			$response->{ts_res} = unixTimeMs();
		}
		
		my $payload = JSON->new->utf8(1)->encode($response);

		# Direct call to MQTT2 Clients
		postMqttPayload($respTopic, $payload);
		
		return { payload=>length($payload), sessionId=>$session_id, command=>$event, error=>undef, state=>"OK " . FmtDateTime(time()) };
	}
			
	return { sessionId=>$session_id, error=>"Command Type $request->{type} not valid", command=>$event, state=>"Error " . FmtDateTime(time()) };
}

sub
executeResponseCommands(@)
{
	my $response = $_[0];
	
	$response->{ver} = "1.0";
	
	# Commands ausführen wenn vorhanden
	if($response->{commands})
	{				
		while ( my ($key, $value) = each( @{$response->{commands}} ) ) 
		{
			my $cmd = $value->{name};

			# ToDo: Prüfen ob ein Fehler auftritt eval?
			my $exec = fhem($cmd);
			
			my ($command, $device, $data) = split(" ", $cmd);
			
			DoTrigger($device, undef) if($command eq "set");
			
			# Try to decode as json Resonse
			my $jsonres = eval { decode_json($exec) };
			if ($@)
			{
				$value->{resp} = $exec;		
			}
			else {
				$value->{resp} = $jsonres;
			}
		}
	}
	else
	{
		# Keine Commandos definiert - PING request
		$response->{resp} = {
			ping => unixTimeMs()
		}
	}

	
	return 0;
}

sub
buildBasicResponse
{	
	my $request = $_[0];
	
	my $response = {};
	$response->{type} = $request->{type};;	
	
	# ToDo: Doppelte Kommandos entfernen
	if($request->{command})
	{
		$response->{commands} = ();
		push(@{$response->{commands}}, buildResponseCommand($request->{command}));
	}
	
	if($request->{commands})
	{
		$response->{commands} = () unless($response->{commands});
		
		while ( my ($key, $value) = each( @{$request->{commands}} ) ) 
		{
			push(@{$response->{commands}}, buildResponseCommand($value));
		}
	}

	return $response;
}

sub
buildResponseCommand($)
{
	return {
		name => shift,
		resp => undef
	};
}

sub
unixTimeMs()
{
	return int( time * 1000 );
}

# ------------ END COMMAND CLI ---------------

# ============================================
# ------------ START MQTT HELPER -------------

sub
postMqttPayload($$)
{
	my ($subChannel, $payload) = @_;
	
	my $channel = getGatewayChannel($subChannel);
	return undef unless $channel;
	
	# Direct call to MQTT2 Clients
	foreach my $dev (devspec2array("TYPE=MQTT2_CLIENT")) {
		next unless $dev;		
		MQTT2_CLIENT_doPublish($defs{$dev}, $channel, $payload, 0);
	}
}

sub
getGatewayChannel($)
{
	# DeviceId -> Die DeviceID ist auch die ClientId des MQQT_CLIENT
	
	my $clientId = getClientId();		
	if($clientId)
	{
		my $subChannel = shift;
		if($subChannel)
		{
			my $channel = "gateway/$clientId/$subChannel";
			$channel =~ s/\/{2}/\//g;
			return "$channel";
		}
		return "gateway/$clientId";
	}
	
	return undef;
}

sub
getClientId()
{
	foreach my $dev (devspec2array("TYPE=MQTT2_CLIENT")) 
	{
		next unless $dev;
		my $clientId = $attr{MqttClient}->{clientId};		
		if($clientId)
		{
			return $clientId;
		}
	}
	return undef;
}

# ------------ END MQTT HELPER ---------------

1;

=pod
=item helper
=item summary    dummy device
=item summary_DE dummy Ger&auml;t
=begin html

<a name="OPENgate"></a>
<h3>OPENgate</h3>
<ul>

  Define a OPENgate. A OPENgate can take via <a href="#set">set</a> any values.
  Used for programming.
  <br><br>

  <a name="OPENgatedefine"></a>
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

  <a name="OPENgateset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt</code><br>
    Set any value.
  </ul>
  <br>

  <a name="OPENgateget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="OPENgateattr"></a>
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
      <a href="#setExtensions">set extensions</a> are available.<br>
      Side-effect: if set, only the specified parameters are accepted, even if
      setList contains no on and off.</li>

    <li><a name="setExtensionsEvent">setExtensionsEvent</a><br>
      If set, the event will contain the command implemented by SetExtensions
      (e.g. on-for-timer 10), else the executed command (e.g. on).</li>

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
      Falls gesetzt, und setList enth&auml;lt on und off, dann sind die <a
      href="#setExtensions">set extensions</a> verf&uuml;gbar.<br>
      Seiteneffekt: falls gesetzt, werden nur die spezifizierten Parameter
      akzeptiert, auch dann, wenn setList kein on und off enth&auml;lt.</li>

    <li><a name="setExtensionsEvent">setExtensionsEvent</a><br>
      Falls gesetzt, enth&auml;lt das Event den im SetExtensions
      implementierten Befehl (z.Bsp. on-for-timer 10), sonst den
      Ausgef&uuml;rten (z.Bsp. on).</li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html_DE

=cut
