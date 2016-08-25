import-module pester
import-module crayon
. "$PSScriptRoot\includes.ps1"

Describe "Beam Smoke tests" {
    copy-item "$psscriptroot\input\*" "testdrive:" -Recurse
    In "testdrive:\" {
        It "Should list available profiles" {
            WithLogRedirect {
                $r = invoke-beam -verbose
                $r | ? { $_ -like "help:   Commands:" } | Should Not BeNullorempty
                $global:exitCode | Should Be -2
            }
        }  
        It "Should execute hello world" {
            $r = invoke-beam test.hello_world.dev -verbose
            $r | should Not BeNullOrEmpty
            $r.Count | Should Be 2 # output line + status line
            $r | select -First 1 | should Be "hello world!"
        }  
    }
}