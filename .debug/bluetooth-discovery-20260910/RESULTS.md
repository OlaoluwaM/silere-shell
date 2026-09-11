# Bluetooth discovery diagnosis

The direct BlueZ discovery path also returned no devices during the initial 15-second scan. The shell UI is not the only failing path. The user confirmed Sony XM5 headphones were in pairing mode; the repeated scan is captured separately in confirmed-pairing-scan.json and inventory.json.

Current evidence: BlueZ 5.86 and kernel 6.18.50; adapter Powered=true, PowerState=off, Discovering=true; rfkill soft and hard blocks false; no connected device objects. btmgmt reports the controller powered. The kernel logged `hci0: Opcode 0x0402 failed: -16` at 15:49:10, alongside BlueZ `Failed to set mode: Busy (0x0a)`. These establish an abnormal Bluetooth stack state, not the precise root cause.

A service restart was selected as a controlled test of stale BlueZ state. It did not execute: systemctl without an authentication prompt was denied, and sudo -n required a password. This was operating-system authentication, not an automatic approval-review rejection. HCI monitoring likewise lacked the required capability. No service restart, power cycle, pairing, removal, or repository change occurred.

Next action requires the user to run `sudo systemctl restart bluetooth.service`, then repeat discovery with the headphones in pairing mode. Recovery remains unverified. If the scan still fails, capture privileged btmon while scanning to distinguish absent radio results, controller command failures, and BlueZ event handling before choosing a driver/firmware recovery.

The searched BlueZ issue 2241 shares a generic startup warning but differs in Discovering state, scan output, and hardware. It does not establish that this machine has the same bug.

## After the user restarted Bluetooth

The restart completed at 16:30:34 with new daemon PID 486616. Powered=true and PowerState=on now agreed, but a direct 20-second scan returned `Failed to start discovery: org.bluez.Error.InProgress`; Discovering was false three seconds into the scan and no device objects appeared. See post-restart-scan.json and post-restart-devices.txt.

A single power-cycle attempt found no connected devices, then returned `Failed to set power off: org.bluez.Error.Failed`. The power-on request succeeded, but BlueZ returned to Powered=true / PowerState=off. See power-off.json, power-on.json, post-power-state.json. This recovery did not clear the failure.

The guarded recover-controller.sh was prepared and passes bash -n. `modprobe -n -r -v btusb` resolves to only `rmmod btusb`. The script has NOT run. It verifies the single Intel 8087:0032 adapter, refuses connected devices, captures controller traffic, reloads btusb, restores the service, and scans. Privileged tracing and driver reload still require terminal sudo authentication.

The user proposed rebooting. A reboot is a reasonable next recovery experiment given the failed inquiry/discovery and power transitions; exact driver-versus-firmware cause remains unconfirmed. Reboot has NOT been initiated by the agent. Defer the prepared driver-reset script pending the reboot result. After reboot, put the Sony headphones back in pairing mode and repeat discovery. If failure remains, use privileged controller capture to determine the next change. No repository files changed during this Bluetooth investigation.

## Recovery verified after reboot

The new boot started at approximately 17:04:03 on September 10. BlueZ reports Powered=true, PowerState=on, Discovering=true, and WH-1000XM5 paired, bonded, trusted, unblocked, and connected. Battery is 40 percent. Current-boot Bluetooth kernel logs have no earlier inquiry-cancel failure; the generic BlueZ default-system-config warning remains despite successful operation.

An isolated offscreen probe imported the deployed shell's actual services/config/modules and read the real BlueZ device. It passed, confirming service availability, enabled state, Sony identity, paired/connected flags, connected count, battery conversion, and status text. The probe requested no discovery, connection, disconnection, or pairing changes. See connected-probe-result.json and connected-probe.log. This verifies the service data path; it is not a visual delegate/details interaction test.

Reboot recovered the observed discovery/connection failure. The exact driver-versus-firmware cause remains unconfirmed, and recurrence resistance is untested. The prepared driver reset is no longer needed. Disconnect/reconnect, row reordering, and forget-device/removal scenarios remain untested. No shell source fix was required for this recovery.

## Subsequent hardware validation

Disconnect/reconnect, reordering, and removal were subsequently tested. See [hardware results](../bluetooth-hardware-20260910/RESULTS.md) and the [details binding-loop fix](../bluetooth-details-fix-20260910/RESULTS.md). The untested scenarios above describe the earlier recovery checkpoint.
