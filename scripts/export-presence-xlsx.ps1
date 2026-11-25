$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent
$data = [System.IO.File]::ReadAllText((Join-Path $repo 'data\developments.json'), $utf8) | ConvertFrom-Json
$xlsxOut = Join-Path $env:USERPROFILE "Downloads\homesni-new-homes-presence-$(Get-Date -Format 'yyyy-MM-dd')-v5.xlsx"

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
try {
  $wb = $excel.Workbooks.Add()
  $ws = $wb.Worksheets.Item(1)
  $ws.Name = 'Presence'
  $headers = @('Development','Address','Town','Status','Homes available','Sale agreed / redundant','Has Microsite?','On HomesNI?','HomesNI URL','HomesNI agent?','Price','Developer(s)','Agent(s)','URL','Path ID')
  for ($c = 0; $c -lt $headers.Count; $c++) { $ws.Cells.Item(1, $c + 1) = $headers[$c] }
  $r = 2
  foreach ($d in $data.developments) {
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
$yes = @($data.developments | Where-Object onHomesNi).Count
$agentYes = @($data.developments | Where-Object homesNiAgent).Count
$gap = @($data.developments | Where-Object { $_.homesNiAgent -and -not $_.onHomesNi }).Count
Write-Host "Wrote $xlsxOut"
Write-Host "onHomesNi=$yes homesNiAgent=$agentYes agentButNoListing=$gap"
