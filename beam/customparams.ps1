$customParams = @{
    SkipServerFiles = @{
        Description = "true - only add new and modified files. false - remove files that are on the server, but not in the published package"
    }
    targetMigration = @{
    }
    Subdir = @{
        Description = "publish only a subdir of IIS site"
    }
}

function get-customparamsflat($customParams, $profile) {
    $h = @{}
    if ($profile -ne $null -and $profile.custom_params -ne $null) {
         $profile.custom_params.GetEnumerator() | `
        ? { $_.Value -ne $null -and $_.Value.Value -ne $null  } `
        | % { 
            $h[$_.Key] = $_.Value.Value
        } 
    }
    $customParams.GetEnumerator() | `
        ? { $_.Value -ne $null -and $_.Value.Value -ne $null  } `
        | % { 
            $h[$_.Key] = $_.Value.Value
        } 
    return $h
}



function parse-customParams($params) {
    $customParams.GetEnumerator() | % {
        if ($_.Value.Name -eq $null) {
            $_.Value.Name = $_.Key
        }
    }
    $params.GetEnumerator() | % { 
        $key = $_.Key
        $val = $_.Value
        $cp = $customParams.Values | ? { $_.Name -eq $key } | select -First 1
        if ($cp -ne $null) {
            $cp.Value = $val
        } else {
            $customParams[$key] = $val
        }
    }
}
