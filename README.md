<img width="1920" height="1080" alt="Screenshot_20260712_073652" src="https://github.com/user-attachments/assets/19dfded7-2445-4594-9654-62fba35af51f" />
<img width="1920" height="1080" alt="Screenshot_20260712_073636" src="https://github.com/user-attachments/assets/f5bf31fb-40d5-4001-b150-7d80a9d3ab4c" />
<img width="1920" height="1080" alt="Screenshot_20260712_073601" src="https://github.com/user-attachments/assets/d6c5f773-33f1-49b2-854c-cfcebac145a9" />

# Testing-Auditing-Script (AirAttack Suite)

A modular Bash-based wireless & network penetration testing toolkit built for
authorized security testing on networks I own or have explicit permission to test.

> ⚠️ **For authorized use only.** This tool is intended strictly for testing
> networks and devices you own, or have explicit written permission to assess.
> Unauthorized use against networks you don't own or control is illegal.

> ⚠️ **WPA3/PMF note:** Deauth-based attacks (mdk4, aireplay) do not work against
> WPA3-only networks with Protected Management Frames (PMF) enforced — this is
> by design per the WPA3 spec, not a script bug. However, testing on a personal
> device confirmed that switching the AP to WPA2/WPA3-transition mode
> reintroduces the vulnerability, even for a client already connected via
> WPA3 — suggesting PMF enforcement is applied at the AP/radio level rather
> than per-client in mixed mode.

## About This Project
This is a **self-taught, learning-purpose project** built as I teach myself
Bash scripting, networking, and security tooling on my own — I'm not currently
enrolled in college. Some parts may not work perfectly yet, but nothing here
is designed to damage your system in any way.

Any comments, suggestions, or corrections are genuinely welcome — thank you
for checking it out!

## Status
🚧 Under active development — some modules are stable, others are still being
debugged (see Known Issues below).

## Features
- **WiFi Auditing** — monitor mode management, target scanning, deauth attacks,
  handshake capture (PMKID pending)
- **Bettercap Integration** — network recon, ARP/DNS spoofing, MITM sniffing
- **Nmap Scanning** — host discovery, port/service scanning, OS detection,
  security/firewall probing, separate module for external/other-network targets
- **Metasploit Integration** — msfconsole session management, payload generation
  (APK/EXE/ELF), reverse listener setup, local file-server tunneling
- **Offline Cracking** — hash extraction and cracking support for ZIP, RAR, PDF,
  7Z, CAP (handshakes), KeePass, and Office documents via John the Ripper / hashcat,
  with mask-based and wordlist-based cracking modes
- Dynamic wireless interface detection
- Color-coded, menu-driven CLI interface
- **Modular architecture** — core logic split across `Config/`, `Handelers/`,
  and `Modules/` for easier maintenance and extension

## Project Structure
```
AirMerge/
├── airmerge.sh          # Entry point — sources all modules and runs the main menu
├── Config/
│   └── config.sh        # Colors, banners, print helpers, global variables
├── Handelers/
│   └── handelers.sh      # Dependency checks, interface selection, cleanup, ctrl+c trap
└── Modules/
    ├── wifi.sh           # Monitor mode, scanning, deauth, handshake capture
    ├── bettercap.sh      # Network recon, ARP/DNS spoofing, MITM
    ├── nmap.sh           # Host/port/service/OS scanning
    ├── metaspliot.sh     # Metasploit console, payloads, listeners
    ├── crack.sh          # Hash extraction and offline cracking (John/hashcat/aircrack)
    ├── parse_scan.py     # Parses airodump-ng CSV scan output
    └── pick_ap.py        # Extracts AP/channel from a selected scan result
```

## Requirements
Tested on Kali Linux. Depends on:
`aircrack-ng`, `bettercap`, `nmap`, `john`, `hashcat`, `figlet`, `xterm`,
`hcxpcapngtool`, `crunch`, `iw`, `mdk4`, `python3`

Run the script once — it checks for all dependencies on startup and reports
anything missing.

## Usage
```bash
git clone https://github.com/ThakurVaibhavSingh/Testing-Auditing-Script.git
cd Testing-Auditing-Script/AirMerge
sudo ./airmerge.sh
```
Must be run as root (required for interface management, packet injection, and raw sockets).

## Known Issues / TODO
- Auto-detected gateway IP (Bettercap / Nmap "Other IP" modules) may briefly
  show as "unavailable" right after a Network scan — this is because switching
  to/from monitor mode drops the network connection; wait ~5 seconds for it
  to reconnect and it resolves correctly
- Metasploit menu module has been implemented with a lot of limitations
  available (sorry for that)
- PMKID capture module currently unavailable — I don't have an external
  adapter to properly test/develop this against, so it's on hold until I do
- hashcat GPU acceleration currently broken on AMD iGPU (RustiCL device type
  issue) — CPU fallback only for now

## Disclaimer
This project is for educational and authorized security-testing purposes only.
I am not responsible for misuse of this tool.
