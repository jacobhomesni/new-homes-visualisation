$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent

function Looks-Street([string]$p) {
  return $p -match '(?i)\b(road|street|avenue|lane|drive|close|way|crescent|terrace|gardens|mews|grove|manor|hall|gate|lodge|hill|park|view)\b'
}

foreach ($name in @('developments.json', 'audit.json')) {
  $path = Join-Path $repo "data\$name"
  $data = [System.IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json
  foreach ($d in $data.developments) {
    if ([string]$d.homesNiUrl -match ' PropURL/') {
      $d.homesNiUrl = [string]$d.homesNiUrl -replace ' PropURL/', '/'
    }
    # Dungannon Spires must not map to Portadown
    if ($d.name -eq 'The Spires' -and $d.address -match 'Bush Road' -and $d.address -match 'Dungannon') {
      if ($d.homesNiUrl -match 'portadown|craigavon') {
        $d.onHomesNi = $false
        $d.homesNiUrl = ''
        Write-Host 'Cleared The Spires (Dungannon) false positive'
      }
    }
    # Strand Road development name that matched a house number listing — keep only if URL mentions scheme-ish path; flag thin matches
    if ($d.name -eq 'Strand Road, Portstewart' -and $d.homesNiUrl -match '/\d+-strand-road/') {
      # 77-strand-road is likely a resale house, not the new scheme — clear
      $d.onHomesNi = $false
      $d.homesNiUrl = ''
      Write-Host 'Cleared Strand Road Portstewart house-number false positive'
    }
  }
  $data.onHomesNiCount = @($data.developments | Where-Object { $_.onHomesNi }).Count
  [System.IO.File]::WriteAllText($path, ($data | ConvertTo-Json -Depth 10), $utf8)
  Write-Host ("{0} onHomesNi={1}" -f $name, $data.onHomesNiCount)
}
