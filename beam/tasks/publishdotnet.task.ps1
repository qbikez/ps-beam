

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