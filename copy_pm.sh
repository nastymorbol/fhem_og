#!/bin/bash

array=("FHEM"/*.pm)
for entry in "${array[@]}"
do
  file=`basename $entry`
  #echo "$file"
done

#exit 1

#array=( "03_MbusNetwork.pm" "00_OPENems.pm" "01_FupMacro.pm" "00_BACnetNetwork.pm" "01_BACnetDevice.pm" "02_BACnetDatapoint.pm" "00_OPENgate.pm" "00_OPENweb.pm" "99_myUtils.pm")
array=( "03_MbusNetwork.pm" "04_MbusDevice.pm")

user=root
#ip=192.168.123.59
ip=172.20.47.200
#ip=172.20.37.51
ip=172.20.66.215
#id="~/.ssh/test_rsa"
id="~/.ssh/id_rsa"

echo Connect $ip with cert: $id

ssh $user@$ip -i $id "sudo bash -c 'mkdir /tmp/fhem; chown -R deos:deos /tmp/fhem'"

for entry in "${array[@]}"
do
    file=`basename $entry`
    scp  -i $id FHEM/$file $user@$ip:/tmp/fhem/
    ssh $user@$ip -i $id "sudo bash -c 'mv -f /tmp/fhem/$file /docker/runtime/fhem/FHEM/$file;chown 6061:6061 /docker/runtime/fhem/FHEM/$file;cd /docker/runtime/fhem; perl fhem.pl 7072 \"reload $file\"'"
    #scp src/$file $user@$ip:/docker/runtime/fhem/FHEM    
    #ssh $user@$ip -i $id "sudo bash -c 'cd /docker/runtime/fhem; perl fhem.pl 7072 \"reload $file\"'"
done

#scp  -i $id src/entry.sh $user@$ip:/tmp/fhem/entry.sh
#ssh $user@$ip -i $id "sudo bash -c 'docker cp /tmp/fhem/entry.sh runtime_fhem_1:/entry.sh'"

# Nur aufräumen
ssh $user@$ip -i $id "sudo bash -c 'rm -Rf /tmp/fhem'"

# Reread Config ... dauert
#ssh $user@$ip -i $id "sudo bash -c 'rm -Rf /tmp/fhem; cd /docker/runtime/fhem; perl fhem.pl 7072 rereadcfg'"

#ssh $user@$ip -i $id "sudo bash -c 'cd /docker/runtime/fhem; perl fhem.pl 7072 shutdown'"