##############################################
# $Id: 99_myUtils.pm 3287 2021-04-12 17:18:58Z sschulze $
#
# Save this file as 99_myUtils.pm, and create your own functions in the new
# file. They are then available in every Perl expression.
# History
# 2021-04-04 Korrekturformel für Temp/Humidity eingepflegt
# 2020-06-16 CLI Commandos Encoding Problem behoben
# 2020-06-18 DoTrigger für set Befehle eingeplegt um instantan Events abzuarbeiten

package main;

use strict;
use warnings;
use utf8;
use Time::HiRes qw(time);
use JSON;

sub
myUtils_Initialize($$)
{
  my ($hash) = @_;
}

# Enter you functions below _this_ line.


sub
postMqttSenMl($$$$)
{
	my ($topic, $basename, $name, $value) = @_;

	# Doppelpunkt am ende des Readings entfernen
	$name = (split(":",$name))[0];
	my $time = int( time * 1000);
	
	my @records = ();
	
	my %rec_hash = (
					'bn' => "revpi01:" . $basename . ":", 
					'bt' => $time, 
					'n' => $name, 
					'vs' => $value
				);

	push(@records, \%rec_hash);
	my $payload = JSON->new->utf8(0)->encode(\@records);
	# Send to ALL MQTT Clients ....
	fhem("set TYPE=MQTT2_CLIENT publish $topic $payload");
}

sub
mqttCommand($$$$)
{
	my ($topic, $name, $devicetopic, $event) = @_;
	
	my $session_id = (split('/', $topic))[-1];
	my $respTopic = $topic;
	$respTopic =~ s/\/req\//\/res\//g;
	my $commands = decode_json $event;
	my $command = "";
	
	for my $hashref (@{$commands}) {
		if($hashref->{n} eq "exec") 
		{
			$command = $hashref->{vs};
			my $resp = fhem("$command");
			postMqttSenMl($respTopic, $command, "exec", $resp) if defined $resp;
		}
	}
		
	return { sessionId=>$session_id, command=>$command, state=>FmtDateTime(time()) };
}

my $E0 = 0.6112; # saturation pressure at T=0 ∞C
my @ab_gt0 = (17.62, 243.12);    # T>0
my @ab_le0 = (22.46, 272.6);     # T<=0 over ice

### ** Public interface ** keep stable
# vapour pressure in kPa
sub myutils_vp($$)
{
	my ($T, $Hr) = @_;
	my ($a, $b);
	
	if ($T > 0) {
		($a, $b) = @ab_gt0;
	} else {
		($a, $b) = @ab_le0;
	}
	
	return 0.01 * $Hr * $E0 * exp($a * $T / ($T + $b));
}

### ** Public interface ** keep stable
# dewpoint in ∞C
sub
myutils_dewpoint($$)
{
	my ($T, $Hr) = @_;
	if ($Hr == 0) {
		Log(1, "Error: dewpoint() Hr==0 !: temp=$T, hum=$Hr");
		return undef;
	}
	
	my ($a, $b);
	
	if ($T > 0) {
		($a, $b) = @ab_gt0;
	} else {
		($a, $b) = @ab_le0;
	}
	
	# solve vp($dp, 100) = vp($T,$Hr) for $dp 
	my $v = log(myutils_vp($T, $Hr) / $E0);
	my $D = $a - $v;
	
	# can this ever happen for valid input?
	if ($D == 0) {
		Log(1, "Error: dewpoint() D==0 !: temp=$T, hum=$Hr");
		return undef;
	}
	
	return round($b * $v / $D, 1);
}


### ** Public interface ** keep stable
# absolute Feuchte in g Wasserdampf pro m3 Luft
sub
myutils_absFeuchte ($$)
{
	my ($T, $Hr) = @_;
	
	# 110 ?
	if (($Hr < 0) || ($Hr > 110)) {
		Log(1, "Error dewpoint: humidity invalid: $Hr");
		return "";
	}
	my $DD = myutils_vp($T, $Hr);
	my $AF  = 1.0E6 * (18.016 / 8314.3) * ($DD / (273.15 + $T));
	return round($AF, 1);
}

### Humidity correction
sub
myutils_calchumidity($$$)
{
	my ($temp, $humi, $temp2) = @_;
	
	# -> 8 g/kG
	my $abs1    = myutils_absFeuchte($temp, $humi);
	
	# -> 17 g/kG
	my $maxAbs2 = myutils_absFeuchte($temp2, 100);
	my $humi2 = $abs1 / $maxAbs2 * 100.0;
	
	return round($humi2,1);
}

1;
