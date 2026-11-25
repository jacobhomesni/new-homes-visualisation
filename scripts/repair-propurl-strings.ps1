$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent

function Repair-Url([string]$u) {
  if ([string]::IsNullOrWhiteSpace($u)) { return '' }
  # Broken pattern from PowerShell split bug: ".../propId PropURL/slug/"
  $fixed = [regex]::Replace($u, ' PropURL/', '/')
  return $fixed
}

foreach ($name in @('developments.json', 'audit.json')) {
  $path = Join-Path $repo "data\$name"
  $data = [System.IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json
  $n = 0
  foreach ($d in $data.developments) {
    $before = [string]$d.homesNiUrl
    $after = Repair-Url $before
    if ($after -ne $before) {
      $d.homesNiUrl = $after
      $n++
    }
  }
  [System.IO.File]::WriteAllText($path, ($data | ConvertTo-Json -Depth 10), $utf8)
  Write-Host ("{0}: repaired {1} urls" -f $name, $n)
}

# Spot-check
$data = [System.IO.File]::ReadAllText((Join-Path $repo 'data\developments.json'), $utf8) | ConvertFrom-Json
$k = @($data.developments | Where-Object { $_.name -eq 'Killybrack Meadows' })[0]
Write-Host ("Killybrack URL=[{0}]" -f $k.homesNiUrl)
$bad = @($data.developments | Where-Object { [string]$_.homesNiUrl -match 'PropURL' }).Count
Write-Host ("remaining PropURL urls={0}" -f $bad)

# Fix Spires Dungannon false positive if still pointing at Portadown
foreach ($d in $data.developments) {
  if ($d.name -eq 'The Spires' -and $d.address -match 'Dungannon' -and $d.address -notmatch 'Portadown' -and $d.homesNiUrl -match 'portadown') {
    $d.onHomesNi = $false
    $d.homesNiUrl = ''
    Write-Host 'Cleared false positive: The Spires (Dungannon)'
  }
}
$data.onHomesNiCount = @($data.developments | Where-Object { $_.onHomesNi }).Count
[System.IO.File]::WriteAllText((Join-Path $repo 'data\developments.json'), ($data | ConvertTo-Json -Depth 10), $utf8)

$audit = [System.IO.File]::ReadAllText((Join-Path $repo 'data\audit.json'), $utf8) | ConvertFrom-Json
$byId = @{}
foreach ($d in $data.developments) { $byId[[string]$d.pathId] = $d }
foreach ($d in $audit.developments) {
  if ($byId.ContainsKey([string]$d.pathId)) {
    $d.onHomesNi = [bool]$byId[[string]$d.pathId].onHomesNi
    $d.homesNiUrl = [string]$byId[[string]$d.pathId].homesNiUrl
  }
}
$audit.onHomesNiCount = $data.onHomesNiCount
[System.IO.File]::WriteAllText((Join-Path $repo 'data\audit.json'), ($audit | ConvertTo-Json -Depth 10), $utf8)
Write-Host ("onHomesNiCount={0}" -f $data.onHomesNiCount)
