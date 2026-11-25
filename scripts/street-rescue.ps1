# Rescue remaining NO rows via street-phrase + brand/postcode matching (New Homes + For Sale AC).
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent
$devPath = Join-Path $repo 'data\developments.json'
$auditPath = Join-Path $repo 'data\audit.json'
$data = [System.IO.File]::ReadAllText($devPath, $utf8) | ConvertFrom-Json

$suffix = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
  'road','street','avenue','lane','drive','close','way','crescent','terrace','gardens',
  'mews','grove','manor','hall','gate','lodge','hill','park','view','square','court','quay','row','green'
))

function Norm([string]$s) {
  if ($null -eq $s) { return '' }
  $t = $s.ToLowerInvariant()
  $t = [regex]::Replace($t, '[^\w\s&/-]', ' ')
  return ([regex]::Replace($t, '\s+', ' ').Trim())
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
function Extract-Street([string]$text) {
  $s = (("" + $text) -split ',')[0].Trim()
  if (-not $s) { return '' }
  $parts = [System.Collections.Generic.List[string]]::new()
  foreach ($p in @($s -split '\s+' | Where-Object { $_ })) { [void]$parts.Add($p) }
  while ($parts.Count -gt 2) {
    $head = $parts[0]
    if ($head -match '^(?i)site$' -and $parts.Count -gt 1 -and $parts[1] -match '^\d+[a-z]?$') {
      $parts.RemoveAt(0); $parts.RemoveAt(0); continue
    }
    if ($head.Length -le 4 -or $head -match '^\d+[a-z]{0,2}$') { $parts.RemoveAt(0); continue }
    break
  }
  $s = ($parts -join ' ')
  $m = [regex]::Match($s, '\b((?:[A-Za-z'']+\s+){0,3}(?:Road|Street|Avenue|Lane|Drive|Close|Way|Crescent|Terrace|Gardens|Mews|Grove|Manor|Hall|Gate|Lodge|Hill|Park|View|Square|Court|Quay|Row|Green))\b', 'IgnoreCase')
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  if ($s.Length -ge 8) { return $s }
  return ''
}
function Brand-Tokens([string]$name, [string]$street) {
  $streetSet = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($t in @((AddrKey $street) -split ' ' | Where-Object { $_ })) { [void]$streetSet.Add($t) }
  $out = @()
  foreach ($t in @((AddrKey $name) -split ' ' | Where-Object { $_ })) {
    if ($t.Length -lt 3) { continue }
    if ($suffix.Contains($t)) { continue }
    if ($streetSet.Contains($t)) { continue }
    if ($t -match '^\d+$') { continue }
    $out += $t
  }
  return $out
}
function Place-Name($dev) {
  $nameN = Norm $dev.name
  $cands = @()
  foreach ($p in @((("" + $dev.address) -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    if ($p -match '^(?i)BT\s*\d') { continue }
    if ((Norm $p) -eq $nameN) { continue }
    if ($p -match '(?i)\b(road|street|avenue|lane|drive|close|way|crescent|terrace|gardens|mews|grove|manor|hall|gate|lodge|hill|park|view)\b') { continue }
    $cands += $p
  }
  if ($cands.Count) { return $cands[-1] }
  $town = ("" + $dev.town).Trim()
  if ($town -and $town -notmatch '^(?i)bt\s*\d') { return $town }
  return ''
}
function Build-Url([string]$id, [string]$hitName) {
  $parts = @($id.Split([char]'|'))
  if ($parts.Count -lt 4 -or $parts[0] -ne 'PropURL') { return '' }
  $townSlug = ($parts[2] + '').Trim().ToLowerInvariant() -replace '\s+', '-'
  $propId = (($parts[3] + '') -replace '\s*PropURL\s*', '').Trim()
  if (-not $propId) { return '' }
  $line1 = ($hitName -split ',')[0].Trim()
  $slug = ((Norm $line1) -replace '\s+', '-')
  if (-not $slug) { $slug = $propId }
  $url = [string]::Concat('https://homesni.com/property/', $townSlug, '/', $propId, '/', $slug, '/')
  return ($url -replace ' PropURL/', '/')
}
function Is-Match($hit, $dev) {
  $id = [string]$hit.id
  if (-not $id.StartsWith('PropURL|')) { return $false }
  $hitName = [string]$hit.name
  $nameKey = AddrKey $dev.name
  $hitKey = AddrKey $hitName
  $street = Extract-Street ("" + $dev.address)
  if (-not $street) { $street = Extract-Street ("" + $dev.name) }
  $streetKey = AddrKey $street
  $fullPc = Extract-FullPc ("" + $dev.address)
  $hitPc = Extract-FullPc $hitName
  $brands = @(Brand-Tokens ("" + $dev.name) $street)

  $ok = $hitKey.Contains($nameKey)
  if (-not $ok -and $streetKey.Length -ge 8 -and $hitKey.Contains($streetKey)) {
    $brandHit = ($brands | Where-Object { $hitKey.Contains($_) }).Count -gt 0
    $pcHit = ($fullPc -and $hitPc -and $fullPc -eq $hitPc)
    if ($brandHit -or $pcHit) { $ok = $true }
  }
  if (-not $ok -and $fullPc -and $hitPc -and $fullPc -eq $hitPc) {
    $tokens = @($nameKey -split ' ' | Where-Object { $_.Length -ge 4 -and $_ -notmatch '^\d' -and $_ -notmatch '^bt\d' })
    if (($tokens | Where-Object { $hitKey.Contains($_) }).Count -gt 0) { $ok = $true }
  }
  if (-not $ok) { return $false }

  $place = Place-Name $dev
  if ($place) {
    $placeN = Norm $place
    $hitN = Norm $hitName
    $tokens = @($hitN -split ' ')
    $placeOk = $false
    if ($placeN.Split(' ').Count -eq 1) { $placeOk = $tokens -contains $placeN }
    else { $placeOk = $hitN.Contains($placeN) }
    if (-not $placeOk) {
      $bt = Extract-Bt ("" + $dev.address)
      $hitBt = Extract-Bt $hitName
      if (-not (($bt -and $hitBt -and $bt -eq $hitBt) -or ($fullPc -and $hitPc -and $fullPc -eq $hitPc))) {
        return $false
      }
    }
  }
  $bt = Extract-Bt ("" + $dev.address)
  $hitBt = Extract-Bt $hitName
  if ($bt -and $hitBt -and $bt -ne $hitBt) { return $false }
  return $true
}

$nos = @($data.developments | Where-Object { $_.onHomesNi -ne $true })
Write-Host ("Street-rescue candidates={0}" -f $nos.Count)
$rescued = 0

foreach ($d in $nos) {
  $queries = New-Object System.Collections.Generic.List[string]
  foreach ($q in @(
    ("" + $d.name).Trim(),
    (Extract-Street ("" + $d.address)),
    (Extract-Street ("" + $d.name))
  )) {
    $t = ("" + $q).Trim()
    if ($t.Length -ge 3 -and -not $queries.Contains($t)) { [void]$queries.Add($t) }
  }
  $pcPretty = [regex]::Match(("" + $d.address).ToUpperInvariant(), '\bBT\d{1,2}\s*\d[A-Z]{2}\b')
  if ($pcPretty.Success -and -not $queries.Contains($pcPretty.Value)) { [void]$queries.Add($pcPretty.Value) }

  $match = $null
  foreach ($q in $queries) {
    foreach ($ep in @('auto-complete-newbuild.php', 'auto-complete.php')) {
      try {
        $url = "https://www.homesni.com/${ep}?q=$([uri]::EscapeDataString($q))"
        $raw = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 25).Content
        if (-not $raw.Trim().StartsWith('[')) { continue }
        foreach ($h in @(ConvertFrom-Json $raw)) {
          if (Is-Match $h $d) { $match = $h; break }
        }
      } catch {}
      if ($match) { break }
      Start-Sleep -Milliseconds 40
    }
    if ($match) { break }
  }

  if ($match) {
    $d.onHomesNi = $true
    $d.homesNiUrl = ((Build-Url ([string]$match.id) ([string]$match.name)) -replace ' PropURL/', '/')
    $rescued++
    Write-Host ("RESCUED {0} -> {1}" -f $d.name, $d.homesNiUrl)
  }
  Start-Sleep -Milliseconds 70
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

Write-Host ("DONE rescued={0} onHomesNi={1}/{2}" -f $rescued, $yes, $data.developments.Count)
