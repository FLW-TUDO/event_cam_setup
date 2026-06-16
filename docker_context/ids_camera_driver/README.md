# Installation
Download the ids peak package from the IDS wedsite. For this code "IDS peak 2.4 für Linux 64-Bit - Debian-Paket" works without errors. Open the installation document and follow it.
https://de.ids-imaging.com/files/downloads/ids-peak/readme/ids-peak-linux-readme-2.6.2_EN.html

I faced problems understanding the installation document, as it is not clealry explained. Therefore, follow the below steps:
Install the dependencies using below command:

**sudo apt-get install (package name)**

Dependencies: libqt5core5a, libqt5gui5, libqt5widgets5, libqt5multimedia5, libqt5quick5, qml-module-qtquick-window2, qml-module-qtquick2, qtbase5-dev, qtdeclarative5-dev, qml-module-qtquick-dialogs, qml-module-qtquick-controls, qml-module-qtquick-layouts, qml-module-qt-labs-settings, qml-module-qt-labs-folderlistmodel, libusb-1.0-0, libatomic1

Go to the location where you downloaded the ids peak package and execute:

**sudo apt install ./ids-peak_(version)_(arch).deb**

# Installation of Python Bindings
1. After installation of IDS peak go to directory:
   /usr/local/share/ids/bindings/python/wheel/
2. Make sure python is installed
3. Enter in the command line:
   
    **python3 -m pip install ids_peak-(version)-cp(version)-cp(version)[m]-linux_(arch).whl**
   
 The version is the same as the default version of python on your machine.
 4. Similarly install ids_peak_ipl and ids_peak_afl.

# Troubleshooting (native install)

**`ids_peak` reports 0 devices even though `ueyeusbd` is running and its own log recognizes the camera** (`Model: UI304xCP-C ... FW` in `journalctl -u ueyeusbd` / syslog):

Check whether `ueye-api` actually finished configuring:

```bash
dpkg -l | grep ueye-api
```

A status of `iF` (half-configured) instead of `ii` means its postinst script failed — typically a leftover symlink from a previous install/upgrade attempt causes `ln: failed to create symbolic link '.../libueye_api.so.4.96': File exists`, which aborts the postinst and leaves the package broken. The daemon still talks to the camera over its own protocol, but `ids_peek`'s GenTL producer needs the fully-configured library and silently sees nothing. Fix:

```bash
sudo rm -f /opt/ids/ueye/lib/x86_64-linux-gnu/libueye_api.so.4.96
sudo dpkg --configure -a
sudo ldconfig
```

Confirm `dpkg -l | grep ueye-api` now shows `ii`, then restart `ueyeusbd` and re-check device detection:

```bash
sudo pkill -9 ueyeusbd
sudo rm -f /run/ueyed/ueyeusbd.pid
sudo /opt/ids/ueye/bin/ueyeusbd -c /etc/ids/ueye/ueyeusbd.conf -P /run/ueyed/ueyeusbd.pid
python3 -c "
from ids_peak import ids_peak as peak
peak.Library.Initialize()
dm = peak.DeviceManager.Instance()
dm.Update()
print('devices:', dm.Devices().size())
"
```

**Camera repeatedly disconnects/reconnects on its own** (`dmesg` shows `Disable of device-initiated U1/U2 failed` → `device firmware changed` → new device number, looping): the camera is likely connected through a USB hub instead of directly into a motherboard USB3 port. Plug it directly into the motherboard and use a short, good-quality USB3 cable. A single re-enumeration right after plugging in is normal (firmware upload); repeated cycles are not.
