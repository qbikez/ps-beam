
function run-TaskTest(
[parameter(mandatory=$true)]$desc,
[parameter(mandatory=$true)]$profile,
[switch][bool] $full,
$params = @{},
$psparams = $null)
{
    $tests = @()
    if (![string]::IsNullOrEmpty($profile.test)) {
        $tests = @($profile.test)
    }
    if ($full -and ![string]::IsNullOrEmpty($profile.full_test)) {
        $tests += @($profile.full_test)
    }
    if ($tests.Length -gt 0) {    
        $totalResult = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = 0
            errors = 0
            failures = 0
            inconclusive = 0
        }

        foreach($test in $tests) {
            if ($desc.test_type -ne $null) {
                $testtype = $desc.test_type
            }
            else {
                $testtype = $null
                if ($desc.test_fixture -ne $null) {
                    if ($desc.test_fixture.StartsWith("ps:") -or ($desc.test_fixture.EndsWith(".ps1"))) {
                        $testtype = "ps"
                        $desc.test_fixture = $desc.test_fixture -replace "ps:", ""
                    }
                    elseif ($desc.test_fixture.StartsWith("nunut:") -or ($desc.test_fixture.EndsWith(".dll")))
                    {
                         $testtype = "nunit"
                    }
                    else {
                        $testtype = $desc.test_fixture
                    }     
                }
                else {
                    if ($test -is [scriptblock]) {
                        $testtype = "script"
                    }     
                    elseif ($test.StartsWith("http")) {
                        $testtype = "webtest"
                    }     
                }       
                if ($testtype -eq $null) {
                    $testtype = "nunit"
                }              
            }
            if ($desc.settings -ne $null -and $desc.settings.siteAuth -ne $null) {
                $secpasswd = ConvertTo-SecureString $desc.settings.siteAuth.password -AsPlainText -Force
                $cred = New-Object System.Management.Automation.PsCredential $desc.settings.siteAuth.username,$secpasswd
            }
            if ($testtype -eq "nunit") {
                $testFixture = (get-item (join-path  ".." $desc.test_fixture)).FullName
                $result = run-nunittest $testFixture $test -Gui:$Gui
            }
            elseif ($testtype -eq "ps") {
                $testFixture = (get-item (join-path  ".." $desc.test_fixture)).FullName        
                $result = run-pstest $testFixture $test -Gui:$Gui
            }
            elseif ($testtype -eq "webtest") {
                $result = run-webtest $test -Gui:$Gui -credentials $cred
            }
            elseif ($testtype -eq "webtest-rest" -or $testtype -eq "rest") {
                $result = run-webtest $test -Gui:$Gui -rest -credentials $cred
            }        
            elseif ($testtype -eq "script") {
                $result = run-scripttest $test -Gui:$Gui -params @{ profile = $profile }
            }      
            $result | Format-Table
            
            $totalResult.all += $result.all
            $totalResult.errors += $result.errors
            $totalResult.failures += $result.failures
            $totalResult.inconclusive += $result.inconclusive  
        }
        $result = $totalResult
        $result | Format-Table

        # TODO: extract a function for running different types of tests (Nunit, webtests, powershell, etc) with a common result class
        $lastResult = import-cache -dir "lgm-publish" -container "$(split-path -leaf $desc.proj).$($profile.profile).json"
        if ($lastResult -ne $null) {
            $lasterrors = [int]::MaxValue
            if (![string]::IsNullOrWhiteSpace($lastresult.errors)) {
                try {
                    $lastErrors = [int]$lastresult.errors
                }
                catch {
                    write-host $Error
                    $lasterrors = 0    
                }
            }            

            if ($lasterrors -ne $null -and $result.errors -gt $lasterrors) {
                $msg = "error number increased from $($lasterrors) to $($result.errors)"
                if (!$force) {
                    throw $msg
                } else {
                    write-error ("[FORCED]" + $msg)
                }
            }
            elseif ($result.errors -lt $lasterrors) {
                write-host -ForegroundColor Green "error number decreased from $($lasterrors) to $($result.errors)! Gratz!"
            }
            else {
                write-host -ForegroundColor DarkGreen "errors number hasn't changed. That's a success!"
            }
        }
        if ($result.errors -eq 0) {
            write-host -ForegroundColor Green "No Errors. AVESOME!"
        } 
        else {
            write-host -ForegroundColor Red "$($result.errors) of $($result.all) test FAILED."
        }
        export-cache -dir "lgm-publish" -container "$(split-path -leaf $desc.proj).$($profile.profile).json" $result
    }
}


function run-pstest($fixture, $test, [switch][bool] $Gui) {
    if ($gui) {
        write-host "starting powershell_ise for fixture $fixture"
        & powershell_ise $fixture
    }
    else {
        write-host "running test fixture from powershell script $fixture"

        $r = & $fixture $test
        $props = [ordered]@{
            timestamp = $r.timestamp
            all = $r.all
            errors = $r.errors
            failures = $r.failures
            inconclusive = $r.inconclusive
        }
        $result = New-Object -TypeName pscustomobject -Property $props
        return $result
    }
}

function run-nunittest($fixture, $test, [switch][bool] $Gui) {
    $run=$($test) -replace "`"", "\\\`""         

    if ($gui) {
        write-host "starting nunit gui for fixture $fixture"
        & nunit $fixture
    }
    else {
        write-host "running test fixture $run from assembly $fixture"
        $result = & nunit-console $fixture "/nologo" "/nodots" "/framework=net-4.5.1" "/run=$run"

        $regex = "Tests run: ([0-9]+), Errors: ([0-9]+), Failures: ([0-9]+), Inconclusive: ([0-9]+)"
        $lines = $result -match $regex 
        $m = $lines[0] -match $regex 
                
        $props =  [ordered]@{
            timestamp = get-date
            all = [int]$Matches[1]
            errors = [int]$Matches[2]
            failures = [int]$Matches[3]
            inconclusive = [int]$Matches[4] 
        }
        $result = New-Object -TypeName pscustomobject -Property $props

        return $result
    }
}

function run-scripttest($test, [switch][bool] $Gui, $params) {
    
    $output = run-script $test $params
    $lastline = $output | select -last 1
    if ($lastline -match "Total: ([0-9]+), Errors: ([0-9]+), Failed: ([0-9]+), Skipped: ([0-9]+), Time: (.*)s") {
        $result = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = $Matches[1]
            errors = $Matches[3]
            failures = $Matches[2]
            inconclusive = 0
        }
    }
    else {
        $result = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = 1
            errors = 0
            failures = 0
            inconclusive = 1
        }
    }
    Write-Host ($output | Out-String)
    return $result
}


function run-webtest($test, [switch][bool] $Gui, [switch][bool]$rest, $credentials = $null)
{
    . "$PSScriptRoot\test-helpers.ps1"

    write-host "testing url $test"
    
    $urls = @($test)

    $ok = @()
    $errors = @()

    $urls | % {
        $url = $_
        $proxy = $null
        if ($url.proxy -ne $null) {
            $proxy = $url.proxy
            $url = $url.url
        }
        if ($rest) {
            $r = Test-RestApi -uri $url -Method Get -proxy $proxy -timeoutsec 120
        }
        else {
            $r = test-url $url -proxy $proxy -credentials $credentials -timeoutsec 120
        }
        if ($r.Response -ne $null) {
            $ok += $r
        }
        else {
            $r | Format-Table | out-string | write-host 
            $errors += $r
        }
    }

    $result = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = $urls.Length
            errors = $errors.Length            
            failures = 0
            inconclusive = 0
        }

        return $result
}

