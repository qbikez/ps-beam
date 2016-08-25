
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


function get-nugetcommand($projpath) {
    $restoreCmd = "nuget"
    $restoreParams = @("restore")
    
    req csproj
    req newtonsoft.json 

    if ($projpath -ne $null -and $projpath -match ".xproj") {
        $dir = split-path -parent $projpath
        $globaljsonpath = find-globaljson "$reporoot\$dir"
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
