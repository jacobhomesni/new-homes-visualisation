$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent
$srcRoot = 'C:\Users\Homes NI\Downloads\ppnh-logos'
$destRoot = Join-Path $repo 'assets\logos'
$sharedRoot = Join-Path $destRoot '_shared'
$devPath = Join-Path $repo 'data\developments.json'

if (-not (Test-Path $srcRoot)) { throw "Logo folder not found: $srcRoot" }

function NormName([string]$s) {
  if (-not $s) { return '' }
  $t = $s.ToLowerInvariant()
  # normalize curly quotes / apostrophes
  $t = $t.Replace([char]0x2019, [char]0x0027).Replace([char]0x2018, [char]0x0027)
  return [regex]::Replace($t, '[^a-z0-9]+', '')
}

function NameFromLogoFile([string]$fileName) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
  $base = [regex]::Replace($base, '^(agent|developer)-', '', 'IgnoreCase')
  $base = $base.Replace([char]0x2019, [char]0x0027).Replace([char]0x2018, [char]0x0027)
  $base = ($base -replace '-', ' ' -replace '\s+', ' ').Trim()
  return $base
}

function SafeSharedName([string]$role, [string]$name) {
  $slug = NormName $name
  if (-not $slug) { $slug = 'unknown' }
  return "$role-$slug.png"
}

function SplitNames([string]$raw) {
  if (-not $raw) { return @() }
  return @($raw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function IsAnonymousDeveloper([string]$orgName) {
  # PropertyPal placeholder labels often ship with the PP logo — never wire those images
  return [bool]($orgName -match '^(?i)(multiple\s+developers|private\s+developer|undisclosed\s+developer)$')
}

function BestKey([string]$fileLabel, [string[]]$candidates) {
  $fileNorm = NormName $fileLabel
  if (-not $fileNorm) { return $null }
  foreach ($c in $candidates) {
    if ((NormName $c) -eq $fileNorm) { return (NormName $c) }
  }
  $best = $null
  $bestLen = -1
  foreach ($c in $candidates) {
    $n = NormName $c
    if (-not $n) { continue }
    if ($fileNorm.Contains($n) -or $n.Contains($fileNorm)) {
      if ($n.Length -gt $bestLen) {
        $best = $n
        $bestLen = $n.Length
      }
    }
  }
  return $best
}

# Reset destination
if (Test-Path $destRoot) { Remove-Item $destRoot -Recurse -Force }
New-Item -ItemType Directory -Path $sharedRoot | Out-Null

# Index all source logos -> unique shared files by role+name
$logoIndex = @{
  agent = @{}
  developer = @{}
}
$copied = 0

Get-ChildItem -LiteralPath $srcRoot -Directory | ForEach-Object {
  Get-ChildItem -LiteralPath $_.FullName -File | Where-Object {
    $_.Extension -match '\.(png|jpe?g|webp|gif|svg)$'
  } | ForEach-Object {
    $role = if ($_.Name -match '^(?i)developer-') { 'developer' } else { 'agent' }
    $label = NameFromLogoFile $_.Name
    $key = NormName $label
    if (-not $key) { return }
    if ($role -eq 'developer' -and (IsAnonymousDeveloper $label)) { return }
    if (-not $logoIndex[$role].ContainsKey($key)) {
      $ext = $_.Extension.ToLowerInvariant()
      if ($ext -eq '.jpeg') { $ext = '.jpg' }
      $sharedName = "$role-$key$ext"
      $dest = Join-Path $sharedRoot $sharedName
      Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
      $rel = ("assets/logos/_shared/" + $sharedName) -replace '\\', '/'
      $logoIndex[$role][$key] = @{
        name = $label
        image = $rel
      }
      $script:copied++
    }
  }
}

# Also keep per-path copies for traceability (optional lightweight): skip to save size
# Wire into developments using global index + name matching
$raw = [System.IO.File]::ReadAllText($devPath, $utf8) | ConvertFrom-Json
$outDevs = New-Object System.Collections.Generic.List[object]
$withLogos = 0

function FindLogo([string]$role, [string]$orgName) {
  if ($role -eq 'developer' -and (IsAnonymousDeveloper $orgName)) { return '' }
  $key = NormName $orgName
  if ($key -and $logoIndex[$role].ContainsKey($key)) {
    return $logoIndex[$role][$key].image
  }
  # fuzzy contains match
  $bestImg = ''
  $bestLen = -1
  foreach ($k in $logoIndex[$role].Keys) {
    if ($key -and ($k.Contains($key) -or $key.Contains($k))) {
      if ($k.Length -gt $bestLen) {
        $bestLen = $k.Length
        $bestImg = $logoIndex[$role][$k].image
      }
    }
  }
  return $bestImg
}

foreach ($d in $raw.developments) {
  $agentNames = SplitNames ([string]$d.agents)
  $devNames = SplitNames ([string]$d.developers)

  $developerOrgs = @()
  foreach ($n in $devNames) {
    $developerOrgs += [ordered]@{ name = $n; image = (FindLogo 'developer' $n) }
  }
  # If no developer names but we somehow only had logos, skip

  $agentOrgs = @()
  foreach ($n in $agentNames) {
    $agentOrgs += [ordered]@{ name = $n; image = (FindLogo 'agent' $n) }
  }

  if (@($developerOrgs + $agentOrgs | Where-Object { $_.image }).Count -gt 0) { $withLogos++ }

  $row = [ordered]@{
      pathId         = $d.pathId
      name           = $d.name
      address        = $d.address
      status         = $d.status
      homesAvailable = $d.homesAvailable
      redundant      = [bool]$d.redundant
      price          = $d.price
      developers     = $d.developers
      developerOrgs  = $developerOrgs
      agents         = $d.agents
      agentOrgs      = $agentOrgs
      url            = $d.url
      town           = $d.town
      lat            = $d.lat
      lng            = $d.lng
  }
  if ($null -ne $d.hasMicrosite) { $row.hasMicrosite = [bool]$d.hasMicrosite }
  if ($null -ne $d.onHomesNi) { $row.onHomesNi = [bool]$d.onHomesNi }
  if ($d.homesNiUrl) { $row.homesNiUrl = [string]$d.homesNiUrl }
  [void]$outDevs.Add($row)
}

$payload = [ordered]@{
  generated         = $raw.generated
  source            = $raw.source
  totalDevelopments = $outDevs.Count
  mappedCount       = $raw.mappedCount
  redundantCount    = $raw.redundantCount
  developments      = $outDevs
  agentTallies      = $raw.agentTallies
  developerTallies  = $raw.developerTallies
}

$json = $payload | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($devPath, $json, $utf8)

Write-Host "uniqueLogos=$copied agentKeys=$($logoIndex.agent.Count) developerKeys=$($logoIndex.developer.Count) developmentsWithLogos=$withLogos"
