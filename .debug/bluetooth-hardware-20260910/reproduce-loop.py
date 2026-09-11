from pathlib import Path
import shutil,os,subprocess,time,re,json
out=Path('/tmp/silere-bt-loop-repro');out.mkdir(parents=True,exist_ok=True);repo=Path('/home/olaolu/Desktop/dev/silere-shell');tree=out/'loop-fixture';tree.mkdir(exist_ok=True)
for folder in ['services','config','modules']:shutil.copytree(repo/folder,tree/folder,dirs_exist_ok=True)
p=tree/'modules/menu/qmldir';p.write_text(p.read_text().replace('internal BluetoothList BluetoothList.qml','BluetoothList 1.0 BluetoothList.qml'))
(tree/'services/Bluetooth.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
 id: root
 property bool available: true
 property bool enabled: true
 property bool _devicesFrozen: false
 property string errorAddr: ""
 property string errorKind: ""
 property string lastError: ""
 property bool managerAvailable: false
 property QtObject probeDevice: QtObject {
  property string address: "test-device"
  property string deviceName: "Test headphones"
  property string icon: "audio-headset"
  property bool connected: true
  property bool paired: true
  property bool trusted: true
  property bool pairing: false
  property bool batteryAvailable: true
  property int state: 0
 }
 property var devices: [root.probeDevice]
 signal deviceRemoved(string address)
 function deviceLabel(d): string { return d.deviceName }
 function deviceGlyph(icon): string { return "" }
 function batteryPercent(d): int { return 40 }
 function setDevicesFrozen(on): void { root._devicesFrozen=on }
 function setScan(on): void {}
 function abandonAttempt(): void {}
}
''')
(tree/'probe.qml').write_text('''import QtQuick
import Quickshell
import "services"
import "modules/menu"
ShellRoot {
 id: root
 property int step: 0
 FloatingWindow {
  visible: true; width: 480; height: 420
  BluetoothList { id: list; width: 480; open: true }
 }
 Timer {
  interval: 400; repeat: true; running: true
  onTriggered: {
   if (root.step === 0) list._detailsAddr = "test-device"
   if (root.step === 1) { console.log("LOOP-TEST disconnect"); Bluetooth.probeDevice.connected = false }
   if (root.step === 2) {
    console.log("LOOP-TEST closed", list._detailsAddr === "", !Bluetooth._devicesFrozen)
    stop()
   }
   root.step++
  }
 }
}
''')
env=os.environ.copy()
for key in ['HYPRLAND_INSTANCE_SIGNATURE','NIRI_SOCKET']:env.pop(key,None)
for key in ['XDG_CONFIG_HOME','XDG_STATE_HOME','XDG_CACHE_HOME','XDG_RUNTIME_DIR']:
 p=out/('loop-'+key.lower());p.mkdir(exist_ok=True,mode=0o700);env[key]=str(p)
env.update(QT_QPA_PLATFORM='offscreen',QT_NO_XDG_DESKTOP_PORTAL='1')
with (out/'loop-fixture.log').open('w') as log:
 p=subprocess.Popen(['qs','-p',str(tree/'probe.qml'),'--no-color'],env=env,stdout=log,stderr=subprocess.STDOUT)
 try:
  for _ in range(50):
   time.sleep(.1)
   if 'LOOP-TEST closed' in (out/'loop-fixture.log').read_text() or p.poll() is not None:break
 finally:
  p.terminate()
  try:p.wait(timeout=3)
  except subprocess.TimeoutExpired:p.kill();p.wait()
text=(out/'loop-fixture.log').read_text();print('\n'.join(s for s in text.splitlines() if 'LOOP-TEST' in s or 'Binding loop' in s or 'ERROR' in s or 'Error' in s))
source_same=(tree/'modules/menu/BluetoothList.qml').read_bytes()==(repo/'modules/menu/BluetoothList.qml').read_bytes()
result={'unmodified_BluetoothList':source_same,'binding_loop': 'Binding loop detected for property "_detailsOpen"' in text,'details_closed':'LOOP-TEST closed true true' in text}
(out/'loop-fixture-result.json').write_text(json.dumps(result,indent=2));print(result)
