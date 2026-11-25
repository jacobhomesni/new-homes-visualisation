# Re-check developments marked NOT on HomesNI via For Sale autocomplete (not just New Homes).
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent
$devPath = Join-Path $repo 'data\developments.json'
$auditPath = Join-Path $repo 'data\audit.json'
$data = [System.IO.File]::ReadAllText($devPath, $utf8) | ConvertFrom-Json

function Norm([string]$s) {
  if ($null -eq $s) { return '' }
  $t = $s.ToLowerInvariant()
  $t = [regex]::Replace($t, "[`'""]", '')
  $t = [regex]::Replace($t, '[^\w\s&/-]', ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}
function AddrKey([string]$s) {
  $t = Norm $s
  $t = [regex]::Replace($t, '\b(\d+)([a-z])\s+([a-z])\b', '$1$2$3')
  $t = [regex]::Replace($t, '\b(\d+)\s+([a-z]{1,2})\b', '$1$2')
  return $t
}
function Extract-Bt([string]$s) {
  $m = [regex]::Match(("" + $s).ToUpperInvariant(), '\bBT\s*(\d{1,2})\b')
  if ($m.Success) { return "BT$($m.Groups[1].Value)" }
  return ''
}
function Extract-FullPc([string]$s) {
  $m = [regex]::Match(("" + $s).ToUpperInvariant(), '\bBT\d{1,2}\s*\d[A-Z]{2}\b')
  if ($m.Success) { return ($m.Value -replace '\s+', '') }
  return ''
}
function Place-Name($dev) {
  $parts = @((("" + $dev.address) -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $nameN = Norm $dev.name
  $cands = @()
  foreach ($p in $parts) {
    if ($p -match '^(?i)BT\s*\d') { continue }
    if ((Norm $p) -eq $nameN) { continue }
    if ($p -match '(?i)\b(road|street|lane|avenue|drive|close|way|crescent|terrace|gardens|hill|park|mews|view|manor|hall|gate|grove|lodge)\b') { continue }
    $cands += $p
  }
  if ($cands.Count) { return $cands[-1] }
  $town = ("" + $dev.town).Trim()
  if ($town -and $town -notmatch '^(?i)bt\s*\d') { return $town }
  return ''
}
function Locality-Bits([string]$hitName) {
  $parts = @(($hitName -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $bits = @()
  foreach ($p in $parts) {
    if ($p -match '^(?i)BT\s*\d') { continue }
    if ($p -match '(?i)\b(road|street|lane|avenue|drive|close|way|crescent|terrace|gardens|hill|park|mews)\b') { continue }
    $bits += $p
  }
  return ($bits -join ', ')
}
function Place-Matches([string]$place, [string]$locality) {
  $pn = Norm $place
  $ln = Norm $locality
  if (-not $pn -or -not $ln) { return $false }
  $tokens = @($ln -split ' ' | Where-Object { $_ })
  $pt = @($pn -split ' ' | Where-Object { $_ })
  if ($pt.Count -eq 1) { return $tokens -contains $pt[0] }
  return $ln.Contains($pn)
}
function Build-Url([string]$id, [string]$hitName) {
  $parts = @($id.Split([char]'|'))
  if ($parts.Count -lt 4 -or $parts[0] -ne 'PropURL') { return '' }
  $townSlug = ($parts[2] + '').Trim().ToLowerInvariant() -replace '\s+', '-'
  $propId = ($parts[3] + '').Trim()
  if (-not $propId) { return '' }
  $line1 = ($hitName -split ',')[0].Trim()
  $slug = ((Norm $line1) -replace '\s+', '-')
  if (-not $slug) { $slug = $propId }
  if ($townSlug) { return ('https://homesni.com/property/{0}/{1}/{2}/' -f $townSlug, $propId, $slug) }
  return ('https://homesni.com/property/{0}/' -f $propId)
}
function Hit-Matches($h, $dev) {
  $id = [string]$h.id
  if (-not $id.StartsWith('PropURL|')) { return $false }
  $hitName = [string]$h.name
  $nameKey = AddrKey $dev.name
  $hitKey = AddrKey $hitName
  if (-not $nameKey) { return $false }
  $nameHit = $hitKey.Contains($nameKey)
  if (-not $nameHit) {
    $fullPc = Extract-FullPc ("" + $dev.address)
    $hitPc = Extract-FullPc $hitName
    $streetTokens = @($nameKey -split ' ' | Where-Object { $_.Length -ge 4 -and $_ -notmatch '^\d' -and $_ -notmatch '^bt\d' })
    if ($fullPc -and $hitPc -and $fullPc -eq $hitPc -and ($streetTokens | Where-Object { $hitKey.Contains($_) }).Count -gt 0) {
      $nameHit = $true
    }
  }
  if (-not $nameHit) { return $false }
  $place = Place-Name $dev
  if ($place) {
    $loc = Locality-Bits $hitName
    if (-not (Place-Matches $place $loc)) { return $false }
  }
  $bt = Extract-Bt ("" + $dev.address)
  if ($bt) {
    $hitBt = Extract-Bt $hitName
    if ($hitBt -and $hitBt -ne $bt) { return $false }
  }
  return $true
}
function Queries($dev) {
  $name = ("" + $dev.name).Trim()
  $address = ("" + $dev.address).Trim()
  $q = New-Object System.Collections.Generic.List[string]
  foreach ($s in @(
    $name,
    ([regex]::Replace($name, '^(\d+)([A-Za-z])([A-Za-z])\b', '$1$2 $3')),
    ([regex]::Replace($name, '^\d+\s*[A-Za-z]{0,2}\s*', '').Trim())
  )) {
    $t = ("" + $s).Trim()
    if ($t.Length -ge 3 -and -not $q.Contains($t)) { [void]$q.Add($t) }
  }
  $pcm = [regex]::Match($address.ToUpperInvariant(), '\bBT\d{1,2}\s*\d[A-Z]{2}\b')
  if ($pcm.Success) {
    $t = $pcm.Value
    if (-not $q.Contains($t)) { [void]$q.Add($t) }
  }
  return @($q | Select-Object -First 4)
}

$candidates = @($data.developments | Where-Object { -not $_.onHomesNi })
Write-Host ("Rechecking {0} NO rows via sale autocomplete…" -f $candidates.Count)
$rescued = 0
$n = 0
foreach ($d in $candidates) {
  $n++
  $queries = Queries $d
  $hits = @()
  $seen = @{}
  foreach ($query in $queries) {
    foreach ($endpoint in @('auto-complete-newbuild.php', 'auto-complete.php')) {
      try {
        $url = "https://www.homesni.com/$endpoint?q=$([uri]::EscapeDataString($query))"
        $raw = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 25).Content
        if (-not $raw.Trim().StartsWith('[')) { continue }
        foreach ($h in @(ConvertFrom-Json $raw)) {
          $id = [string]$h.id
          if (-not $id -or $seen.ContainsKey($id)) { continue }
          $seen[$id] = $true
          $hits += $h
        }
      } catch { }
      Start-Sleep -Milliseconds 40
    }
  }
  $match = $null
  foreach ($h in $hits) {
    if (Hit-Matches $h $d) { $match = $h; break }
  }
  if ($match) {
    $d.onHomesNi = $true
    $d.homesNiUrl = Build-Url ([string]$match.id) ([string]$match.name)
    $rescued++
    Write-Host ("  RESCUED [{0}/{1}] {2} -> {3}" -f $n, $candidates.Count, $d.name, $d.homesNiUrl)
  } elseif ($n % 25 -eq 0) {
    Write-Host ("  …{0}/{1}" -f $n, $candidates.Count)
  }
  Start-Sleep -Milliseconds 120
}

$yes = @($data.developments | Where-Object { $_.onHomesNi }).Count
$data.onHomesNiCount = $yes
$data.generated = (Get-Date).ToString('o')
[System.IO.File]::WriteAllText($devPath, ($data | ConvertTo-Json -Depth 10), $utf8)

$audit = [System.IO.File]::ReadAllText($auditPath, $utf8) | ConvertFrom-Json
$byId = @{}
foreach ($d in $data.developments) { $byId[[string]$d.pathId] = $d }
foreach ($d in $audit.developments) {
  if ($byId.ContainsKey([string]$d.pathId)) {
    $d.onHomesNi = [bool]$byId[[string]$d.pathId].onHomesNi
    $d.homesNiUrl = [string]$byId[[string]$d.pathId].homesNiUrl
  }
}
$audit.onHomesNiCount = $yes
[System.IO.File]::WriteAllText($auditPath, ($audit | ConvertTo-Json -Depth 10), $utf8)

Write-Host ("DONE rescued={0} onHomesNi={1}" -f $rescued, $yes)
$c = @($data.developments | Where-Object { $_.name -eq '6Aa Carmavy Road' })[0]
Write-Host ("Carmavy on={0} url={1}" -f $c.onHomesNi, $c.homesNiUrl)
