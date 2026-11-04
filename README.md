# MouseDebounceFix

**Portable anti-chatter filter for mouse buttons on Windows 11** — kills the phantom
double/triple clicks produced by worn mechanical switches.

Built for the classic **Logitech G102 / G203 Omron double-click defect**, but works with
any mouse whose switches bounce.

![Platform](https://img.shields.io/badge/platform-Windows%2011%20x64-0078D6)
![Runtime](https://img.shields.io/badge/runtime-AutoHotkey%20v2%20(embedded)-green)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## The problem

A worn switch does not close cleanly. One physical press produces a burst of
2–5 "clicks" 40–120 ms apart. Windows treats every one of them as real input:
folders open twice, drag & drop drops early, text gets selected instead of clicked,
and in games a single shot becomes a burst.

## The solution

A single 1.3 MB portable executable that installs a low-level mouse hook
(`WH_MOUSE_LL`) and **destroys** any press that arrives sooner than the configured
threshold after the previous accepted press. Nothing is installed system-wide,
no drivers, no background services.

## Features

| | |
|---|---|
| 🖱️ **Both buttons** | `LButton` and `RButton` are tracked **independently** |
| 🎚️ **Adaptive threshold** | GUI slider **10–150 ms**, default **105 ms**, applied instantly — no restart |
| 📊 **Live counter** | Real-time count of suppressed clicks per button |
| 💾 **Persistent settings** | `config.ini` next to the executable |
| 🚀 **Zero-UAC autostart** | Checkbox creates a Task Scheduler task that runs **at logon with highest privileges** — no UAC prompt on boot |
| ✋ **Native behaviour kept** | Drag & drop, text selection and intentional double-clicks (150–300 ms) are untouched |
| ⏱️ **Low latency** | 1 ms multimedia timer (`timeBeginPeriod`) + `High` process priority |
| 📦 **No dependencies** | AutoHotkey runtime is embedded in the exe |

## Download

Take `MouseDebounceFix.exe` from the [Releases](../../releases) page.
Requires Windows 10/11 **x64**. No installation required.

## Usage

1. Run `MouseDebounceFix.exe` — Windows asks for elevation (the filter needs admin rights
   to work over elevated windows; see *Limitations*).
2. Move the slider to the smallest value that stops the phantom clicks
   (start at 105 ms; worn switches often need 80–120 ms).
3. Press **«Сохранить и применить»**.
4. Optional: tick **«Запускать автоматически при старте Windows»** to create the
   scheduled task.
5. Close the window — the tray icon keeps filtering. Menu: *open window / pause / exit*.

> The window title and tray tooltip are English; the control labels are Russian.
> Title: `MouseDebounceFix`, task name: `MouseDebounceFixTask`.

## How it works

```
physical press ──► WH_MOUSE_LL hook ──► delta = A_TickCount - lastAccepted
                                          │
                        delta < threshold ┤──► event destroyed (counter++)
                                          │
                        delta >= threshold└──► SendInput {button Down}
physical release ─────────────────────────► SendInput {button Up}
```

Details that matter:

* `#UseHook True` — every hotkey goes through the script's own low-level hook.
* Hotkeys are registered **for both `down` and `up`**: when AHK swallows a mouse
  `down`, it also swallows the paired `up`, so the release is injected explicitly.
  Without this the button "sticks" after a long hold and drag & drop breaks
  (this was caught by an automated test, not by luck).
* `DllCall("winmm\timeBeginPeriod", 1)` — without a 1 ms timer the hotkey thread only
  wakes on the 15.6 ms scheduler tick and the injected press lags 15–45 ms.
* `ProcessSetPriority "High"`, `Critical` inside handlers, `SendLevel 0` so the
  injected events never re-enter the script's own hooks.
* Self-elevation block at the very top (`Run '*RunAs'`), with command-line arguments
  forwarded so `--tray` survives the UAC relaunch.

## Autostart without UAC

Ticking the checkbox creates a Task Scheduler task via the `Schedule.Service` COM API:

* trigger: **at logon**
* principal: current user, `TASK_LOGON_INTERACTIVE_TOKEN`
* `RunLevel = Highest` (elevated, so no UAC dialog)
* action: `MouseDebounceFix.exe --tray` (starts silently in the tray)

The checkbox state mirrors the **actual** existence of the task, not just a stored flag.
Unticking removes the task completely.

> Implementation note: `RegisterTaskDefinition` must be called **without** an explicit
> `userId`/SID. Passing one makes Task Scheduler answer `0x8007052E` on Microsoft-account
> profiles (verified on 7 variants). If COM ever fails, the code falls back to
> `schtasks /Create … /SC ONLOGON /RL HIGHEST /F`.

## Configuration file

`config.ini`, in the same directory as the executable:

```ini
[settings]
ms=105
startup=1
```

## Build from source

Requirements: [AutoHotkey v2](https://www.autohotkey.com/) + `Ahk2Exe`.

```powershell
$ahk2exe = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
$base    = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
Start-Process $ahk2exe -Wait -ArgumentList `
    '/in','"MouseDebounceFix.ahk"', `
    '/out','"MouseDebounceFix.exe"', `
    '/base',('"'+$base+'"'),'/silent'
```

Or simply run the script directly with the AutoHotkey v2 interpreter.

## Limitations & fair warning

* **Injected events carry the `LLMHF_INJECTED` flag.** No user-mode filter can avoid
  that; only a signed kernel driver (e.g. Interception) produces flag-free input.
* The utility does **not** amplify input: exactly one injected press per accepted
  physical press, no macros, no automation, no timing manipulation. Still, many
  anti-cheat systems (EAC, BattlEye, Vanguard, FACEIT) prohibit *any* input-injecting
  software — using this in online games is at your own risk and may violate their rules.
* Admin rights are required, so manual launches show a UAC prompt.
  The scheduled task is the silent path.
* The exe is unsigned, so SmartScreen may warn on first run.
* A software filter treats the symptom. A worn switch is a hardware failure —
  replacing the switch (or buying an optical-switch mouse) is the permanent fix.

## License

MIT — see [LICENSE](LICENSE).
