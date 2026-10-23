# Cisco IOL Router Lab in Docker

## Overview

This project runs multiple **Cisco IOL (IOS on Linux)** routers inside Docker containers and connects them to external Docker networks using **uBridge** and Linux bridges.

The goal is to create a lightweight and reproducible lab environment that provides:

- Cisco IOS routing
- Docker-attached LAN segments
- Inter-router WAN connectivity
- Internet access
- VPN/IPsec experimentation
- Integration with other containers (FortiGate, Linux hosts, test clients, etc.)

The design intentionally separates:

- Container management connectivity
- Cisco LAN networks
- Cisco WAN networks

This makes the topology easier to understand and troubleshoot.

---

# Architecture

Each Docker container contains:

```text
+-----------------------------------+
| Debian Container                  |
|                                   |
|  Cisco IOL                        |
|       |                           |
|    uBridge                        |
|       |                           |
|  TAP Interfaces                   |
|       |                           |
|  Linux Bridges                    |
|       |                           |
| Docker Networks                   |
+-----------------------------------+
```

The Cisco router never connects directly to Docker interfaces.

Instead, traffic follows:

```text
Cisco IOS
   |
uBridge
   |
tap-lan / tap-wan
   |
br-lan / br-wan
   |
Docker Interfaces
```

This provides behavior similar to a physical router connected to Ethernet networks.

---

# Components

## Cisco IOL

Cisco IOL provides the routing functionality.

Each container launches:

```bash
/iol.bin -u 10000 ${APP_ID}
```

The `APP_ID` uniquely identifies each router instance.

Example:

```text
r1 -> APP_ID=1
r2 -> APP_ID=2
r3 -> APP_ID=3
```

---

## uBridge

uBridge acts as the Layer 2 transport between:

```text
Cisco IOL
↕
Linux TAP interfaces
```

This is the same bridge engine used by GNS3.

The project builds uBridge directly from source because some traffic-control modules are disabled to simplify compilation inside Docker.

---

## Linux Bridges

Two bridges are created:

```text
br-lan
br-wan
```

### br-lan

Connects:

```text
eth0
tap-lan
```

Used for:

- Cisco LAN interfaces
- External Docker containers
- Test clients
- FortiGate containers

---

### br-wan

Connects:

```text
wan0
tap-wan
```

Used for:

- Cisco WAN interface
- Linux routing/NAT

---

# Docker Networks

## lan

Management and Internet access network.

Attached as:

```text
lan0
```

Example:

```text
192.168.167.0/24
```

This network provides:

- Internet access
- Package downloads
- NAT egress

Linux uses this network as its default route.

---

## wan

Router WAN transport network.

Attached as:

```text
wan0
```

Example:

```text
192.168.171.0/24
```

This network carries traffic between Cisco and Linux through the bridge architecture.

---

## r1-lan

External Docker network.

Attached as:

```text
eth0
```

Example:

```text
172.16.200.0/24
```

This network represents the LAN connected to the Cisco router.

Example devices:

```text
Cisco LAN Interface    172.16.200.1
Trip Container         172.16.200.129
FortiGate              172.16.200.x
```

---

# Interface Layout

Inside the container:

```text
lan0  = Internet uplink
wan0  = Cisco WAN bridge
eth0  = Cisco LAN bridge
```

Configured in the entrypoint:

```bash
UPLINK_IF=lan0
CISCO_WAN_IF=wan0
CISCO_LAN_IF=eth0
```

---

# WAN Addressing

Each router automatically receives a dedicated /31 transit network.

Router 1:

```text
Cisco: 172.16.255.0/31
Linux: 172.16.255.1/31
```

Router 2:

```text
Cisco: 172.16.255.2/31
Linux: 172.16.255.3/31
```

Router 3:

```text
Cisco: 172.16.255.4/31
Linux: 172.16.255.5/31
```

Generated automatically:

```bash
CID=$(( (APP_ID - 1) * 2 ))
LID=$(( CID + 1 ))
```

---

# Internet Access

Linux performs NAT for the Cisco WAN subnet:

```bash
iptables -t nat -A POSTROUTING \
    -s 172.16.255.0/24 \
    -o lan0 \
    -j MASQUERADE
```

This allows Cisco routers to reach the Internet through the container's Docker uplink.

Traffic flow:

```text
Cisco
  |
172.16.255.x
  |
Linux NAT
  |
192.168.167.x
  |
Internet
```

---

# Why NAT Is Performed on Cisco

The original design attempted to NAT all downstream networks on Linux.

However, because the Linux container is simultaneously:

- Bridging the Cisco LAN
- Routing the Cisco WAN
- Connected to the same Docker network

Linux conntrack/NAT behavior became unreliable for traffic originating behind the router.

A simpler and more realistic design is:

```text
Clients
   |
Cisco NAT
   |
172.16.255.x
   |
Linux NAT
   |
Internet
```

This allows all client containers to access the Internet while keeping the architecture simple.

For VPN/IPsec labs, NAT exemption can be implemented on Cisco so that remote sites still see the original client IP addresses.

---

# MAC Learning

Linux bridge MAC learning is disabled:

```bash
bridge link set dev eth0 learning off
bridge link set dev wan0 learning off
```

This prevents MAC addresses from being learned through incorrect bridge ports.

Without this setting, Cisco forwarding became inconsistent and traffic was occasionally sent to the wrong interface.

---

# Example Lab Topology

```text
                    Internet
                        |
                  Docker NAT
                        |
                    lan0
                        |
                +---------------+
                | Linux Router  |
                | Container     |
                +---------------+
                      |
             172.16.255.0/31
                      |
                Cisco IOL
                      |
             172.16.200.0/24
                      |
        +-------------+-------------+
        |                           |
      Trip                     FortiGate
```

---

# Docker Compose

Three routers are created:

```text
r1
r2
r3
```

Each router:

- Uses the same image
- Has a unique APP_ID
- Has its own configuration directory
- Runs independently

Configuration persistence:

```yaml
volumes:
  - ./r1:/data
```

This stores:

- Startup-config
- VLAN database
- IOL files
- NETMAP

outside the container.

---

# Building

```bash
docker compose build
```

---

# Starting

```bash
docker compose up -d
```

---

# Creating the Shared LAN Network

A dedicated Docker network must exist before starting the lab:

```bash
docker network create \
  --driver bridge \
  --subnet 172.16.200.0/24 \
  r1-lan
```

Verify:

```bash
docker network inspect r1-lan
```

---

# Connecting Test Containers

Example:

```bash
docker run -it \
  --network r1-lan \
  alpine sh
```

Configure:

```bash
ip addr add 172.16.200.10/24 dev eth0
ip route add default via 172.16.200.1
```

The Cisco router becomes the default gateway.

---

# VPN/IPsec Use Cases

A primary goal of this project is testing:

- Site-to-site IPsec
- Route-based VPNs
- FortiGate integrations
- Dynamic routing over VPN
- NAT exemption scenarios

Internet-bound traffic is NATed.

VPN traffic can bypass NAT and preserve original client addresses.

Example:

```text
172.16.200.129
        |
      IPsec
        |
10.10.10.50
```

This allows realistic VPN testing without address translation inside the tunnel.

---

# Troubleshooting

## Verify Cisco Connectivity

```cisco
show ip interface brief
show ip route
ping 1.1.1.1
```

---

## Verify Linux Routing

```bash
ip addr
ip route
```

---

## Verify NAT

```bash
iptables -t nat -L -n -v
```

---

## Capture Traffic

```bash
tcpdump -ni br-lan
tcpdump -ni br-wan
tcpdump -ni lan0
```

---

## To do

- [ ] Review the full readme written by ai 
- [ ] Cleanup files from testing
- [ ] Test network speed
- [ ] Add future features
- [ ] Add static version of ubridge
- [ ] Make de IOL external to the container to be able to legally make it available prebuilt
- [ ] Implementing a Release Process with GitHub Actions for Docker Image Management



---

# Roadmap

## Planned Features

### Networking

- [ ] Remove Cisco NAT dependency and perform all NAT on the Linux container
- [ ] Support multiple independent LAN segments per router

### Security

- [ ] Site-to-site IPsec examples
- [ ] FortiGate integration examples

### Routing

- [ ] OSPF between routers
- [ ] BGP between routers
- [ ] Route redistribution examples
- [ ] MPLS/VRF experiments

### Container Integration

- [ ] Linux client templates
- [ ] Containerized application testing behind Cisco routers

### Automation

- [ ] Automatic router bootstrap configuration
- [ ] Startup configuration templates
- [ ] Environment variable driven router configuration
- [ ] Terraform deployment examples
- [ ] Ansible integration

### Monitoring & Troubleshooting

- [ ] Built-in health checks
- [ ] Automatic router restart watchdog
- [ ] Connectivity validation script
- [ ] Packet capture helper scripts
- [ ] Router status dashboard

### Documentation

- [ ] Multi-router topology examples
- [ ] FortiGate IPsec lab guide
- [ ] Architecture diagrams

---


# Disclaimer

This project requires a legally obtained Cisco IOL image.

The repository intentionally does not include Cisco software.

Users are responsible for complying with Cisco licensing requirements.
