$runningdir = pwd
  
$reporoot = ""


#. "$PSScriptRoot/publishmap.config.ps1"
. $PSScriptRoot\helpers.ps1
. $PSScriptRoot\customparams.ps1
foreach($t in (get-childitem "$PSScriptRoot\tasks" -filter "*.ps1")) {
    write-verbose "importing task $($t.name)"
    . "$($t.fullname)"c
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
    if ($reporoot -eq $null) { throw "could not find repository root for directory '$((get-item ..).FullName)'" }

    parse-customParams $params
    $defaultTasks = @("Deploy", "Test")
    $tasks = @()
    if ($task -ne $null) {
        $tasks = @($task)
    }

    if ($NoAuthCache) {
        #$container = "$(split-path -leaf $desc.proj).$($profile.profile).cred"
        $container = get-profilecredentialscontainer $profile
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
                write-warning " publish.ps1 $($parent)swap_$($profile._name)"
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

