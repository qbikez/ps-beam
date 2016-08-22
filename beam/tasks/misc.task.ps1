
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


