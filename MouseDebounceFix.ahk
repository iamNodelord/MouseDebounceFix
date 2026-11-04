#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName MouseDebounceFix
;@Ahk2Exe-SetDescription MouseDebounceFix - anti-chatter filter for mouse buttons (AHK v2)
;@Ahk2Exe-SetVersion 1.0.0.0
;@Ahk2Exe-SetCopyright MIT License
; =============================================================================
;  MouseDebounceFix.ahk — портативная утилита антидребезга кнопок мыши
;  AutoHotkey v2.0 | Windows 11 x64
;
;  Что делает:
;    * подавляет эхо контакта (дребезг) на ЛКМ и ПКМ независимо;
;    * порог 10–150 мс, по умолчанию 105 мс, меняется на лету из окна;
;    * живой счётчик подавленных кликов;
;    * галка автозапуска: задача в Планировщике (Schedule.Service) с
;      Highest Privileges — старт при входе в систему без запроса UAC.
;
;  Настройки хранятся в config.ini рядом с exe:
;      [settings]
;      ms=105
;      startup=0
;
;  Запуск с ключом --tray (так стартует задача) — окно не показывать.
; =============================================================================

#SingleInstance Force
#UseHook True                  ; все хоткеи — через свой низкоуровневый WH_MOUSE_LL
#MaxThreads 255
#MaxThreadsPerHotkey 10
#MaxThreadsBuffer False

; --- Самоповышение прав (аргументы командной строки переносятся) ------------
if !A_IsAdmin {
    params := ""
    for a in A_Args
        params .= ' "' a '"'
    try Run('*RunAs "' A_ScriptFullPath '"' params)
    ExitApp
}

ListLines False
SetMouseDelay -1
SendMode "Input"
ProcessSetPriority "High"

; Точность системного таймера 1 мс: иначе поток хоткея просыпается на тике
; 15.6 мс и инжект нажатия опаздывает на 15–45 мс.
try DllCall("winmm\timeBeginPeriod", "UInt", 1)
OnExit(RestoreTimer)

; ------------------------------------------------------------------ конфиг ---
global APP_TITLE   := "MouseDebounceFix"
global TASK_NAME   := "MouseDebounceFixTask"
global CONFIG_PATH := A_ScriptDir "\config.ini"
global DEFAULT_MS  := 105

global DEBOUNCE_MS := ReadIniInt("settings", "ms", DEFAULT_MS, 10, 150)
global HIDDEN_MODE := (A_Args.Length >= 1 && A_Args[1] = "--tray")

global gLast    := Map("LButton", -1073741824, "RButton", -1073741824)
global gBlocked := Map("LButton", 0, "RButton", 0)

global gGui := 0, gSlider := 0, gValue := 0, gStats := 0, gChkStartup := 0

; ------------------------------------------------------------------ трей ---
A_TrayMenu.Delete()
A_TrayMenu.Add("Открыть окно", (*) => ShowMain())
A_TrayMenu.Add("Пауза (нативное поведение)", TogglePause)
A_TrayMenu.Add()
A_TrayMenu.Add("Выход", (*) => ExitApp())
A_IconTip := APP_TITLE " — антидребезг " DEBOUNCE_MS " мс"

; ----------------------------------------------------------------- хоткеи ---
; Без "~": событие гасится хуком. up инжектится явно — иначе кнопка «залипает».
LButton::OnDown("LButton")
RButton::OnDown("RButton")
LButton Up::OnUp("LButton")
RButton Up::OnUp("RButton")

if !HIDDEN_MODE
    ShowMain()

; ------------------------------------------------------------- обработчики ---
OnDown(btn, *) {
    Critical

    now   := A_TickCount
    delta := now - gLast[btn]                 ; знаковая разница: переживает
                                              ; переполнение 32-бит A_TickCount
    if (delta >= 0 && delta < DEBOUNCE_MS) {
        gBlocked[btn] += 1
        return                                ; дребезг: событие уничтожено
    }

    gLast[btn] := now
    SendLevel 0                               ; своя инъекция не попадает в свой хук
    Send "{" btn " Down}"
}

OnUp(btn, *) {
    Critical
    SendLevel 0
    Send "{" btn " Up}"
}

; -------------------------------------------------------------------- окно ---
ShowMain() {
    global gGui, gSlider, gValue, gStats, gChkStartup

    if IsObject(gGui) {
        try {
            gGui.Show()
            return
        }
        gGui := 0
    }

    gGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", APP_TITLE)
    gGui.SetFont("s10", "Segoe UI")
    gGui.MarginX := 20
    gGui.MarginY := 16
    gGui.OnEvent("Close", CloseMain)

    gGui.SetFont("s11 Bold")
    gGui.AddText("w400", "Порог подавления дребезга")
    gGui.SetFont("s9 Norm")
    gGui.AddText("w400 cGray", "Интервал между нажатиями, который считается эхом контакта.")

    gGui.SetFont("s22 Bold")
    gValue := gGui.AddText("w400 Center", DEBOUNCE_MS " мс")

    gGui.SetFont("s10 Norm")
    gSlider := gGui.AddSlider("w400 Range10-150 TickInterval10 ToolTip", DEBOUNCE_MS)
    gGui.SetFont("s9 Norm")
    gGui.AddText("w400 Center cGray", "10 мс … 150 мс")

    gGui.SetFont("s10 Bold")
    gStats := gGui.AddText("w400", "")
    gGui.SetFont("s10 Norm")

    gChkStartup := gGui.AddCheckbox("w400", "Запускать автоматически при старте Windows")
    gChkStartup.Value := StartupTaskExists() ? 1 : 0

    btnSave  := gGui.AddButton("x20 w200 Default", "Сохранить и применить")
    btnClose := gGui.AddButton("x+12 w140", "Закрыть")

    gGui.SetFont("s8 Norm")
    gGui.AddText("x20 w400 Center cGray", "Created by iamNodelord")
    gGui.SetFont("s10 Norm")

    gSlider.OnEvent("Change", OnSliderChange)
    btnSave.OnEvent("Click", OnSaveApply)
    btnClose.OnEvent("Click", CloseMain)
    gChkStartup.OnEvent("Click", OnStartupToggled)

    UpdateStats()
    SetTimer(UpdateStats, 400)
    gGui.Show("AutoSize Center")
}

CloseMain(*) {
    global gGui, gSlider, gValue, gStats, gChkStartup
    SetTimer(UpdateStats, 0)
    if IsObject(gGui)
        gGui.Destroy()
    gGui := 0
    gSlider := 0
    gValue := 0
    gStats := 0
    gChkStartup := 0
}

OnSliderChange(ctrl, *) {
    global gValue
    if IsObject(gValue)
        gValue.Text := ctrl.Value " мс"
}

OnSaveApply(*) {
    global gSlider
    ApplyThreshold(gSlider.Value)
    WriteIni("settings", "ms", gSlider.Value)
}

OnStartupToggled(ctrl, *) {
    if ctrl.Value {
        if !CreateStartupTask() {
            ctrl.Value := 0
            MsgBox "Не удалось создать задачу в Планировщике.`n`n"
                . "Утилита должна быть запущена от администратора.",
                APP_TITLE, "Iconx"
            return
        }
    } else {
        if !DeleteStartupTask()
            WriteIni("settings", "startup", 0)
    }
    WriteIni("settings", "startup", ctrl.Value ? 1 : 0)
}

UpdateStats() {
    global gStats
    if !IsObject(gStats)
        return
    try {
        gStats.Text := "Подавлено кликов: " (gBlocked["LButton"] + gBlocked["RButton"])
            . "   (ЛКМ " gBlocked["LButton"] " / ПКМ " gBlocked["RButton"] ")"
    }
}

; ---------------------------------------------------------------- действия ---
ApplyThreshold(ms) {
    DEBOUNCE_MS := ms                             ; супер-глобальная
    A_IconTip := A_IsSuspended
        ? APP_TITLE " — ПАУЗА (клики идут нативно)"
        : APP_TITLE " — антидребезг " ms " мс"
}

TogglePause(*) {
    Suspend -1
    if A_IsSuspended {
        A_TrayMenu.Check("Пауза (нативное поведение)")
        A_IconTip := APP_TITLE " — ПАУЗА (клики идут нативно)"
    } else {
        A_TrayMenu.Uncheck("Пауза (нативное поведение)")
        A_IconTip := APP_TITLE " — антидребезг " DEBOUNCE_MS " мс"
    }
}

RestoreTimer(*) {
    try DllCall("winmm\timeEndPeriod", "UInt", 1)
    return 0
}

; ------------------------------------------------------------ Планировщик ---
; Задача «при входе в систему», Highest Privileges, аргумент --tray.
;
; Важно: userId в RegisterTaskDefinition НЕ передаётся (пустая строка).
; Если передать имя/SID явно, Task Scheduler на MSA-аккаунтах отвечает
; 0x8007052E «Неверное имя пользователя или пароль» — проверено.
; Текущий пользователь подставляется автоматически при
; TASK_LOGON_INTERACTIVE_TOKEN. Резерв — schtasks /RL HIGHEST.
CreateStartupTask() {
    global TASK_NAME

    try {
        svc  := ComObject("Schedule.Service")
        svc.Connect()
        root := svc.GetFolder("\")
        td   := svc.NewTask(0)                    ; 0 = TASK_CREATE

        td.RegistrationInfo.Description := "MouseDebounceFix — anti-chatter filter"

        td.Settings.Enabled := true
        td.Settings.AllowDemandStart := true
        td.Settings.DisallowStartIfOnBatteries := false
        td.Settings.StopIfGoingOnBatteries := false
        td.Settings.StartWhenAvailable := true
        td.Settings.ExecutionTimeLimit := "PT0S"  ; без ограничения времени

        pr := td.Principal
        pr.LogonType := 3                         ; TASK_LOGON_INTERACTIVE_TOKEN
        pr.RunLevel  := 1                         ; TASK_RUNLEVEL_HIGHEST

        tr := td.Triggers.Create(9)               ; TASK_TRIGGER_LOGON
        tr.Enabled := true

        ac := td.Actions.Create(0)                ; TASK_ACTION_EXEC
        ac.Path := A_ScriptFullPath
        ac.Arguments := "--tray"
        ac.WorkingDirectory := A_ScriptDir

        ; 6 = TASK_CREATE_OR_UPDATE, 3 = TASK_LOGON_INTERACTIVE_TOKEN
        root.RegisterTaskDefinition(TASK_NAME, td, 6, "", "", 3)
    } catch {
        ; резерв: тот же результат через schtasks
        schCmd := A_ComSpec ' /c schtasks /Create /TN "' TASK_NAME '" /TR "\"'
        schCmd .= A_ScriptFullPath '\"" /SC ONLOGON /RL HIGHEST /F'
        try RunWait(schCmd, , "Hide")
    }

    return StartupTaskExists()
}

DeleteStartupTask() {
    global TASK_NAME
    try {
        svc := ComObject("Schedule.Service")
        svc.Connect()
        svc.GetFolder("\").DeleteTask(TASK_NAME, 0)
    } catch {
        try RunWait(A_ComSpec ' /c schtasks /Delete /TN "' TASK_NAME '" /F', , "Hide")
    }
    return !StartupTaskExists()
}

StartupTaskExists() {
    global TASK_NAME
    try {
        svc := ComObject("Schedule.Service")
        svc.Connect()
        svc.GetFolder("\").GetTask(TASK_NAME)
        return true
    } catch {
        return false
    }
}

; --------------------------------------------------------------------- ini ---
ReadIniInt(section, key, def, min, max) {
    v := ""
    try v := IniRead(CONFIG_PATH, section, key, "")
    if (v != "" && IsNumber(v)) {
        n := Round(v)
        if (n >= min && n <= max)
            return n
    }
    return def
}

WriteIni(section, key, value) {
    try IniWrite(value, CONFIG_PATH, section, key)
}
