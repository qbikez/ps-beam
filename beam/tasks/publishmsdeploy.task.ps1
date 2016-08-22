
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