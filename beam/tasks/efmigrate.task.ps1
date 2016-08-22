
function run-taskMigrate(
[parameter(mandatory=$true)]$desc,
[parameter(mandatory=$true)]$profile,
$params = @{}
) {
    $csproj = (get-item (join-path ".." $desc.proj))
    if ($csproj -ne $null) {
        $projdir = split-path $csproj.fullname -Parent
    }
    else {
        $projdir = (split-path -Leaf $desc.proj) -replace ".csproj",""
        $projdir = join-path "..\migrations" $projdir
    }
    if (!(test-path $projdir)) {
        throw "directory $projdir not found"
    }
    $config = $profile.Config
    if ($config -eq $null) {
        $config = "Debug"
    }
    $dir = Join-Path ($projdir) "bin\$Config"
    if (!(test-path $dir)) {
        $dir = $projdir
    }
    $asm = (split-path -Leaf $desc.proj) -replace ".csproj",""
    $asm += ".dll"
    $toolsPath = $desc.toolsPath
    $efVersion = $desc.efVersion
    if ($efVersion -eq $null) {
        $efVersion = "6.1.3"
    }
    if ($toolsPath -eq $null) {
        $toolsPath = "$PSScriptRoot\..\packages\EntityFramework.$efVersion\tools"
    }
    $additionalArgs = @{}
    if ($customParams.targetMigration.Value -ne $null) {
        write-host "setting targetMigration to $($params.targetMigration)"
        $additionalArgs += @{ targetMigration = $params.targetMigration }
    }
    Migrate-Db -asm $asm -connectionStringName $($profile.connectionStringName) -ToolsPath $toolsPath -dir $dir @additionalArgs 
}
