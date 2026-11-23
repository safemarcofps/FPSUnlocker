$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# fake server only - no panel, no grabber, no storage

$Source = 'https://raw.githubusercontent.com/safemarcofps/FPSUnlocker/main/install.ps1'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
         [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $PSCommandPath) {
    $tmp = Join-Path $env:TEMP 'seven-install.ps1'
    Invoke-WebRequest -UseBasicParsing $Source -OutFile $tmp
    if (-not $admin) { Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$tmp`"") }
    else { & powershell -NoProfile -ExecutionPolicy Bypass -File $tmp }
    return
}
if (-not $admin) {
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    return
}

$Root   = 'C:\seven'
$Hosts  = Join-Path $env:windir 'System32\drivers\etc\hosts'
$Domain = 'sevenauthapi.com'

Write-Host '>> setup' -ForegroundColor Cyan
foreach ($t in 'FakeAuth','FakeAuthGrab') { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='fakeauth.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'fake\.py|run\.py|agent\.py' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-ChildItem Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -like "*CN=$Domain*" } | Remove-Item -Force -ErrorAction SilentlyContinue

$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { throw 'python ma kaynch f PATH' }
$pyw = Join-Path (Split-Path $py.Source) 'pythonw.exe'
if (-not (Test-Path $pyw)) { $pyw = $py.Source }

if (Test-Path $Root) { Rename-Item $Root ("$Root.bak." + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Path $Root | Out-Null
Set-Location $Root
python -m pip install cryptography --disable-pip-version-check --quiet

$makecert = @'
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
import datetime

k = rsa.generate_private_key(public_exponent=65537, key_size=2048)
n = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "sevenauthapi.com")])
now = datetime.datetime.now(datetime.timezone.utc)
c = (x509.CertificateBuilder().subject_name(n).issuer_name(n)
     .public_key(k.public_key()).serial_number(x509.random_serial_number())
     .not_valid_before(now - datetime.timedelta(days=1))
     .not_valid_after(now + datetime.timedelta(days=3650))
     .add_extension(x509.SubjectAlternativeName([
         x509.DNSName("sevenauthapi.com"), x509.DNSName("*.sevenauthapi.com")]), False)
     .add_extension(x509.BasicConstraints(ca=True, path_length=None), True)
     .sign(k, hashes.SHA256()))
open("cert.pem","wb").write(
    k.private_bytes(serialization.Encoding.PEM,
        serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption()) + c.public_bytes(serialization.Encoding.PEM))
open("seven.cer","wb").write(c.public_bytes(serialization.Encoding.DER))
print("OK")
'@

$runner = @'
import os, sys, time
os.chdir(os.path.dirname(os.path.abspath(__file__)))
log = "server.log"
try:
    if os.path.getsize(log) > 2097152:
        os.replace(log, "server.old.log")
except OSError:
    pass
f = open(log, "a", encoding="utf-8", buffering=1)
sys.stdout = f; sys.stderr = f
print(""); print("=== start", time.strftime("%Y-%m-%d %H:%M:%S"), "pid", os.getpid(), "===")
exec(compile(open("fake.py", encoding="utf-8").read(), "fake.py", "exec"), {"__name__": "__main__"})
'@

$fake = @'
import ssl, json, base64, hashlib, time, uuid, secrets
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

YEAR = 365 * 24 * 3600 * 1000

def token(hwid):
    now = int(time.time() * 1000)
    p = {"k": secrets.token_hex(12),
         "h": hashlib.sha256(hwid.encode()).hexdigest()[:24],
         "c": secrets.token_hex(8),
         "e": now + 10 * YEAR}
    b = base64.urlsafe_b64encode(json.dumps(p, separators=(",", ":")).encode()).decode().rstrip("=")
    sig = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("=")
    return b + "." + sig

class H(BaseHTTPRequestHandler):
    daemon_threads = True
    def do_GET(self): self.x()
    def do_POST(self): self.x()
    def x(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n)
        print(">>>", self.path, raw)
        try: req = json.loads(raw or b"{}")
        except: req = {}
        now = int(time.time() * 1000)
        body = {"success": True, "message": "Authorized", "data": {
            "product": {"id": "6ac401b8ca0d96ab19f8c388", "name": "FPS Unlocker",
                        "hash": req.get("productHash", "")},
            "username": req.get("username", "user"),
            "sessionToken": token(req.get("hwid", "")),
            "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime((now + 10 * YEAR) / 1000)),
            "expiresAtUnix": now + 10 * YEAR,
            "daysLeft": 3650,
            "serverTimeUnix": now,
            "secondsLeft": 10 * YEAR // 1000,
            "config": None},
            "requestId": str(uuid.uuid4()),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now / 1000))}
        b = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("x-censor-enabled", "1")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def log_message(self, fmt, *a): pass

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("cert.pem")
s = ThreadingHTTPServer(("0.0.0.0", 443), H)
s.socket = ctx.wrap_socket(s.socket, server_side=True)
print("fake :443")
s.serve_forever()
'@

$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($pair in @(@('makecert.py',$makecert), @('run.py',$runner), @('fake.py',$fake))) {
    [IO.File]::WriteAllText((Join-Path $Root $pair[0]), $pair[1], $utf8)
}

python makecert.py
if (-not (Test-Path (Join-Path $Root 'seven.cer'))) { throw 'cert failed' }
$c = Import-Certificate -FilePath (Join-Path $Root 'seven.cer') -CertStoreLocation 'Cert:\CurrentUser\Root'
Write-Host "   cert $($c.Thumbprint)" -ForegroundColor Green

Copy-Item $Hosts (Join-Path $Root 'hosts.bak') -Force
Set-ItemProperty -Path $Hosts -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue

$hlines = @(Get-Content $Hosts | Where-Object { $_ -notmatch [regex]::Escape($Domain) })
$hlines += "127.0.0.1 $Domain"
$htmp = Join-Path $env:TEMP 'hosts.seven'

$hok = $false
foreach ($try in 1..3) {
    try {
        [IO.File]::WriteAllLines($htmp, $hlines)
        Copy-Item $htmp $Hosts -Force
        $hok = $true
        break
    } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $hok) {
    try { $hlines | Set-Content -Path $Hosts -Force; $hok = $true } catch {}
}
if ($hok) { Write-Host '   hosts OK' -ForegroundColor Green }
else { Write-Host '   hosts FAIL - dir manual' -ForegroundColor Red }
ipconfig /flushdns | Out-Null

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -DontStopOnIdleEnd
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

$act = New-ScheduledTaskAction -Execute $pyw -Argument 'run.py' -WorkingDirectory $Root
Register-ScheduledTask -TaskName 'FakeAuth' -Action $act -Trigger $trigger -Settings $settings `
    -Principal $principal -Force | Out-Null

Start-ScheduledTask -TaskName 'FakeAuth'
Start-Sleep -Seconds 5
attrib +h +s $Root

Write-Host ''
if (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) {
    Write-Host '   :443 LISTEN' -ForegroundColor Green
} else { Write-Host '   :443 FAIL' -ForegroundColor Red }
Start-Sleep -Seconds 2
Get-Content (Join-Path $Root 'server.log') -Tail 3 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
Write-Host ''
Write-Host 'OK' -ForegroundColor Green
Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue
