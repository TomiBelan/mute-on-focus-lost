#Include "VA.ahk"
#Include "WinHook.ahk"

WinHook.Event.Add(0x3, 0x3, "MOFL_ForegroundChangeFn")  ; EVENT_SYSTEM_FOREGROUND

A_TrayMenu.Add("MOFL Report Status", MOFL_Report)

A_TrayMenu.Add("MOFL Toggle Log", MOFL_ToggleLog)

MOFL_Apps := Map()

MOFL_LogLines := []

MOFL_EnableLog := false

MOFL_Log(message)
{
    static LogGui := false
    static LogControl := false
    static LogShown := false
    LogMax := 30

    MOFL_LogLines.Push(message)
    if (MOFL_LogLines.Length > LogMax) {
        MOFL_LogLines.RemoveAt(1)
    }
    if (MOFL_EnableLog) {
        if !LogGui {
            ; https://www.autohotkey.com/docs/v2/lib/Gui.htm#ExOSD
            ; Pass through clicks: https://stackoverflow.com/q/13069717
            ; 0x80000 = WS_EX_LAYERED, 0x20 = WS_EX_TRANSPARENT
            LogGui := Gui()
            LogGui.Opt("+AlwaysOnTop -Caption +ToolWindow +Disabled +E0x80000 +E0x20")
            LogGui.BackColor := "111111"
            LogGui.SetFont("s12 w700", "Consolas")
            LogControl := LogGui.Add("Text", "cRed -Wrap R" LogMax " W" A_ScreenWidth, "")
            ; WinSetTransColor(LogGui.BackColor, LogGui)
            WinSetTransparent(150, LogGui)
        }
        if !LogShown {
            LogGui.Show("x0 y0 NoActivate")
            LogShown := true
        }

        lines := ""
        for index, line in MOFL_LogLines
            lines .= line . "`n"
        LogControl.Value := lines
    } else if (LogShown) {
        LogGui.Hide()
        LogShown := false
    }
}

MOFL_ToggleLog(*)
{
    global MOFL_EnableLog
    MOFL_EnableLog := !MOFL_EnableLog
    MOFL_Log(MOFL_EnableLog ? "Enabled log" : "Disabled log")
}

MOFL_Report(*)
{
    try {
        ActiveTitle := WinGetTitle("A")
        ActivePID := WinGetPID("A")
        ActiveProcessPath := WinGetProcessPath("A")
        result := "Active window:`n`"" ActiveTitle "`"`n" ActivePID " (" ActiveProcessPath ")"
    } catch {
        result := "Active window: none"
    }

    result .= "`n`nMute on focus lost:"
    have := false
    for prog, val in MOFL_Apps {
        if val {
            have := true
            result .= "`n* " prog
        }
    }
    if !have {
        result .= "`n  No programs"
    }

    result .= "`n`nAudio sessions:"
    MOFL_IterateAudioSessions(handler)
    handler(pid, isav) {
        path := "no path"
        try path := ProcessGetPath(pid)
        VA_ISimpleAudioVolume_GetMute(isav, &muted)
        result .= "`n* " pid " (" path ") " (muted ? "muted" : "unmuted")
    }

    MsgBox(result)
}

MOFL_ForegroundChangeFn(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime)
{
    ; AutoHotkey simulates multiple threads on one real thread. So it has disadvantages of both.
    ; According to https://www.autohotkey.com/docs/v2/misc/Threads.htm
    ; "By default, a given hotkey or hotstring subroutine cannot be run a second time if it is already running."
    ; But it seems MOFL_ForegroundChangeFn *can* be interrupted by itself.
    ; This is mostly just an annoyance because MOFL_Log lines are in wrong order.
    ;
    ; Calling "Critical" should fix the problem (prevent interruptions), but that didn't work.
    ; My guess is that the thread gets interrupted because it counts as an "emergency".
    ; Emergencies include: "Any callback indirectly triggered by the thread itself (e.g. via SendMessage or DllCall)."
    ; But does WinHook's CallbackCreate and DllCall count? I don't think it is "triggered by the thread itself". Unclear.
    ;
    ; Workaround: let's move most of the logic into a oneshot timer that calls "Critical".
    ; But let's check hwnd now, because it might not exist later (especially for the alt tab UI).
    ; Not that it matters (we ignore alt tab anyway) but this should be more robust against HWND reuse.

    ZzzActiveTitle := ""
    ZzzActivePID := ""
    ZzzActiveStyle := ""
    ZzzActiveClass := ""
    ZzzActiveProcessPath := ""
    ZzzSuccess := false
    ZzzLogLine := "event=" event " hwnd=" hwnd " failed to winget"

    try {
        ZzzActiveTitle := WinGetTitle("ahk_id " hwnd)
        ZzzActivePID := WinGetPID("ahk_id " hwnd)
        ZzzActiveStyle := WinGetStyle("ahk_id " hwnd)
        ZzzActiveClass := WinGetClass("ahk_id " hwnd)
        ZzzActiveProcessPath := WinGetProcessPath("ahk_id " hwnd)
        ZzzLogLine := (
            "event=" event
            " hwnd=" hwnd
            " title=" SubStr(ZzzActiveTitle, 1, 15) "..."
            " style=0x" Format("{1:X}", ZzzActiveStyle)
            " class=" ZzzActiveClass
            " pid=" ZzzActivePID
            " ppath=..." SubStr(ZzzActiveProcessPath, -15)
        )
        ZzzSuccess := true
    } catch {
    }

    SetTimer(MOFL_ForegroundChangeInner.Bind(ZzzActiveClass, ZzzActiveProcessPath, ZzzLogLine, ZzzSuccess), -1)
}

MOFL_ForegroundChangeInner(ZzzActiveClass, ZzzActiveProcessPath, ZzzLogLine, ZzzSuccess)
{
    Critical

    MOFL_Log(ZzzLogLine)

    if !ZzzSuccess {
        return
    }

    ; Try to ignore events related to the Alt+Tab GUI.
    ; It's better to wait until the user selects a window, so that we don't
    ; mute it if the user decides to stay on it.
    ; EVENT_SYSTEM_SWITCHEND doesn't work: https://stackoverflow.com/q/49588438
    ; This detection algorithm is based on: https://stackoverflow.com/q/65380485
    if (ZzzActiveProcessPath = A_WinDir "\explorer.exe") && (
            ZzzActiveClass = "MultitaskingViewFrame" ||
            ZzzActiveClass = "ForegroundStaging" ||
            ZzzActiveClass = "TaskSwitcherWnd" ||
            ZzzActiveClass = "TaskSwitcherOverlayWnd") {
        MOFL_Log("  looks like alt tab, ignoring event")
        return
    }

    ; TODO: Do we still need to ignore hidden windows? (ZzzActiveStyle & 0x10000000 = 0) ; WS_VISIBLE

    MOFL_IterateAudioSessions(handler)
    handler(pid, isav) {
        try {
            name := ProcessGetName(pid)
            path := ProcessGetPath(pid)
        } catch {
            name := ""
            path := ""
        }
        if !(name && path) {
            MOFL_Log("  " pid " (" name ") (" path ") empty")
        } else if !(MOFL_Apps.Get(name, false) || MOFL_Apps.Get(path, false)) {
            MOFL_Log("  " pid " (" name ") (" path ") not in MOFL mode")
        } else {
            muting := path != ZzzActiveProcessPath
            MOFL_Log("  " pid " (" name ") (" path ") " (muting ? "muting!" : "unmuting!"))
            VA_ISimpleAudioVolume_SetMute(isav, muting)
        }
    }
}

MOFL_ToggleMute()
{
  ActivePid := WinGetPID("A")
  ActivePath := WinGetProcessPath("A")
  found := false
  MOFL_IterateAudioSessions(handler)
  handler(pid, isav) {
    path := ""
    try path := ProcessGetPath(pid)
    if pid = ActivePid || (path && path = ActivePath) {
      found := true
      VA_ISimpleAudioVolume_GetMute(isav, &muted)
      MOFL_Log("Application " ActivePid " is currently " (muted ? "muted -> unmuting" : "not muted -> muting"))
      VA_ISimpleAudioVolume_SetMute(isav, !muted)
    }
  }
  if !found {
    MsgBox("Program '" ActivePath "' doesn't seem to be using audio")
  }
}

MOFL_ToggleMuteOnFocusLostMode()
{
  try {
    ActiveName := WinGetProcessName("A")
    ActivePath := WinGetProcessPath("A")
  } catch {
    ActiveName := ""
    ActivePath := ""
  }
  if !(ActiveName && ActivePath) {
    MsgBox("There is no active window")
  } else if (MOFL_Apps.Get(ActiveName, false) || MOFL_Apps.Get(ActivePath, false)) {
    MOFL_Log("Removing '" ActivePath "'")
    if MOFL_Apps.Has(ActiveName) {
      MOFL_Apps.Delete(ActiveName)
    }
    if MOFL_Apps.Has(ActivePath) {
      MOFL_Apps.Delete(ActivePath)
    }
    SoundBeep(423, 300)
  } else {
    found := false
    MOFL_IterateAudioSessions(handler)
    handler(pid, isav) {
      try {
        if ProcessGetPath(pid) = ActivePath {
          found := true
        }
      }
    }
    if !found {
      MsgBox("Program '" ActivePath "' doesn't seem to be using audio")
    } else {
      MOFL_Log("Adding '" ActivePath "'")
      MOFL_Apps[ActivePath] := true
      SoundBeep(523, 300)
    }
  }
}

MOFL_IterateAudioSessions(handler)
{
    static IID_IASM2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"
    , IID_IASC2 := "{bfb7ff88-7239-4fc9-8fa2-07c950be9c6d}"
    , IID_ISAV := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"

    ; GetDefaultAudioEndpoint
    DAE := VA_GetDevice()

    ; activate the session manager
    VA_IMMDevice_Activate(DAE, IID_IASM2, 0, 0, &IASM2)

    ; enumerate sessions for on this device
    VA_IAudioSessionManager2_GetSessionEnumerator(IASM2, &IASE)
    VA_IAudioSessionEnumerator_GetCount(IASE, &Count)

    ; search for an audio session with the required name
    Loop Count
    {
        ; Get the IAudioSessionControl object
        VA_IAudioSessionEnumerator_GetSession(IASE, A_Index-1, &IASC)

        ; Query the IAudioSessionControl for an IAudioSessionControl2 object
        IASC2 := ComObjQuery(IASC, IID_IASC2)
        ObjRelease(IASC)

        ; Get the session's process ID
        VA_IAudioSessionControl2_GetProcessID(IASC2.ptr, &SPID)

        ; Query for the ISimpleAudioVolume
        ISAV := ComObjQuery(IASC2, IID_ISAV)

        handler(SPID, ISAV.ptr)
    }
    ObjRelease(IASE)
    ObjRelease(IASM2)
    ObjRelease(DAE)
}

;
; ISimpleAudioVolume : {87CE5498-68D6-44E5-9215-6DA47EF883D8}
;
VA_ISimpleAudioVolume_SetMasterVolume(this, fLevel, GuidEventContext:="") {
    return DllCall(NumGet(NumGet(this+0, "UPtr")+3*A_PtrSize, "UPtr"), "ptr", this, "float", fLevel, "ptr", VA_GUID(GuidEventContext))
}
VA_ISimpleAudioVolume_GetMasterVolume(this, &fLevel) {
    return DllCall(NumGet(NumGet(this+0, "UPtr")+4*A_PtrSize, "UPtr"), "ptr", this, "float*", &fLevel := 0)
}
VA_ISimpleAudioVolume_SetMute(this, Muted, GuidEventContext:="") {
    return DllCall(NumGet(NumGet(this+0, "UPtr")+5*A_PtrSize, "UPtr"), "ptr", this, "int", Muted, "ptr", VA_GUID(GuidEventContext))
}
VA_ISimpleAudioVolume_GetMute(this, &Muted) {
    return DllCall(NumGet(NumGet(this+0, "UPtr")+6*A_PtrSize, "UPtr"), "ptr", this, "int*", &Muted := 0)
}
