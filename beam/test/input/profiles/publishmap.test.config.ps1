param([switch][bool] $silent)

$publishmap = @{
   
    test = [ordered]@{
        settings = @{
            siteAuth = @{
                    username = ""
                    password = ""
            }
        }
        global_profiles =@{
            dev = @{
                    connectionStringName = "MyDb-dev"
                    db_portal = @{ connectionStringName = "MyDb-dev" }
                    Config = "Debug"
                    Password = "?"
                    profile = "dev.pubxml"
                    Machine = "machine"
                }
        }
        db_portal = @{
        }
        server = @{
            sln = "sln\MySolution\MySolution.sln"        
            proj = "src\MyProject.Server\MyProject.Server.csproj"
            #deployprop="DeployBookMeta"
            appname="svc/content"           
        }  
        hello_world = @{
            dev = @{ 
                command = { write-output "hello world!" }
            }
        }   
    }
    
}

return $publishmap