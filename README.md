# OPNsense WAN Healer
A small recovery script for OPNsense that brings the WAN connection back when it silently drops.

## Why this exists
My ISP occasionally drops routing after a short outage, which leaves OPNsense without connection (pings fail).
This script automatically detects that state and restores the connection without having to manually reboot or reload the WAN interface.

## How it works
1. Periodically pings the default gateway and a couple of public IPs.  
2. If all fail:
   1. Runs `configctl interface reconfigure wan` which is same as to going to *Interfaces -> Overview* and clicking "Reload" on the WAN interface.  
      This resolves the issue most of the time, so steps 2 and 3 usually don’t execute.  
   2. If still down, toggles the interface using `ifconfig <iface> down/up`, simulating a physical cable reconnect.  
   3. As a last resort, reboots the system if the previous steps fail.  
      `REBOOT_COOLDOWN_UPTIME` prevents constant reboots during extended outages.
3. Logs all actions to `/var/log/wan_healer.log` and to the system log under the tag `wan_healer`.  
   You can view these in *System -> Log Files -> General*.


## How to install
Recomendation: If you're on ZFS, create a snapshot before making any changes or updates.

1. SSH into your OPNsense box.
2. Download the script:
    ```bash
   fetch -o ./wan_healer.sh https://raw.githubusercontent.com/larrypozdeev/opnsense-wan-healer/main/wan_healer.sh
   ```
4. Make it executable:
   ```bash
   chmod +x ./wan_healer.sh
   ```
5. Run it:
   ```bash
   ./wan_healer.sh
   ```
7. In the OPNsense GUI, go to System → Settings → Cron, click Add:
   - For Command, choose "Reconfigure or reboot when WAN is unresponsive"
   - I set the minutes to "3", so the script executes every 3 min. That's up to your preference.
   - Add a description, save, and apply
