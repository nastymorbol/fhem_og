##############################################
# $Id: 99_myUtils.pm 1617 2020-12-02 03:44:40 sschulze $
#
# Save this file as 99_myUtils.pm, and create your own functions in the new
# file. They are then available in every Perl expression.
# History
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

1;
