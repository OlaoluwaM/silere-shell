## QML Code Review Report

**Scope**: BluetoothList.qml changed lines and new Bluetooth-details regression files. Existing coordinator/workspace changes excluded.
**Files reviewed**: 3 QML files, plus their runner and registration changes.
**Issues found**: 0 confirmed remaining issues in this change.
**Python lint**: completed with findings, exit 1. Exact command, full output and status are in python-lint.command.json, python-lint.log and python-lint.exit. No findings on changed production lines. The fixture ordering diagnostic refers to a property inside its inline Device component; it does not identify a misplaced root property. Existing production diagnostics remain outside this diff.
**qmllint**: completed, clean, exit 0 for the production list, synthetic Bluetooth singleton, and probe under its proper temporary module context. All JSON file results report success=true with no warnings. See qmllint.* and probe-qmllint.*.
**Runtime checks**: the original regression failed on two _detailsOpen binding-loop warnings despite passing its seven functional assertions. The fixed regression passes all seven and the runtime-error scan in the full repository gate. The live test passed 15 checks, including actual BlueZ disconnection, reconnection, correct details cleanup, no QML errors, and restoration after the disposable probe exited.
**Deep-analysis coverage**: 6/6 completed as local analysis passes, not independent subagents.

### Lint findings

No changed-line production findings. The generic fixture ordering diagnostic and unchanged production warnings were reviewed in context; no further edits are required.

### Deep analysis findings

1. Bindings and properties: cleanup now runs from the device's connectedChanged event. The expanded binding only reads the selected address and connection state. Other-device disconnection is guarded by address equality. Synthetic tests cover both devices and selection changes; the live path is clean.
2. Layout and anchoring: the production change adds a nonvisual Connections object and leaves dimensions, visibility and anchors unchanged. The regression FloatingWindow uses implicit dimensions.
3. Loading and lifecycle: Connections is owned by its row, automatically follows modelData and disconnects when destroyed. No manual callback connection or retained QObject is introduced. Existing removal purge behavior is preserved.
4. Delegates: required modelData/index and the ScriptModel remain intact. The live Sony delegate survives the disconnect/reconnect. The new listener only observes that row's device.
5. States and transitions: disconnected selection is cleared immediately; reconnection cannot reopen old details. List-close cleanup and the existing disclosure animation remain in place. No new state machine, timer or delayed cleanup is introduced.
6. Performance and code quality: one direct device signal listener per instantiated row replaces a derived-property change handler. The handler performs constant-time checks, with no polling, collection scan, extra model reset or new production component.

### Investigation targets

None within this fix. This change does not claim to resolve the earlier adapter discovery hang or unexplained connection drop.
