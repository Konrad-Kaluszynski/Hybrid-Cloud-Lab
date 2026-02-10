kk@router-01 ~ $ cat firewall/firewall_newest.sh 
#!/bin/bash
# ==============================================================================
# ROUTER-01 FIREWALL: v10.14.0 - PROXMOX CLUSTER & ZABBIX INTEGRATION
# ==============================================================================
# Node A (Physical) | Node B (.253) | Node C (.54) | Node D (Add as needed)
# ==============================================================================
set -e

# --- 1. INTERFACE CONFIGURATION ---
export WAN_IF="ens18"
export MGMT_IF="ens19"
export DC_IF="ens20"
export WG_IF="wg0"

# --- 2. NETWORK & IP DEFINITIONS ---
export LAN_SUBNET_DC="192.168.0.0/24"
export LAN_SUBNET_MGMT="1.1.1.0/24"
export WG_SUBNET="10.10.10.0/24"

# Host IPs
export ZABBIX_SRV="192.168.0.203"
export TARGET_DC_IP="192.168.0.1"
export PHYS_PX_HOST="1.1.1.252"

# Nested Cluster Nodes
export PX_NESTED_01="1.1.1.253"   # Node B
export PX_NESTED_02="1.1.1.54"    # Node C
export PX_NESTED_03="1.1.1.55"    # Node D (Example IP, adjust as needed)

export FIREWALL_SUBNETS_FILE="/home/kk/firewall/subnets.txt"

# --- 3. PORT DEFINITIONS ---
export WG_PORT="51820"
export ROUTER_SSH_PORT="988"

# External GUI Access Ports
export PX_GUI_EXT_01="984"        # For Node B
export PX_GUI_EXT_02="982"        # For Node C
export PX_GUI_EXT_03="980"        # For Node D

export DC_RDP_EXT_PORT="986"
export ZABBIX_PORT="10051"       # Traps/Active Checks
export ZABBIX_AGENT_PORT="10050" # Passive Checks
export PX_API_PORT="8006"        # Internal Proxmox Port

log_message() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_message "Applying v10.14.0: Cluster Access for PX_01 and PX_02..."

# --- 4. IPSET & KERNEL ---
ipset create trusted_ssh_src hash:net -! 2>/dev/null
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# --- 5. WHITELIST LOAD ---
if [ -f "$FIREWALL_SUBNETS_FILE" ]; then
    log_message "Loading trusted subnets..."
    ipset flush trusted_ssh_src || true
    awk '!/^#|^\s*$/ {print "add trusted_ssh_src " $1}' "$FIREWALL_SUBNETS_FILE" | ipset restore -!
fi

# --- 6. RESET ---
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -F && iptables -t nat -F && iptables -X && iptables -t mangle -F

# --- 7. BASIC SAFETY ---
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# --- 8. DNS, ICMP & MGMT SERVICES ---
for IFACE in "$MGMT_IF" "$DC_IF" "$WG_IF"; do
    iptables -A INPUT -i "$IFACE" -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -i "$IFACE" -p tcp --dport 53 -j ACCEPT
    iptables -A INPUT -i "$IFACE" -p icmp --icmp-type echo-request -j ACCEPT
    iptables -A INPUT -i "$IFACE" -p tcp --dport "$ROUTER_SSH_PORT" -j ACCEPT
    
    if [ "$IFACE" != "$WG_IF" ]; then
        iptables -A INPUT -i "$IFACE" -p udp --dport 67:68 --sport 67:68 -j ACCEPT
    fi
done

# --- 9. EXTERNAL ACCESS (WAN) ---
iptables -A INPUT -i "$WAN_IF" -p udp --dport "$WG_PORT" -j ACCEPT
iptables -A INPUT -i "$WAN_IF" -p tcp --dport "$ROUTER_SSH_PORT" -m set --match-set trusted_ssh_src src -j ACCEPT

# --- 10. NAT & KERNEL TWEAKS ---
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# --- 11. FORWARDING RULES (THE CORE ENGINE) ---

# 11.1 VPN & Inter-VLAN (Full Access for Clustering/Storage)
iptables -A FORWARD -i "$WG_IF" -o "$DC_IF" -j ACCEPT
iptables -A FORWARD -i "$WG_IF" -o "$MGMT_IF" -j ACCEPT
iptables -A FORWARD -i "$DC_IF" -o "$MGMT_IF" -j ACCEPT
iptables -A FORWARD -i "$MGMT_IF" -o "$DC_IF" -j ACCEPT

# 11.2 Outbound to Internet (WAN Egress)
iptables -A FORWARD -i "$MGMT_IF" -o "$WAN_IF" -s "$LAN_SUBNET_MGMT" -j ACCEPT
iptables -A FORWARD -i "$DC_IF" -o "$WAN_IF" -s "$LAN_SUBNET_DC" -j ACCEPT
iptables -A FORWARD -i "$WG_IF" -o "$WAN_IF" -j ACCEPT

# 11.3 ZABBIX MONITORING
iptables -A FORWARD -i "$DC_IF" -s "$ZABBIX_SRV" -p tcp -m multiport --dports "$PX_API_PORT","$ZABBIX_AGENT_PORT" -j ACCEPT
iptables -A FORWARD -p tcp --dport "$ZABBIX_PORT" -j ACCEPT

# --- 12. PORT FORWARDS (DNAT) ---

# Nested PX_01 (Node B)
iptables -t nat -A PREROUTING -i "$WAN_IF" -p tcp --dport "$PX_GUI_EXT_01" -m set --match-set trusted_ssh_src src -j DNAT --to-destination "$PX_NESTED_01:8006"
iptables -A FORWARD -d "$PX_NESTED_01" -p tcp --dport 8006 -j ACCEPT

# Nested PX_02 (Node C)
iptables -t nat -A PREROUTING -i "$WAN_IF" -p tcp --dport "$PX_GUI_EXT_02" -m set --match-set trusted_ssh_src src -j DNAT --to-destination "$PX_NESTED_02:8006"
iptables -A FORWARD -d "$PX_NESTED_02" -p tcp --dport 8006 -j ACCEPT

# DC-01 RDP
iptables -t nat -A PREROUTING -i "$WAN_IF" -p tcp --dport "$DC_RDP_EXT_PORT" -m set --match-set trusted_ssh_src src -j DNAT --to-destination "$TARGET_DC_IP:3389"
iptables -A FORWARD -d "$TARGET_DC_IP" -p tcp --dport 3389 -j ACCEPT

# --- 13. SAVE & FINISH ---
# iptables-save > /etc/iptables/rules.v4
log_message "Firewall applied. PX_01 (984) and PX_02 (982) active."
