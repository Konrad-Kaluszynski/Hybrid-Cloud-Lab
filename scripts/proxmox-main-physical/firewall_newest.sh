#!/bin/bash
set -e

# --- 1. CONFIGURATION (Identical to v1.13) ---
export WAN_IF="vmbr0"
export MGMT_IF="vmbr1"
export SSH_PORT="987"
export PX_GUI_PORT="8006"
export OBFUSCATED_GUI="998"
export WG_PORT="51820"
export ZABBIX_SRV="192.168.0.203"
export IPSET_NAME="px_trusted"
export RECENT_LIST="PX_ATTACKERS" # Name for the dynamic ban list

log_message() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"; }

# --- 2. IPv6 TOTAL LOCKDOWN ---
log_message "Hardening IPv6 (Dropping all except loopback)..."
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT
ip6tables -F
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# --- 3. IPSET SETUP ---
ipset create $IPSET_NAME hash:net -! 2>/dev/null
if [ -f "/home/px-admin/firewall/subnets.txt" ]; then
    ipset flush $IPSET_NAME || true
    awk '!/^#|^\s*$/ {print "add '$IPSET_NAME' " $1}' "/home/px-admin/firewall/subnets.txt" | ipset restore -!
fi

# --- 4. CORE RESET ---
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -F && iptables -t nat -F && iptables -X

# --- 5. HYGIENE & PERSISTENT BANS ---
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state INVALID -j DROP 
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Check if IP is in the dynamic 'Attacker' list (Ban for 1 hour)
iptables -A INPUT -i "$WAN_IF" -m recent --name "$RECENT_LIST" --update --seconds 3600 -j DROP

# --- 6. INTERNAL & MONITORING (Full Functionality Kept) ---
# Trust Internal Bridge & VPN fully for cluster stability
iptables -A INPUT -i "$MGMT_IF" -j ACCEPT
iptables -A INPUT -s 10.10.10.0/24 -j ACCEPT

# Zabbix Specific API & Agent access
iptables -A INPUT -s "$ZABBIX_SRV" -p tcp --dport "$PX_GUI_PORT" -j ACCEPT
iptables -A INPUT -s "$ZABBIX_SRV" -p tcp --dport 10050 -j ACCEPT

# --- 7. EXTERNAL ACCESS (WAN) ---
# WireGuard UDP always open
iptables -A INPUT -i "$WAN_IF" -p udp --dport "$WG_PORT" -j ACCEPT

# SSH with Brute Force Protection (Check whitelist -> check rate -> allow)
iptables -A INPUT -i "$WAN_IF" -p tcp --dport "$SSH_PORT" -m state --state NEW \
    -m set --match-set $IPSET_NAME src \
    -m recent --name "$RECENT_LIST" --set \
    -m recent --name "$RECENT_LIST" --update --seconds 60 --hitcount 3 -j DROP

iptables -A INPUT -i "$WAN_IF" -p tcp --dport "$SSH_PORT" -m set --match-set $IPSET_NAME src -j ACCEPT

# GUI Obfuscation (998 -> 8006)
iptables -t nat -A PREROUTING -i "$WAN_IF" -p tcp --dport "$OBFUSCATED_GUI" -m set --match-set $IPSET_NAME src -j REDIRECT --to-ports $PX_GUI_PORT
iptables -A INPUT -i "$WAN_IF" -p tcp --dport $PX_GUI_PORT -m set --match-set $IPSET_NAME src -j ACCEPT

# --- 8. SAVE ---
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6
log_message "SUCCESS: v1.14.1 Applied. Host is now IPv6-safe and dynamically protected."
