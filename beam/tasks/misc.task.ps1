
function run-task(
[parameter(mandatory=$true)]$desc,
[parameter(mandatory=$true)]$profile,
[parameter(mandatory=$true)]$taskname,
[switch][bool] $silent,
$params = @{},
$psparams) {
    if ($reporoot -eq $null) { throw "could not detect repository root" }
    if ($desc.sln -ne $null) {        
        $slnpath = (join-path $reporoot $desc.sln)
        if (!(test-path $slnpath)) { throw "SLN file '$slnpath' not found" }
        $sln = (get-item $slnpath).FullName
    }
    $csproj = get-csprojpath $desc

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
             run-taskSwapTask $profile
        }
        "Backup" {
            $fullBackup = $true
             $taskProfile = get-swapbaseprofile $profile
    
            $computerName = $profile.ComputerName
            if ($computername -eq $null) { $computername = $taskprofile.ComputerName }
            
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
            run-taskSwapWebsite $profile  
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


