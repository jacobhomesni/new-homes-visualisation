# Re-scan all developments against HomesNI (include sale agreed + autocomplete + locality gates).
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent
$devPath = Join-Path $repo 'data\developments.json'
$auditPath = Join-Path $repo 'data\audit.json'
$agentsPath = Join-Path $repo 'data\homesni-agents.json'
$progressPath = Join-Path $repo 'data\homesni-presence-progress.json'
$xlsxOut = Join-Path $env:USERPROFILE "Downloads\homesni-new-homes-presence-$(Get-Date -Format 'yyyy-MM-dd')-v2.xlsx"

$data = [System.IO.File]::ReadAllText($devPath, $utf8) | ConvertFrom-Json
$agentsRaw = [System.IO.File]::ReadAllText($agentsPath, $utf8) | ConvertFrom-Json

function Norm([string]$s) {
  if ($null -eq $s) { return '' }
  $t = $s.ToLowerInvariant()
  $t = [regex]::Replace($t, "[`'""]", '')
  $t = [regex]::Replace($t, '[^\w\s&/-]', ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}

function Extract-Bt([string]$s) {
  $m = [regex]::Match(("" + $s).ToUpperInvariant(), '\bBT\s*(\d{1,2})\b')
  if ($m.Success) { return "BT$($m.Groups[1].Value)" }
  return ''
}

function Place-Name($dev) {
  $parts = @((("" + $dev.address) -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $nameN = Norm $dev.name
  $cands = @()
  foreach ($p in $parts) {
    if ($p -match '^(?i)BT\s*\d') { continue }
    if ((Norm $p) -eq $nameN) { continue }
    $cands += $p
  }
  if ($cands.Count) { return $cands[-1] }
  $town = ("" + $dev.town).Trim()
  if ($town -and $town -notmatch '^(?i)bt\s*\d') { return $town }
  return ''
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

$agentNorms = @($agentsRaw | ForEach-Object { Norm $_ } | Where-Object { $_.Length -ge 3 })

function Agent-OnHomesNi([string]$agentsField) {
  $parts = @(($agentsField -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))
  foreach ($p in $parts) {
    $n = Norm $p
    if (-not $n) { continue }
    foreach ($a in $agentNorms) {
      if ($a.Contains($n) -or $n.Contains($a)) { return $true }
      # UPS / CPS brand shortcuts
      $core = [regex]::Replace($n, '\b(ulster property sales|ups|cps|estate agents?|property|sales|lettings|ltd|limited|co)\b', ' ')
      $core = [regex]::Replace($core, '\s+', ' ').Trim()
      $acore = [regex]::Replace($a, '\b(ulster property sales|ups|cps|estate agents?|property|sales|lettings|ltd|limited|co)\b', ' ')
      $acore = [regex]::Replace($acore, '\s+', ' ').Trim()
      if ($core.Length -ge 5 -and $acore.Length -ge 5 -and ($acore.Contains($core) -or $core.Contains($acore))) { return $true }
    }
  }
  return $false
}

function Get-Text([string]$url) {
  return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30).Content
}

function Post-Form([string]$url, $fields) {
  $body = ($fields.GetEnumerator() | ForEach-Object { "{0}={1}" -f [uri]::EscapeDataString($_.Key), [uri]::EscapeDataString([string]$_.Value) }) -join '&'
  return (Invoke-WebRequest -Uri $url -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded; charset=UTF-8' -UseBasicParsing -TimeoutSec 30).Content
}

function Check-Dev($dev) {
  $name = ("" + $dev.name).Trim()
  $out = [ordered]@{
    onHomesNi = $false
    homesNiUrl = ''
    homesNiAgent = [bool](Agent-OnHomesNi ("" + $dev.agents))
    resultCount = 0
    matchedCount = 0
  }
  if (-not $name) { return $out }

  $acUrl = "https://www.homesni.com/auto-complete-newbuild.php?q=$([uri]::EscapeDataString($name))"
  $acRaw = ''
  try { $acRaw = Get-Text $acUrl } catch { return $out }
  $hits = @()
  if ($acRaw.Trim().StartsWith('[')) {
    try { $hits = @(ConvertFrom-Json $acRaw) } catch { $hits = @() }
  }
  if (-not $hits.Count) { return $out }

  $place = Place-Name $dev
  $bt = Extract-Bt ("" + $dev.address)
  $nameN = Norm $name

  foreach ($h in $hits) {
    $id = [string]$h.id
    if (-not $id.StartsWith('PropURL|')) { continue }
    $hitName = [string]$h.name
    $hitN = Norm $hitName
    if (-not $hitN.Contains($nameN)) { continue }
    if ($place -and -not (Place-Matches $place $hitName)) { continue }
    if ($bt) {
      $hitBt = Extract-Bt $hitName
      if ($hitBt -and $hitBt -ne $bt) { continue }
    }
    # id shape: PropURL||Town|propertyId
    $parts = @($id.Split([char]'|'))
    $townSlug = ''
    $propId = ''
    if ($parts.Count -ge 4) {
      $townSlug = ($parts[2] + '').Trim().ToLowerInvariant() -replace '\s+', '-'
      $propId = ($parts[3] + '').Trim()
    }
    if (-not $propId) { continue }
    $line1 = ($hitName -split ',')[0].Trim()
    $slug = ((Norm $line1) -replace '\s+', '-')
    if (-not $slug) { $slug = $propId }
    $out.onHomesNi = $true
    if ($townSlug) {
      $out.homesNiUrl = ('https://homesni.com/property/{0}/{1}/{2}/' -f $townSlug, $propId, $slug)
    } else {
      $out.homesNiUrl = ('https://homesni.com/property/{0}/' -f $propId)
    }
    $out.matchedCount = 1
    $out.resultCount = $hits.Count
    return $out
  }

  # Fallback search with sale agreed included
  $searchStr = "KW:$name"
  if ($bt) { $searchStr += "|Postcode:$bt" }
  $sid = ''
  try {
    $sid = (Post-Form 'https://www.homesni.com/_search-includes/new-search' @{
      searchStr = $searchStr
      minPrice = ''
      maxPrice = ''
      sector = 'NEW BUILD'
      bedrooms = ''
      receptionrooms = ''
      includeagreed = '1'
      propertytype = ''
    }).Trim()
  } catch { return $out }
  if ($sid -notmatch '^\d+$') { return $out }

  $html = ''
  try { $html = Get-Text "https://www.homesni.com/search/$sid/" } catch { return $out }
  if ($html -match 'no-results' -and $html -notmatch 'property-card') { return $out }

  $cardMatches = [regex]::Matches($html, '(?s)<li class="property-card"[^>]*>.*?</li>')
  $out.resultCount = $cardMatches.Count
  foreach ($cm in $cardMatches) {
    $card = $cm.Value
    $href = ''
    $hm = [regex]::Match($card, 'href="(/property/[^"]+)"')
    if ($hm.Success) { $href = 'https://homesni.com' + $hm.Groups[1].Value }
    $line1 = ''
    $l1 = [regex]::Match($card, 'prop-address[^>]*>\s*<strong>(.*?)</strong>')
    if ($l1.Success) { $line1 = [regex]::Replace($l1.Groups[1].Value, '<[^>]+>', '').Trim() }
    else {
      $l1b = [regex]::Match($card, 'class="prop-address"[^>]*>(.*?)</')
      if ($l1b.Success) { $line1 = [regex]::Replace($l1b.Groups[1].Value, '<[^>]+>', '').Trim() }
    }
    $line2 = ''
    $l2 = [regex]::Match($card, 'class="prop-address-2"[^>]*>(.*?)</')
    if ($l2.Success) { $line2 = [regex]::Replace($l2.Groups[1].Value, '<[^>]+>', '').Trim() }
    $blob = "$line1 | $line2"
    $blobN = Norm $blob
    if (-not $blobN.Contains($nameN)) { continue }
    if ($place) {
      if ($line2) {
        if (-not (Place-Matches $place $line2)) { continue }
      } elseif (-not (Place-Matches $place $blob)) { continue }
    } elseif (-not $bt) { continue }
    if ($bt) {
      $cardBt = Extract-Bt $line2
      if (-not $cardBt) { $cardBt = Extract-Bt $blob }
      if ($cardBt -and $cardBt -ne $bt) { continue }
    }
    $out.onHomesNi = $true
    $out.homesNiUrl = $href
    $out.matchedCount++
    if ($out.matchedCount -eq 1) { break }
  }
  return $out
}

$devs = @($data.developments)
$start = 0
if (Test-Path $progressPath) {
  $prog = [System.IO.File]::ReadAllText($progressPath, $utf8) | ConvertFrom-Json
  if ($prog.nextIndex -gt 0 -and $prog.nextIndex -lt $devs.Count) {
    $start = [int]$prog.nextIndex
    Write-Host "Resuming at $start / $($devs.Count)"
  }
}

for ($i = $start; $i -lt $devs.Count; $i++) {
  $d = $devs[$i]
  Write-Host ("[{0}/{1}] {2}" -f ($i + 1), $devs.Count, $d.name)
  try {
    $r = Check-Dev $d
    $d.onHomesNi = [bool]$r.onHomesNi
    $d.homesNiUrl = [string]$r.homesNiUrl
    $d | Add-Member -NotePropertyName homesNiAgent -NotePropertyValue ([bool]$r.homesNiAgent) -Force
  } catch {
    Write-Host ("  ERROR: {0}" -f $_.Exception.Message)
    $d.onHomesNi = $false
    $d.homesNiUrl = ''
    $d | Add-Member -NotePropertyName homesNiAgent -NotePropertyValue ([bool](Agent-OnHomesNi ("" + $d.agents))) -Force
  }
  $payload = [ordered]@{ nextIndex = $i + 1; ts = (Get-Date).ToString('o') }
  [System.IO.File]::WriteAllText($progressPath, ($payload | ConvertTo-Json), $utf8)
  Start-Sleep -Milliseconds 280
}

$yes = @($devs | Where-Object { $_.onHomesNi }).Count
$agentYes = @($devs | Where-Object { $_.homesNiAgent }).Count
$onAgentNotListed = @($devs | Where-Object { $_.homesNiAgent -and -not $_.onHomesNi }).Count
Write-Host ("DONE onHomesNi={0}/{1} homesNiAgent={2} agentButNoListing={3}" -f $yes, $devs.Count, $agentYes, $onAgentNotListed)

# Write developments.json
$outDevs = New-Object System.Collections.Generic.List[object]
foreach ($d in $devs) {
  $row = [ordered]@{
    pathId         = $d.pathId
    name           = $d.name
    address        = $d.address
    status         = $d.status
    homesAvailable = $d.homesAvailable
    redundant      = [bool]$d.redundant
    hasMicrosite   = [bool]$d.hasMicrosite
    onHomesNi      = [bool]$d.onHomesNi
    homesNiUrl     = [string]$d.homesNiUrl
    homesNiAgent   = [bool]$d.homesNiAgent
    price          = $d.price
    developers     = $d.developers
    developerOrgs  = $d.developerOrgs
    agents         = $d.agents
    agentOrgs      = $d.agentOrgs
    url            = $d.url
    town           = $d.town
    lat            = $d.lat
    lng            = $d.lng
  }
  [void]$outDevs.Add($row)
}
$devPayload = [ordered]@{
  generated         = (Get-Date).ToString('o')
  source            = $data.source
  totalDevelopments = $outDevs.Count
  mappedCount       = $data.mappedCount
  redundantCount    = $data.redundantCount
  onHomesNiCount    = $yes
  developments      = $outDevs
  agentTallies      = $data.agentTallies
  developerTallies  = $data.developerTallies
}
[System.IO.File]::WriteAllText($devPath, ($devPayload | ConvertTo-Json -Depth 10), $utf8)

# Sync flags into audit.json
$audit = [System.IO.File]::ReadAllText($auditPath, $utf8) | ConvertFrom-Json
$byId = @{}
foreach ($d in $outDevs) { $byId[[string]$d.pathId] = $d }
foreach ($d in $audit.developments) {
  $id = [string]$d.pathId
  if ($byId.ContainsKey($id)) {
    $d.onHomesNi = [bool]$byId[$id].onHomesNi
    $d.homesNiUrl = [string]$byId[$id].homesNiUrl
    $d | Add-Member -NotePropertyName homesNiAgent -NotePropertyValue ([bool]$byId[$id].homesNiAgent) -Force
  }
}
$audit.onHomesNiCount = $yes
[System.IO.File]::WriteAllText($auditPath, ($audit | ConvertTo-Json -Depth 10), $utf8)

# Excel via COM
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
try {
  $wb = $excel.Workbooks.Add()
  $ws = $wb.Worksheets.Item(1)
  $ws.Name = 'Presence'
  $headers = @(
    'Development','Address','Town','Status','Homes available','Sale agreed / redundant',
    'Has Microsite?','On HomesNI?','HomesNI URL','HomesNI agent?','Price','Developer(s)','Agent(s)','URL','Path ID'
  )
  for ($c = 0; $c -lt $headers.Count; $c++) { $ws.Cells.Item(1, $c + 1) = $headers[$c] }
  $r = 2
  foreach ($d in $outDevs) {
    $ws.Cells.Item($r, 1) = [string]$d.name
    $ws.Cells.Item($r, 2) = [string]$d.address
    $ws.Cells.Item($r, 3) = [string]$d.town
    $ws.Cells.Item($r, 4) = [string]$d.status
    $ws.Cells.Item($r, 5) = $(if ($null -eq $d.homesAvailable) { '' } else { $d.homesAvailable })
    $ws.Cells.Item($r, 6) = $(if ($d.redundant) { 'Yes' } else { 'No' })
    $ws.Cells.Item($r, 7) = $(if ($d.hasMicrosite) { 'YES' } else { 'NO' })
    $ws.Cells.Item($r, 8) = $(if ($d.onHomesNi) { 'YES' } else { 'NO' })
    $ws.Cells.Item($r, 9) = $(if ($d.onHomesNi) { [string]$d.homesNiUrl } else { '' })
    $ws.Cells.Item($r, 10) = $(if ($d.homesNiAgent) { 'YES' } else { 'NO' })
    $ws.Cells.Item($r, 11) = [string]$d.price
    $ws.Cells.Item($r, 12) = [string]$d.developers
    $ws.Cells.Item($r, 13) = [string]$d.agents
    $ws.Cells.Item($r, 14) = [string]$d.url
    $ws.Cells.Item($r, 15) = [string]$d.pathId
    $r++
  }
  if (Test-Path $xlsxOut) { Remove-Item -LiteralPath $xlsxOut -Force }
  $wb.SaveAs($xlsxOut)
  $wb.Close($false)
} finally {
  $excel.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
}

Remove-Item -LiteralPath $progressPath -ErrorAction SilentlyContinue
Write-Host "Wrote $devPath"
Write-Host "Wrote $xlsxOut"
