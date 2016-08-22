param ($path = $null)


if ($path -eq $null) { $path = "$PSScriptRoot\..\test" }
#$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", [System.EnvironmentVariableTarget]::User)
import-module require
req pester -version 3.3.14

$artifacts = "$path\artifacts"

if (!(test-path $artifacts)) { $null = new-item -type directory $artifacts }

write-host "running tests. artifacts dir = $((gi $artifacts).FullName)"

if (!(Test-Path $artifacts)) {
    $null = new-item $artifacts -ItemType directory
}
$r = Invoke-Pester "$path" -OutputFile "$artifacts\test-result.xml" -OutputFormat NUnitXml 

return $r
