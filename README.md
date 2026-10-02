# MacFanControl

[English](README.md) | [Русский](README.ru.md) | [Беларуская](README.be.md)

A native SwiftUI utility for **Mac mini M4**, tested on `Mac16,10` with macOS 27. It monitors temperatures and fan speed, and lets you control the fan manually.

Apple does not provide a public API for fan control. Sensor readings use SMC without elevated privileges; writing fan settings is handled by a small background `LaunchDaemon` running as root.

## Features

- Real-time fan monitoring. Mac mini M4 has one fan, with an approximate operating range of 1,000–4,900 RPM.
- CPU, GPU, NAND, and Wi-Fi temperature readings.
- Auto, Quiet, Balanced, Performance, and Maximum profiles, plus a custom speed slider.
- Automatic return to macOS fan control when the app exits or the Mac sleeps. If the app crashes, the helper's lease expires after about 20 seconds.
- Thermal safety: at CPU temperatures of 95 °C or higher, Quiet mode is raised to Performance.

## Build and install

Building requires a Mac with Xcode Command Line Tools. From the repository directory, run:

```bash
make
open dist/MacFanControl.app
```

To create a compressed disk image:

```bash
make dmg
```

The image is written to `dist/MacFanControl-macos-arm64.dmg`. Alternatively, install the app in `~/Applications` and launch it with:

```bash
make install
```

On first launch, choose **Allow fan control** and enter an administrator password. This installs the helper that writes the `F0Md` and `F0Tg` values to the SMC.

## Remove the background helper

To remove the system helper and its files:

```bash
sudo launchctl bootout system/ru.macfancontrol.helper
sudo rm -f /Library/LaunchDaemons/ru.macfancontrol.helper.plist
sudo rm -f /Library/PrivilegedHelperTools/ru.macfancontrol.helper
sudo rm -f /var/run/macfancontrol.sock
```

> **Safety:** Manual fan control changes the default macOS cooling behavior. Do not leave the fan at minimum speed under heavy load or attempt to bypass firmware limits.