function invoke-beam {
[cmdletbinding(SupportsShouldProcess=$true)]
param(
[parameter(mandatory=$false)] $profile,
$map = $null,
[switch][bool] $Test = $false,
[switch][bool] $FullTest = $false,
[switch][bool] $Build = $false,
[switch][bool] $Force =$false,
[Alias("ResetCredentials", "ClearCredentials")]
[switch][bool] $NoAuthCache,
[switch][bool] $NoTest,
[switch][bool] $CompareConfig,
[switch][bool] $silent = $false,
[switch][bool] $Restore = $false,
[switch][bool] $StopOnError = $false,
[switch][bool] $withbackup = $false,
[switch][bool] $noBackup = $false,
[switch][bool] $wait = $false,
[switch][bool] $reload = $false,
[switch][bool] $logtime = $false,
[switch][bool] $NoBuild,
$task = $null,
$params = @{}
 )
    if ((gmo crayon) -and $reload) { rmo crayon }
    if (!(gmo crayon)) { ipmo crayon -DisableNameChecking -ErrorAction Continue }
    if ((gmo crayon)) {
        $logPattern.Add("^(?<cyan>help):", "help log level")
        $global:timepreference = $VerbosePreference
        if ($logtime) {
            $global:timepreference = "Continue"
        }
    }
 else {
    function log-info([Parameter(ValueFromRemainingArguments=$true)]$ExtraParameters) { Write-Host @ExtraParameters }
    function log-message([Parameter(ValueFromRemainingArguments=$true)]$ExtraParameters) { Write-Host @ExtraParameters  }
    function log-time([Parameter(ValueFromPipeline=$true)]$script,[Parameter(ValueFromRemainingArguments=$true)]$ExtraParameters) { Invoke-Command $script }
}


log-info "Legimi publish CLI" 

. "$psscriptroot\includes.ps1"

if ($reload) {
    if ($cache -ne $null) {
        $cache.clear()
    }
}

if ($profile -ieq "status") {
    return $publishstatus.GetEnumerator() | sort Name
}


if ($profile -ieq "clear") {
    $global:publishstatus = $null
    return
}

#. "$PSScriptRoot\setup-helpers.ps1"
#{ 
#    & "$PSScriptRoot\init-env.ps1"
#} | log-time -m "initializing env" 


function write-globalhelp() {
        #write-host ""    
        #Write-Host "Please select a publish profile from `$publishmap" -ForegroundColor Yellow
        #write-host ""

        #write-host "you can select one of these profiles:"

        #write-host ""
        #write-host "like this:"
        #write-host ".\publish.ps1 `$publishmap.legimi.www.local_release" -ForegroundColor Yellow        
        $projects = get-propertynames $publishmap
        log-message "" -prefix "help"
        log-message "" -prefix "help"
        log-message "  ``cyan``Get last operation status" 
        log-message "    status" 
        log-message "" 
        log-message "  Commands:" 
        $projects | % {
            log-message "    $_  " -prefix "help"
        }

}


function write-projecthelp($profile) {
        log-message "" -prefix "help"
        log-message "  Project: ``green``$($profile.fullpath)" -prefix "help"
        log-message "" -prefix "help"
        log-message "  Commands:" -prefix "help"

        if ($profile._level -eq 2) {
            $tasks = get-propertynames $profile.profiles 
        }
        else {
            $tasks = get-propertynames $profile 
        }
        $tasks = $tasks | ? {
            $_ -notin @("settings","global_profiles", "level", "fullpath") -and !$_.StartsWith("_")
        } | sort 
        $tasks = $tasks | % { "$($profile.fullpath).$_" }
        
        $len = ($tasks | % { $_.length } | measure -Maximum).Maximum        
        
        $tasks | % {
            $fullpath = $_
            $p = get-profile -name "$fullpath"
            $msg = "    $fullpath".PadRight($len + 5)
            if ($p.isGroup) {
				$group = $p.profile.Group
                $groupstr = [string]::Join(", ", $group)
                $msg += "``cyan``@($groupstr)"
            } 
            log-message $msg  -prefix "help"
        }
}

Push-Location

cd $PSScriptRoot

try {
 
$profilesDir = find-upwards -pattern "profiles"
if ($profilesDir -eq $null) {
    throw "profiles dir 'profiles' not found in any of parent directories"
}
$singleMap = $map
if ($profile -ne $null -and $profile -is [string] -and $singlemap -eq $null) {
    $splits = $profile.Split('.')
    if ($splits.length -eq 0) { $project = $profile }
    else { $project = $splits[0] }
    
    $singleMap = gi "$profilesDir\publishmap.$project.config.ps1"
}

{
    if ($singleMAp -ne $null) {
         $map = import-publishmap -maps $singleMap
    } else {
        $maps = (gci "$profilesDir" -Filter publishmap.*.config.ps1)
        $map = import-publishmap -maps $maps
    }
    $global:psSessionsMap = . "$profilesDir\sessionmap.config.ps1"
} | log-time -m "importing publishmap" 


 if ($profile -eq $null) {
        write-globalhelp

        exit -2
}

. "$PSScriptRoot\beam\beam.ps1"



$profiles = $profile
$errors = @()
$status = @{}

if ($global:publishStatus -eq $null) {
    $global:publishStatus = @{}
}

if ($profile -ieq "failed" -or $profile -ieq "firstfailed" ) {
    $profiles = $publishstatus.Keys | ? { $publishstatus[$_].status -ieq "ERROR" }
    if ($profile -ieq "firstfailed") {
        $profiles = $profiles | select -First 1
    }
}

foreach($profile in $profiles) {
    try {
        if ($profile -is [string]) {
            $p = get-profile $profile
            if ($p -eq $null) {
                throw "unknown profile $profName"
            }
            $profile = $p.profile

            if ($p.isGroup -and $p.taskname -ne $null) {
                # make sure bound parameters do not overlap with manual parameters
                $bound = $PSBoundParameters
                $bound.remove("project")
                $bound.remove("profile")
                $bound.remove("group")
                $a = $args
				return ./publish-group.ps1 -project $p.Project -group $p.Group -profile $p.TaskName @bound
            }

            if ($p.profile._level -lt 3) {
                write-projecthelp $p.profile
                exit -2
            }
        }
   

        
    $desc = $profile.project
    $params = $PSBoundParameters     
    $params.profile = $profile
    $params.desc = $desc

    
    if ($profile._bin_dir -ne $null) {
        $bindir = get-repopath $profile._bin_dir
        add-topath $bindir -first
        
        where-is grunt
    }

    publish-project @params 

    $status[$profile.fullpath] = New-Object pscustomobject -Property @{ Status = "OK"; Timestamp = Get-Date }

    } catch {
        $key = $profile.fullpath
        if ($key -eq $null) { $key = $profName }
        if ($key -eq $null) { $key = "?" }
        $errors += $_ 
        $errors += $_.ScriptStackTrace
        if ($profile -ne $null -and $profile.fullpath -ne $null) {
            $status[$profile.fullpath] = New-Object pscustomobject -Property @{ Status = "Error"; Timestamp = Get-Date; Error = $_ }
        }
        #$ErrorRecord | Format-List * -Force
        #$ErrorRecord.InvocationInfo |Format-List *
        #$Exception = $ErrorRecord.Exception
        #for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
        #{   "$i" * 80
        #    $Exception | Format-List * -Force
        #}

        write-warning "Error when publishing profile $($key): $_ `r`n $($_.ScriptStackTrace)"
        if ($StopOnError) {
            Write-Warning "stop on error = $true. Stopping"
            break
        }
    }
    finally {
        if ($profile -ne $null -and $profile.fullpath -ne $null) {
            $global:publishStatus[$profile.fullpath] = $status[$profile.fullpath]        
        }
    }
}



$status

if ($errors.Count -gt 0) {
    Write-Warning "ERRORS:"
    $errors
}
if ($errors.Count -gt 0) {
    $errors| % { $_ | out-string | Write-error }
    throw "$($errors.Count) errors encountered during publish"
}

if ($errors.Count -gt 0) {
    exit -1
} else {
    exit 0
}

} 
finally {
    Pop-Location
}

}


invoke-beam @PSBoundParameters