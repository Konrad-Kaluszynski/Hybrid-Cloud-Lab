#!/bin/bash
# ==============================================================================
# ROUTER-01 FIREWALL: v10.15.0 - PROXMOX CLUSTER + DYNAMIC BLACKLISTING
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
export PX_NESTED_01="1.1.1.253"
export PX_NESTED_02="1.1.1.54"

export FIREWALL_SUBNETS_FILE="/home/kk/firewall/subnets.txt"
export IPTABLES_RECENT_LIST="SSH_BRUTE"

# --- 3. PORT DEFINITIONS ---
export WG_PORT="51820"
export ROUTER_SSH_PORT="988"
export PX_GUI_EXT_01="984"
export PX_GUI_EXT_02="982"
export DC_RDP_EXT_PORT="986"
export PX_API_PORT="8006"
export ZABBIX_PORT="10051"
export ZABBIX_AGENT_PORT="10050"

log_message() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_message "Applying v10.15.0: Hardening WAN with Dynamic Blacklisting..."

# --- 4. IPSET & KERNEL ---
ipset create trusted_ssh_src hash:net -! 2>/dev/null
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# --- 5. WHITELIST LOAD ---
if [ -f "$FIREWALL_SUBNETS_FILE" ]; then
    log_message "Loading trusted subnets..."
    ipset flush trusted_ssh_src || true
    awk '!/^#|^\s*$/ {print "add trusted_ssh_src " $1}' "$FIREWALL_SUBNETS_FILE" | ipset restore -!
fi

# --- 6. RESET & CUSTOM CHAINS ---
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -F && iptables -t nat -F && iptables -X && iptables -t mangle -F

# NEW: Initialize the Blacklist Chain
iptables -N BLACKLIST_ATTACKERS 2>/dev/null || true
iptables -A BLACKLIST_ATTACKERS -m recent --name "$IPTABLES_RECENT_LIST" --set -j LOG --log-prefix "FW_BRUTE_FORCE: "
iptables -A BLACKLIST_ATTACKERS -m recent --name "$IPTABLES_RECENT_LIST" --set -j DROP

# --- 7. BASIC SAFETY & DROP BANNED ---
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Check if the IP is already flagged as an attacker before processing anything else
iptables -A INPUT -i "$WAN_IF" -m recent --name "$IPTABLES_RECENT_LIST" --update --seconds 3600 -j DROP

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

# --- 9. EXTERNAL ACCESS (WAN) WITH BRUTE FORCE PROTECTION ---
iptables -A INPUT -i "$WAN_IF" -p udp --dport "$WG_PORT" -j ACCEPT

# Protected SSH: Check Trusted IPSet -> Check Hit Count (3 hits in 60s) -> Accept or Blacklist
iptables -A INPUT -i "$WAN_IF" -p tcp --dport "$ROUTER_SSH_PORT" -m state --state NEW \
    -m set --match-set trusted_ssh_src src \
    -m recent --name "$IPTABLES_RECENT_LIST" --update --seconds 60 --hitcount 3 -j BLACKLIST_ATTACKERS

iptables -A INPUT -i "$WAN_IF" -p tcp --dport "$ROUTER_SSH_PORT" -m set --match-set trusted_ssh_src src -j ACCEPT

# --- 10. NAT & KERNEL TWEAKS ---
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# --- 11. FORWARDING RULES ---
iptables -A FORWARD -i "$WG_IF" -o "$DC_IF" -j ACCEPT
iptables -A FORWARD -i "$WG_IF" -o "$MGMT_IF" -j ACCEPT
iptables -A FORWARD -i "$DC_IF" -o "$MGMT_IF" -j ACCEPT
iptables -A FORWARD -i "$MGMT_IF" -o "$DC_IF" -j ACCEPT
iptables -A FORWARD -i "$MGMT_IF" -o "$WAN_IF" -s "$LAN_SUBNET_MGMT" -j ACCEPT
iptables -A FORWARD -i "$DC_IF" -o "$WAN_IF" -s "$LAN_SUBNET_DC" -j ACCEPT
iptables -A FORWARD -i "$WG_IF" -o "$WAN_IF" -j ACCEPT

# ZABBIX MONITORING
iptables -A FORWARD -i "$DC_IF" -s "$ZABBIX_SRV" -p tcp -m multiport --dports "$PX_API_PORT","$ZABBIX_AGENT_PORT" -j ACCEPT
iptables -A FORWARD -p tcp --dport "$ZABBIX_PORT" -j ACCEPT

# --- 12. PORT FORWARDS (DNAT) WITH DYNAMIC CHECKS ---

# Function for Protected DNAT (Checks hitcounts on GUI/RDP ports)
# Usage: <internal_ip> <ext_port> <int_port>
protected_dnat() {
    iptables -t nat -A PREROUTING -i "$WAN_IF" -p tcp --dport "$2" -m set --match-set trusted_ssh_src src -j DNAT --to-destination "$1:$3"
    # Forwarding rule with rate limiting
    iptables -A FORWARD -d "$1" -p tcp --dport "$3" -m state --state NEW \
        -m recent --name "$IPTABLES_RECENT_LIST" --update --seconds 60 --hitcount 5 -j BLACKLIST_ATTACKERS
    iptables -A FORWARD -d "$1" -p tcp --dport "$3" -j ACCEPT
}

protected_dnat "$PX_NESTED_01" "$PX_GUI_EXT_01" "8006"
protected_dnat "$PX_NESTED_02" "$PX_GUI_EXT_02" "8006"
protected_dnat "$TARGET_DC_IP" "$DC_RDP_EXT_PORT" "3389"

# --- 13. SAVE & FINISH ---
log_message "Firewall v10.15.0 applied. IPs exceeding hitcounts will be banned for 1 hour."
