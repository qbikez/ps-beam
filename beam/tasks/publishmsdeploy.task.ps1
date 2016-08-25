
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
        if ($appPath.startswith($($profile.baseapppath))) {
            # should the apppath contain baseapppath also?
            $site = $appPath
        } else {
            if ($profile.type -eq "task" -or ($profile.task -eq $null -and $profile.project.type -eq "task")) {
                $site = "$($profile.baseapppath)/_deploy/$($appPath)"
            }
            else {
                $site = "$($profile.baseapppath)/$($appPath)"
           }
       }
       
    }


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

    $args = @("-verb:sync", $dest, $source, "-verbose", "-allowUntrusted")
    write-host "running msdeploy: " ($args -replace $($cred.password),'{PASSWORD-REMOVED-FROM-LOG}')
    
    Start-Executable $msdeploy -ArgumentList $args

    $computerName = $profile.ComputerName
    $taskName = $profile.TaskName
    $targetDir = $profile.TargetDir
    $srcDir = $profile.SourceDir

}