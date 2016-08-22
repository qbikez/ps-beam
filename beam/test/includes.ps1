$root = $psscriptroot
if ([string]::isnullorempty($root)) {
    $root = "."
}

. "$psscriptroot\..\beam.ps1"