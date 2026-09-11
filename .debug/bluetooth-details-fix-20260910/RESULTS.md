# Bluetooth details fix verification

Verified September 10, 2026. The selected device now clears its details selection from connectedChanged instead of feeding back into the expanded binding.

- Before the fix: the new synthetic regression passed its functional assertions but correctly failed on two _detailsOpen binding-loop warnings.
- After the fix: all seven regression assertions pass with no QML runtime errors. The regression uses the actual production BluetoothList with a synthetic Bluetooth service and runs in test-logic.sh.
- Live WH-1000XM5 retest: all 15 checks pass. Actual row handlers disconnect and reconnect through BlueZ; details close and release the model, remain closed on reconnection, and emit no binding loops or QML errors. This invokes handlers through test-only IPC, not physical pointer input.
- The headphones remained connected through observations at approximately 2, 7, and 15 seconds after the disposable probe exited. Their default audio output was restored.
- Final ci-lint.sh and check.sh both exit 0; check.sh reports six environmental warnings. The full gate includes the seven Bluetooth assertions.
- qmllint reports no warnings for all three QML files in the appropriate module context. The generic Python linter retains reviewed findings outside the changed production lines; see REVIEW.md for all six local analysis passes.
- The tested production file SHA-256 matches the final source. The production shell was not restarted, and changes have not been committed or deployed.

The runner falls back to removing its generated temporary directory if rip is unavailable or fails. An earlier gate attempt passed functional checks but failed this cleanup; the final gate includes the corrected cleanup.

This fix does not establish a cause or resolution for the earlier adapter discovery hang or connection drop. No sustained audio playback or long-duration stability claim is made.

## Subsequent consistency cleanup

A later consistency pass corrected comments in BluetoothList.qml and Bluetooth.qml. The live-source hash records the tested pre-cleanup snapshot; these subsequent Bluetooth edits change comments only. The workspace setting description and test-runner executable mode were also corrected.
