$runningdir = pwd
    

$customParams = @{
    SkipServerFiles = @{
        Description = "true - only add new and modified files. false - remove files that are on the server, but not in the published package"
    }
    targetMigration = @{
    }
    Subdir = @{
        Description = "publish only a subdir of IIS site"
    }
}

$reporoot = ""

function get-customparamsflat($customParams, $profile) {
    $h = @{}
    if ($profile -ne $null -and $profile.custom_params -ne $null) {
         $profile.custom_params.GetEnumerator() | `
        ? { $_.Value -ne $null -and $_.Value.Value -ne $null  } `
        | % { 
            $h[$_.Key] = $_.Value.Value
        } 
    }
    $customParams.GetEnumerator() | `
        ? { $_.Value -ne $null -and $_.Value.Value -ne $null  } `
        | % { 
            $h[$_.Key] = $_.Value.Value
        } 
    return $h
}

#param(
#[parameter(mandatory=$true)] $profile,
#[parameter(mandatory=$false)] $desc,
#[switch][bool] $Test = $false,
#[switch][bool] $Build = $false,
#[switch][bool] $Force =$false,
#[switch][bool] $NoAuthCache,
#[switch][bool] $NoTest,
#[switch][bool] $Gui
# )

function parse-customParams($params) {
    $customParams.GetEnumerator() | % {
        if ($_.Value.Name -eq $null) {
            $_.Value.Name = $_.Key
        }
    }
    $params.GetEnumerator() | % { 
        $key = $_.Key
        $val = $_.Value
        $cp = $customParams.Values | ? { $_.Name -eq $key } | select -First 1
        if ($cp -ne $null) {
            $cp.Value = $val
        } else {
            $customParams[$key] = $val
        }
    }
}

#. "$PSScriptRoot/publishmap.config.ps1"

req legimitasks
req  deployment

function get-msbuild($msbuilddesc) {
    $msbuild = "msbuild"
    if ($msbuilddesc -ne $null) {
        $msbuildver = 0.0
        if ([double]::TryParse($desc.msbuild,  [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref] $msbuildver)) {
            $msbuild = join-path (get-msbuildpath -version $msbuildver) "msbuild.exe"
        }
        else {
            $msbuild = $desc.msbuild
        }
    }
    return $msbuild
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

function run-script($cmd, $params)
{
pushd
try {    
     if ($cmd -is [scriptblock]) {
            $global:reporoot = $reporoot 
            #for script blocks, use root of publish.ps1
            $global:libRoot = $psscriptroot
            cd $global:libRoot
            icm -ScriptBlock $cmd -ArgumentList @($params)
        }
        else {
            if (([string]$cmd).StartsWith(".\") -or ([string]$cmd).StartsWith("./")) {
                cd $PSScriptRoot\..
            }
            log-message -prefix "info" "running command '$cmd'"
            & $cmd $params
        }
} finally {
    popd
}
}


# from csproj module:
function find-reporoot($path) {
        if (!(test-path $path)) { return $null }
        $path = (get-item $path).FullName

        if (!(get-item $path).PsIsContainer) {
            $dir = split-path -Parent $path
        }
        else {
            $dir = $path
        }
        while(![string]::IsNullOrEmpty($dir)) {
            if ((test-path "$dir/.hg") -or (Test-Path "$dir/.git")) {
                $reporoot = $dir
                break;
            }
            $dir = split-path -Parent $dir
        }
        return $reporoot
}


function get-repopath($relPath) {    
    $r = find-reporoot $relPath
    if ($r -eq $null){ 
        $repo = "$PSScriptRoot\.."
        $abspath = Join-Path $repo $relpath
        if (Test-Path $abspath) {
            $abspath = (get-item $abspath).FullName
        }
        $r = $abspath
    }

    return $r
    
    #return $abspath
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

function run-taskPublishTaskDotnet
(
[parameter(mandatory=$true)]$desc,
[parameter(mandatory=$true)]$profile)
{
    pushd 
    try {
        $reporoot = find-reporoot ".."
        $dir = join-path $reporoot (split-path -parent $desc.proj)
        

        cd $dir

        $msdeploy = "c:\Program Files (x86)\IIS\Microsoft Web Deploy V3\msdeploy.exe"
        $hostname = $profile.Host
        if ($hostname -eq $null) {
            $hostname = $profile.Machine
        }
       

        $appPath = get-appPath $profile $projectroot
    
        $site = $profile.Site
        if ($site -eq $null) {
            if ($profile.type -eq "task" -or ($profile.task -eq $null -and $profile.project.type -eq "task")) {
                $site = "$($profile.baseapppath)/_deploy/$($appPath)"
            }
            else {
                $site = "$($profile.baseapppath)/$($appPath)"
           }
       
        }

        $publishresult = $null
        dotnet publish | Tee-Object -Variable "publishresult"
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet publish failed"    
        }
        $publishdir = $publishresult | % { if ($_ -match "publish: Published to (.*)$") { $matches[1] } }
        if ($publishdir -eq $null) {
            throw "failed to parse dotnet publish dir"
        }

        $config = $profile.Config
        $targetDir = $profile.TargetDir
        $targetTask = $profile.TaskName

        $password = $profile.password
        if ($password -eq "?") {
            $container = "$(split-path -leaf $desc.proj).$($profile.profile).cred"
            $cred = get-CredentialsCached -container $container -message "publishing credentials for project $($profile.fullpath) host $hostname"
            $password = $cred.GetNetworkCredential().Password
            $username = $cred.UserName
        }

        #$appurl = "https://$($hostname)/msdeploy.axd"
        $appurl = match-appurl $hostname $appPath       
        $dest = "-dest:$($appurl.msdeployurl),username=$username,password=$password"
        
        $src = $publishdir
        if (!(test-path $src)) {
            throw "source directory '$src' not found!"
        }
    

        $src = (get-item $src).FullName
        $appurl = (match-appurl $src)
        $source = "-source:$($appurl.msdeployurl -replace "contentPath=","IisApp=")"

        $a = @("-verb:sync", $dest, $source, "-verbose", "-allowUntrusted")
        write-host "running msdeploy: " ($a -replace $password,'{PASSWORD-REMOVED-FROM-LOG}')
    
        Start-Executable $msdeploy -ArgumentList $a

        $computerName = $profile.ComputerName
        $taskName = $profile.TaskName
        $targetDir = $profile.TargetDir
        $srcDir = $profile.SourceDir
    } finally {
        popd
    }
}

function run-taskPublishTask
(
[parameter(mandatory=$true)]$desc,
[parameter(mandatory=$true)]$profile)
{
    $msdeploy = "c:\Program Files (x86)\IIS\Microsoft Web Deploy V3\msdeploy.exe"
    $hostname = $profile.Host
    if ($hostname -eq $null) {
        $hostname = $profile.Machine
    }
    if ($hostname -notmatch ":[0-9]+") {
        $hostname += ":8172"
    }

    $appPath = get-appPath $profile $projectroot
    
    $site = $profile.Site
    if ($site -eq $null) {
        if ($profile.type -eq "task" -or ($profile.task -eq $null -and $profile.project.type -eq "task")) {
            $site = "$($profile.baseapppath)/_deploy/$($appPath)"
        }
        else {
            $site = "$($profile.baseapppath)/$($appPath)"
       }
       
    }


    $config = $profile.Config
    $targetDir = $profile.TargetDir
    $targetTask = $profile.TaskName

    $password = $profile.password
    if ($password -eq "?") {
        $container = "$(split-path -leaf $desc.proj).$($profile.profile).cred"
        $cred = get-CredentialsCached -container $container -message "publishing credentials for project $($profile.fullpath) host $hostname"
        $password = $cred.GetNetworkCredential().Password
        $username = $cred.UserName
    }

    $dest = "-dest:iisApp=`"$site`",wmsvc=https://$($hostname)/msdeploy.axd,username=$username,password=$password"
    $csproj = (get-item (join-path ".." $desc.proj)).FullName
    $src = split-path -Parent $csproj 
    $src = $src + "\bin\" + $config
    if (!(test-path $src)) {
        throw "source directory '$src' not found!"
    }
    $src = (get-item $src).FullName
    $source = "-source:iisApp=`"$src`""

    $args = @("-verb:sync", $dest, $source, "-verbose", "-allowUntrusted")
    write-host "running msdeploy: " ($args -replace $password,'{PASSWORD-REMOVED-FROM-LOG}')
    
    Start-Executable $msdeploy -ArgumentList $args

    $computerName = $profile.ComputerName
    $taskName = $profile.TaskName
    $targetDir = $profile.TargetDir
    $srcDir = $profile.SourceDir

}

function run-taskMigrate(
[parameter(mandatory=$true)]$desc,
[parameter(mandatory=$true)]$profile,
$params = @{}
) {
    $csproj = (get-item (join-path ".." $desc.proj))
    if ($csproj -ne $null) {
        $projdir = split-path $csproj.fullname -Parent
    }
    else {
        $projdir = (split-path -Leaf $desc.proj) -replace ".csproj",""
        $projdir = join-path "..\migrations" $projdir
    }
    if (!(test-path $projdir)) {
        throw "directory $projdir not found"
    }
    $config = $profile.Config
    if ($config -eq $null) {
        $config = "Debug"
    }
    $dir = Join-Path ($projdir) "bin\$Config"
    if (!(test-path $dir)) {
        $dir = $projdir
    }
    $asm = (split-path -Leaf $desc.proj) -replace ".csproj",""
    $asm += ".dll"
    $toolsPath = $desc.toolsPath
    $efVersion = $desc.efVersion
    if ($efVersion -eq $null) {
        $efVersion = "6.1.3"
    }
    if ($toolsPath -eq $null) {
        $toolsPath = "$PSScriptRoot\..\packages\EntityFramework.$efVersion\tools"
    }
    $additionalArgs = @{}
    if ($customParams.targetMigration.Value -ne $null) {
        write-host "setting targetMigration to $($params.targetMigration)"
        $additionalArgs += @{ targetMigration = $params.targetMigration }
    }
    Migrate-Db -asm $asm -connectionStringName $($profile.connectionStringName) -ToolsPath $toolsPath -dir $dir @additionalArgs 
}


function get-nugetcommand($projpath) {
    $restoreCmd = "nuget"
    $restoreParams = @("restore")
    
    req csproj
    req newtonsoft.json 

    if ($projpath -ne $null -and $projpath -match ".xproj") {
        $dir = split-path -parent $projpath
        $globaljsonpath = find-globaljson "$psscriptroot\..\$dir"
        if ($globaljsonpath -ne $null) {
            $globaljson = ConvertFrom-JsonNewtonsoft (get-content "$globaljsonpath" | out-string)
            $sdkver = $globaljson.sdk.version
            if ($sdkver -match "1\.0\.0-rc1" -or $sdkver -match "1\.0\.0-beta") {
                $restoreCmd = "dnu"
            }
            else {
                $restorecmd = "dotnet"
            }
        }
        
        if ($restorecmd -eq "dnu" -and !(test-command dnu)) {
            # TODO: get sdk version from global.json
            dnvm use default 
        }
        $restoreVersion = & $restoreCmd --version | select -First 1
        $restoreParams = @("restore")
        if ($nocache) { $restoreParams += @("--no-cache") }


        $arpath = (gi "$psscriptroot\..").FullName
        write-host -ForegroundColor Magenta "looking for artifacts at $($arpath)..."
        $ar = Get-ChildItem -Path "$arpath" -Include "artifacts" -ErrorAction Ignore #-recurse 
        $ar = $ar | ? { 
            $_.name -eq "artifacts" -and $_.PsIsContainer 
        }
        $ar | % { 
                remove-item $_.FullName -Force -verbose -Recurse 
            }
            #>
                    
    }
    else {
        $restoreVersion = & nuget | select -First 1
        if ($projpath -ne $null) {
            $restoreParams += $projpath
        }
    }    
    return $restoreCmd,$restoreParams,$restoreVersion
}

function get-apppath ($profile, $projectroot)
{
    $isVnext = $false
    if ($projectroot -ne $null) {
        $isVnext = (gci $projectroot -Filter "*.xproj").Length -gt 0
    }
    $isAzure = $profile.machine -match "(.*)\.scm\.azurewebsites\.net"

    $appname = $profile.appname 
    if ($appname -eq $null) { $appname = $profile.project.appname }
    if ($appname -ne $null) {                
        $appPath = $($appname)
        if ($profile.baseapppath -ne $null) {
            if ($isazure) {
                $appPath = "$($profile.baseapppath)"
                return $appPath 
            }
            elseif ($profile.project._fullpath -match "\.task_") {
                $appPath = "$($profile.baseapppath)/_deploy/$($appname)"
            }
            else {
                $appPath = "$($profile.baseapppath)/$($appname)"
            }
        }
        if ($isVnext -and $appPath -ne $null) {
            $appPath = $appPath + "-deploy"
        }
        if ($profile.appPostfix -ne $null) {
            $appPath += $($profile.appPostfix)
        } elseif ($profile.fullpath.EndsWith("staging")) {
            $appPath += "-staging"
        }
    }

    return $appPath
}

function run-task(
[parameter(mandatory=$true)]$desc,
[parameter(mandatory=$true)]$profile,
[parameter(mandatory=$true)]$taskname,
[switch][bool] $silent,
$params = @{},
$psparams) {
    if ($desc.sln -ne $null) {
        $sln = (get-item (join-path $reporoot $desc.sln)).FullName
    }
    if ($desc.proj -ne $null) {
        $csproj = (get-item (join-path $reporoot $desc.proj)).FullName
    }
    $task = $taskname
    $scriptTriggers = "Deploy"
    if ($task -in $scriptTriggers -and $profile.before -ne $null) {
        write-host "running BEFORE script..."
        run-script $profile.before -params $psparams
        write-host "BEFORE script DONE."
    }
    if ($profile."before_$task" -ne $null) {
        write-host "running BEFORE_$task script..."
        run-script $profile."before_$task" -params $psparams
        write-host "BEFORE script DONE."
    }

    switch($task) {
        { $_ -in "Build" } { 
            $msbuild = get-msbuild ($desc.msbuild)
            $additionalArgs = $null
            if ($profile.msbuildprops -ne $null) {
                $msbuildprops = $profile.msbuildprops 
                $additionalArgs = $msbuildprops.psobject.properties | % { "/p:$($_.Name)=$($_.Value)" }
            }
           
           $pubprof = $profile.profile 
            if ($pubprof -eq $null) { $pubprof = "" }
            publish-legimiproject -sln $desc.sln -csproj $desc.proj -config $profile.config -BuildOnly:$true -msbuild:$msbuild -additionalArgs:$additionalArgs
        }
        { $_ -match "^dnu$" } {
            push-location
            $projectRoot = (Split-Path -Parent $csproj)                
            try {
                if ($desc.proj -match ".xproj") {
                    if (!(test-command dnu)) {
                        dnvm use default 
                    }
                    $dnuVersion = dnu --version | select -First 1
                    $cmd = "dnu"
                    $params = @("build")
                    write-host "running command ($cmd $params) version '$restoreVersion' at root: $projectRoot"
                    push-location
                    try {
                        cd $projectRoot
                        $r = ""
                        & $cmd $params | Tee-Object -Variable "r"
                        $result += $r
                    } finally {
                        pop-location
                    }
                }
            }
            finally {
                Pop-Location
            }           
        }
        { $_ -in "Restore" } { 
            
            push-location
            try {
                $root = @()

                # ipmo csproj
                # get-slnprojects $sln | ? { $_.path -match ".csproj" } | % { push-location; try { cd (split-path -parent $_.path); nuget restore; } finally { pop-location } }

                $useSlnRoot = $false
                if ($desc.proj -match ".xproj" -or $desc.proj -match ".csproj" -or $desc.use_sln_root) {
                    $useSlnRoot = $true
                }
                $projectRoot = (Split-Path -Parent $csproj)               
                
                if ($desc.restore_root -ne $null) {
                    $r = $desc.restore_root |  % { 
                        (get-item (join-path $reporoot $_)).FullName 
                    }
                    write-host "adding restore_root: $r"
                    $root += $r
                }
                elseif ($useSlnRoot)
                {
                    $r  = $sln
                    #$r = (Split-Path -Parent $sln)
                    write-host "adding sln restore root: $r"
                    $root += $r
                }
                else {
                    $root += $projectRoot
                }
                

                $projpath = $desc.proj 
               
                
                                
                $result = ""
                $root = $root | select -Unique
                write-host "will run restore ($restoreCmd $p) version '$restoreVersion' in following root folders:"
                $root | write-host
                $error.Clear()
                $root | % { 
                    $it = get-item $_
                    if ($it.psisContainer) {
                        $restoreCmd,$restoreParams,$restoreVersion = get-nugetcommand $projpath
                    } else {
                        $restoreCmd,$restoreParams,$restoreVersion = get-nugetcommand $_
                        $_ = split-path -Parent $_
                    }
                    $p = $restoreParams
                    #$p += "$_"
                    write-host "running package restore ($restoreCmd $p) version '$restoreVersion' at root: $_"
                    push-location
                    try {
                        if ($it.psisContainer) {
                            cd $_
                        }
                        $r = ""
                        & $restoreCmd $restoreParams | tee-object -Variable "r"
                        $result += $r
                        if ($LASTEXITCODE -ne 0) {
                            if ($StopOnError) {
                                $msg = $error | Out-String
                                throw "restore for root '$_' failed!:" + $msg
                            }
                        }
                    } finally {
                        pop-location
                    }
                }               
                if ([string]::IsNullOrEmpty($result)) {                
                    Write-Warning "package restore gave no output"
                }
            } finally {
                pop-location
            }
        }
        "Pubxml" {
            $resetPubProfile = $params.resetPubProfile
            if ($resetPubProfile -eq $null) { $resetPubProfile = $false }
            $password = $profile.password
            if ($password -eq "?") {
                #$container = "$(split-path -leaf $desc.proj).$($profile.profile).cred"
                $container = $profile.credentials_container
                if ($container -eq $null) {
                    $container = $profile.machine -replace ":","_"
                }
                $cred = get-CredentialsCached -container $container -message "publishing credentials for `
                project: $($profile.fullpath)`
                profile: $($profile.profile)`
                host: $($profile.machine)"
                $password = $cred.GetNetworkCredential().Password
                $username = $cred.UserName
            }
           
           $projectRoot = (Split-Path -Parent $csproj)               

           $appPath = get-appPath $profile $projectroot
         
           ipmo pubxml
           
           $cp = (get-customparamsflat $customParams)

           
           generate-pubprofile -projectroot $projectRoot -profilename $profile.profile -machine $profile.machine -appPath $appPath -reset:$resetPubProfile  -customparams $cp -username $username
        }

        "Deploy" {
           $p = $PSBoundParameters
           $p["taskname"] = "pubxml"

           # TODO: add tasks dependencies
           run-task @p
           $additionalArgs = $null
           if ($profile.msbuildprops -ne $null) {
                $msbuildprops = $profile.msbuildprops 
                $additionalArgs = $msbuildprops.psobject.properties | % { "/p:$($_.Name)=$($_.Value)" }
            }
            $container = $profile.credentials_container
             if ($container -eq $null) {
                    $container = $profile.machine -replace ":","_"
                }
             $cred = get-CredentialsCached -container $container -message "publishing credentials for `
                project: $($profile.fullpath)`
                profile: $($profile.profile)`
                host: $($profile.machine)"
            $password = $cred.GetNetworkCredential().Password
            $username = $cred.UserName

            $msbuild = get-msbuild ($desc.msbuild)

            <#
            if (test-path "$env:LOCALAPPDATA\Temp\PublishTemp\pubtmp") {
                # make sure there are no leftovers
                remove-item "$env:LOCALAPPDATA\Temp\PublishTemp\pubtmp"
            }
            #>
            $slnfile = $desc.sln 
            if ($desc.deployproject -ne $null) {
                $slnfile = $desc.deployproject 
            }
            publish-legimiproject -sln $slnfile -csproj $desc.proj -config $profile.config -profile $profile.profile -password $password -deployprop $desc.deployprop -username $username -BuildOnly:$false -msbuild:$msbuild -additionalArgs:$additionalArgs
        }
        "Test" { run-TaskTest $desc $profile }
        "FullTest" { run-TaskTest $desc $profile -full }
        "PublishTask" {
            if ($desc.proj.endsWith(".xproj")) {
                $dotnet = $true
                if ($dotnet) {
                    run-taskPublishTaskDotnet $desc $profile
                } else {
                    $p = $PSBoundParameters
                    $p["taskname"] = "deploy"
                    run-task @p
                }
            }
            else {
                run-taskPublishTask $desc $profile
            }
            #if (![string]::IsNullOrEmpty($desc.type)) {
            #    if ($desc.type -eq "task") {
            #        $target = "Build"
            #        $sln = (get-item (join-path ".." $desc.sln)).FullName
            #        msbuild $sln /m /p:Configuration="$($profile.config)" /p:Platform="Any CPU" /p:RunOctoPack="true" "/target:$target" 
            #    }
            #}
        }
        "SwapTask" {
            $taskProfile = get-profile ($profile.fullpath -replace "swap_","")
            if ($taskProfile -ne $null) { $taskProfile = $taskProfile.profile }
            $computerName = $profile.ComputerName
            $taskName = $profile.TaskName
            $appname = get-apppath $profile
            if ($taskname -eq $null) {
                
                $taskname = $appname -replace "task_","" -replace "_","-"
                $taskname = "-" + $taskname
            }

            $baseAppPath = $profile.BaseAppPath
            if ($baseAppPath -eq $null) { $baseAppPath = $taskProfile.BaseAppPath }

            if ($taskname -match "^\-") {
                $taskname = $baseAppPath + $taskname
            }
            $taskUser = $profile.TaskUser
            $taskPassword = $profile.TaskPassword

            if ($taskUser -eq $null) {
                $reset = $false
                if ($psparams.NoAuthCache -ne $null -or $params.ClearCredentials) { $reset = $psparams.NoAuthCache -or  $params.ClearCredentials }
                $cred = Get-CredentialsCached -message "user for $taskname task" -container "task-$($profile.fullpath)" -reset:$reset
                $taskuser = $cred.username
                $taskpassword = $cred.getnetworkcredential().password
            }

            if ($appName -eq $null) { $appName = get-apppath $taskProfile }
            $baseDir = $profile.basedir
            if ($baseDir -eq $null) { $baseDir = $taskProfile.baseDir }
            if ($baseDir -eq $null) {
                $basepathtrimmed = $baseAppPath.trim("/")
                $baseDir = "c:/www/$basepathtrimmed"
            }
            $targetDir = $profile.TargetDir
            if ($targetDir -eq $null) { $targetDir = $taskProfile.TargetDir }
            if ($targetDir -eq $null) {
                $targetDir = "$basedir/tasks/$($appname)"
            }
            $srcDir = $profile.SourceDir
            if ($srcDir -eq $null) {
                $srcDir = "$basedir/_deploy/$($appname)"
            }
            

           
            write-host "running remote command to copy from deployment to staging. server=$computerName src=$srcDir target=$targetDir"
            if ($computerName -ne "localhost") { 
                $s = New-RemoteSession $computerName -Verbose
            }
            $icm = @{
                ScriptBlock = {
                    param($tn, $src, $dst) 
                    ipmo LegimiTasks
                    $staging = $dst + "-staging"
                    if (!$src.EndsWith("-staging")) { $src = "$src-staging" }
                    #if (!(test-path $src) -and (test-path "$src-staging")) { $src = "$src-staging" }
                    if (!(test-path $src)) { throw "source directory '$src' not found" }
                    if (!(test-path $staging)) { new-item -ItemType directory $staging }
                    copy-item "$src/*" $staging -Recurse -Verbose -Force
                    if (!(test-path $dst)) { new-item -ItemType directory $dst }
                    cd $dst
                } 
                ArgumentList = @($taskname, $srcDir, $targetDir)   
            }
            if ($s -ne $null) { $icm += @{ Session = $s } }
  
            icm @icm
            $shouldCompare = ($psparams["CompareConfig"] -eq $null -or  $psparams["CompareConfig"] -eq $true);           
            if (!$silent -and !$profile.Silent -and $shouldCompare) {
                write-host "running Compare-StagingConfig" 
                Compare-StagingConfig -Session $s -path $targetDir
            }
            
            write-host "running remote command to copy from staging"
            $icm = @{
                ScriptBlock = {
                    param($tn, $src, $dst, $taskUser, $taskPassword) 
                    ipmo LegimiTasks
                    ipmo TaskScheduler
                    cd $dst
                    do-backup -verbose
                    $t = get-Scheduledtask $tn
                    if ($t -eq $null) {
                        write-warning "Task '$tn' not found!"
                        write-host "creating task '$tn' with $taskUser/$taskPassword"
                        Create-TaskHere -Name $tn -Username $taskUser -Password $taskPassword -Silent
                        $t = get-Scheduledtask $tn
                    }
                    write-host "stopping task '$($t.Name)'"
                    $t | stop-task
                    Start-Sleep -Seconds 3
                    write-host "copy-fromstaging"
                    copy-fromstaging -verbose
                    write-host "starting task '$($t.Name)'"
                    $t | Start-Task
                } 
                ArgumentList = @($taskname, $srcDir, $targetDir, $taskUser, $taskPassword)   
            }
            if ($s -ne $null) { $icm += @{ Session = $s } }
            icm @icm         
        }
        "Backup" {
            $fullBackup = $true
            $computerName = $profile.ComputerName
            $taskName = $profile.TaskName
            $targetDir = $profile.TargetDir
            $srcDir = $profile.SourceDir
            if ($targetDir -eq $null) {
                $site = $profile.Site
                if ($site -eq $null) {
                   $site = "$($profile.baseapppath)/$($profile.appname)$($profile.appPostfix)"       
                }
                $targetDir = "IIS://Sites/$site"
            }
            write-host "running remote command to do a backup of '$targetDir' server=$computerName"
            if ($computerName -ne "localhost") { 
                $s = New-RemoteSession $computerName -Verbose
            }
            $icm = @{
                ScriptBlock = {
                    param($tn, $src, $dst, $fullBackup) 
                    ipmo LegimiTasks
                    ipmo TaskScheduler
                    if ($dst -match "^IIS://") {
                        ipmo WebAdministration
                        $phys = (gi $dst).PhysicalPath                        
                        $dst = $phys                  
                        if ($fullBackup -and $dst -match "[/\\]wwwroot$") {
                            $dst = split-path -Parent $dst
                        }     
                        
                    }
                    Write-Host "doing backup at '$dst'"
                    cd $dst
                    do-backup -verbose                   
                } 
                ArgumentList = @($taskname, $srcDir, $targetDir, $fullBackup)   
            }
            if ($s -ne $null) { $icm += @{ Session = $s } }
            icm @icm         
        }
        "SwapWebsite" {
            $computerName = $profile.ComputerName
            
            $taskProfile = get-profile ($profile.fullpath -replace "swap_","")
            if ($taskProfile -ne $null) { $taskProfile = $taskProfile.profile }

            $baseAppPath = $profile.BaseAppPath
            if ($baseAppPath -eq $null) { $baseAppPath = $taskProfile.BaseAppPath }
            $appName = $profile.appname
            if ($appName -eq $null) { $appName = $taskProfile.AppName }
            $baseDir = $profile.basedir
            if ($baseDir -eq $null) { $baseDir = $taskProfile.baseDir }
            if ($baseDir -eq $null) {
                $basepathtrimmed = $baseAppPath.trim("/")
                $baseDir = "c:/www/$basepathtrimmed"
            }
            $targetDir = $profile.TargetDir
            if ($targetDir -eq $null) { $targetDir = $taskProfile.TargetDir }
            if ($targetDir -eq $null) {
                $targetDir = "$basedir/$($appname)"
            }
            $srcDir = $profile.SourceDir
            if ($srcDir -eq $null) {
                $srcDir = "$basedir/$($appname)-staging"
            }


            $s = New-RemoteSession $computerName -Verbose:$($VerbosePreference -eq "Continue")

            icm -Session $s -ScriptBlock {
                param($dst) 
                cd $dst
            } -ArgumentList @($targetDir)           

            $shouldCompare = ($psparams["CompareConfig"] -eq $null -or  $psparams["CompareConfig"] -eq $true);           
            if (!$silent -and !$profile.Silent -and $shouldCompare) {
                Compare-StagingConfig -Session $s -path $targetDir
            }
            icm -Session $s -ScriptBlock {
                param($dst, $dobackup) 
                ipmo LegimiTasks
                ipmo TaskScheduler 
                write-host "imported LegimiTasks from '$((gmo LegimiTasks).Path)'"
                cd $dst
                if ($dobackup) {
                  do-backup -verbose:($verbosepreference -eq "Continue")
                }
                write-host "copy-fromstaging at '$dst'"
                copy-fromstaging -verbose
            } -ArgumentList @($targetDir, $dobackup)           
        }
        "SwapAzureSite" {
        }
        "Powershell" {
            Push-Location
            try {
                $cmd = $profile.Command
                run-script $cmd -params @{ Silent = $silent }
            }
            finally {
                Pop-Location
            }
        }
        "CompareConfig" {
            $computerName = $profile.ComputerName
            $targetDir = $profile.TargetDir

            if ($computerName -ne "localhost") {
                $s = New-RemoteSession $computerName
            }

            $icm = @{ 
                ScriptBlock = {
                    param($dst) 
                    cd $dst
                } 
                ArgumentList = @($targetDir)           
            }
            if ($s -ne $null) { $icm += @{ Session = $s } }
            icm @icm
            $shouldCompare = ($psparams["CompareConfig"] -eq $null -or  $psparams["CompareConfig"] -eq $true);           
            
            if ($shouldCompare) {
                if ($s -ne $null) {
                    Compare-StagingConfig -Session $s
                }
                else {
                    push-location
                    try {
                        cd $dst
                        Compare-StagingConfig
                    } finally {
                    Pop-Location
                    }
                }
            }
        }
        "Migrate" {
            run-taskMigrate -desc $desc -profile $profile -params $params
        }
        "BuildAzurePackage" {
            $msbuild = get-msbuild $desc.msbuild
            # EnableWebDeploy should be retrieved from azurepubxml
            & $msbuild "$sln" `
                                /p:Configuration=$($profile.config) `
                                /p:DebugType=None `
                                /p:Platform="Any Cpu" `
                                /p:TargetProfile=Cloud `
                                /p:EnableWebDeploy=true `
                                /p:WebDeployPorts=$($profile.WebDeployPorts) `
                                /t:publish `
                                /verbosity:normal                                
        }
        "PublishAzurePackage" {
            $msbuild = get-msbuild ($desc.msbuild)
            $csprojdir = split-path -Parent $csproj
            $package = (get-item (join-path $reporoot $profile.package)).FullName
            $pubxml =  "$csprojdir\profiles\$($profile.profile)"
            & "$psscriptroot\AzureDeploy.ps1" -publishProfilePath $pubxml -package $package
        }
        "dependencies" {
            foreach($kvp in $profile.project.dependencies.GetEnumerator()) {
                $alias = $kvp.key
                if ($alias.startswith("_")) { continue }
                $dep = $kvp.value
                write-host "restoring $alias : $($dep.name)"
                switch($dep.source) {
                    "webpicmd" {
                        $pkgname = $dep.name
                        write-host "running: webpicmd /install /products:$pkgname /AcceptEula"
                        webpicmd /install /products:$pkgname  /AcceptEula
                    }
                }
            }
        }
    }

   if ($taskname -in $scriptTriggers -and $profile.after -ne $null) {
        write-host "running AFTER script..."
        run-script $profile.after
        write-host "AFTER script DONE."
    }
    if ($profile."after_$task" -ne $null) {
        write-host "running AFTER_$task script..."
        run-script $profile."after_$task" -params $psparams
        write-host "AFTER script DONE."
    }
}



function publish-project {
[cmdletbinding()]
param(
[parameter(mandatory=$true)]$desc,
 [parameter(mandatory=$true)]$profile,
 # run tests only
 [switch][bool] $Test,
 #run full test suite
 [switch][bool] $FullTest,
 # run build only
 [switch][bool] $Build,
 [switch][bool] $Force,
 [Alias("ResetCredentials", "ClearCredentials")]
 [switch][bool] $NoAuthCache,
 [switch][bool] $NoTest,
 [switch][bool] $Gui,
 [switch][bool] $CompareConfig,
 [switch][bool] $silent = $false,
 [switch][bool] $Restore = $false,
 [switch][bool] $StopOnError = $true,
 [switch][bool] $withbackup = $false,
 [switch][bool] $noBackup = $false,
 [switch][bool] $NoBuild,
 $task = $null,
$params = @{},
 [Parameter(ValueFromRemainingArguments=$true)]
$ExtraParameters
 ) 
    write-host "publishing project $desc"
    $reporoot = find-reporoot ".."

    parse-customParams $params
    $defaultTasks = @("Deploy", "Test")
    $tasks = @()
    if ($task -ne $null) {
        $tasks = @($task)
    }

    if ($NoAuthCache) {
        $container = "$(split-path -leaf $desc.proj).$($profile.profile).cred"
        Remove-CredentialsCached $container
    }

    if ($Test) { $tasks = @("Test"); }
    if ($FullTest) { $tasks = @("FullTest"); }
    if ($Build) { $tasks = @("Build"); }
    if ($Restore) { $tasks = @("Restore"); }
    if ($CompareConfig) { $tasks = @("CompareConfig"); }

  
    $forceNoBackup = $false
    if ($tasks.Length -eq 0) { 
        if ($profile.type -eq "task" -or ($profile.type -eq $null -and $profile.project.type -eq "task"))  # why isn't it inherited??
        {
            if ($profile._name -notmatch "swap_" -and $profile._name -notmatch "_staging") {
                $parent = $profile.fullpath.Replace($profile._name,"")
                write-warning ""
                write-warning "Direct publishing of tasks is not supported. Use: "
                write-warning " publish.ps1 $($profile.fullpath)_staging"
                write-warning " publish.ps1 $($parent)swap_$($profile.name)"
                return
            }
            if ($profile._fullpath -match "\.swap_") {
                $tasks = @("SwapTask","Test")
                $forceNoBackup = $true
            }
            else {
                if (!$NoBuild) {
                    $tasks += @("Build")
                }
                $tasks += @("PublishTask")
            }
        }
        else {
            if ($profile._fullpath -match "\.swap_") {
                $tasks = @("SwapWebsite","Test")
            } elseif ($profile.command -ne $null) {
                $tasks = @("powershell")
            }
            else {
                $tasks = $defaultTasks 
            }
        }
    }
    
    if ($tasks.Length -eq 0 -and ![string]::IsNullOrEmpty($profile.Task)) {
        $tasks = $tasks | ? { $_ -ne "Deploy" }
        $taskname = $profile.Task
        #do not duplicate tasks
        $tasks = $tasks | ? { $_ -ne $taskname }    
        
        $tasks = @($taskname) + $tasks        
    }
        
    
    $doBackup = $false    
    # by default, do backup when swapping
    if ($profile.fullpath -match "staging") { $doBackup = $false }
    if ($profile.fullpath -match "swap") { $doBackup = $true }

    if ($withbackup.IsPresent) { $doBackup = $withbackup }
    if ($noBackup.IsPresent) { $doBackup = !$noBackup }

    if ($forceNoBackup) { $doBackup = $false }
    if ($doBackup) { $tasks = @("Backup") + $tasks } 

    else { write-warning "not doing backup" }

    if ($NoTest) {  $tasks = $tasks | ? { $_ -ne "Test" } }
    elseif ($tasks -notcontains "Test" -and $tasks -contains "Deploy") { $tasks += "Test" }


    write-host "running tasks:"
    $tasks | out-string | write-host 
    foreach($t in $tasks) {
        run-task -desc $desc -profile $profile -taskname $t -silent:$silent -params $params -psparams $PSBoundParameters
    }
}

function publish-legimiproject {
param(
    [parameter(mandatory=$true)]
    $sln, 
    [parameter(mandatory=$true)]
    $csproj, 
    [parameter(mandatory=$true)]
    $config, 
    [parameter(mandatory=$false)]
    $profile, 
    [Switch]
    [bool] $LocalOnly = $true,
    [Switch]
    [bool] $FromLocal = $false,
    [Switch]
    [bool] $Clean = $false,
    [string] $Target = $null,
    [bool] $WithBackup = $true,
    [string] $password,
    [string] $username,
    [string] $deployprop,
    [switch][bool] $buildOnly,
    [string] $msbuild,
    [array] $additionalArgs = $null,
    [switch][bool] $Restore = $false
)

    if (Get-Module legimitasks) { remove-module legimitasks }
    import-module LegimiTasks

    
    cd $PSScriptRoot


    $sln = (get-item (join-path $reporoot $sln)).FullName
    $csproj = (get-item (join-path $reporoot $csproj)).FullName

    $defaultServer = [LegimiServer]::DEVEL

    if ([string]::IsNullOrEmpty($target)-and ![string]::IsNullOrEmpty($config)) {
        $target = $config
    }
    if ($Target -ne $null) { 
        if ($Target -in @("release", "prod", "rel")) {
            $serverconfig = [LegimiServer]::RELEASE
        }
    }   
    if ($serverconfig -eq $null) {
        $serverconfig = $defaultServer 
    }

    $solutionFile=$sln
    $projectname = (split-path -Leaf $csproj).Replace(".cproj", "")
    $cfg = New-LegimiConfig -Server $serverconfig -ProjectName $projectname
    $baseDir = split-path -Parent $csproj

    $srv = $cfg.server    
    

    $srv.buildConfiguration = $config
    if ($solutionFile.EndsWith(".csproj") -and $srv.buildArchitecture -eq "Any CPU") {
        $srv.buildArchitecture = "AnyCPU"
    }

    $cfg.server = $srv
    
    if ([string]::IsNullOrEmpty($deployprop)) {
        $deployprop = "DeployOnBuild"
    }

    Publish-LegimiWebsite -Config $cfg `
    -solution $sln `
    -LocalOnly:$LocalOnly -Clean:$Clean `
    -FromLocal:$FromLocal -WithBackup:$withBackup `
    -baseDir $baseDir -profileName $profile -deployprop $deployprop `
    -password $password -username $username `
    -buildOnly:$buildOnly `
    -msbuild $msbuild `
    -NoBackup `
    -additionalArgs:$additionalArgs

}


#if ($desc -eq $null) {
#    $desc = $profile.project
#}

#publish-project -desc $desc -profile $profile -Test:$Test -force:$force -NoAuthCache:$NoAuthCache -NoTest:$NoTest -Build:$Build -Gui:$Gui

