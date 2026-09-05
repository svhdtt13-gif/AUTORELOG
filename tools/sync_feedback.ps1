param([string]$TokenFile = 'C:\Users\ADMIN\Documents\ai tool\tools\feedback.token.xml')
$owner='svhdtt13-gif'; $repo='AUTORELOG'
$planEnc='phase0.md'
$fbEnc='ph%E1%BA%A3n%20h%E1%BB%93i'
$shaFile='C:\Users\ADMIN\Documents\ai tool\tools\.phase0.sha'

if (-not (Test-Path -LiteralPath $TokenFile)) { throw "Feedback token file not found: $TokenFile" }
$secureToken = Import-Clixml -LiteralPath $TokenFile
$tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
try { $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr) }
$headers=@{Authorization="Bearer $Token";'User-Agent'='opencode'}
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$plan = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/contents/$planEnc" -Headers $headers
$planSha = $plan.sha

$prev = $null
if (Test-Path $shaFile) { $prev = (Get-Content $shaFile -Raw).Trim() }

if ($planSha -eq $prev) {
  Write-Host "phase0.md unchanged ($planSha), skip"
  exit 0
}

$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$note = "`n`n---`nPHASE0 UPDATED at $ts (SHA $planSha) - AI re-review required. Latest full review kept above.`n---"

try {
  $fb = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/contents/$fbEnc" -Headers $headers
  $fbSha = $fb.sha
  $existing = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($fb.content))
  $newText = $existing + $note
} catch {
  $fbSha = $null
  $newText = "# PHAN HOI (auto-notify)`n$note"
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($newText)
$b64 = [Convert]::ToBase64String($bytes)

$payload = @{ message="Notify phase0.md changed ($ts) - re-review needed"; content=$b64 }
if ($fbSha) { $payload.sha = $fbSha }
$payloadJson = $payload | ConvertTo-Json
Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/contents/$fbEnc" -Method Put -Headers $headers -Body $payloadJson -ContentType 'application/json' | Out-Null
Set-Content -Path $shaFile -Value $planSha
Write-Host "phase0.md changed -> appended re-review note (SHA $planSha)"
