<img width="1920" height="1080" alt="Screenshot_20260712_073652" src="https://github.com/user-attachments/assets/19dfded7-2445-4594-9654-62fba35af51f" />
<img width="1920" height="1080" alt="Screenshot_20260712_073636" src="https://github.com/user-attachments/assets/f5bf31fb-40d5-4001-b150-7d80a9d3ab4c" />
<img width="1920" height="1080" alt="Screenshot_20260712_073601" src="https://github.com/user-attachments/assets/d6c5f773-33f1-49b2-854c-cfcebac145a9" />
# Testing-Auditing-Script (AirAttack Suite)

A modular Bash-based wireless & network penetration testing toolkit built for
authorized security testing on networks I own or have explicit permission to test.

> ⚠️ **For authorized use only.** This tool is intended strictly for testing
> networks and devices you own, or have explicit written permission to assess.
> Unauthorized use against networks you don't own or control is illegal.

> ⚠️ Deauth-based attacks (mdk4, aireplay) do not work against WPA3 networks with Protected Management Frames enabled — this is by design per the WPA3 spec, not a script bug.
>
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
- **Offline Cracking** — hash extraction and cracking support for ZIP, RAR, PDF,
  7Z, CAP (handshakes), KeePass, and Office documents via John the Ripper / hashcat
- Dynamic wireless interface detection
- Color-coded, menu-driven CLI interface

## Requirements
Tested on Kali Linux. Depends on:
`aircrack-ng`, `bettercap`, `nmap`, `john`, `hashcat`, `figlet`, `xterm`,
`hcxpcapngtool`, `crunch`, `iw`

Run the script once — it checks for all dependencies on startup and reports
anything missing.

## Usage
```bash
sudo ./suite.sh
```
Must be run as root (required for interface management, packet injection, and raw sockets).

## Known Issues / TODO
- Metasploit menu module not yet implemented
- PMKID capture module disabled pending hcxdumptool integration
- hashcat GPU acceleration currently broken on AMD iGPU (RustiCL device type issue) — CPU fallback only for now
- Wordlist handling inconsistent across cracking modules (hardcoded filenames in some)

## Disclaimer
This project is for educational and authorized security-testing purposes only.
I am not responsible for misuse of this tool.
