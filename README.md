# OPNsense WAN Healer
A small recovery script for OPNsense that brings the WAN connection back when it silently drops.

## Why this exists
Some modems or ISPs occasionally drop routing after a short outage, leaving OPNsense but without connection (pings fail).
This script automatically detects that state and restores the connection without having to manually reboot or reload the WAN interface.

## How it works
1. Periodically pings the default gateway and a couple of public IPs.  
2. If all fail:
   1. Runs `configctl interface reconfigure wan` which is same as to going to *Interfaces → Overview* and clicking "Reload" on the WAN interface.  
      This resolves the issue most of the time, so steps 2 and 3 usually don’t execute.  
   2. If still down, toggles the interface using `ifconfig <iface> down/up`, simulating a physical cable reconnect.  
   3. As a last resort, reboots the system if the previous steps fail.  
      `REBOOT_COOLDOWN_UPTIME` prevents constant reboots during extended outages.
3. Logs all actions to `/var/log/wan_healer.log` and to the system log under the tag `wan_healer`.  
   You can view these in *System → Log Files → General*.
