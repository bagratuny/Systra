# Systra 0.9.4

A native macOS system monitor with a dashboard, menu bar controls, and detailed resource usage by application and process.

## Features

- CPU, memory, GPU, disk, network, temperatures, and detailed system uptime.
- Applications and background services with expandable process groups, sorting, and configurable columns.
- Application summaries with CPU/memory history and process role breakdowns.
- Restart, quit, and Force Quit with confirmation and process identity checks.
- Configurable menu bar metrics and a popover showing resource-intensive applications.
- English and Russian interfaces, appearance settings, and launch at login.
- Animated tabs, readable temperature groups, and the current Systra icon in About.

## Build 33

This build uses Systra identifiers throughout the application and source code, including its bundle identifier and sensor bridge.

## Installation

Download `Systra-0.9.4-build33-macOS-arm64.zip`, extract it, and move `Systra.app` to Applications.

Requirements: **macOS 14 or later** and **Apple Silicon (M1 or later)**. The build is ad-hoc signed, without Developer ID signing or Apple notarization. macOS may require additional confirmation on first launch. The archive checksum is included in `SHA256SUMS-build33.txt`.

Developed by **Arsen Kocharyan**.
