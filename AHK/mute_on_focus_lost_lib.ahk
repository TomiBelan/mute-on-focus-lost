#Include "VA.ahk"
#Include "WinHook.ahk"

WinHook.Event.Add(0x3, 0x3, "MOFL_ForegroundChangeFn")  ; EVENT_SYSTEM_FOREGROUND

MOFL_CurrentMutingHwnd := -1

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

MOFL_ForegroundChangeFn(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime)
{
    global MOFL_CurrentMutingHwnd

    ZzzActiveTitle := WinGetTitle("ahk_id " hwnd)
    ZzzActivePID := WinGetPID("ahk_id " hwnd)
    ZzzActiveStyle := WinGetStyle("ahk_id " hwnd)

    MOFL_Log("event=" . event . " hwnd=" . hwnd . " title=" . SubStr(ZzzActiveTitle, 1, 15) . " pid=" . ZzzActivePID . " style=" . ZzzActiveStyle . " current=" . MOFL_CurrentMutingHwnd)

    if (MOFL_CurrentMutingHwnd == -1) {
        return
    }

    if (!WinExist("ahk_id " MOFL_CurrentMutingHwnd)) {
        return
    }

    ; Process only events for windows which are visible and have a window title.
    ; Otherwise we get spurious events when Alt+Tab starts (the task switcher window) and
    ; when it ends (some invisible window with an empty title).
    ; This might be related to: https://stackoverflow.com/q/65380485
    ; Also, EVENT_SYSTEM_SWITCHEND doesn't work: https://stackoverflow.com/q/65380485
    if ((ZzzActiveStyle & 0x10C00000) != 0x10C00000) {   ; WS_VISIBLE | WS_CAPTION
        MOFL_Log("  bad style, ignoring event")
        return
    }

    ZzzMutingPid := WinGetPID("ahk_id " MOFL_CurrentMutingHwnd)
    if !(Volume := GetVolumeObject(ZzzMutingPid)) {
        MsgBox("There was a problem retrieving the application volume interface")
        return
    }
    Mute := (hwnd != MOFL_CurrentMutingHwnd)
    MOFL_Log("  mute=" . mute)
    VA_ISimpleAudioVolume_SetMute(Volume.ptr, Mute)
}

MOFL_ToggleMute()
{
  ActivePid := WinGetPID("A")
  if !(Volume := GetVolumeObject(ActivePid)) {
    MsgBox("There was a problem retrieving the application volume interface")
    return
  }
  VA_ISimpleAudioVolume_GetMute(Volume.ptr, &Mute)  ;Get mute state
  ; Msgbox % "Application " ActivePID " is currently " (mute ? "muted" : "not muted")
  VA_ISimpleAudioVolume_SetMute(Volume.ptr, !Mute) ;Toggle mute state
}

MOFL_ToggleMuteOnFocusLostMode()
{
  global MOFL_CurrentMutingHwnd
  ZzzActiveHwnd := WinGetID("A")
  if (ZzzActiveHwnd = MOFL_CurrentMutingHwnd) {
    MOFL_CurrentMutingHwnd := -1
    SoundBeep(423, 300)
  } else {
    MOFL_CurrentMutingHwnd := ZzzActiveHwnd
    SoundBeep(523, 300)
  }
}

;Required for app specific mute
GetVolumeObject(Param := 0)
{
    static IID_IASM2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"
    , IID_IASC2 := "{bfb7ff88-7239-4fc9-8fa2-07c950be9c6d}"
    , IID_ISAV := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"

    ; Get PID from process name
    if !isInteger(Param)
    {
        ErrorLevel := ProcessExist(Param)
        Param := ErrorLevel
    }

    ; GetDefaultAudioEndpoint
    DAE := VA_GetDevice()

    ; activate the session manager
    VA_IMMDevice_Activate(DAE, IID_IASM2, 0, 0, &IASM2)

    ; enumerate sessions for on this device
    VA_IAudioSessionManager2_GetSessionEnumerator(IASM2, &IASE)
    VA_IAudioSessionEnumerator_GetCount(IASE, &Count)

    ISAV := ""

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

        ; If the process name is the one we are looking for
        if (SPID == Param)
        {
            ; Query for the ISimpleAudioVolume
            ISAV := ComObjQuery(IASC2, IID_ISAV)

            break
        }
    }
    ObjRelease(IASE)
    ObjRelease(IASM2)
    ObjRelease(DAE)
    return ISAV
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
