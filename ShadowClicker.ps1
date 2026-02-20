# ShadowClicker - by Tonynoh

$ErrorActionPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- P/Invoke for SendInput and GetAsyncKeyState ---
# Random class names to avoid type conflicts if the script is reloaded in the same session
$script:uid1 = -join ((65..90) + (97..122) | Get-Random -Count 15 | % { [char]$_ })
$script:uid2 = -join ((65..90) + (97..122) | Get-Random -Count 14 | % { [char]$_ })
$tmpId = Get-Random -Minimum 1000 -Maximum 9999

$nativeCode = @"
using System;
using System.Runtime.InteropServices;

public class $($script:uid1) {
    [DllImport("user32.dll", CharSet = CharSet.Auto, CallingConvention = CallingConvention.StdCall)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public MOUSEINPUT mi; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT {
        public int dx; public int dy;
        public uint mouseData; public uint dwFlags;
        public uint time; public IntPtr dwExtraInfo;
    }

    private const uint INPUT_MOUSE          = 0;
    private const uint MOUSEEVENTF_LEFTDOWN  = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP    = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP   = 0x0010;

    public static void ClickLeft() {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_MOUSE; inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
        inputs[1].type = INPUT_MOUSE; inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
        SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void ClickRight() {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_MOUSE; inputs[0].mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
        inputs[1].type = INPUT_MOUSE; inputs[1].mi.dwFlags = MOUSEEVENTF_RIGHTUP;
        SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
}

public class $($script:uid2) {
    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);
    public static bool IsPressed(int vKey) { return (GetAsyncKeyState(vKey) & 0x8000) != 0; }
}
"@

if (-not ([System.Management.Automation.PSTypeName]$script:uid1).Type) {
    Add-Type -TypeDefinition $nativeCode
}

# --- Global state ---
$state = @{
    leftActive     = $false
    rightActive    = $false
    leftCps        = 10
    rightCps       = 10
    leftVK         = 0
    rightVK        = 0
    waitingLeft    = $false
    waitingRight   = $false
    skipToggleL    = $false
    skipToggleR    = $false
    leftTimer      = $null
    rightTimer     = $null
    pollTimer      = $null
    leftBarDrag    = $false
    rightBarDrag   = $false
    formDrag       = $false
    formDragOrigin = $null
    prevKeyL       = $false
    prevKeyR       = $false
    bgImage        = $null
}

# Supported keys map (VK codes)
$keyMap = @{
    'F1'=0x70;'F2'=0x71;'F3'=0x72;'F4'=0x73;'F5'=0x74;'F6'=0x75
    'F7'=0x76;'F8'=0x77;'F9'=0x78;'F10'=0x79;'F11'=0x7A;'F12'=0x7B
    'A'=0x41;'B'=0x42;'C'=0x43;'D'=0x44;'E'=0x45;'F'=0x46
    'G'=0x47;'H'=0x48;'I'=0x49;'J'=0x4A;'K'=0x4B;'L'=0x4C
    'M'=0x4D;'N'=0x4E;'O'=0x4F;'P'=0x50;'Q'=0x51;'R'=0x52
    'S'=0x53;'T'=0x54;'U'=0x55;'V'=0x56;'W'=0x57;'X'=0x58
    'Y'=0x59;'Z'=0x5A
    'D0'=0x30;'D1'=0x31;'D2'=0x32;'D3'=0x33;'D4'=0x34
    'D5'=0x35;'D6'=0x36;'D7'=0x37;'D8'=0x38;'D9'=0x39
    'Space'=0x20;'Shift'=0x10;'Control'=0x11;'Alt'=0x12
    'XButton1'=0x05;'XButton2'=0x06
}

# --- Decorative image (optional, non-blocking) ---
$imgPath = "$env:TEMP\$tmpId.tmp"
if (-not (Test-Path $imgPath)) {
    try {
        $wr = [System.Net.WebRequest]::Create('https://raw.githubusercontent.com/MeowTonynoh/ShadowClicker/main/download__4_.jpg')
        $wr.Timeout = 5000
        $resp = $wr.GetResponse()
        $stream = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($imgPath)
        $stream.CopyTo($fs)
        $fs.Close(); $stream.Close(); $resp.Close()
    } catch {}
}
if (Test-Path $imgPath) {
    try {
        # Load into MemoryStream so GDI does not lock the temp file
        $bytes = [System.IO.File]::ReadAllBytes($imgPath)
        $ms = New-Object System.IO.MemoryStream(@(,$bytes))
        $state.bgImage = [System.Drawing.Image]::FromStream($ms)
    } catch {}
}

# ============================================================
# GUI
# ============================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = ''
$form.Size            = New-Object System.Drawing.Size(420, 380)
$form.StartPosition   = 'CenterScreen'
$form.BackColor       = [System.Drawing.Color]::FromArgb(250, 250, 250)
$form.FormBorderStyle = 'None'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.ShowInTaskbar   = $true
$form.KeyPreview      = $true
$form.TopMost         = $true

# Titlebar
$header = New-Object System.Windows.Forms.Panel
$header.Location  = New-Object System.Drawing.Point(0, 0)
$header.Size      = New-Object System.Drawing.Size(420, 60)
$header.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$form.Controls.Add($header)

$btnMin = New-Object System.Windows.Forms.Button
$btnMin.Text      = [char]0x2500
$btnMin.Location  = New-Object System.Drawing.Point(345, 10)
$btnMin.Size      = New-Object System.Drawing.Size(30, 30)
$btnMin.FlatStyle = 'Flat'
$btnMin.FlatAppearance.BorderSize = 0
$btnMin.BackColor = [System.Drawing.Color]::Transparent
$btnMin.ForeColor = [System.Drawing.Color]::White
$btnMin.Font      = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$btnMin.Add_MouseEnter({ $btnMin.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70) })
$btnMin.Add_MouseLeave({ $btnMin.BackColor = [System.Drawing.Color]::Transparent })
$btnMin.Add_Click({ $form.WindowState = 'Minimized' })
$header.Controls.Add($btnMin)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text      = [char]0x00D7
$btnClose.Location  = New-Object System.Drawing.Point(380, 10)
$btnClose.Size      = New-Object System.Drawing.Size(30, 30)
$btnClose.FlatStyle = 'Flat'
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.BackColor = [System.Drawing.Color]::Transparent
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.Font      = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$btnClose.Add_MouseEnter({ $btnClose.BackColor = [System.Drawing.Color]::FromArgb(200, 50, 50) })
$btnClose.Add_MouseLeave({ $btnClose.BackColor = [System.Drawing.Color]::Transparent })
$btnClose.Add_Click({
    if ($state.leftTimer)  { $state.leftTimer.Stop();  $state.leftTimer.Dispose() }
    if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
    if ($state.pollTimer)  { $state.pollTimer.Stop();  $state.pollTimer.Dispose() }
    $form.Close()
})
$header.Controls.Add($btnClose)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = [char]0x2601 + ' Shadow Clicker ' + [char]0x2601
$lblTitle.Location  = New-Object System.Drawing.Point(0, 15)
$lblTitle.Size      = New-Object System.Drawing.Size(420, 35)
$lblTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.TextAlign = 'MiddleCenter'
$header.Controls.Add($lblTitle)

# Side image
$picBox = New-Object System.Windows.Forms.PictureBox
$picBox.Location = New-Object System.Drawing.Point(15, 75)
$picBox.Size     = New-Object System.Drawing.Size(150, 220)
$picBox.SizeMode = 'Zoom'
if ($state.bgImage) { $picBox.Image = $state.bgImage }
else { $picBox.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220) }
$form.Controls.Add($picBox)

# Controls panel
$ctrlPanel = New-Object System.Windows.Forms.Panel
$ctrlPanel.Location  = New-Object System.Drawing.Point(180, 75)
$ctrlPanel.Size      = New-Object System.Drawing.Size(225, 220)
$ctrlPanel.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($ctrlPanel)

# -- LEFT --
$lblLeft = New-Object System.Windows.Forms.Label
$lblLeft.Text      = [char]0x25C8 + ' Left Action'
$lblLeft.Location  = New-Object System.Drawing.Point(10, 15)
$lblLeft.Size      = New-Object System.Drawing.Size(205, 22)
$lblLeft.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$lblLeft.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$ctrlPanel.Controls.Add($lblLeft)

$btnLeftKey = New-Object System.Windows.Forms.Button
$btnLeftKey.Text      = 'none'
$btnLeftKey.Location  = New-Object System.Drawing.Point(10, 42)
$btnLeftKey.Size      = New-Object System.Drawing.Size(90, 28)
$btnLeftKey.FlatStyle = 'Flat'
$btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$btnLeftKey.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$btnLeftKey.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnLeftKey.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
$btnLeftKey.FlatAppearance.BorderSize  = 1
$btnLeftKey.Add_Click({
    $state.waitingLeft = $true
    $btnLeftKey.Text      = '...'
    $btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnLeftKey.ForeColor = [System.Drawing.Color]::White
    $lblStatus.Text = [char]0x2601 + ' Press a key ' + [char]0x2601
    $form.Focus()
})
$ctrlPanel.Controls.Add($btnLeftKey)

$lblLeftCps = New-Object System.Windows.Forms.Label
$lblLeftCps.Text      = "$($state.leftCps) CPS"
$lblLeftCps.Location  = New-Object System.Drawing.Point(110, 42)
$lblLeftCps.Size      = New-Object System.Drawing.Size(105, 28)
$lblLeftCps.Font      = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblLeftCps.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$lblLeftCps.TextAlign = 'MiddleRight'
$ctrlPanel.Controls.Add($lblLeftCps)

# Left slider
$sliderLeftBg = New-Object System.Windows.Forms.Panel
$sliderLeftBg.Location    = New-Object System.Drawing.Point(10, 75)
$sliderLeftBg.Size        = New-Object System.Drawing.Size(205, 12)
$sliderLeftBg.BackColor   = [System.Drawing.Color]::FromArgb(230, 230, 230)
$sliderLeftBg.BorderStyle = 'FixedSingle'
$sliderLeftBg.Cursor      = [System.Windows.Forms.Cursors]::Hand

$sliderLeftFill = New-Object System.Windows.Forms.Panel
$sliderLeftFill.Location  = New-Object System.Drawing.Point(0, 0)
$sliderLeftFill.Size      = New-Object System.Drawing.Size(21, 12)
$sliderLeftFill.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$sliderLeftFill.Enabled   = $false
$sliderLeftBg.Controls.Add($sliderLeftFill)

$sliderLeftBg.Add_MouseDown({
    param($s, $e)
    $state.leftBarDrag = $true
    $nc = [math]::Max(1, [math]::Min(500, [int]($e.X / 205.0 * 500)))
    $state.leftCps = $nc
    $lblLeftCps.Text = "$($state.leftCps) CPS"
    $sliderLeftFill.Width = [int](205 * ($state.leftCps / 500.0))
    if ($state.leftActive) {
        if ($state.leftTimer) { $state.leftTimer.Stop(); $state.leftTimer.Dispose() }
        $state.leftTimer = New-Object System.Windows.Forms.Timer
        $state.leftTimer.Interval = [math]::Max(1, [int](1000.0 / $state.leftCps))
        $state.leftTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickLeft()" })
        $state.leftTimer.Start()
    }
})
$sliderLeftBg.Add_MouseMove({
    param($s, $e)
    if ($state.leftBarDrag) {
        $nc = [math]::Max(1, [math]::Min(500, [int]($e.X / 205.0 * 500)))
        $state.leftCps = $nc
        $lblLeftCps.Text = "$($state.leftCps) CPS"
        $sliderLeftFill.Width = [int](205 * ($state.leftCps / 500.0))
        if ($state.leftActive) {
            if ($state.leftTimer) { $state.leftTimer.Stop(); $state.leftTimer.Dispose() }
            $state.leftTimer = New-Object System.Windows.Forms.Timer
            $state.leftTimer.Interval = [math]::Max(1, [int](1000.0 / $state.leftCps))
            $state.leftTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickLeft()" })
            $state.leftTimer.Start()
        }
    }
})
$sliderLeftBg.Add_MouseUp({ $state.leftBarDrag = $false })
$ctrlPanel.Controls.Add($sliderLeftBg)

# -- RIGHT --
$lblRight = New-Object System.Windows.Forms.Label
$lblRight.Text      = [char]0x25C8 + ' Right Action'
$lblRight.Location  = New-Object System.Drawing.Point(10, 105)
$lblRight.Size      = New-Object System.Drawing.Size(205, 22)
$lblRight.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$lblRight.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$ctrlPanel.Controls.Add($lblRight)

$btnRightKey = New-Object System.Windows.Forms.Button
$btnRightKey.Text      = 'none'
$btnRightKey.Location  = New-Object System.Drawing.Point(10, 132)
$btnRightKey.Size      = New-Object System.Drawing.Size(90, 28)
$btnRightKey.FlatStyle = 'Flat'
$btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$btnRightKey.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$btnRightKey.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnRightKey.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
$btnRightKey.FlatAppearance.BorderSize  = 1
$btnRightKey.Add_Click({
    $state.waitingRight = $true
    $btnRightKey.Text      = '...'
    $btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnRightKey.ForeColor = [System.Drawing.Color]::White
    $lblStatus.Text = [char]0x2601 + ' Press a key ' + [char]0x2601
    $form.Focus()
})
$ctrlPanel.Controls.Add($btnRightKey)

$lblRightCps = New-Object System.Windows.Forms.Label
$lblRightCps.Text      = "$($state.rightCps) CPS"
$lblRightCps.Location  = New-Object System.Drawing.Point(110, 132)
$lblRightCps.Size      = New-Object System.Drawing.Size(105, 28)
$lblRightCps.Font      = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblRightCps.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$lblRightCps.TextAlign = 'MiddleRight'
$ctrlPanel.Controls.Add($lblRightCps)

# Right slider
$sliderRightBg = New-Object System.Windows.Forms.Panel
$sliderRightBg.Location    = New-Object System.Drawing.Point(10, 165)
$sliderRightBg.Size        = New-Object System.Drawing.Size(205, 12)
$sliderRightBg.BackColor   = [System.Drawing.Color]::FromArgb(230, 230, 230)
$sliderRightBg.BorderStyle = 'FixedSingle'
$sliderRightBg.Cursor      = [System.Windows.Forms.Cursors]::Hand

$sliderRightFill = New-Object System.Windows.Forms.Panel
$sliderRightFill.Location  = New-Object System.Drawing.Point(0, 0)
$sliderRightFill.Size      = New-Object System.Drawing.Size(21, 12)
$sliderRightFill.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$sliderRightFill.Enabled   = $false
$sliderRightBg.Controls.Add($sliderRightFill)

$sliderRightBg.Add_MouseDown({
    param($s, $e)
    $state.rightBarDrag = $true
    $nc = [math]::Max(1, [math]::Min(500, [int]($e.X / 205.0 * 500)))
    $state.rightCps = $nc
    $lblRightCps.Text = "$($state.rightCps) CPS"
    $sliderRightFill.Width = [int](205 * ($state.rightCps / 500.0))
    if ($state.rightActive) {
        if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
        $state.rightTimer = New-Object System.Windows.Forms.Timer
        $state.rightTimer.Interval = [math]::Max(1, [int](1000.0 / $state.rightCps))
        $state.rightTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickRight()" })
        $state.rightTimer.Start()
    }
})
$sliderRightBg.Add_MouseMove({
    param($s, $e)
    if ($state.rightBarDrag) {
        $nc = [math]::Max(1, [math]::Min(500, [int]($e.X / 205.0 * 500)))
        $state.rightCps = $nc
        $lblRightCps.Text = "$($state.rightCps) CPS"
        $sliderRightFill.Width = [int](205 * ($state.rightCps / 500.0))
        if ($state.rightActive) {
            if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
            $state.rightTimer = New-Object System.Windows.Forms.Timer
            $state.rightTimer.Interval = [math]::Max(1, [int](1000.0 / $state.rightCps))
            $state.rightTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickRight()" })
            $state.rightTimer.Start()
        }
    }
})
$sliderRightBg.Add_MouseUp({ $state.rightBarDrag = $false })
$ctrlPanel.Controls.Add($sliderRightBg)

# Footer
$footer = New-Object System.Windows.Forms.Panel
$footer.Location  = New-Object System.Drawing.Point(0, 305)
$footer.Size      = New-Object System.Drawing.Size(420, 75)
$footer.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$form.Controls.Add($footer)

$lblDecL = New-Object System.Windows.Forms.Label
$lblDecL.Text      = [char]0x2605 + ' <3'
$lblDecL.Location  = New-Object System.Drawing.Point(15, 10)
$lblDecL.Size      = New-Object System.Drawing.Size(60, 32)
$lblDecL.Font      = New-Object System.Drawing.Font('Segoe UI', 12)
$lblDecL.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$lblDecL.TextAlign = 'MiddleLeft'
$footer.Controls.Add($lblDecL)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = [char]0x2601 + ' Ready ' + [char]0x2601
$lblStatus.Location  = New-Object System.Drawing.Point(80, 8)
$lblStatus.Size      = New-Object System.Drawing.Size(260, 32)
$lblStatus.Font      = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Italic)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$lblStatus.TextAlign = 'MiddleCenter'
$footer.Controls.Add($lblStatus)

$lblDecR = New-Object System.Windows.Forms.Label
$lblDecR.Text      = ';) ' + [char]0x2605
$lblDecR.Location  = New-Object System.Drawing.Point(345, 10)
$lblDecR.Size      = New-Object System.Drawing.Size(60, 32)
$lblDecR.Font      = New-Object System.Drawing.Font('Segoe UI', 12)
$lblDecR.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$lblDecR.TextAlign = 'MiddleRight'
$footer.Controls.Add($lblDecR)

$lblCredits = New-Object System.Windows.Forms.Label
$lblCredits.Text      = 'Made By Tonynoh'
$lblCredits.Location  = New-Object System.Drawing.Point(20, 45)
$lblCredits.Size      = New-Object System.Drawing.Size(380, 25)
$lblCredits.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$lblCredits.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$lblCredits.TextAlign = 'MiddleCenter'
$footer.Controls.Add($lblCredits)

# Drag borderless form
$form.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $state.formDrag = $true
        $state.formDragOrigin = $e.Location
    }
})
$form.Add_MouseMove({
    param($s, $e)
    if ($state.formDrag) {
        $form.Location = New-Object System.Drawing.Point(
            ($form.Location.X + $e.X - $state.formDragOrigin.X),
            ($form.Location.Y + $e.Y - $state.formDragOrigin.Y)
        )
    }
})
$form.Add_MouseUp({ $state.formDrag = $false; $state.leftBarDrag = $false; $state.rightBarDrag = $false })

$header.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $state.formDrag = $true
        $state.formDragOrigin = New-Object System.Drawing.Point($e.X, $e.Y)
    }
})
$header.Add_MouseMove({
    param($s, $e)
    if ($state.formDrag) {
        $form.Location = New-Object System.Drawing.Point(
            ($form.Location.X + $e.X - $state.formDragOrigin.X),
            ($form.Location.Y + $e.Y - $state.formDragOrigin.Y)
        )
    }
})
$header.Add_MouseUp({ $state.formDrag = $false })

# ============================================================
# Autoclicker toggle
# ============================================================
function Toggle-Left {
    $state.leftActive = -not $state.leftActive
    if ($state.leftActive) {
        $btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
        $btnLeftKey.ForeColor = [System.Drawing.Color]::White
        $lblStatus.Text = [char]0x2601 + ' ACTION 1 ACTIVE ' + [char]0x2601
        if ($state.leftTimer) { $state.leftTimer.Stop(); $state.leftTimer.Dispose() }
        $state.leftTimer = New-Object System.Windows.Forms.Timer
        $state.leftTimer.Interval = [math]::Max(1, [int](1000.0 / $state.leftCps))
        $state.leftTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickLeft()" })
        $state.leftTimer.Start()
    } else {
        $btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
        $btnLeftKey.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
        $lblStatus.Text = [char]0x2601 + ' Action 1 stopped ' + [char]0x2601
        if ($state.leftTimer) { $state.leftTimer.Stop() }
    }
}

function Toggle-Right {
    $state.rightActive = -not $state.rightActive
    if ($state.rightActive) {
        $btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
        $btnRightKey.ForeColor = [System.Drawing.Color]::White
        $lblStatus.Text = [char]0x2601 + ' ACTION 2 ACTIVE ' + [char]0x2601
        if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
        $state.rightTimer = New-Object System.Windows.Forms.Timer
        $state.rightTimer.Interval = [math]::Max(1, [int](1000.0 / $state.rightCps))
        $state.rightTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickRight()" })
        $state.rightTimer.Start()
    } else {
        $btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
        $btnRightKey.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
        $lblStatus.Text = [char]0x2601 + ' Action 2 stopped ' + [char]0x2601
        if ($state.rightTimer) { $state.rightTimer.Stop() }
    }
}

# Capture hotkey
$form.Add_KeyDown({
    param($s, $e)
    $ks = $e.KeyCode.ToString()
    if ($state.waitingLeft) {
        if ($keyMap.ContainsKey($ks)) {
            $state.leftVK         = $keyMap[$ks]
            $btnLeftKey.Text      = $ks
            $btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
            $btnLeftKey.ForeColor = [System.Drawing.Color]::Black
            $lblStatus.Text = [char]0x2601 + " Key set: $ks " + [char]0x2601
            $state.waitingLeft  = $false
            $state.skipToggleL  = $true
        }
    } elseif ($state.waitingRight) {
        if ($keyMap.ContainsKey($ks)) {
            $state.rightVK         = $keyMap[$ks]
            $btnRightKey.Text      = $ks
            $btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
            $btnRightKey.ForeColor = [System.Drawing.Color]::Black
            $lblStatus.Text = [char]0x2601 + " Key set: $ks " + [char]0x2601
            $state.waitingRight = $false
            $state.skipToggleR  = $true
        }
    }
})

# Poll hotkey (50ms)
$state.pollTimer = New-Object System.Windows.Forms.Timer
$state.pollTimer.Interval = 50

$state.pollTimer.Add_Tick({
    if ($state.leftVK -ne 0) {
        $pressed = Invoke-Expression "[$($script:uid2)]::IsPressed($($state.leftVK))"
        if ($pressed -and -not $state.prevKeyL) {
            if (-not $state.skipToggleL) { Toggle-Left } else { $state.skipToggleL = $false }
            $state.prevKeyL = $true
        } elseif (-not $pressed) {
            $state.prevKeyL = $false
        }
    }
    if ($state.rightVK -ne 0) {
        $pressed = Invoke-Expression "[$($script:uid2)]::IsPressed($($state.rightVK))"
        if ($pressed -and -not $state.prevKeyR) {
            if (-not $state.skipToggleR) { Toggle-Right } else { $state.skipToggleR = $false }
            $state.prevKeyR = $true
        } elseif (-not $pressed) {
            $state.prevKeyR = $false
        }
    }
})
$state.pollTimer.Start()

$form.Add_FormClosing({
    if ($state.leftTimer)  { $state.leftTimer.Stop();  $state.leftTimer.Dispose() }
    if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
    if ($state.pollTimer)  { $state.pollTimer.Stop();  $state.pollTimer.Dispose() }
    if ($state.bgImage)    { $state.bgImage.Dispose() }
})

[void]$form.ShowDialog()
