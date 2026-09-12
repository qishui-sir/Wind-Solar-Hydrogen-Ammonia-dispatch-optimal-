param(
    [Parameter(Mandatory=$true)][string]$Query,
    [int]$Rows = 20,
    [int]$MinYear = 0,
    [string]$Sort = "score"
)

$ErrorActionPreference = 'Continue'
function Clean-Jats($xml) {
    if ($null -eq $xml -or $xml -eq "") { return "" }
    $t = $xml -replace '<[^>]+>', ' '
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

$q = [uri]::EscapeDataString($Query)
$url = "https://api.crossref.org/works?query.bibliographic=$q&rows=$Rows&sort=$Sort&order=desc&select=DOI,title,author,container-title,issued,is-referenced-by-count,abstract,type&mailto=research@example.org"

$resp = $null
for ($a = 1; $a -le 5; $a++) {
    try {
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 90 -Headers @{ 'User-Agent' = 'LitReview/1.0 (mailto:research@example.org)' }
    } catch { Write-Warning "try $a : $($_.Exception.Message)" }
    if ($null -ne $resp) { break }
    Start-Sleep -Seconds (4 * $a)
}
if ($null -eq $resp) { Write-Output "### FAILED: $Query"; exit 1 }

Write-Output "### QUERY: $Query | total=$($resp.message.'total-results') | shown=$($resp.message.items.Count)"
Write-Output ""
$n = 0
foreach ($it in $resp.message.items) {
    $yr = 0
    if ($it.issued.'date-parts' -and $it.issued.'date-parts'[0][0]) { $yr = [int]$it.issued.'date-parts'[0][0] }
    if ($MinYear -gt 0 -and $yr -lt $MinYear) { continue }
    $n++
    $title = ($it.title -join ' ')
    $jrn = ($it.'container-title' -join ' ')
    $auth = (($it.author | Select-Object -First 4 | ForEach-Object { "$($_.given) $($_.family)" }) -join '; ')
    $abs = Clean-Jats $it.abstract
    if ($abs.Length -gt 2000) { $abs = $abs.Substring(0,2000) + " ...[truncated]" }
    Write-Output "TITLE   : $title"
    Write-Output "AUTHORS : $auth"
    Write-Output "JOURNAL : $jrn"
    Write-Output "YEAR    : $yr  | CITED: $($it.'is-referenced-by-count') | TYPE: $($it.type)"
    Write-Output "DOI     : https://doi.org/$($it.DOI)"
    Write-Output "ABSTRACT: $abs"
    Write-Output "---"
}
Write-Output "(filtered-in: $n)"
