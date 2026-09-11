#!/usr/bin/env bash
set -euo pipefail
umask 077
out="$(mktemp -d /tmp/silere-bt-recovery.XXXXXX)"
shopt -s nullglob
controllers=(/sys/class/bluetooth/hci*)
[[ ${#controllers[@]} == 1 && ${controllers[0]} == /sys/class/bluetooth/hci0 ]] || {
    echo 'Expected one Bluetooth controller; stopping.' >&2; exit 1;
}
usb=/sys/bus/usb/devices/3-10
[[ $(cat "$usb/idVendor") == 8087 && $(cat "$usb/idProduct") == 0032 ]] || {
    echo 'Intel adapter identity changed; stopping.' >&2; exit 1;
}
[[ $(readlink -f /sys/class/bluetooth/hci0/device) == "$(readlink -f "$usb")/3-10:1.0" ]] || exit 1
bluetoothctl devices Connected > "$out/connected-before.txt"
[[ ! -s "$out/connected-before.txt" ]] || {
    echo 'A Bluetooth device is connected; stopping.' >&2; exit 1;
}
sudo -v
bluetoothctl show > "$out/adapter-before.txt"
sudo -n timeout --signal=INT 35s btmon > "$out/controller.log" 2>&1 &
monitor_pid=$!
restore_needed=1
restore() {
    if [[ $restore_needed == 1 ]]; then
        sudo -n modprobe btusb || true
        sudo -n systemctl start bluetooth.service || true
    fi
}
trap restore EXIT
trap 'exit 130' INT TERM
sudo -n systemctl stop bluetooth.service
sudo -n modprobe -r btusb
sleep 1
sudo -n modprobe btusb
sudo -n systemctl start bluetooth.service
restore_needed=0
for ((attempt=0; attempt<10; attempt++)); do
    if bluetoothctl show > "$out/adapter-after.txt" 2>&1; then break; fi
    sleep 1
done
bluetoothctl --timeout 20 scan on > "$out/scan.txt" 2>&1 || true
bluetoothctl devices > "$out/devices-after.txt"
bluetoothctl show > "$out/adapter-after.txt"
journalctl -k --since '2 minutes ago' --no-pager -g 'Bluetooth|hci0|btusb' > "$out/kernel.txt"
journalctl -u bluetooth --since '2 minutes ago' --no-pager > "$out/service.txt"
monitor_status=0
wait "$monitor_pid" || monitor_status=$?
printf '%s\n' "$monitor_status" > "$out/monitor-status.txt"
printf 'Driver reset completed. Discovery results saved in %s\n' "$out"
if [[ -s "$out/devices-after.txt" ]]; then
    echo 'BlueZ now has discovered device objects. Check the shell Bluetooth list.'
else
    echo 'No devices discovered. The controller trace is ready for diagnosis.'
fi
