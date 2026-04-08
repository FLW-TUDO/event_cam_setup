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
