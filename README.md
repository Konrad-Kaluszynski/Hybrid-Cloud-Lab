# Hybrid Cloud Project | Phase 01: Infrastructure & Networking

## 📌 Project Overview
This project documents the architectural design and deployment of a **Nested Virtualization Lab**. The environment is designed to simulate a hybrid cloud infrastructure, focusing on advanced networking, resource isolation, and enterprise-grade virtualization management.

## 🛠 Technology Stack
* **Hypervisor:** VMware ESXi / Proxmox
* **Orchestration:** VMware vCenter Server
* **Network Services:** pfSense / VyOS (Routing, Firewall, DHCP, DNS)
* **Storage:** Shared Storage (iSCSI/NFS) for klastrowanie (HA/vMotion)

---

## 🌐 Network Segmentation & Topology
To ensure security and traffic isolation, the environment is divided into specific logical segments (VLANs).

### IP Address Management (IPAM)
| Segment | Network ID | VLAN ID | Purpose |
| :--- | :--- | :--- | :--- |
| **Management** | `10.0.10.0/24` | 10 | ESXi Management, vCenter, Infrastructure Tools |
| **vMotion** | `10.0.20.0/24` | 20 | Live migration traffic between nested hosts |
| **Storage** | `10.0.30.0/24` | 30 | Dedicated backend for iSCSI/NFS shared storage |
| **Provisioning**| `10.0.40.0/24` | 40 | Deployment of new VMs and PXE booting |
| **Workload** | `192.168.100.0/24`| 100 | General application and VM traffic |

---

## ⚙️ Phase 01: Core Infrastructure Setup

### 1. Physical/Base Hypervisor Configuration
* **Nested Virtualization:** Hardware-assisted virtualization (VT-x/AMD-V) exposed to the Guest OS.
* **Virtual Switches:** Standard or Distributed Switch configured with **Promiscuous Mode** and **Forged Transmits** set to *Accept* (required for nested ESXi connectivity).
* **MTU Settings:** Jumbo Frames (9000 MTU) enabled for the Storage and vMotion segments to optimize performance.

### 2. Network Services Layer
* Deployment of a virtualized router/firewall to act as the **Default Gateway**.
* Configuration of **Inter-VLAN Routing** and Firewall rules to restrict access between segments (Hardening).
* Setup of local **DNS (A/PTR records)** to ensure successful vCenter and ESXi integration.

### 3. Storage Architecture
* Initial setup of a shared storage target.
* Mapping LUNs to nested ESXi hosts to enable **High Availability (HA)** and **Distributed Resource Scheduler (DRS)** in later phases.

---

## 🚀 Future Roadmap
- [ ] **Phase 02:** Automated deployment of Nested ESXi hosts using Kickstart.
- [ ] **Phase 03:** vCenter Cluster configuration and HA/DRS testing.
- [ ] **Phase 04:** Integration of Ansible for automated VM provisioning.

---
**Author:** Konrad Kałuszyński  
**Status:** Phase 01 Completed / Documentation Updated
