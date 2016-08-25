$Global:errorsDict = @()
$Global:successDict = @()


function Wrap-Response(
[Parameter(Mandatory=$true)] [uri] $uri,
[Parameter(Mandatory=$true)] [scriptblock] $scriptblock,
[Parameter(Mandatory=$false)] [string] $body = ""
)
{

    try {
        $resp = Invoke-Command -ScriptBlock $scriptblock
        $s = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Response" = $resp; "Body"= $body; "Message" = $null }
        $Global:successDict += $s    
        return $s   
    }
    catch {
        $err = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Message" = $_.Exception.Message; "Body"= $body; "Response" = $null }
        $Global:errorsDict += $err
        return $err
    }
}


function New-TestResult(
[Parameter(Mandatory=$true)][int] $totalCount,
[Parameter(Mandatory=$true)][int] $errorsCount,
[Parameter(Mandatory=$false)][int] $failureCount = 0,
[Parameter(Mandatory=$false)][int] $inconclusiveCount = 0
) {

    $result = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = $totalCount
            errors = $errorsCount
            failures = $failureCount
            inconclusive = $inconclusiveCount
        }

        return $result
}

function Test-RestApi(
[Parameter(Mandatory=$true)] [Microsoft.PowerShell.Commands.WebRequestMethod] $Method,
[Parameter(Mandatory=$true)] [uri] $uri,
[Parameter(Mandatory=$false)] [string] $body = "", 
$proxy = $null,
$timeoutSec = $null
) 
{
    
    try {
        
        write-verbose "invoking rest $method $url $body"
        if ($proxy -ne $null) {
            write-verbose "using proxy: $proxy"
        }
        $p = @{
            method = $method
            uri = $uri
            proxy = $proxy
        }
        if ($method -eq [Microsoft.PowerShell.Commands.WebRequestMethod]::Post) {
            $p.Body = $body
        }
        if ($timeoutSec -ne $null) {
            $p.timeoutSec = $timeoutSec
        }

        $resp = Invoke-RestMethod @p
        
    
        $s = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Response" = $resp; "Body"= $body; "Message" = $null }
        $Global:successDict += $s
        write-verbose "$method $url DONE"

        return $s
        
    } catch [Exception] {
        $err = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Message" = $_.Exception.Message; "Body"= $body; "Response" = $null }
        $Global:errorsDict += $err
        return $err
    }

    
    
}




function Test-Server(
[Parameter(Mandatory=$true)] [string] $hostname,
[Parameter(Mandatory=$true)] [string] $path,
[string] $body,
[Microsoft.PowerShell.Commands.WebRequestMethod] $method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Post,
$proxy = $null
)
{
    if (!$hostname.StartsWith("http")) {
        $baseUri = "http://$hostname"
    }
    $url = "$baseUri/$path"

    $r = Test-RestApi -Method $method -Uri "$url" -Body $body -proxy $proxy
    return $r
}

function Test-Url(
[Parameter(Mandatory=$true)] [string] $url,
[string] $body,
[Microsoft.PowerShell.Commands.WebRequestMethod] $method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get,
$proxy = $null,
[pscredential] $credentials = $null,
[Alias("SessionVariable")]$SessionOutVariable = $null,
[Alias("WebSession")]$session = $null,
[switch][bool]$autosession = $false,
[switch][bool]$noredirects,
$headers = @{},
$timeoutSec = $null
)
{
    $uri = $url
    try {
        if ($proxy -ne $null) {
            write-verbose "using proxy: $proxy"
        }
        $maxRedirects = $null
        if ($noredirects) {
            $maxRedirects = 0
        }
        if ($credentials -ne $null) {        
            $username = $credentials.UserName
            $password = $credentials.GetNetworkCredential().Password
            $headers += @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+$password ))} 
            #$maxRedirects = 0
        }
        $a = @{
            Method = $Method
            Uri = $uri
        }

        if ($proxy -ne $null) { $a += @{ Proxy = $proxy } }
        if ($method -eq [Microsoft.PowerShell.Commands.WebRequestMethod]::Post) { $a += @{ Body = $body } }
        if ($credentials -ne $null) { $a += @{ Credential = $credentials; }  }
        if ($maxRedirects -ne $null) { $a += @{ MaximumRedirection = $maxRedirects } }
        if ($timeoutSec -ne $null) { $a += @{ TimeoutSec = $timeoutSec } }

        if ($autosession) { 
            if (!(test-path "variable:_websession") -or $_websession -eq $null) {
                $a += @{ SessionVariable = "_websession" }
				$SessionOutVariable = "_websession"
            } else {
                $a += @{ WebSession = $_websession }
            }
        }
        else 
        {
            if ($SessionOutVariable -ne $null) {
                $a += @{ SessionVariable = $SessionOutVariable }
            }
            elseif ($session -ne $null) {
                $a += @{ Session = $session }
            }
        }

        if ($headers -ne $null) {
            $a += @{ Headers = $headers }
        }

        write-verbose "invoking web $method $url $body."
        write-verbose "args="
        $a | format-table | out-string | Write-Verbose
        

        $resp = Invoke-WebRequest @a -ErrorAction SilentlyContinue -UseBasicParsing
        if ($SessionOutVariable -ne $null) { 
               set-variable $SessionOutVariable -Value ((get-variable $SessionOutVariable)).Value -Scope script
        }
        
        $s = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Response" = $resp; "Body"= $body; "Message" = $null }
        $Global:successDict += $s
        write-verbose "$method $url DONE"

        return $s
        
    } catch [Exception] {
        $err = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Message" = $_.Exception.Message; "Body"= $body; "Response" = $null }
        
        return $err
    }
}