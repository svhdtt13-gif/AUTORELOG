param([string]$Message = 'AUTORELOG alert')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = [System.Drawing.SystemIcons]::Information
$ni.Visible = $true
$ni.BalloonTipTitle = 'AUTORELOG'
$ni.BalloonTipText = $Message
$ni.ShowBalloonTip(12000)
Start-Sleep -Seconds 14
$ni.Dispose()
