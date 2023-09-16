#Include "VA.ahk"
#Include "WinHook.ahk"

WinHook.Event.Add(0x3, 0x3, "MOFL_ForegroundChangeFn")  ; EVENT_SYSTEM_FOREGROUND

MOFL_Apps := Map()

MOFL_LogLines := []

MOFL_EnableLog := false

MOFL_Log(message)
{
    MOFL_LogLines.Push(message)
    if (MOFL_LogLines.Length > 10) {
        MOFL_LogLines.RemoveAt(1)
    }
    if (MOFL_EnableLog) {
        lines := ""
        for index, line in MOFL_LogLines
            lines .= line . "`n"
        ToolTip(lines)
    }
}

MOFL_Report()
{
    ZzzActiveTitle := WinGetTitle("A")
    ZzzActivePID := WinGetPID("A")
    ZzzActiveProcessPath := WinGetProcessPath("A")
    result := "Active window:`n`"" ZzzActiveTitle "`"`n" ZzzActivePID " (" ZzzActiveProcessPath ")"

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
    ZzzActiveTitle := WinGetTitle("ahk_id " hwnd)
    ZzzActivePID := WinGetPID("ahk_id " hwnd)
    ZzzActiveStyle := WinGetStyle("ahk_id " hwnd)
    ZzzActiveProcessPath := WinGetProcessPath("ahk_id " hwnd)

    MOFL_Log(
        "event=" event
        " hwnd=" hwnd
        " title=" SubStr(ZzzActiveTitle, 1, 15)
        " style=" ZzzActiveStyle
        " pid=" ZzzActivePID
        " ppath=" ZzzActiveProcessPath
    )

    ; Process only events for windows which are visible and have a window title.
    ; Otherwise we get spurious events when Alt+Tab starts (the task switcher window) and
    ; when it ends (some invisible window with an empty title).
    ; This might be related to: https://stackoverflow.com/q/65380485
    ; Also, EVENT_SYSTEM_SWITCHEND doesn't work: https://stackoverflow.com/q/65380485
    if ((ZzzActiveStyle & 0x10C00000) != 0x10C00000) {   ; WS_VISIBLE | WS_CAPTION
        MOFL_Log("  bad style, ignoring event")
        return
    }

    MOFL_IterateAudioSessions(handler)
    handler(pid, isav) {
        try {
            name := ProcessGetName(pid)
            path := ProcessGetPath(pid)
        } catch TargetError {
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
  } catch TargetError {
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
