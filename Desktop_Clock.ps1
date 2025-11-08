#Created by drox-Ph-Ceb
# ================================
# Oval Transparent Gray Clock + Date + Advanced Alarm Manager (12-Hour AM/PM)
# ================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Rounded/Oval shape support ---
$code = @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateRoundRectRgn(int nLeft, int nTop, int nRight, int nBottom, int nWidthEllipse, int nHeightEllipse);
    [DllImport("user32.dll")]
    public static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
}
"@
Add-Type $code

# Determine path for EXE or script
if ($PSScriptRoot) {
    $scriptPath = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $scriptPath = [IO.Path]::GetTempPath()
}

$alarmFile = Join-Path $scriptPath "alarms.json"
$global:alarms = @()

# --- Function: Save alarms to JSON ---
function Save-Alarms {
    try {
        $global:alarms | ConvertTo-Json -Depth 5 | Set-Content $alarmFile
    } catch {
        Write-Warning "Failed to save alarms: $_"
    }
}

# Load alarms from file if exists
if (Test-Path $alarmFile) {
    try {
        $json = Get-Content $alarmFile -Raw
        if ($json -and $json.Trim() -ne "") {
            $loaded = ConvertFrom-Json $json
            if ($loaded -is [System.Collections.IEnumerable] -and $loaded -isnot [string]) {
                $global:alarms = @($loaded)
            } else {
                $global:alarms = @($loaded)
            }
        }
    } catch {
        Write-Warning "Alarms file is empty or invalid. Starting with no alarms."
        $global:alarms = @()
    }
}


# ================================
# --- Function: Set Alarm Dialog ---
# ================================
function Show-SetAlarmDialog {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Set Alarm"
    $dialog.Size = New-Object System.Drawing.Size(400,320)
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.StartPosition = 'CenterParent'
    $dialog.TopMost = $true

    # --- Days checkboxes ---
    $days = @('Sun','Mon','Tue','Wed','Thu','Fri','Sat')
    $dayBoxes = @()
    for ($i=0; $i -lt $days.Count; $i++) {
        $index = [int]$i
        $x = 10 + ($index % 4) * 60
        $y = 10 + [math]::Floor($index / 4) * 25
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $days[$index]
        $cb.Size = New-Object System.Drawing.Size(55,20)
        $cb.Location = New-Object System.Drawing.Point($x,$y)
        $dialog.Controls.Add($cb)
        $dayBoxes += $cb
    }

    # --- Time inputs (12-hour with AM/PM dropdown) ---
    $lblHour = New-Object System.Windows.Forms.Label
    $lblHour.Text = "Hour (1-12):"
    $lblHour.AutoSize = $true
    $lblHour.Location = New-Object System.Drawing.Point(10,70)
    $dialog.Controls.Add($lblHour)

    $txtHour = New-Object System.Windows.Forms.TextBox
    $txtHour.Location = New-Object System.Drawing.Point(100,70)
    $txtHour.Size = New-Object System.Drawing.Size(40,20)
    $dialog.Controls.Add($txtHour)

    $lblMin = New-Object System.Windows.Forms.Label
    $lblMin.Text = "Minute (0-59):"
    $lblMin.AutoSize = $true
    $lblMin.Location = New-Object System.Drawing.Point(160,70)
    $dialog.Controls.Add($lblMin)

    $txtMin = New-Object System.Windows.Forms.TextBox
    $txtMin.Location = New-Object System.Drawing.Point(260,70)
    $txtMin.Size = New-Object System.Drawing.Size(40,20)
    $dialog.Controls.Add($txtMin)

    # AM/PM dropdown
    $lblAmPm = New-Object System.Windows.Forms.Label
    $lblAmPm.AutoSize = $true
    $lblAmPm.Location = New-Object System.Drawing.Point(305,70)
    $dialog.Controls.Add($lblAmPm)

    $cmbAmPm = New-Object System.Windows.Forms.ComboBox
    $cmbAmPm.Items.AddRange(@("AM","PM"))
    $cmbAmPm.DropDownStyle = 'DropDownList'
    $cmbAmPm.SelectedIndex = 0
    $cmbAmPm.Location = New-Object System.Drawing.Point(305,70)
    $cmbAmPm.Size = New-Object System.Drawing.Size(50,20)
    $dialog.Controls.Add($cmbAmPm)

    # Allow only digits
    $txtHour.Add_KeyPress({ if ($_.KeyChar -notmatch '\d' -and $_.KeyChar -ne 8) { $_.Handled = $true } })
    $txtMin.Add_KeyPress({ if ($_.KeyChar -notmatch '\d' -and $_.KeyChar -ne 8) { $_.Handled = $true } })

    # --- Sound file input ---
    $lblSound = New-Object System.Windows.Forms.Label
    $lblSound.Text = "Sound File:"
	$lblSound.AutoSize = $true
    $lblSound.Location = New-Object System.Drawing.Point(10,110)
    $dialog.Controls.Add($lblSound)

    $txtSound = New-Object System.Windows.Forms.TextBox
    $txtSound.Location = New-Object System.Drawing.Point(80,110)
    $txtSound.Size = New-Object System.Drawing.Size(200,20)
    $dialog.Controls.Add($txtSound)

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = "..."
    $btnBrowse.Location = New-Object System.Drawing.Point(290,110)
    $btnBrowse.Size = New-Object System.Drawing.Size(25,20)
    $btnBrowse.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "WAV Files|*.wav"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtSound.Text = $ofd.FileName
        }
    })
    $dialog.Controls.Add($btnBrowse)

    # --- OK / Cancel buttons ---
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "OK"
    $btnOK.Location = New-Object System.Drawing.Point(80,160)
    $btnOK.Add_Click({
        $hText = $txtHour.Text.Trim()
        $mText = $txtMin.Text.Trim()
        $ampm = $cmbAmPm.SelectedItem
        if ($hText -match '^\d{1,2}$' -and $mText -match '^\d{1,2}$') {
            $h = [int]$hText
            $m = [int]$mText
            if ($h -ge 1 -and $h -le 12 -and $m -ge 0 -and $m -lt 60) {
                # Convert to 24-hour internally
                if ($ampm -eq "PM" -and $h -lt 12) { $h += 12 }
                if ($ampm -eq "AM" -and $h -eq 12) { $h = 0 }

                $selectedDays = @()
                foreach ($cb in $dayBoxes) {
                    if ($cb.Checked) { $selectedDays += $days.IndexOf($cb.Text) }
                }

                if ($selectedDays.Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show("Select at least one day!","Error")
                    return
                }

                $exists = $false
                foreach ($a in $global:alarms) {
                    if ($a.Hour -eq $h -and $a.Minute -eq $m -and 
                        (Compare-Object $a.Days $selectedDays -SyncWindow 0 | Measure-Object).Count -eq 0) {
                        $exists = $true; break
                    }
                }

                if ($exists) {
                    [System.Windows.Forms.MessageBox]::Show("An alarm for this time and days already exists!","Duplicate Alarm")
                    return
                }

                $alarmObj = [PSCustomObject]@{
                    Hour   = $h
                    Minute = $m
                    Days   = $selectedDays
                    Sound  = $txtSound.Text
                    Active = $true
                }

                $global:alarms += $alarmObj
                Save-Alarms
                [System.Windows.Forms.MessageBox]::Show("Alarm set!","OK")
                $dialog.Close()
            } else {
                [System.Windows.Forms.MessageBox]::Show("Hour must be 1-12 and minute 0-59.","Error")
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Please enter valid numbers for hour and minute.","Error")
        }
    })
    $dialog.Controls.Add($btnOK)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(180,160)
    $btnCancel.Add_Click({ $dialog.Close() })
    $dialog.Controls.Add($btnCancel)

    $dialog.ShowDialog() | Out-Null
}

# ================================
# --- Function: Manage Alarms ---
# ================================
function Show-AlarmManager {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Manage Alarms"
    $dialog.Size = New-Object System.Drawing.Size(450,300)
    $dialog.StartPosition = 'CenterParent'
    $dialog.TopMost = $true

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'
    $lv.FullRowSelect = $true
    $lv.CheckBoxes = $true
    $lv.Size = New-Object System.Drawing.Size(420,200)
    $lv.Location = New-Object System.Drawing.Point(10,10)
    $lv.Columns.Add("Time",80)
    $lv.Columns.Add("Days",160)
    $lv.Columns.Add("Sound",150)

    $lv.Items.Clear()
    foreach ($alarm in $global:alarms) {
        $displayHour = $alarm.Hour
        $ampm = "AM"
        if ($alarm.Hour -ge 12) { $ampm = "PM" }
        if ($alarm.Hour -gt 12) { $displayHour = $alarm.Hour - 12 }
        if ($alarm.Hour -eq 0) { $displayHour = 12 }

        $daysText = ($alarm.Days | ForEach-Object {
            @('Sun','Mon','Tue','Wed','Thu','Fri','Sat')[$_]
        }) -join ','

        $timeText = "{0:00}:{1:00} {2}" -f $displayHour, $alarm.Minute, $ampm
        $item = New-Object System.Windows.Forms.ListViewItem($timeText)
        $item.SubItems.Add($daysText)
        $item.SubItems.Add([IO.Path]::GetFileName($alarm.Sound))
        $item.Checked = [bool]$alarm.Active
        $lv.Items.Add($item) | Out-Null
    }

    $dialog.Controls.Add($lv)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save Changes"
    $btnSave.AutoSize = $true
	$btnSave.Location = New-Object System.Drawing.Point(80,220)
    $btnSave.Add_Click({
        for ($i=0; $i -lt $lv.Items.Count; $i++) {
            $global:alarms[$i].Active = $lv.Items[$i].Checked
        }
        Save-Alarms
        [System.Windows.Forms.MessageBox]::Show("Changes saved!","OK")
    })
    $dialog.Controls.Add($btnSave)

    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = "Delete Selected"
	$btnDelete.AutoSize = $true
    $btnDelete.Location = New-Object System.Drawing.Point(220,220)
    $btnDelete.Add_Click({
        if ($lv.SelectedItems.Count -gt 0) {
            $toRemove = @()
            foreach ($item in $lv.SelectedItems) {
                $index = $lv.Items.IndexOf($item)
                $toRemove += $index
            }
            foreach ($idx in ($toRemove | Sort-Object -Descending)) {
                $global:alarms = $global:alarms | Where-Object { $_ -ne $global:alarms[$idx] }
            }
            Save-Alarms
            [System.Windows.Forms.MessageBox]::Show("Deleted selected alarms.","OK")
            $dialog.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Select at least one alarm to delete.","Error")
        }
    })
    $dialog.Controls.Add($btnDelete)

    $dialog.ShowDialog() | Out-Null
}

# ================================
# --- Function: Oval Clock ---
# ================================
function Start-OvalClock {
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.BackColor = [System.Drawing.Color]::Gray
    $form.Opacity = 0.3
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.Width = 220
    $form.Height = 90

    $rgn = [WinAPI]::CreateRoundRectRgn(0,0,$form.Width,$form.Height,$form.Height,$form.Height)
    [WinAPI]::SetWindowRgn($form.Handle,$rgn,$true)

    $screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.Primary } | Select-Object -First 1
    $workArea = $screen.WorkingArea
    $form.StartPosition = 'Manual'
    $form.Location = New-Object System.Drawing.Point(
        ($workArea.Right - $form.Width - 20),
        ($workArea.Bottom - $form.Height - 20)
    )

    $lblTime = New-Object System.Windows.Forms.Label
    $lblTime.Dock = 'Top'
    $lblTime.TextAlign = 'MiddleCenter'
    $lblTime.ForeColor = [System.Drawing.Color]::White
    $lblTime.Font = New-Object System.Drawing.Font('Segoe UI',24,[System.Drawing.FontStyle]::Bold)
    $lblTime.Height = 50
    $form.Controls.Add($lblTime)

    $lblDate = New-Object System.Windows.Forms.Label
    $lblDate.Dock = 'Top'
    $lblDate.TextAlign = 'MiddleCenter'
    $lblDate.ForeColor = [System.Drawing.Color]::White
    $lblDate.Font = New-Object System.Drawing.Font('Segoe UI',13)
    $lblDate.Height = 25
    $form.Controls.Add($lblDate)

    $lastTriggered = @{}

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        $now = Get-Date
        $lblTime.Text = $now.ToString("hh:mm tt")
        $lblDate.Text = $now.ToString("MMM dd, yyyy")

        foreach ($alarm in $global:alarms) {
            if ($alarm.Active) {
                $dayIndex = [int]$now.DayOfWeek
                if ($alarm.Days -contains $dayIndex) {
                    $key = "$($alarm.Hour):$($alarm.Minute):$dayIndex"
                   if ($now.Hour -eq $alarm.Hour -and $now.Minute -eq $alarm.Minute) {
    if (-not $lastTriggered.ContainsKey($key)) {
    $lastTriggered[$key] = $true

    # Play sound in loop
    try {
        if ($alarm.Sound -and (Test-Path $alarm.Sound)) {
            $player = New-Object System.Media.SoundPlayer $alarm.Sound
            $player.PlayLooping()
        } else {
            [System.Media.SystemSounds]::Exclamation.Play()
            $player = $null
        }
    } catch {
    [System.Media.SystemSounds]::Exclamation.Play()
    $player = $null
}


    # Show message once and stop sound when OK is clicked
    $result = [System.Windows.Forms.MessageBox]::Show(
        "⏰ Alarm for $($now.ToString('hh:mm tt'))!",
        "Alarm Triggered",
        [System.Windows.Forms.MessageBoxButtons]::OK
    )

    if ($player) { $player.Stop() }
}
} else {
    # Only reset if minute has changed and key exists
    $expiredKeys = $lastTriggered.Keys | Where-Object {
        $minuteExpired = ($_.Split(':')[1] -ne $now.Minute.ToString())
        $minuteExpired
    }
    foreach ($k in $expiredKeys) { $lastTriggered.Remove($k) | Out-Null }
}

                }
            }
        }
    })
    $timer.Start()

    # --- Allow dragging the form ---
    $drag=$false;$ox=0;$oy=0
    $form.Add_MouseDown({ if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left){ $drag=$true;$ox=[System.Windows.Forms.Cursor]::Position.X-$form.Left;$oy=[System.Windows.Forms.Cursor]::Position.Y-$form.Top }})
    $form.Add_MouseMove({ if ($drag){ $form.Left=[System.Windows.Forms.Cursor]::Position.X-$ox;$form.Top=[System.Windows.Forms.Cursor]::Position.Y-$oy }})
    $form.Add_MouseUp({ $drag=$false })

    # --- Right-click menu ---
    $cm = New-Object System.Windows.Forms.ContextMenuStrip
    $cm.Items.Add("Set Alarm").Add_Click({ Show-SetAlarmDialog })
    $cm.Items.Add("Manage Alarms").Add_Click({ Show-AlarmManager })
    $cm.Items.Add("Exit").Add_Click({ $form.Close() })
    $form.ContextMenuStrip = $cm
	
	# ====== VERTICAL FACEBOOK LABEL ON PANEL LEFT EDGE ======
$fbLabel = New-Object System.Windows.Forms.Label
$fbLabel.Text = "Facebook"
$fbLabel.BackColor = [System.Drawing.Color]::FromArgb(24,119,242)
$fbLabel.ForeColor = [System.Drawing.Color]::White
$fbLabel.Font = New-Object System.Drawing.Font("Segoe UI",8,[System.Drawing.FontStyle]::Bold)
$fbLabel.Width = 17
$fbLabel.Height = 55
$fbLabel.TextAlign = 'MiddleCenter'
$fbLabel.Cursor = [System.Windows.Forms.Cursors]::Hand

# Custom Paint event to rotate text vertically
$fbLabel.Add_Paint({
    param($sender,$e)
    $e.Graphics.Clear($sender.BackColor)
    $e.Graphics.TranslateTransform(0, $sender.Height)
    $e.Graphics.RotateTransform(-90)
    $e.Graphics.DrawString($sender.Text, $sender.Font, [System.Drawing.Brushes]::White, 0, 0)
})

# Manual vertical position (Y)
$fbYPosition = 15  # Change this value to move the label up/down

# Function to update label position
function Update-FBLabelPosition {
    $x = 198
    $y = [int]$fbYPosition
    $fbLabel.Location = New-Object System.Drawing.Point($x, $y)
}

# Initial placement
$form.Add_Shown({ Update-FBLabelPosition })

# Keep placement when resizing
$form.Add_Resize({ Update-FBLabelPosition })

# Click opens Facebook
$fbLabel.Add_Click({
    Start-Process "https://www.facebook.com/jairah.mazo.5"
})

$form.Controls.Add($fbLabel)
$fbLabel.BringToFront()

    [void]$form.ShowDialog()
}

# --- Start Clock ---
Start-OvalClock | Out-Null
