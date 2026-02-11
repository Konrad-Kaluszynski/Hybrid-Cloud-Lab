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

