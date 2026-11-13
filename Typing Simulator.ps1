param([switch]$Check)
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class TypingKeys {
    [StructLayout(LayoutKind.Sequential)]
    struct Key { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct Mouse { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)]
    struct Payload {
        [FieldOffset(0)] public Key key;
        [FieldOffset(0)] public Mouse mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Input { public uint type; public Payload payload; }
    [DllImport("user32.dll", SetLastError=true)]
    static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    public static bool Send(string value, int virtualKey, IntPtr target) {
        var inputs = new Input[virtualKey == 0 ? value.Length * 2 : 2];
        for (int i = 0; i < inputs.Length; i++) {
            inputs[i].type = 1;
            inputs[i].payload.key.vk = (ushort)virtualKey;
            inputs[i].payload.key.scan = virtualKey == 0 ? value[i / 2] : (ushort)0;
            inputs[i].payload.key.flags = (uint)((virtualKey == 0 ? 4 : 0) | (i % 2 == 1 ? 2 : 0));
        }
        return GetForegroundWindow() == target &&
            SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(Input))) == inputs.Length;
    }
}
"@
$form = New-Object Windows.Forms.Form
$form.Text = 'Typing Simulator'
$form.ClientSize = [Drawing.Size]::new(620,470)
$form.MinimumSize = [Drawing.Size]::new(636,509)
$form.StartPosition = 'CenterScreen'
$form.Font = [Drawing.Font]::new('Segoe UI',10)
function Add-Control($kind, $caption, $x, $y, $width, $height) {
    $control = New-Object "Windows.Forms.$kind"
    $control.Text = $caption
    $control.SetBounds($x,$y,$width,$height)
    $form.Controls.Add($control)
    $control
}
$null = Add-Control Label 'Text to type' 16 12 580 24
$source = Add-Control TextBox '' 16 40 588 282
$source.Multiline = $true
$source.ScrollBars = 'Vertical'
$source.AcceptsReturn = $true
$source.AcceptsTab = $true
$source.Anchor = 'Top, Bottom, Left, Right'
$null = Add-Control Label 'Words per minute' 16 334 160 24
$null = Add-Control Label 'Typo chance (%)' 201 334 160 24
$null = Add-Control Label 'Countdown (seconds)' 386 334 200 24
$speed = Add-Control NumericUpDown '' 16 359 120 28
$speed.Minimum = 5
$speed.Maximum = 240
$speed.Value = 55
$mistakes = Add-Control NumericUpDown '' 201 359 120 28
$mistakes.Maximum = 40
$mistakes.Value = 4
$countdown = Add-Control NumericUpDown '' 386 359 120 28
$countdown.Minimum = 2
$countdown.Maximum = 30
$countdown.Value = 5
$start = Add-Control Button 'Start countdown' 16 399 154 32
$status = Add-Control Label 'Press Esc to stop.' 16 438 588 24
$status.Anchor = 'Bottom, Left, Right'
foreach ($control in $form.Controls) {
    if ($control.Top -ge 334 -and $control -ne $status) { $control.Anchor = 'Bottom, Left' }
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 15
$random = New-Object System.Random
$state = @{ Phase = 'Idle' }
function Stop-Typing($message) {
    $timer.Stop()
    $state.Phase = 'Idle'
    $start.Text = 'Start countdown'
    $status.Text = $message
}
$start.Add_Click({
    if ($state.Phase -ne 'Idle') { Stop-Typing 'Stopped.'; return }
    if ($source.Text.Length -eq 0) { $status.Text = 'Enter text first.'; return }
    $state.Text = $source.Text.Replace("`r`n","`n").Replace("`r","`n")
    $state.Index = 0
    $state.Correction = ''
    $state.Delay = 12000 / [double]$speed.Value
    $state.Typos = [double]$mistakes.Value / 100
    $state.Clock = [Diagnostics.Stopwatch]::StartNew()
    $state.Due = [double]$countdown.Value * 1000
    $state.Phase = 'Countdown'
    $start.Text = 'Cancel'
    $status.Text = "Click inside your document within $($countdown.Value) seconds. Esc stops."
    $timer.Start()
})
$timer.Add_Tick({
    if ([TypingKeys]::GetAsyncKeyState(27) -ne 0) { Stop-Typing 'Stopped.'; return }
    $now = $state.Clock.ElapsedMilliseconds
    if ($state.Phase -eq 'Countdown') {
        if ($now -lt $state.Due) {
            $remaining = [Math]::Ceiling(($state.Due - $now) / 1000)
            $status.Text = "Click inside your document. Starting in $remaining s. Esc stops."
            return
        }
        $state.Target = [TypingKeys]::GetForegroundWindow()
        if ($state.Target -eq [IntPtr]::Zero -or $state.Target -eq $form.Handle) {
            Stop-Typing 'Start again and click inside your document during the countdown.'
            return
        }
        $state.Phase = 'Typing'
        $status.Text = 'Typing. Press Esc to stop.'
    }
    if ([TypingKeys]::GetForegroundWindow() -ne $state.Target) {
        Stop-Typing 'Stopped because the active window changed.'
        return
    }
    if ($now -lt $state.Due) { return }
    foreach ($key in 16,17,18,91,92) {
        if ([TypingKeys]::GetAsyncKeyState($key) -lt 0) { return }
    }
    $virtualKey = 0
    $advance = 0
    $delay = $state.Delay * (0.75 + $random.NextDouble() * 0.5)
    $letter = [Globalization.StringInfo]::GetNextTextElement($state.Text, $state.Index)
    if ($state.Correction -eq 'Erase') {
        $virtualKey = 8
        $state.Correction = 'Replace'
    } elseif ($state.Correction -eq '' -and $letter -cmatch '^[a-zA-Z]$' -and $random.NextDouble() -lt $state.Typos) {
        $alphabet = if ($letter -cmatch '[A-Z]') { 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' } else { 'abcdefghijklmnopqrstuvwxyz' }
        $offset = ($alphabet.IndexOf($letter) + $random.Next(1,26)) % 26
        $letter = $alphabet.Substring($offset,1)
        $state.Correction = 'Erase'
        $delay += 150
    } else {
        $advance = $letter.Length
        $state.Correction = ''
        if ($letter -eq "`n") { $virtualKey = 13 }
        if ($letter -eq "`t") { $virtualKey = 9 }
    }
    if (-not [TypingKeys]::Send($letter,$virtualKey,$state.Target)) {
        Stop-Typing 'Stopped because Windows could not deliver a keystroke.'
        return
    }
    $state.Index += $advance
    if ($state.Index -ge $state.Text.Length) { Stop-Typing 'Finished typing.'; return }
    $state.Due = $now + $delay
})
$form.Add_FormClosed({ $timer.Dispose() })
if ($Check) {
    $form.Dispose()
    $timer.Dispose()
    Write-Output 'Typing Simulator initialized successfully.'
    return
}
[void]$form.ShowDialog()
