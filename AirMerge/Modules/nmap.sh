#!/bin/bash



network () {
	
	while true; do 
	ip_check
	info "$SUBNET"
	info "---Make a choice---"
		into "1) Hosts Scan"
		into "2) Ports"
		into "3) Service"
		into "4) Security & Firewall"
		into "5) OS Version"
		out "0) Back"
		out "00) Main Menu"
		
	read -p ">>" choice
	
	case $choice in 
		
		1) sudo nmap -sn --send-eth --resolve-all -T4 $SUBNET;;

		2) read -rp "$(printf "${ORANGE}Scan all ports? (y/n): ${NC}")" allports
			if [[ $allports = y ]]; then
				sudo nmap -p- --open -T4 -n --min-rate 5000 $SUBNET
			else
			read -rp "$(printf "${ORANGE}Enter port/range (e.g. 80 or 1-1000): ${NC}")" PORT
			sudo nmap -p "$PORT" -sV -sC -O -A --open -T4 \
			--script=banner,vulners,exploit \
			$SUBNET			
			fi;;		
			
		3) sudo nmap -sV --version-intensity 7 -p- -T4 --min-rate 3000 --script=banner,http-headers,http-title,ssh-hostkey,ftp-anon,smtp-commands,http-enum,ssl-cert,dns-service-discovery,http-server-header $SUBNET;;

		4) sudo nmap -sS -Pn --open -T4 --min-rate 3000 --script=ipidseq,snmp-info,auth,dns-recursion,dns-cache-snoop,broadcast-dns-service-discovery $SUBNET;;

		5) sudo nmap -O --osscan-guess --fuzzy -T4 --script=nbstat,smb-os-discovery,broadcast-dhcp-discover $SUBNET;;
    
		0) break;;
		
		00) GOTO_MAIN=1; break;;
		#00 — set flag to 1 (true), then break out of network loop. Control returns to wherever network was called from (nmap_menu).
		
		*);;
		
	esac
	done
}

other () {
	
	while true; do 
	ip_check
	info "$SUBNET"
		into "1) IP Scan"
		into "2) Server Runtime"
		into "3) Server Security,Firewall"
		into "4) Last Patched"
		into "5) Active Users"
		out "0) Back"
		out "00) Main Menu"
	
	read -p ">>" choice
	
	case $choice in 
		
		1) sudo nmap -Pn -sn --reason $SUBNET \
			--script=asn-query,whois-ip,ip-geolocation-ipinfodb;;
		
		2) sudo nmap -sV -sS -Pn $SUBNET \
			--script=uptime-agent,snmp-sysdescr,clock;;
		
		3) sudo nmap -sS -sA -Pn -T4 $SUBNET \
			--script=firewalk,firewall-bypass,vulners,exploit,auth,\
			http-shellshock,http-put,http-git,ftp-anon,\
			smb-vuln-ms17-010,ssl-heartbleed;;
		
		4) sudo nmap -sV -sU -O -Pn -p 161,445,22 $SUBNET \
			--script=snmp-sysdescr,snmp-win32-updates,\
			smb-os-discovery,banner;;
		
		5) sudo nmap -sV -Pn -p 22,445,161,79 $SUBNET \
			--script=finger,smb-enum-users,smb-enum-sessions,\
			snmp-win32-users,users-brute;;
		
		0) break;;
		
		00) GOTO_MAIN=1; break;;
		
		*);;
		
	esac
	done
}

# ══════════════════════════════════════════════════════════════════════════════
# NMAP MENU Logic
# ══════════════════════════════════════════════════════════════════════════════

nmap_menu () {		
	while true; do
		clear
		nmap_banner
		
		into "1) Network IP"
		into "2) Other IP"
		out "0) Main Menu"
	
	read -rp "$(printf "${BOLD}${DIM}${GREEN}Choose any option ==>${NC}\t")" choice
	
	case $choice in 
	
			1) read -rp "$(info "Enter the Network IP or Leave Blank")" SUBNET
               [[ -z $SUBNET ]] && SUBNET=$(ip route | grep -v default | grep "$INTER" | awk '{print $1}') #Logic is that if -z is false (string is not empty) so it skips the auto-fill line and uses whatever the user typed directly — $SUBNET stays as their input and network runs with it.
               network
               [[ $GOTO_MAIN -eq 1 ]] && { GOTO_MAIN=0; break; } ;;
            
            2) if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
				err "No internet connection — geolocation scripts need internet"
				read -p "Press [Enter] to continue..."
				return 0
				fi

			read -rp "$(info "Enter Target IP or Leave Blank for Gateway")" SUBNET
			[[ -z $SUBNET ]] && SUBNET=$(ip route | awk '/^default/ {print $3; exit}')
			other
			[[ $GOTO_MAIN -eq 1 ]] && { GOTO_MAIN=0; break; } ;; #After nmap_main (which called network) returns — check the flag. If it's 1, reset it to 0 and break out of nmap_menu loop. Control returns to main menu.
            
		
		0) info "Bye Bye"
			break ;;
			
		*) read -rp "$(printf "${RED}Choose correct option [ENTER]${NC}")"
			continue ;;
	
	
	esac	
	done
}

