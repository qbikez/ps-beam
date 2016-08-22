

function run-script($cmd, $params)
{
pushd
try {    
     if ($cmd -is [scriptblock]) {
            $global:reporoot = $reporoot 
            #for script blocks, use root of publish.ps1
            $global:libRoot = $psscriptroot
            cd $global:libRoot
            icm -ScriptBlock $cmd -ArgumentList @($params)
        }
        else {
            if (([string]$cmd).StartsWith(".\") -or ([string]$cmd).StartsWith("./")) {
                cd $PSScriptRoot\..
            }
            log-message -prefix "info" "running command '$cmd'"
            & $cmd $params
        }
} finally {
    popd
}
}

