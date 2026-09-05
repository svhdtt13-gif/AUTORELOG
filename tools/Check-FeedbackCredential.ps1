param(
  [string]$SchedulePath = (Join-Path $PSScriptRoot 'feedback_credential_schedule.json'),
  [int]$RenewalWindowDays = 7
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $SchedulePath)) {
  Write-Error "Credential schedule not found: $SchedulePath"
  exit 2
}

$schedule = Get-Content -LiteralPath $SchedulePath -Raw -Encoding UTF8 | ConvertFrom-Json
$expiresAt = [datetime]::Parse([string]$schedule.expires_at)
$remaining = ($expiresAt - (Get-Date)).TotalDays

if ($remaining -lt 0) {
  Write-Error ("Feedback credential expired on {0:yyyy-MM-dd}. Create a replacement PAT manually." -f $expiresAt)
  exit 1
}
if ($remaining -le $RenewalWindowDays) {
  Write-Warning ("Feedback credential expires in {0:N1} days ({1:yyyy-MM-dd}). Create a replacement PAT manually." -f $remaining, $expiresAt)
  exit 1
}

Write-Host ("Feedback credential valid for {0:N1} more days (expires {1:yyyy-MM-dd})." -f $remaining, $expiresAt)
exit 0
