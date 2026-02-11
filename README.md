Understood—keeping it strictly text-based for your README.

The issue with the "non-generating" version was indeed the whitespace. It contained **non-breaking spaces** (hex `A0`) instead of standard spaces (hex `20`). Mermaid interpreters on GitHub will fail if they encounter those characters.

Here is the clean, standard-space version of your `README.md`. You can copy this directly into your file:

```markdown
# Hybrid Cloud Lab: Nested Virtualization & Security Gateway

## 🚀 Overview

This repository contains the architectural design, network configuration, and automation scripts for a **Nested Proxmox Cluster** deployed on a Hetzner Dedicated server. The project demonstrates advanced skills in Layer 3 networking, firewall automation, and enterprise-grade virtualization.

## 🛠 Technology Stack

* **L0 Hypervisor:** Proxmox VE (Physical)
* **L1 Compute:** 4x Nested Proxmox Nodes (High-Availability Cluster)
* **Networking:** Iptables (Stateful Firewall), WireGuard (VPN), Tailscale (OOB Management)
* **Monitoring:** Zabbix (Active/Passive Agent Integration)
* **OS:** Debian/Fedora/Windows Server (DC)

---

## 📊 Lab Topology

The diagram below illustrates the flow from the public Internet through the security gateway to the isolated nested segments.

```mermaid
graph TD
    subgraph Internet_Cloud [Internet / Hetzner Network]
        Public_IP[138.201.192.241/26]
    end

    subgraph Physical_Host_L0 [Physical Proxmox L0 - Hetzner Dedicated]
        enp[enp0s31f6] --- vmbr0
        vmbr0[vmbr0: WAN Bridge]
        ts[Tailscale: 100.108.238.89]
        vmbr1[vmbr1: Management 1.1.1.252/24]
        vmbr2[vmbr2: Cluster Sync]
        vmbr3[vmbr3: Isolated Storage]
    end

    subgraph L1_Virtual_Network [L1 Virtual Machines]
        router[ID 254: router-01 - Security Gateway]
        p-node1[ID 250: nested-proxmox-01 .253]
        p-node2[ID 252: nested-proxmox-02 .54]
        p-node3[ID 251: nested-proxmox-03 .55]
        p-nodeB[ID 253: BIG-nested-proxmox]
    end

    %% Connections
    Public_IP --- vmbr0
    vmbr0 --- router
    router --- vmbr1
    vmbr1 --- p-node1
    vmbr1 --- p-node2
    vmbr1 --- p-node3
    vmbr1 --- p-nodeB
    
    %% Multihome for Nested Nodes
    p-node1 --- vmbr2
    p-node2 --- vmbr2
    p-node3 --- vmbr2

```

---

## 🌐 Networking & Segmentation

| Segment | Network ID | Interface | Purpose |
| --- | --- | --- | --- |
| **WAN** | `138.201.192.x` | `ens18` | Public Egress / External Access |
| **MGMT** | `1.1.1.0/24` | `ens19` | Infrastructure & Proxmox GUI Management |
| **DC** | `192.168.0.0/24` | `ens20` | Internal Workloads (Active Directory, Zabbix) |
| **VPN** | `10.10.10.0/24` | `wg0` | Encrypted Administrative Access |

---

## 🛡️ Firewall Automation (`iptables`)

The core of the security gateway is managed via a custom Bash script (`apply_firewall.sh`) found in the `scripts/` directory.

### Key Features:

* **Stateful Inspection:** Default `DROP` policy with granular `ACCEPT` rules for established connections.
* **Dynamic Whitelisting:** Uses `ipset` to load trusted source IPs from an external file, preventing unauthorized SSH/GUI access attempts.
* **DNAT (Port Forwarding):** Maps external high-range ports to internal nested Proxmox nodes (e.g., WAN:984 -> NodeB:8006).
* **MTU Optimization:** Implements TCP MSS Clamping (`--clamp-mss-to-pmtu`) to ensure stable traffic through nested tunnels and VPN interfaces.

---

## 📝 Implementation Highlights

### 1. Nested Virtualization Tweak

To allow L1 Proxmox nodes to host their own VMs, the L0 host is configured to expose hardware-assisted virtualization:

```bash
# Example configuration on L0 for nested nodes
args: -cpu host,kvm=on

```

### 2. Zabbix Monitoring Integration

The firewall allows specific traffic for Zabbix (Port `10050/10051`) between the Data Center segment and the Management segment, enabling full-stack visibility of both physical and virtual layers.

---

## 📂 Repository Structure

* `architecture/`: High-resolution diagrams and network maps.
* `scripts/router/`: Firewall and routing automation scripts.
* `docs/`: Detailed phase-by-phase implementation notes.

---

**Author:** Konrad Kałuszyński
**Role:** IT Systems Engineer / L3 Support Engineer
**Status:** Active Lab Environment

```

Would you like me to review the `apply_firewall.sh` script logic as well to ensure the NAT rules match this topology?

```
