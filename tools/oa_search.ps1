param(
    [Parameter(Mandatory=$true)][string]$Query,
    [int]$PerPage = 25,
    [int]$MinYear = 0,
    [string]$Sort = "cited_by_count:desc"
)

$ErrorActionPreference = 'Continue'
function Convert-AbstractInvertedIndex($inv) {
    if ($null -eq $inv) { return "" }
    $pairs = @()
    foreach ($p in $inv.PSObject.Properties) {
        foreach ($pos in $p.Value) { $pairs += [pscustomobject]@{ w = $p.Name; p = [int]$pos } }
    }
    if ($pairs.Count -eq 0) { return "" }
    return (($pairs | Sort-Object p | ForEach-Object { $_.w }) -join ' ')
}

$q = ($Query.Trim() -split '\s+') -join '+'
$url = "https://api.openalex.org/works?filter=title_and_abstract.search:$q&per-page=$PerPage&sort=$Sort&mailto=research@example.org"

$resp = $null
for ($a = 1; $a -le 5; $a++) {
    try { $resp = Invoke-RestMethod -Uri $url -TimeoutSec 90 } catch { Write-Warning "try $a : $($_.Exception.Message)" }
    if ($null -ne $resp) { break }
    Start-Sleep -Seconds (4 * $a)
}
if ($null -eq $resp) { Write-Output "### FAILED: $Query"; exit 1 }

Write-Output "### QUERY: $Query | sort=$Sort | shown=$($resp.results.Count) of $($resp.meta.count)"
Write-Output ""
foreach ($w in $resp.results) {
    if ($MinYear -gt 0 -and $w.publication_year -lt $MinYear) { continue }
    $journal = ""
    if ($w.primary_location -and $w.primary_location.source) { $journal = $w.primary_location.source.display_name }
    $abs = Convert-AbstractInvertedIndex $w.abstract_inverted_index
    if ($abs.Length -gt 2000) { $abs = $abs.Substring(0, 2000) + " ...[truncated]" }
    Write-Output "TITLE   : $($w.title)"
    Write-Output "AUTHORS : $((($w.authorships | ForEach-Object { $_.author.display_name }) | Select-Object -First 4) -join '; ')"
    Write-Output "JOURNAL : $journal"
    Write-Output "YEAR    : $($w.publication_year)  | CITED: $($w.cited_by_count)"
    Write-Output "DOI     : $($w.doi)"
    Write-Output "ABSTRACT: $abs"
    Write-Output "---"
}
