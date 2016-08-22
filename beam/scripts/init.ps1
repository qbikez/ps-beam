pushd

cd "$PSScriptRoot\.."

try {
    if (!(test-path ".scripts")) { mkdir ".scripts" }
    if (!(test-path ".scripts\.bootstrapped")) {
        #init build tools
	    wget http://bit.ly/qbootstrap1 -UseBasicParsing -OutFile ".scripts/bootstrap.ps1" 
        get-content ".scripts/bootstrap.ps1" | out-string | iex
     
        #Install-Module pathutils
        #refresh-env
        get-date | out-string | Out-File ".scripts\.bootstrapped"
    }
} finally {
	popd
}


install-module require
req crayon