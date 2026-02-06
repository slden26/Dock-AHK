#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

global PanelsDir := A_ScriptDir "\Panels"
if !DirExist(PanelsDir)
    DirCreate(PanelsDir)

global DockInstances := Map()
global RegPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global AppName := "MyDock"

; --- Настройка трея ---
Tray := A_TrayMenu
Tray.Delete()
Tray.Add("Добавить панель", (*) => CreateNewDock())
Tray.Add("Перерисовать все", (*) => ReloadAll())
Tray.Add("Автозапуск с Windows", (*) => ToggleStartup())

; Проверяем реестр при запуске, чтобы поставить галочку
try {
    RegRead(RegPath, AppName)
    Tray.Check("Автозапуск с Windows")
}

Tray.Add()
Tray.Add("Выход", (*) => ExitApp())

if !DirExist(PanelsDir "\Panel1")
    DirCreate(PanelsDir "\Panel1")

OnMessage(0x0201, WM_LBUTTONDOWN)
OnMessage(0x0202, WM_LBUTTONUP)

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    for id, instance in DockInstances {
        if (HasProp(instance, "Gui") && instance.Gui.Hwnd = hwnd) {
            if !instance.Locked {
                PostMessage(0xA1, 2,,, "ahk_id " hwnd)
                return 0
            }
        }
    }
}

WM_LBUTTONUP(wParam, lParam, msg, hwnd) {
    for id, instance in DockInstances {
        if (HasProp(instance, "Gui") && instance.Gui.Hwnd = hwnd)
            instance.SavePosition()
    }
}

class DockPanel {
    __New(ID) {
        this.ID := ID
        this.Path := PanelsDir "\Panel" ID
        this.IsHidden := false
        this.LoadSettings()
        this.Render()
        SetTimer(() => this.WatchMouse(), 200)
    }

    LoadSettings() {
        s := "Panel" this.ID
        this.Locked := IniRead("config.ini", s, "Locked", 0), this.IcoSize := IniRead("config.ini", s, "Size", 42)
        this.Transp := IniRead("config.ini", s, "Transp", 250), this.BgColor := IniRead("config.ini", s, "BgColor", "1A1A1A")
        this.PosX := IniRead("config.ini", s, "PosX", "Center"), this.PosY := IniRead("config.ini", s, "PosY", "Center")
        this.AutoHide := IniRead("config.ini", s, "AutoHide", 0)
    }

    CreateGui() {
        if HasProp(this, "Gui")
            this.Gui.Destroy()
        this.Gui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x80000", "MyDock_" this.ID)
        this.Gui.BackColor := this.BgColor
        this.Menu := Menu()
        this.Menu.Add("Закрепить", (n, p, m) => this.ToggleLock(m))
        (this.Locked ? this.Menu.Check("Закрепить") : 0)
        this.Menu.Add("Автоскрытие", (n, p, m) => this.ToggleAutoHide(m))
        (this.AutoHide ? this.Menu.Check("Автоскрытие") : 0)
        this.Menu.Add("Добавить панель", (*) => CreateNewDock())
        this.Menu.Add("Настройки", (*) => this.ShowSettings())
        this.Menu.Add("Удалить панель", (*) => this.DeletePanel())
        this.Menu.Add("Выход", (*) => ExitApp())
        this.Gui.OnEvent("ContextMenu", (*) => this.Menu.Show())
        this.Gui.OnEvent("DropFiles", (g, c, f, *) => this.OnDrop(f))
    }

    Render() {
        this.CreateGui()
        this.Gui.SetFont("s" (this.IcoSize/5) " cGray")
        this.Gui.Add("Text", "x5 y" (this.IcoSize/3) " BackgroundTrans", "⋮")
        
        Loop Files, this.Path "\*.lnk" {
            try {
                FileGetShortcut(A_LoopFileFullPath, &Target)
                pic := this.Gui.Add("Picture", ((A_Index=1)?"x25 y10":"x+15 y10") " w" this.IcoSize " h" this.IcoSize, "HICON:" LoadPicture(Target, "w" this.IcoSize " h" this.IcoSize " Icon1", &Type))
                pic.OnEvent("Click", this.HandleIconClick.Bind(this, A_LoopFileFullPath))
            }
        }
        
        this.Gui.Add("Text", "x+10 w1", "") 
        posStr := (IsNumber(this.PosX) ? "x" this.PosX : "xCenter") " " (IsNumber(this.PosY) ? "y" this.PosY : "yCenter")
        this.Gui.Show("AutoSize NoActivate " posStr)
        try WinSetTransparent(this.Transp, "ahk_id " this.Gui.Hwnd)
        WinGetPos(&realX, &realY, &W, &H, "ahk_id " this.Gui.Hwnd)
        this.PosX := realX, this.PosY := realY
        Rgn := DllCall("gdi32.dll\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", W, "Int", H, "Int", 20, "Int", 20, "Ptr")
        DllCall("user32.dll\SetWindowRgn", "Ptr", this.Gui.Hwnd, "Ptr", Rgn, "Int", 1)
    }

    OnDrop(files) {
        MouseGetPos(&mX)
        this.Gui.GetPos(&dX)
        currentFiles := []
        Loop Files, this.Path "\*.lnk" {
            cleanName := RegExReplace(A_LoopFileName, "^\d+_(.*)", "$1")
            currentFiles.Push({path: A_LoopFileFullPath, name: cleanName})
        }
        relX := mX - dX - 25
        step := this.IcoSize + 15
        insertIdx := Floor(relX / step) + 1
        (insertIdx < 1 ? insertIdx := 1 : 0)
        (insertIdx > currentFiles.Length + 1 ? insertIdx := currentFiles.Length + 1 : 0)
        for file in files {
            SplitPath(file, &name)
            currentFiles.InsertAt(insertIdx, {path: file, name: name ".lnk", isNew: true})
            insertIdx++
        }
        for i, fileObj in currentFiles {
            newName := Format("{1:03}_{2}", i, fileObj.name)
            if HasProp(fileObj, "isNew")
                FileCreateShortcut(fileObj.path, this.Path "\" newName)
            else
                FileMove(fileObj.path, this.Path "\" newName, 1)
        }
        this.Render()
    }

    HandleIconClick(filePath, *) {
        if GetKeyState("Shift") {
            SplitPath(filePath, &name)
            if MsgBox("Удалить ярлык " name "?", "Удаление", "YesNo Icon!") = "Yes" {
                FileDelete(filePath), this.Render()
            }
        } else Run(filePath)
    }

    SavePosition() {
        if HasProp(this, "Gui") {
            this.Gui.GetPos(&x, &y)
            this.PosX := x, this.PosY := y
            IniWrite(x, "config.ini", "Panel" this.ID, "PosX"), IniWrite(y, "config.ini", "Panel" this.ID, "PosY")
        }
    }

    WatchMouse() {
        if !this.AutoHide || !HasProp(this, "Gui")
            return
        try {
            MouseGetPos(&mX, &mY)
            this.Gui.GetPos(&dX, &dY, &dW, &dH)
            Margin := 10
            Over := (mX >= dX-Margin && mX <= dX+dW+Margin && mY >= dY-Margin && mY <= dY+dH+Margin)
            if Over && this.IsHidden {
                WinSetTransparent(this.Transp, "ahk_id " this.Gui.Hwnd)
                this.IsHidden := false
            } else if !Over && !this.IsHidden {
                WinSetTransparent(1, "ahk_id " this.Gui.Hwnd)
                this.IsHidden := true
            }
        }
    }

    ToggleAutoHide(m) => (this.AutoHide := !this.AutoHide, IniWrite(this.AutoHide, "config.ini", "Panel" this.ID, "AutoHide"), m.ToggleCheck("Автоскрытие"))
    ToggleLock(m) => (this.Locked := !this.Locked, IniWrite(this.Locked, "config.ini", "Panel" this.ID, "Locked"), m.ToggleCheck("Закрепить"))

    ShowSettings() {
        SetGui := Gui("+AlwaysOnTop", "Настройки панели " this.ID)
        SetGui.SetFont("s10", "Segoe UI")
        SetGui.Add("Text", "vTxtSize w260 Center", "Размер: " this.IcoSize)
        sldS := SetGui.Add("Slider", "w260 Range32-128 NoTicks", this.IcoSize)
        sldS.OnEvent("Change", (s, *) => SetGui["TxtSize"].Value := "Размер: " s.Value)
        SetGui.Add("Text", "vTxtTrans w260 Center", "Прозрачность: " this.Transp)
        sldT := SetGui.Add("Slider", "w260 Range5-25 NoTicks", this.Transp / 10)
        sldT.OnEvent("Change", (t, *) => (val := t.Value * 10, SetGui["TxtTrans"].Value := "Прозрачность: " val, WinSetTransparent(val, "ahk_id " this.Gui.Hwnd)))
        btnCol := SetGui.Add("Button", "w260 h30", "ЦВЕТ ПАНЕЛИ")
        btnCol.OnEvent("Click", (*) => (c := ChooseColor(this.BgColor), (c != -1) ? (this.BgColor := c, this.Gui.BackColor := c) : 0))
        btnSave := SetGui.Add("Button", "w260 h40", "СОХРАНИТЬ")
        btnSave.OnEvent("Click", (*) => (this.IcoSize := sldS.Value, this.Transp := sldT.Value * 10, this.SaveData(), SetGui.Destroy(), this.Render()))
        SetGui.Show()
    }

    SaveData() {
        s := "Panel" this.ID
        this.Gui.GetPos(&x, &y)
        IniWrite(this.IcoSize, "config.ini", s, "Size"), IniWrite(this.Transp, "config.ini", s, "Transp")
        IniWrite(this.BgColor, "config.ini", s, "BgColor"), IniWrite(x, "config.ini", s, "PosX"), IniWrite(y, "config.ini", s, "PosY")
    }

    DeletePanel() {
        if MsgBox("Удалить панель " this.ID "?", "Удаление", "YesNo Icon!") = "Yes" {
            if (this.ID = 1) {
                MsgBox("Основную панель нельзя удалить.", "Внимание")
                return
            }
            this.Gui.Destroy(), DockInstances.Delete(this.ID)
            try DirDelete(this.Path, 1)
            try IniDelete("config.ini", "Panel" this.ID)
        }
    }
}

; --- Глобальные функции ---
ToggleStartup() {
    try {
        RegRead(RegPath, AppName)
        RegDelete(RegPath, AppName)
        A_TrayMenu.Uncheck("Автозапуск с Windows")
    } catch {
        RegWrite(A_ScriptFullPath, "REG_SZ", RegPath, AppName)
        A_TrayMenu.Check("Автозапуск с Windows")
    }
}

CreateNewDock() {
    ID := 1
    while DirExist(PanelsDir "\Panel" ID)
        ID++
    DirCreate(PanelsDir "\Panel" ID)
    DockInstances[ID] := DockPanel(ID)
}

ReloadAll() {
    for id, instance in DockInstances
        instance.Render()
}

if DirExist(PanelsDir) {
    Loop Files, PanelsDir "\*", "D" {
        if RegExMatch(A_LoopFileName, "Panel(\d+)", &m)
            DockInstances[m[1]] := DockPanel(m[1])
    }
}

ChooseColor(DefaultColor) {
    static CustomColors := Buffer(64, 0)
    BGR := "0x" SubStr(DefaultColor, 5, 2) SubStr(DefaultColor, 3, 2) SubStr(DefaultColor, 1, 2)
    cc := Buffer(A_PtrSize * 9, 0), NumPut("UInt", cc.Size, cc, 0), NumPut("Ptr", A_ScriptHwnd, cc, A_PtrSize)
    NumPut("UInt", BGR, cc, A_PtrSize * 3), NumPut("Ptr", CustomColors.Ptr, cc, A_PtrSize * 4), NumPut("UInt", 0x103, cc, A_PtrSize * 5)
    if DllCall("comdlg32\ChooseColor", "Ptr", cc, "UInt") {
        resBGR := NumGet(cc, A_PtrSize * 3, "UInt")
        return Format("{1:02X}{2:02X}{3:02X}", resBGR & 0xFF, (resBGR >> 8) & 0xFF, (resBGR >> 16) & 0xFF)
    }
    return -1
}