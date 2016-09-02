# Beam me up, Scotty!

# configuration

Profile file are stored in `profiles` dir and should be of form `publishmap.{xxx}.config.ps1` (where {xxx} is your project name.
A minimal config for a website looks like this:

```powershell
@{
    qlogger = @{
        global_profiles = @{
            dev = @{
                    Config = "Debug"
                    ComputerName = "phobos"                    
                    Machine = "phobos:8172"
                    BaseAppPath = "devserver-dev"
            }                     
        }
        viewer = @{ 
            sln = "Qlogger.sln"
            proj = "src\Qlogger.Viewer.Web\Qlogger.Viewer.Web.csproj"
            appname = "/svc/log"
            deployprop="DeployLogViewer"
            profiles = @{
                dev = @{ 
                    test = "http://phobos:10080/svc/log"
                }
                dev_staging = @{ 
                    test = "http://phobos:10080/svc/log-staging"
                }
            }
        }
    }
}
```