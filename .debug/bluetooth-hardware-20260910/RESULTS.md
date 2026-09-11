# Bluetooth hardware test results

Status: functional scenarios completed; one confirmed QML issue remains. Tested September 10, 2026, against real BlueZ devices on Hyprland. The selected WH-1000XM5s are re-paired, trusted, and connected, and their original default audio-output selection was restored. A final independent bluetoothctl connection persisted through checks at approximately 2, 7, and 15 seconds after the client exited.

## Coverage

| Scenario | Result | Evidence |
| --- | --- | --- |
| Disconnect confirmation | PASS | First row activation displayed Disconnect? and preserved the connection; a second activation after the guard disconnected the device. |
| Disconnect/reconnect | PASS | Two cycles through actual row handlers reached real BlueZ disconnection and connection states; pairing and Sony delegate identity survived. |
| Row reordering | PASS | Controlled reversal of the model using live BlueZ objects retained both initial delegate IDs. Independently, new real discoveries moved the reference row from index 1 to 6 with the same delegate ID. |
| Details identity | PASS | Name, address, connected, paired, trusted, and available battery fields matched the Sony object. |
| Details on disconnect | FUNCTIONAL PASS, QML WARNING | Details closed, the saved address cleared, and the frozen model was released. Reconnection did not reopen old details. The path emitted the binding loop described below. |
| Forget/removal | PASS | The user explicitly approved forgetting and re-pairing. BlueZ emitted InterfacesRemoved including org.bluez.Device1 for the Sony object. Quickshell emitted objectRemovedPost, destroyed the old Sony delegate, cleared details, and removed the object from the published array. |
| Re-pair | PASS | After the user re-entered pairing mode, the actual row handler paired and connected the new object. Trust was restored and its details bound to the new device. |
| Connection restoration | PASS with observation | The connection dropped sometime after the restoration probe exited. Its cause is unconfirmed. A direct bluetoothctl reconnect succeeded and persisted for the final 15-second observation; the Sony default audio sink was restored. |

The test invoked the real row signals and handlers through test-only IPC; it did not synthesize physical pointer input. No reference device was paired, connected, renamed, or forgotten. There were no active playback streams before disruptive operations, and each operation had a fresh audio-idle guard.

## Confirmed finding

**P2: disconnecting with Bluetooth details open causes a binding loop.**

Source: modules/menu/BluetoothList.qml:115 and :163. `_detailsOpen` depends on `_detailsAddr` and the device connection state; the row binds `expanded` to `_detailsOpen`. When disconnection turns that binding false, `onExpandedChanged` synchronously clears `_detailsAddr`, writing back into the dependency currently being evaluated.

The hardware log emitted `Binding loop detected for property "_detailsOpen"` on both details-open disconnection/removal paths. A separate offscreen fixture reproduced the same warning using the byte-identical, uninstrumented production BluetoothList and a synthetic device. It also confirmed that the details eventually closed and the frozen flag cleared. See loop-fixture-result.json and loop-fixture.log.

Recommended fix: handle disconnect-driven address cleanup from the device connection signal rather than writing into `_detailsOpen`'s inputs from its derived `expanded` handler. Re-run the isolated reproduction and the live details-open disconnect scenario after implementing it. No production fix was applied during this test task.

Reproduce without real hardware:

```sh
dbus-run-session -- python3 /home/olaolu/Desktop/dev/silere-shell/.debug/bluetooth-hardware-20260910/reproduce-loop.py
```

## Test corrections and evidence limits

- The initial test window could not import BluetoothList because it is an internal module type. Only the disposable tree's qmldir was adjusted; no hardware action occurred in that attempt.
- The first live test window had its own visible/screen binding loop. Its temporary visibility binding was corrected for the restoration probe. This was separate from the independently reproduced production details loop.
- The first removal assertion incorrectly required details to remain open at the removal signal. They were open before RemoveDevice, but BlueZ disconnected first, correctly triggering the existing close behavior. The original failed assertion is retained in checks.json; the before/after snapshots and the actual Device1 removal signal establish successful cleanup. This particular removal did not exercise deletion while the frozen flag remained true until the purge callback.
- After explicit user approval, automatic approval review initially rejected the run due to presumed active audio. PipeWire showed the Sony sink suspended and no playback streams. The runner gained checks before each disconnect/removal, and review then approved the guarded run.
- Exact underlying cause of the earlier adapter discovery hang and the later post-probe connection drop remains unconfirmed. No claim of sustained audio playback or long-duration connection stability is made.

## Cleanup

All test-owned Quickshell and monitor processes were stopped. The deployed shell PID 4045 was retained. Production Bluetooth.qml, BluetoothList.qml, and BluetoothDetails.qml match their pre-test SHA-256 hashes. Other outstanding repository changes were preserved. The evidence here redacts hardware addresses. Temporary instrumentation lives only in /tmp test copies, and the reusable reproduction uses synthetic hardware state.

## Follow-up: binding-loop fix

The confirmed details binding loop was subsequently fixed and verified with a regression and the connected WH-1000XM5s. See [fix verification](../bluetooth-details-fix-20260910/RESULTS.md). The original observations above describe the pre-fix test.
