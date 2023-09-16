# Mute on focus lost

This script can automatically mute playing audio for an application when it loses focus, and unmute it when it regains focus. The feature is sometimes also known as "mute in background", "mute when inactive", "mute on minimize", or "mute on Alt+Tab".

For example, this is useful for games if you need to Alt+Tab out of the game and watch a video, but the game sounds keep playing. Some games have a built in "mute on focus lost" option, but this script should work for apps and games that don't.

Press **Win+F1** to mute/unmute the active app right now.

Press **Win+F2** to enable "mute on focus lost" mode for the active app. A short beep will let you know it worked. In this mode, the app will mute when you minimize it or switch to another window, and unmute when you switch back. Pressing the key again will disable "mute on focus lost" mode for this app and play a lower beep.

### How to install it

**Step 1:** Download [AutoHotkey](https://www.autohotkey.com/). You will see two buttons. First, click "Download v2.0" and install it. Second, click "Download v1.1 (deprecated)" and install it.

<details><summary>Notes about AutoHotkey</summary>

- This script only needs AutoHotkey v2, but most other scripts usually need v1, so it's safest to get both.
- I prefer to install v2 first, but [either way should work](https://www.autohotkey.com/docs/v2/Program.htm#install_v1).
- Personally, I like to install Windows software with [Chocolatey](https://community.chocolatey.org/), but at the moment their autohotkey.install package is still v1.

</details>

**Step 2:** Download this script. Find the "Code" button on top of this GitHub page and choose "Download ZIP". Extract the zip file somewhere. (Or if you prefer, you can clone it with Git.)

**Step 3:** Double click the `mute_on_focus_lost.ahk` file. It should show a system tray icon.

**Step 4:** (optional) To run the script automatically after reboot, create a shortcut in the "Startup" folder. Open the "Startup" folder by pressing Win+R and typing `shell:startup`. Holding the Alt key, drag and drop the .ahk file to the "Startup" window. (It should say "Create link in Startup" while dragging.)

### Settings

If you want, you can change some settings by opening `mute_on_focus_lost.ahk` in Notepad.

After you save the file, run it again to load the new version.

- If you want to change the key bindings, just replace `#F1::` or `#F2::` with another key shortcut. See the AutoHotkey documentation for [modifier symbols](https://www.autohotkey.com/docs/v2/Hotkeys.htm#Symbols) (`#` means Win) and the [list of keys](https://www.autohotkey.com/docs/v2/KeyList.htm).

- The list of apps in "mute on focus lost" mode is not remembered permanently. It resets when the script restarts. If you want some programs to be in "mute on focus lost" mode by default, add lines like this. You can give the full .exe path or just the filename. You can still toggle it with Win+F2.

  ``` autohotkey
  MOFL_Apps["C:\Program Files (x86)\Steam\steamapps\common\Some Example Game\somegame.exe"] := true
  ```

- For debugging and troubleshooting, add these lines to enable more key shortcuts. These keys show internal details.

  ``` autohotkey
  #F3:: MOFL_Report()

  #F4:: MOFL_ToggleLog()
  ```

### Credits

- **mute-on-focus-lost** by TomiBelan (me)
- [**mute-current-application** by kristoffer-tvera](https://github.com/kristoffer-tvera/mute-current-application)
- [**VA.ahk** by Lexikos](https://www.autohotkey.com/board/topic/21984-vista-audio-control-functions/)
- [**WinHook.ahk** by FanaticGuru](https://www.autohotkey.com/boards/viewtopic.php?t=59149)
- [**AHK-v2-script-converter** by mmikeww](https://github.com/mmikeww/AHK-v2-script-converter)

Thanks!

### Similar software

- [How do I make Windows mute background applications?](https://superuser.com/q/1438597)
- <https://github.com/Codeusa/Borderless-Gaming>
- <https://github.com/nefares/Background-Muter>
- Linux: [How can I automatically mute an application when not in focus?](https://askubuntu.com/q/786055)
