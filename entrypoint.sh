#!/bin/bash

set -e

mkdir -p /data
cd /data

#
# Interfaces fixes via docker-compose
#


UPLINK_IF=lan0      # Internet
CISCO_WAN_IF=wan0   # lien Cisco WAN
CISCO_LAN_IF=eth0   # réseau r1-lan

echo "UPLINK_IF=${UPLINK_IF}"
echo "CISCO_LAN_IF=${CISCO_LAN_IF}"
echo "CISCO_WAN_IF=${CISCO_WAN_IF}"

#LAN_IF=lan0
#WAN_IF=wan0

#
# NETMAP
#

cat > NETMAP <<EOF
${APP_ID}:0/0 $((100 + APP_ID)):0/0
${APP_ID}:0/1 $((100 + APP_ID)):0/1
EOF

#
# Sauvegarder la config du réseau LAN
#

LAN_IP=$(ip -4 -o addr show dev "${LAN_IF}" | awk '{print $4}')
LAN_GW=$(ip route | awk '/default/ {print $3}')

echo "LAN_IF=${LAN_IF}"
echo "WAN_IF=${WAN_IF}"
echo "LAN_IP=${LAN_IP}"
echo "LAN_GW=${LAN_GW}"

#
# Bridges Linux
#


ip link add br-lan type bridge 2>/dev/null || true
ip link add br-wan type bridge 2>/dev/null || true

ip link set br-lan up
ip link set br-wan up

ip link set "${CISCO_LAN_IF}" master br-lan
ip link set "${CISCO_WAN_IF}" master br-wan

ip route replace default via 192.168.167.1 dev lan0

#ip link add br-lan type bridge 2>/dev/null || true
#ip link add br-wan type bridge 2>/dev/null || true

#ip link set br-lan up
#ip link set br-wan up

#
# Attacher les interfaces Docker
#

#ip link set "${LAN_IF}" master br-lan
#ip link set "${WAN_IF}" master br-wan

#
# IMPORTANT
# Empêche Linux d'apprendre les MAC Cisco sur le mauvais port
#

bridge link set dev "${CISCO_LAN_IF}" learning off
bridge link set dev "${CISCO_WAN_IF}" learning off

#bridge link set dev "${LAN_IF}" learning off
#bridge link set dev "${WAN_IF}" learning off

#
# Déplacer l'IP management vers br-lan
#

#ip addr flush dev "${CISCO_LAN_IF}"

#ip addr add "${LAN_IP}" dev br-lan

#ip route replace default via "${LAN_GW}" dev br-lan

#
# WAN point-to-point automatique
#
# APP_ID=1
# Cisco = 172.16.255.0/31
# Linux = 172.16.255.1/31
#

CID=$(( (APP_ID - 1) * 2 ))
LID=$(( CID + 1 ))

ip addr add 172.16.255.${LID}/31 dev br-wan

#
# Internet pour le Cisco
#

sysctl -w net.ipv4.ip_forward=1

iptables -t nat -F

iptables -t nat -A POSTROUTING \
    -s 172.16.255.0/24 \
    -o "${UPLINK_IF}" \
    -j MASQUERADE

#
# Licence IOU
#

python3 /CiscoIOUKeygen3f.py

#
# Démarrage IOS
#

tmux new-session -d -s iol "/iol.bin -u 10000 ${APP_ID}"

#
# Attendre NETIO
#

until [ -S "/tmp/netio0/${APP_ID}" ]; do
    sleep 1
done

#
# Démarrage uBridge
#

tmux new-session -d -s ubridge "ubridge -H 9000"

sleep 2

{
sleep 1

echo "tap create tap-lan"
echo "tap create tap-wan"

echo "iol_bridge create BR${APP_ID} $((100 + APP_ID))"

echo "iol_bridge add_nio_tap BR${APP_ID} ${APP_ID} 0 0 tap-lan"
echo "iol_bridge add_nio_tap BR${APP_ID} ${APP_ID} 0 1 tap-wan"

echo "iol_bridge start BR${APP_ID}"

} | telnet 127.0.0.1 9000

#
# TAPs
#

ip link set tap-lan up
ip link set tap-wan up

ip link set tap-lan master br-lan
ip link set tap-wan master br-wan

echo
echo "========================================"
echo "Router ID      : ${APP_ID}"
echo "Cisco WAN      : 172.16.255.${CID}/31"
echo "Linux WAN      : 172.16.255.${LID}/31"
echo "Next-hop Cisco : 172.16.255.${LID}"
echo "========================================"
echo

sleep 5

while true; do
if ! tmux has-session -t iol 2>/dev/null; then
echo "IOL terminated"
exit 1
fi

sleep 5
done
