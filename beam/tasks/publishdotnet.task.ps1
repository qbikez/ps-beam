

function run-taskPublishTaskDotnet
(
[parameter(mandatory=$true)]$desc,
[parameter(mandatory=$true)]$profile)
{
    pushd 
    try {
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

        $publishresult = invoke dotnet publish -passthru
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

       $cred = get-profilecredentials $profile
       $username = $cred.username
       $password = $cred.password

        #$appurl = "https://$($hostname)/msdeploy.axd"
        $appurl = match-appurl $hostname $site       
        $dest = "-dest:$($appurl.msdeployurl),username=$username,password=$password"
        
        $src = $publishdir
        if (!(test-path $src)) {
            throw "source directory '$src' not found!"
        }
    

        $src = (get-item $src).FullName
        $appurl = (match-appurl $src)
        $source = "-source:$($appurl.msdeployurl -replace "contentPath=","IisApp=")"

        $a = @("-verb:sync", $dest, $source, "-verbose", "-allowUntrusted")
        #write-host "running msdeploy: " ($a -replace $password,'{PASSWORD-REMOVED-FROM-LOG}')
    
        $r = invoke $msdeploy -arguments $a -passthru -verbose

        $computerName = $profile.ComputerName
        $taskName = $profile.TaskName
        $targetDir = $profile.TargetDir
        $srcDir = $profile.SourceDir
    } finally {
        popd
    }
}