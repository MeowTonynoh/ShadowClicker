# ShadowClicker - by Tonynoh

Shadow Clicker, a clicker intended to be run as fileless for fun testing and also bypassing

## ⚠️ Important Notice

This tool uses **Windows native APIs** (SendInput, GetAsyncKeyState) to simulate mouse input at the system level. For this reason:

- **VirusTotal and some antiviruses may flag it as a false positive**
- The behavior (simulating mouse input, reading keyboard state globally) can be interpreted as suspicious
- **The tool is completely safe** - full source code is available for verification
- Some antiviruses may block execution: in that case, temporarily disable Real-Time protection during usage


## Usage

Run the following command in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/MeowTonynoh/Shadowclicker/main/ShadowClicker.ps1')"
```

The GUI opens automatically. No installation required.


## Features

Two independent autoclicker actions:

**[Left Action]** - Automated left mouse click at configurable CPS

**[Right Action]** - Automated right mouse click at configurable CPS


## How It Works

### GUI Overview

The borderless window is fully draggable and always-on-top, designed to stay accessible during gaming or other activities.

**Header**: Title bar with minimize and close buttons

**Control Panel**: Independent configuration for Left and Right actions

**Footer**: Status bar showing current autoclicker state


### Hotkey Binding

**Supported key types:**
- Function keys: `F1` through `F12`
- Alphabet keys: `A` through `Z`
- Digit keys: `D0` through `D9`
- Special keys: `Space`, `Shift`, `Control`, `Alt`
- Mouse side buttons: `XButton1`, `XButton2`

**How to bind a key:**
1. Click the key binding button (`none` by default) for Left or Right action
2. The button switches to `...` and the status bar shows *"Press a key"*
3. Press any supported key — it gets instantly registered
4. The button updates with the key name

**Toggle behavior:**
- First press → autoclicker **starts**
- Second press → autoclicker **stops**


### CPS Configuration

Each action has an independent CPS (Clicks Per Second) slider.

**Range**: 1 to 500 CPS

**Default**: 10 CPS

**Interaction:**
- Click and drag the slider to adjust CPS in real time
- The label updates live during drag
- If the autoclicker is active while adjusting, the timer restarts automatically at the new interval


### Input Simulation

**Technology**: Windows `SendInput` API via P/Invoke

**Click method:**
- Each click sends two `INPUT` events: `MOUSEDOWN` + `MOUSEUP`
- Left click: `MOUSEEVENTF_LEFTDOWN` + `MOUSEEVENTF_LEFTUP`
- Right click: `MOUSEEVENTF_RIGHTDOWN` + `MOUSEEVENTF_RIGHTUP`

**Why SendInput?**
- Works across most applications
- More reliable at high CPS values than standard simulation methods


### Hotkey Polling

**Technology**: `GetAsyncKeyState` via P/Invoke

**Poll interval**: 50ms

**Edge detection:**
- Tracks previous key state to avoid repeated toggling while a key is held
- Toggles only on **rising edge** (key goes from released to pressed)


## Antivirus False Positives

**It is normal for antivirus software to flag this file as suspicious.**

Technical reasons:

1. **Inline C# compilation**: Compiling native code at runtime via `Add-Type` → common in legitimate tools but also flagged by heuristics
2. **SendInput API**: Simulating system-level mouse input → flagged by behavioral analysis
3. **GetAsyncKeyState**: Global keyboard state polling → typical signature of keyloggers
4. **External script execution**: Running a script directly from a URL → flagged by some security policies

**Verify authenticity:**
- The full source is readable directly at the .ps1 file
- You can directly DM me if you have any suspicions :3

## Security and Privacy

- **The script does NOT send any data online**
- **The script does NOT log keystrokes** — key polling is used only to detect registered hotkeys
- **The script does NOT modify any system files**
- **The script does NOT collect personal information**

## Contacts

**Creator**: Tonynoh

💬 Discord: `tonyboy90_`

📎 GitHub: [MeowTonynoh](https://github.com/MeowTonynoh)

🎥 YouTube: tonynoh-07
