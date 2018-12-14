#!/bin/bash
_input="/root/binarium/bina_old.ip"
IPT=/sbin/iptables
#$IPT -F -t droplist
$IPT -N droplist
$IPT -F droplist
$IPT -D INPUT -j droplist
$IPT -D OUTPUT -j droplist
$IPT -D FORWARD -j droplist
#$IPT -X droplist
#sleep 2

#egrep -v "^#|^$" x | while IFS= read -r ip
while IFS= read -r ip
do
#       $IPT -A INPUT -i eth0 -s $ip -j droplist
#        $IPT -A droplist -i eth0 -p tcp --dport 8884 -s $ip -j DROP
        $IPT -A droplist -i eth0 -s $ip -j DROP
done < "$_input"
# Drop it
$IPT -I INPUT -j droplist
$IPT -I OUTPUT -j droplist
$IPT -I FORWARD -j droplist

