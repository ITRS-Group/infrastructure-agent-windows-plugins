# nagios compatible plugin; checks file for existence and not to be older then the thresholds 
# usage: ./check_file -filename THEFILE -warn warningLevel -crit criticalLevel
# Levels given in minutes
param(
    [Parameter(Mandatory=$False,Position=1)][string]$filename,
    [string]$warn = 5,
    [string]$crit = 8,
    [alias("h")] [switch]$help
)

Import-Module -Name 'C:\Program Files\Infrastructure Agent\plugins\lib\powershell\PlugNpshell'

[Check] $Check
[Metric] $Metric

function CreateCheckObj() {
    $script:check = [Check]::New("checkfileage", "", 
        "Checks file for existence and not to be older than the thresholds",
        "Plugin Options:`n
        -filename <filename>`n
        -warn warning level in minutes (default 5 mins)`n
        -crit critical level in minutes (default 8 mins)`n"
    )
}

function Main {
    if ($help) {
        CreateCheckObj
        $script:check.HelpText()
    }
    else {
        if (!(Test-Path $filename)) {
            echo "CRITICAL: File $filename does not exist"
            $host.SetShouldExit(2)
            exit
        }
        $lastWrite = (Get-Item $filename).LastWriteTime
        $ctimespan = New-Timespan -Minutes $crit
        $wtimespan = New-Timespan -Minutes $warn
        if (((Get-Date) - $lastWrite) -gt $ctimespan) {
            echo "CRITICAL: File $filename older than $crit minutes"
            $host.SetShouldExit(2)
            exit
        }
        if (((Get-Date) - $lastWrite) -gt $wtimespan) {
            echo "WARNING: File $filename older than $warn minutes"
            $host.SetShouldExit(1)
            exit
        }
      
        echo "OK: File $filename not older than $warn minutes"
        $host.SetShouldExit(0)
        exit
        $script:check.final()
    }
}

try {
    Main
} catch [ParamError] {
    Write-Output $_.Exception.ErrorMessage
    exit(3)
} catch {
    Write-Output  $_.Exception.Message
    exit(3)
}
