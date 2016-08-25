[cmdletbinding()]
param([switch][bool]$wait, [switch][bool]$reload)

import-module require
$global:timepreference = $VerbosePreference

{
    req crayon -wait:$wait -reload:$reload
    (gmo crayon) | format-table Name,Path,Version | out-string | write-verbose
    
} | log-time -m "importing crayon module" 

{
    req publishmap -version 1.1.35 -source "oneget" -wait:$wait -reload:$reload
    gmo publishmap | format-table Name,Path,Version | out-string | write-verbose
} | log-time -m "importing publishmap module" 

{
   #req LegimiTasks -version 1.3.6 -wait:$wait -reload:$reload -source choco -package "PS-LegimiTasks"
} | log-time -m "importing legimitasks" 


{
    req pathutils -wait:$wait -reload:$reload -version 1.0.10.63
    gmo pathutils | format-table Name,Path,Version | out-string | write-verbose
} | log-time -m "importing pathutils" 


gmo | format-table Name,Version | out-string | write-verbose