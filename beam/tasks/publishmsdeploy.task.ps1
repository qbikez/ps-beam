
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
    
    $site = get-siteName $profile


    $config = $profile.Config
    $targetDir = $profile.TargetDir
    $targetTask = $profile.TaskName

    $cred = get-profilecredentials $profile
   

    $dest = "-dest:iisApp=`"$site`",wmsvc=https://$($hostname)/msdeploy.axd,username=$($cred.username),password=$($cred.password)"
    
    $csproj = get-csprojpath $desc
    
    $src = split-path -Parent $csproj 
    $src = $src + "\bin\" + $config
    if (!(test-path $src)) {
        throw "source directory '$src' not found!"
    }
    $src = (get-item $src).FullName
    $source = "-source:iisApp=`"$src`""

    if ($profile.project.additional_files -ne $null) {
        cp (get-fullpath $profile $profile.project.additional_files) $src -verbose -Recurse
    }

    $args = @("-verb:sync", $dest, $source, "-verbose", "-allowUntrusted")
    write-host "running msdeploy: " ($args -replace $($cred.password),'{PASSWORD-REMOVED-FROM-LOG}')
    
    Start-Executable $msdeploy -ArgumentList $args

    $computerName = $profile.ComputerName
    $taskName = $profile.TaskName
    $targetDir = $profile.TargetDir
    $srcDir = $profile.SourceDir

}

function run-taskSwapTask([parameter(mandatory=$true)]$profile) {
            $taskProfile = get-swapbaseprofile $profile
            
            $computerName = $profile.ComputerName
            if ($computername -eq $null) { $computername = $taskprofile.ComputerName }

            $baseAppPath = $profile.BaseAppPath
            if ($baseAppPath -eq $null) { $baseAppPath = $taskProfile.BaseAppPath }


            $taskname = get-taskname $taskprofile
            $appPath = get-apppath $profile 
            if ($appPath -eq $null) { $appName = get-apppath $taskProfile }

            $site = get-siteName $profile
        
            $taskUser = $profile.TaskUser
            $taskPassword = $profile.TaskPassword

            if ($taskUser -eq $null) {
                $reset = $false
                if ($psparams.NoAuthCache -ne $null -or $params.ClearCredentials) { $reset = $psparams.NoAuthCache -or  $params.ClearCredentials }
                $cred = Get-CredentialsCached -message "user for $taskname task" -container "task-$($profile.fullpath)" -reset:$reset
                $taskuser = $cred.username
                $taskpassword = $cred.getnetworkcredential().password
            }

            
            $baseDir = get-basedir $profile $taskProfile

            $targetDir = $profile.TargetDir
            if ($targetDir -eq $null) { $targetDir = $taskProfile.TargetDir }
            if ($targetDir -eq $null) {                
                $dirname = split-path -leaf $appPath
                $targetDir = "$basedir/tasks/$($dirname)"
            }
            $srcDir = $profile.SourceDir
            if ($srcDir -eq $null) {
                $dirname = split-path -leaf $appPath
                $srcDir = "$basedir/_deploy/$($dirname)-staging"
            }
            

           
            write-host "running remote command to copy from deployment to staging. server=$computerName src=$srcDir target=$targetDir"
            if ($computerName -ne "localhost") { 
                $s = New-RemoteSession $computerName -Verbose
            }
            $icm = @{
                ScriptBlock = {r
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
                    #do-backup -verbose
                    $folder = ""
                    $fulltn = $tn
                    if ($tn.contains("\")) {
                        $folder = split-path -Parent $tn
                        $tn = split-path -leaf $tn
                    }
                    $t = get-Scheduledtask $tn -Folder $folder
                    if ($t -eq $null) {
                        write-warning "Task '$tn' not found!"
                        write-host "creating task '$tn' with $taskUser/$taskPassword"
                        Create-TaskHere -Name $fulltn -Username $taskUser -Password $taskPassword -Silent
                        $t = get-Scheduledtask $tn -Folder $folder
                    }
                    write-host "stopping task '$folder/$($t.Name)'"
                    $t | stop-task
                    Start-Sleep -Seconds 3
                    write-host "copy-fromstaging"
                    copy-fromstaging -verbose
                    write-host "starting task '$folder/$($t.Name)'" 
                    $t | Start-Task
                } 
                ArgumentList = @($taskname, $srcDir, $targetDir, $taskUser, $taskPassword)   
            }
            if ($s -ne $null) { $icm += @{ Session = $s } }
            icm @icm         
        }


function run-taskswapwebsite([parameter(mandatory=$true)]$profile) {
    
    $taskProfile = get-swapbaseprofile $profile
    
    $computerName = $profile.ComputerName
    if ($computername -eq $null) { $computername = $taskprofile.ComputerName }

    $baseAppPath = $profile.BaseAppPath
    if ($baseAppPath -eq $null) { $baseAppPath = $taskProfile.BaseAppPath }


    $appname = get-apppath $profile 
    if ($appName -eq $null) { $appName = get-apppath $taskProfile }

    $baseDir = get-basedir $profile $taskprofile
    

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
        if (!(test-path $dst)) { $null = mkdir $dst }
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