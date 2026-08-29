$root = "C:\Users\ADMIN\Documents\ai tool\tools"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:8080/")
$listener.Start()
Write-Host "Serving $root on http://localhost:8080/"

function Restart-Cycle {
    @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'AutoCycle.ps1' -and $_.CommandLine -match '-Background' -and $_.CommandLine -notmatch 'NonInteractive' }) | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    Start-Process -FilePath "C:\Users\ADMIN\Documents\ai tool\tools\start_cycle.bat" -WindowStyle Hidden
}

while ($true) {
    try {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $p = $req.Url.LocalPath
        if ($req.HttpMethod -eq 'POST' -and $p -eq '/api/master') {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Dispose()
            try {
                $body | ConvertFrom-Json | Out-Null
                [System.IO.File]::WriteAllText("$root\clients_master.json", $body, (New-Object System.Text.UTF8Encoding $false))
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\sync_master.ps1`"" -WindowStyle Hidden -Wait
                Restart-Cycle
                $resp = "OK"
                $ctx.Response.StatusCode = 200
            } catch {
                $resp = "ERROR: " + $_.Exception.Message
                $ctx.Response.StatusCode = 400
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
            $ctx.Response.ContentType = "text/plain; charset=utf-8"
            $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
            $ctx.Response.Close()
            continue
        }
        if ($p -eq "/") { $p = "/db.html" }
        $file = Join-Path $root $p.TrimStart('/')
        if (Test-Path $file) {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $ext = [System.IO.Path]::GetExtension($file)
            $ct = switch ($ext) {
                ".html" { "text/html; charset=utf-8" }
                ".js"   { "application/javascript" }
                ".css"  { "text/css" }
                ".json" { "application/json; charset=utf-8" }
                ".csv"  { "text/csv; charset=utf-8" }
                default { "application/octet-stream" }
            }
            $ctx.Response.ContentType = $ct
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $ctx.Response.StatusCode = 404
        }
        $ctx.Response.Close()
    } catch {
        Start-Sleep -Seconds 1
    }
}
