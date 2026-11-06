# VPN13 Android launcher icon

The launcher artwork is stored at `assets/icon/vpn13_icon.jpg`.

After pulling the repository, run these commands from the `client` directory:

```powershell
D:\PCTMoveData\Desktop\flutter\bin\flutter.bat pub get
D:\PCTMoveData\Desktop\flutter\bin\dart.bat run flutter_launcher_icons
```

The generator writes the legacy and adaptive Android launcher resources under `android/app/src/main/res`. Then build the APK as usual. If Android still shows the old icon after installing, uninstall the previous VPN13 build and install the new APK.
