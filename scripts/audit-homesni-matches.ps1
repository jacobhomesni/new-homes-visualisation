$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$a = [System.IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'data\audit.json'), $utf8) | ConvertFrom-Json
$yes = @($a.developments | Where-Object { $_.onHomesNi -eq $true })
$no = @($a.developments | Where-Object { $_.onHomesNi -eq $false })

Write-Host ("YES={0} NO={1}" -f $yes.Count, $no.Count)
Write-Host ""
Write-Host "=== Suspicious: URL town does not appear in PP address/town ==="

$mismatched = @()
foreach ($d in $yes) {
  $urlTown = ''
  if ($d.homesNiUrl -match '/property/([^/]+)/') { $urlTown = $Matches[1] -replace '-', ' ' }
  $hay = (("" + $d.address + " " + $d.town).ToLower())
  $hayNorm = ($hay -replace '[^a-z0-9\s]', ' ' -replace '\s+', ' ').Trim()
  $townNorm = ($urlTown.ToLower() -replace '[^a-z0-9\s]', ' ' -replace '\s+', ' ').Trim()
  $ok = $false
  if ($townNorm) {
    # allow partial: donaghadee in address, or urlTown tokens
    $tokens = $townNorm -split '\s+' | Where-Object { $_.Length -ge 4 }
    if (-not $tokens.Count) { $tokens = @($townNorm) }
    foreach ($t in $tokens) {
      if ($hayNorm.Contains($t)) { $ok = $true; break }
    }
  }
  if (-not $ok) {
    $mismatched += [pscustomobject]@{
      name = $d.name
      address = $d.address
      urlTown = $urlTown
      homesNiUrl = $d.homesNiUrl
    }
  }
}
$mismatched | Format-Table -AutoSize -Wrap
Write-Host ("mismatched town count: {0}" -f $mismatched.Count)

Write-Host ""
Write-Host "=== Short names (1-2 words) marked YES ==="
$yes | Where-Object { @($_.name -split '\s+' | Where-Object { $_ }).Count -le 2 } |
  Select-Object name, address, @{n='url';e={$_.homesNiUrl}} |
  Format-Table -AutoSize -Wrap

Write-Host ""
Write-Host "=== Duplicate development names with mixed YES/NO ==="
$byName = $a.developments | Group-Object name | Where-Object { $_.Count -gt 1 }
foreach ($g in $byName) {
  $flags = @($g.Group | ForEach-Object { if ($_.onHomesNi) { 'YES' } else { 'NO' } }) | Sort-Object -Unique
  if ($flags.Count -gt 1 -or ($flags -contains 'YES')) {
    Write-Host ("--- {0} ---" -f $g.Name)
    $g.Group | ForEach-Object {
      Write-Host ("  {0}  {1}  {2}" -f ($(if ($_.onHomesNi) {'YES'} else {'NO'})), $_.address, $_.homesNiUrl)
    }
  }
}
