param(
  [int]$Port = 8080,
  [string]$MasterPath,
  [string]$ScenePath = 'C:\Users\ADMIN\Desktop\MIUUUUUUUUUU.json',
  [string]$SecretPath,
  [switch]$NoAuth
)
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
if (-not $MasterPath) { $MasterPath = Join-Path $ScriptDir 'clients_master.json' }
if (-not $SecretPath) { $SecretPath = Join-Path $ScriptDir 'web.secret' }
Import-Module (Join-Path $ScriptDir 'AUTORELOG.Core.psm1') -Force
$WebLog = Join-Path $ScriptDir 'web.log'

# Auth token
$Token = $null
if (-not $NoAuth) {
  if (Test-Path $SecretPath) { $Token = (Get-Content $SecretPath -Raw -Encoding UTF8).Trim() }
  if (-not $Token) { $Token = (New-Guid).Guid; Set-Content $SecretPath -Value $Token -Encoding UTF8; Write-Host ('Generated web.secret token: ' + $Token) }
}

function WLog($m) { try { Add-Content -Path $WebLog -Encoding UTF8 -Value (('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m)) } catch { } }

# --- shared helpers (mirror executor) ---
function Get-LaunchMap($scenePath) {
  $scene = Get-Content $scenePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $arr = if ($scene -is [System.Array]) { $scene } else { @($scene) }
  $map = @{}
  foreach ($e in $arr) {
    $ei = $e.emuInfo
    $cid = [string]$ei.vmName
    if (-not $cid) { if ($ei.commandLine -match '-instance:(\S+)') { $cid = $Matches[1] } }
    if ($cid) { $map[$cid] = [pscustomobject]@{ exe = $ei.executablePath; wd = $ei.workingDirectory; cmd = $ei.commandLine } }
  }
  return $map
}
function Test-InstanceRunning($cid) {
  $procs = Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    $cl = $p.CommandLine
    if ($cl -and (($cl -split '\s+') -contains "-instance:$cid")) { return $true }
  }
  return $false
}
function Start-Instance($info) {
  $cmd = $info.cmd; $args = $cmd
  if ($args -match '^"([^"]+)"\s*(.*)$') { $args = $Matches[2] } else { $args = $args.Substring($info.exe.Length).Trim() }
  Start-Process -FilePath $info.exe -ArgumentList $args -WorkingDirectory $info.wd -WindowStyle Minimized
}
function Get-Overrides() {
  $o = @{}; $p = Join-Path $ScriptDir 'overrides.json'
  if (Test-Path $p) {
    try {
      $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($k in $j.PSObject.Properties) {
        $ov = $k.Value; $u = $null
        if ($ov.until -and [datetime]::TryParse([string]$ov.until, [ref]$u)) { $o[$k.Name] = @{ action = [string]$ov.action; until = $u } }
      }
    } catch { }
  }
  return $o
}
function Write-Override($cid, $actionWord, $minutes) {
  $ov = @{}
  $p = Join-Path $ScriptDir 'overrides.json'
  if (Test-Path $p) {
    try {
      $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($k in $j.PSObject.Properties) { $ov[$k.Name] = $k.Value }
    } catch { }
  }
  $until = (Get-Date).AddMinutes($minutes)
  $ov[$cid] = [ordered]@{ action = $actionWord; until = $until.ToString('yyyy-MM-dd HH:mm:ss') }
  $ov | ConvertTo-Json | Set-Content $p -Encoding UTF8
}

# --- HTTP helpers ---
function Get-Cookie($req, $name) {
  $c = $req.Headers['Cookie']
  if (-not $c) { return $null }
  foreach ($p in ($c -split ';')) {
    $p = $p.Trim()
    if ($p -like ($name + '=*')) { return $p.Substring($name.Length + 1) }
  }
  return $null
}
function Test-Auth($req) {
  if ($NoAuth) { return $true }
  $tok = Get-Cookie $req 'autorelog'
  if (-not $tok) {
    $h = $req.Headers['Authorization']
    if ($h -and $h -like 'Bearer *') { $tok = $h.Substring(7) }
  }
  if (-not $tok) {
    $q = $req.QueryString['token']
    if ($q) { $tok = [string]$q }
  }
  if ($tok -and $tok -eq $Token) { return $true }
  return $false
}
function Read-Body($req) {
  $enc = if ($req.ContentEncoding) { $req.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
  $r = New-Object System.IO.StreamReader($req.InputStream, $enc)
  return $r.ReadToEnd()
}
function Write-Text($resp, $txt, $ctype = 'text/html; charset=utf-8', $code = 200) {
  $b = [System.Text.Encoding]::UTF8.GetBytes($txt)
  $resp.StatusCode = $code
  $resp.ContentType = $ctype
  $resp.ContentEncoding = [System.Text.Encoding]::UTF8
  $resp.OutputStream.Write($b, 0, $b.Length)
  $resp.Close()
}
function Write-Redirect($resp, $loc) {
  $resp.StatusCode = 302
  $resp.Headers.Add('Location', $loc)
  $resp.Close()
}

$LoginHtml = @'
<!doctype html><html><head><meta charset=utf-8><title>AUTORELOG Login</title>
<style>body{font-family:Consolas,monospace;background:#111;color:#eee}input{padding:6px;font-size:16px}button{padding:6px 16px}</style></head>
<body><h2>AUTORELOG Master - Login</h2>
<form id=f>Token: <input name=token type=password size=40><br><br><button type=submit>Login</button></form>
<script>document.getElementById('f').onsubmit=function(e){e.preventDefault();var t=this.token.value;fetch('login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:t})}).then(r=>{if(r.ok)location.href='/';else alert('bad token');});};</script>
</body></html>
'@

$DashboardHtml = @'
<!doctype html><html><head><meta charset=utf-8><title>AUTORELOG Master</title>
<style>body{font-family:Consolas,monospace;background:#111;color:#eee}table{border-collapse:collapse;margin-bottom:16px}td,th{border:1px solid #444;padding:4px 8px}.up{color:#6f6}.down{color:#f66}button{margin:2px;cursor:pointer}input{padding:3px}</style></head>
<body>
<h2>AUTORELOG Master Data</h2>
<div id=win></div>
<table id=tbl><thead><tr><th>client</th><th>name</th><th>group</th><th>desired</th><th>running</th><th>conn</th><th>override</th><th>drift</th><th>action</th></tr></thead><tbody></tbody></table>
<h3>Add / Edit client</h3>
<form id=f>
 client <input name=client placeholder=client_XX><br>
 name <input name=name><br>
 group <input name=group placeholder=fixed|gr1|gr2|gr3|gr4|none><br>
 open <input name=open placeholder=HH:mm><br>
 close <input name=close placeholder=HH:mm><br>
 policy <input name=policy placeholder=always|window|none><br>
 <button type=submit>Save</button>
</form>
<pre id=log style="color:#9cf"></pre>
<script>
function load(){
 fetch('api/status').then(r=>r.json()).then(d=>{
  document.getElementById('win').textContent='Now '+d.now+' | windows: '+d.windows.map(w=>w.group+' '+w.open+'-'+w.close).join('  ');
  var tb=document.querySelector('#tbl tbody'); tb.innerHTML='';
  d.clients.forEach(c=>{
   var tr=document.createElement('tr');
   var dcls=c.drift&&c.drift!=='-'?'down':'';
   tr.innerHTML='<td>'+c.client+'</td><td>'+c.name+'</td><td>'+c.group+'</td><td>'+c.desired+'</td><td class="'+(c.running?'up':'')+'">'+(c.running?'yes':'no')+'</td><td class="'+(c.connected?'up':'')+'">'+(c.connected?'yes':'no')+'</td><td>'+(c.override||'-')+'</td><td class="'+dcls+'">'+(c.drift||'-')+'</td>';
   var td=document.createElement('td');
   ['start','stop','restart'].forEach(a=>{var b=document.createElement('button');b.textContent=a;b.onclick=()=>ctrl(c.client,a);td.appendChild(b);});
   tr.appendChild(td); tb.appendChild(tr);
  });
 }).catch(e=>log('status err: '+e));
}
function ctrl(client,action){fetch('api/control',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({client:client,action:action,minutes:60})}).then(r=>r.json()).then(j=>log(client+' '+action+' -> '+(j.ok?'ok':'fail'+(j.error||''))));}
document.getElementById('f').onsubmit=function(e){e.preventDefault();var o={};new FormData(this).forEach((v,k)=>{if(v!=='')o[k]=v;});fetch('api/client',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(o)}).then(r=>r.json()).then(j=>{log('saved '+o.client+(j.ok?'':' '+JSON.stringify(j)));load();});};
function log(m){document.getElementById('log').textContent+=m+'\n';}
load(); setInterval(load,15000);
</script>
</body></html>
'@

function Get-StatusJson() {
  $master = Get-Content $MasterPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $windows = Get-ScheduleWindows $master
  $now = Get-NowInTz
  $overrides = Get-Overrides
  $out = [ordered]@{
    now = ('{0:HH:mm}' -f $now)
    windows = @(foreach ($w in $windows) { [ordered]@{ group = $w.group; open = $w.open; close = $w.close } })
    clients = @()
  }
  foreach ($c in @($master.clients)) {
    $cid = [string]$c.client
    $desired = Get-DesiredState $c $windows $now
    $ovStr = $null
    if ($overrides.ContainsKey($cid) -and $now -lt $overrides[$cid].until) { $desired = $overrides[$cid].action; $ovStr = $overrides[$cid].action }
    $isRun = Test-InstanceRunning $cid
    $isConn = if ($isRun) { Test-InstanceConnected $cid } else { $false }
    if ($desired -eq 'running' -and -not $isRun) { $dr = 'YES(up)' }
    elseif (($desired -eq 'stopped' -or $desired -eq 'blocked') -and $isRun) { $dr = 'YES(down)' }
    elseif ($desired -eq 'running' -and $isRun -and -not $isConn) { $dr = 'YES(zombie)' }
    else { $dr = '-' }
    $out.clients += [ordered]@{ client = $cid; name = [string]$c.name; group = [string]$c.group; desired = $desired; running = $isRun; connected = $isConn; override = $ovStr; drift = $dr }
  }
  return ($out | ConvertTo-Json -Depth 5)
}

function Save-Master($master) {
  $master | ConvertTo-Json -Depth 10 | Set-Content $MasterPath -Encoding UTF8
}

function Handle-Request($req, $resp) {
  $path = $req.Url.AbsolutePath
  $method = $req.HttpMethod
  if ($path -eq '/login') {
    if ($method -eq 'GET') { Write-Text $resp $LoginHtml; return }
    if ($method -eq 'POST') {
      try {
        $j = Read-Body $req | ConvertFrom-Json
        if ($NoAuth -or ($j.token -and [string]$j.token -eq $Token)) {
          $resp.Headers.Add('Set-Cookie', ('autorelog=' + $Token + '; HttpOnly; Path=/'))
          Write-Redirect $resp '/'
        } else { Write-Text $resp 'Bad token' 'text/plain' 401 }
      } catch { Write-Text $resp 'Bad request' 'text/plain' 400 }
      return
    }
  }
  if (-not (Test-Auth $req)) {
    if ($path -eq '/') { Write-Text $resp $LoginHtml }
    else { Write-Text $resp '{"error":"unauthorized"}' 'application/json' 401 }
    return
  }
  if ($path -eq '/') { Write-Text $resp $DashboardHtml; return }
  if ($path -eq '/api/status') { Write-Text $resp (Get-StatusJson) 'application/json'; return }
  if ($path -eq '/api/control' -and $method -eq 'POST') {
    try {
      $j = Read-Body $req | ConvertFrom-Json
      $cid = [string]$j.client; $action = [string]$j.action; $mins = [int]($j.minutes)
      if ($mins -le 0) { $mins = 60 }
      $map = Get-LaunchMap $ScenePath
      if ($action -eq 'stop') {
        $pidv = $null
        $procs = Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue
        foreach ($p in $procs) { if ($p.CommandLine -and (($p.CommandLine -split '\s+') -contains "-instance:$cid")) { $pidv = $p.ProcessId } }
        if ($pidv) { Stop-Process -Id $pidv -Force }
        Write-Override $cid 'stopped' $mins
      } elseif ($action -eq 'start' -or $action -eq 'restart') {
        if ($action -eq 'restart') {
          $procs = Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue
          foreach ($p in $procs) { if ($p.CommandLine -and (($p.CommandLine -split '\s+') -contains "-instance:$cid")) { Stop-Process -Id $p.ProcessId -Force } }
        }
        if ($map.ContainsKey($cid)) { Start-Instance $map[$cid] }
        else { Write-Text $resp ('{"ok":false,"error":"no launch cmd for ' + $cid + '"}') 'application/json' 400; return }
        Write-Override $cid 'running' $mins
      } else { Write-Text $resp '{"ok":false,"error":"bad action"}' 'application/json' 400; return }
      Write-Text $resp '{"ok":true}' 'application/json'
    } catch { WLog ('control err ' + $_); Write-Text $resp '{"ok":false,"error":"server"}' 'application/json' 500 }
    return
  }
  if ($path -eq '/api/client' -and $method -eq 'POST') {
    try {
      $j = Read-Body $req | ConvertFrom-Json
      $cid = [string]$j.client
      if (-not ($cid -match '^client_\d+$')) { Write-Text $resp '{"ok":false,"error":"bad client id"}' 'application/json' 400; return }
      $master = Get-Content $MasterPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $found = $null
      foreach ($c in @($master.clients)) { if ([string]$c.client -eq $cid) { $found = $c; break } }
      if (-not $found) {
        $found = [pscustomobject]@{ client = $cid; name = ''; group = 'none'; open = $null; close = $null; policy = $null }
        $master.clients += $found
      }
      if ($j.name) { $found.name = [string]$j.name }
      if ($j.group) { $found.group = [string]$j.group }
      if ($j.open) { $found.open = [string]$j.open }
      if ($j.close) { $found.close = [string]$j.close }
      if ($j.policy) { $found.policy = [string]$j.policy }
      Save-Master $master
      WLog ('client upsert ' + $cid)
      Write-Text $resp '{"ok":true}' 'application/json'
    } catch { WLog ('client err ' + $_); Write-Text $resp '{"ok":false,"error":"server"}' 'application/json' 500 }
    return
  }
  if ($path -eq '/api/client' -and $method -eq 'DELETE') {
    try {
      $cid = [string]$req.QueryString['id']
      $master = Get-Content $MasterPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $kept = @()
      foreach ($c in @($master.clients)) { if ([string]$c.client -ne $cid) { $kept += $c } }
      $master.clients = $kept
      Save-Master $master
      WLog ('client delete ' + $cid)
      Write-Text $resp '{"ok":true}' 'application/json'
    } catch { Write-Text $resp '{"ok":false,"error":"server"}' 'application/json' 500 }
    return
  }
  Write-Text $resp 'not found' 'text/plain' 404
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add(('http://localhost:' + $Port + '/'))
try { $listener.Start() } catch {
  Write-Host ('FAILED to start listener. If permission denied, run as Admin once: netsh http add urlacl url=http://localhost:' + $Port + '/ user=' + $env:USERDOMAIN + '\' + $env:USERNAME)
  exit 1
}
Write-Host ('AUTORELOG web master-data listening on http://localhost:' + $Port + '/')
WLog ('server start port=' + $Port)
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  try { Handle-Request $ctx.Request $ctx.Response } catch { WLog ('handler err ' + $_); try { $ctx.Response.StatusCode = 500; $ctx.Response.Close() } catch { } }
}
