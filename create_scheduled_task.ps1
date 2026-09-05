$ErrorActionPreference = 'Stop'
$exe = 'C:\Users\ADMIN\Documents\ai tool\AUTORELOG\Executor-Agent.ps1'
$log = 'C:\Users\ADMIN\Documents\ai tool\AUTORELOG\executor.log'
$script = 'C:\Users\ADMIN\Documents\ai tool\AUTORELOG\create_scheduled_task.ps1'

$svc = New-Object -ComObject Schedule.Service
$svc.Connect()
$root = $svc.GetFolder('\')

$task = $svc.NewTask(0)
$task.RegistrationInfo.Description = 'AUTORELOG: disabled; clients must be opened through the remote client row.'
$task.RegistrationInfo.Author = "$env:USERDOMAIN\$env:USERNAME"

# Run only when the user is logged on (so launched qnyh.exe appears on the desktop session)
$principal = $task.Principal
$principal.LogonType = 3
$principal.UserId = "$env:USERDOMAIN\$env:USERNAME"
$principal.RunLevel = 0

$set = $task.Settings
$set.Enabled = $false
$set.StartWhenAvailable = $true
$set.MultipleInstances = 3
$set.ExecutionTimeLimit = 'PT0S'
$set.Hidden = $false

$action = $task.Actions.Create(0)
$action.Path = 'powershell.exe'
$action.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& ''{0}'' -Apply"' -f $exe)

$trigger = $task.Triggers.Create(2)  # daily (repeats every minute, survives reboot)
$trigger.StartBoundary = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
$trigger.Repetition.Interval = 'PT1M'
$trigger.Repetition.Duration = ''   # indefinite

$root.RegisterTaskDefinition('AUTORELOG-Executor', $task, 6, $null, $null, 3)
Write-Host 'Task AUTORELOG-Executor registered.'

# Keep this task disabled. Local process control can reorder remote client IDs.
$reg = $root.GetTask('AUTORELOG-Executor')
Write-Host ("Task AUTORELOG-Executor enabled: {0}" -f $reg.Enabled)
