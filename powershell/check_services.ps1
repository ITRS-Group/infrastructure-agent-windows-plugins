<#

.SYNOPSIS
This is a Powershell script to check status of Windows Services

.DESCRIPTION
This script will check the status of the Windows Services. When you do not specify Services or Service Start Modes using the -ServiceName parameter and/or the -StartMode parameter, the script will check all Services. You can exclude Services (-ExcludeService), Service State (-ExcludeState) and Service Status (-ExcludeStatus).

.EXAMPLE
./check_service.ps1
Check All Services

.EXAMPLE
./check_service.ps1 -ExcludeState Stopped
Check All Services and Exclude services in state Stopped

.EXAMPLE
./check_service.ps1 -ServiceName MSExchangeADTopology,MSExchangeAntispamUpdate,MSExchangeCompliance -ExcludeStatus Degraded
Check Some Services and exclude those in the state Degraded

.NOTES
Copyright (C) 2003-2026 ITRS Group Ltd. All rights reserved.

.LINK
http://www.opsview.com

#>

param(
[alias("h")] [switch]$help,
[string[]]$ServiceName,
[string[]]$ExcludeService,
[string[]]$ExcludeState,
[string[]]$ExcludeStatus,
[string[]]$StartMode
)

$NagiosStatus = "0"
$StatusList = [ordered]@{
    "OK" = "0";
    "Error" = "0";
    "Degraded" = "0";
    "Unknown" = "0";
    "Pred_Fail" = "0";
    "Starting" = "0";
    "Stopping" = "0";
    "Service" = "0";
    "Stressed" = "0";
    "NonRecover" = "0";
    "No_Contact" = "0";
    "Lost_Comm" = "0"
}

if ($help) {
    Get-Help $MyInvocation.MyCommand.Definition
    exit 3
}

if ($ServiceName -ne $null) {
    $serviceNameList = $ServiceName.split(",")
} else {
    $serviceNameList = ""
}

if ($ExcludeService -ne $null) {
    $excludeServiceList = $ExcludeService.split(",")
} else {
    $excludeServiceList = ""
}

if ($ExcludeState -ne $null) {
    $excludeStateList = $ExcludeState.split(",")
} else {
    $excludeStateList = ""
}

if ($ExcludeStatus -ne $null) {
    $excludeStatusList = $ExcludeStatus.split(",")
} else {
    $excludeStatusList = ""
}

if (!$StartMode) {
    $startModeList = @("Boot", "System", "Auto", "Manual", "Disabled", "Unknown")
} else {
    $startModeList = $StartMode.split(",")
}

if (!$ServiceName) {
    Get-WmiObject win32_Service | Select-Object Name, State, Status, StartMode | Sort-Object -Property Name | ForEach-Object {

        $wildcardMatched = $false
        foreach ($wildcardservice in $excludeServiceList) {
            if($wildcardservice -match "\*") {
                if ($_.Name -like $wildcardservice) {
                    $wildcardMatched = $true
                }
            }
        }

        if (!$wildcardMatched) {
            if (
                $excludeServiceList -notcontains $_.Name -and
                $excludeStateList -notcontains $_.State -and
                $startModeList -contains $_.StartMode -and
                $excludeStatusList -notcontains $_.Status
            ) {
                if ($_.State -ne "Running") {
                    if ($NagiosDescription) {
                        $NagiosDescription = $NagiosDescription + ", "
                    }
                    $NagiosDescription = $NagiosDescription + $_.Name + " (" + $_.State + ", Status: " + $_.Status + ")"
                    $NagiosStatus = "2"
                } elseif ($_.State -eq "Running" -and $_.Status -ne "OK") {
                    if ($NagiosDescription) {
                        $NagiosDescription = $NagiosDescription + ", "
                    }
                    $NagiosDescription = $NagiosDescription + $_.Name + " (" + $_.State + ", Status: " + $_.Status + ")"
                    if ($NagiosStatus -ne "2") {
                        $NagiosStatus = "1"
                    }
                }
                $SStatus = $_.Status -replace '\s','_'
                $Old = $StatusList[$SStatus]
                $StatusList[$SStatus] = [int]$Old + 1;
            }
        }
    }
} else {
    Get-WmiObject win32_Service | Select-Object Name, State, Status, StartMode | ForEach-Object {

        $matchedService = $false
        foreach ($singleService in $serviceNameList) {
            if ($_.Name -like $singleService) {
                $matchedService = $true
            }
        }

        $matchedExcludeService = $false
        foreach ($excludeService in $excludeServiceList) {
            if ($_.Name -like $excludeService) {
                $matchedExcludeService=$true
            }
        }

        if (
            $matchedService -and
            !$matchedExcludeService -and
            $excludeServiceList -notcontains $_.Name -and
            $excludeStateList -notcontains $_.State -and
            $startModeList -contains $_.StartMode -and
            $excludeStatusList -notcontains $_.Status
        ) {
            if ($_.State -ne "Running") {
                if ($NagiosDescription) {
                    $NagiosDescription = $NagiosDescription + ", "
                }
                $NagiosDescription = $NagiosDescription + $_.Name + " (" + $_.State + ", Status: " + $_.Status + ")"
                $NagiosStatus = "2"
            } elseif ($_.State -eq "Running" -and $_.Status -ne "OK") {
                if ($NagiosDescription) {
                    $NagiosDescription = $NagiosDescription + ", "
                }
                $NagiosDescription = $NagiosDescription + $_.Name + " (" + $_.State + ", Status: " + $_.Status + ")"
                if ($NagiosStatus -ne "2") {
                    $NagiosStatus = "1"
                }
            }
            $SStatus = $_.Status -replace '\s','_'
            $Old = $StatusList[$SStatus]
            $StatusList[$SStatus] = [int]$Old + 1;
        }
    }
}

foreach ($ServiceState in $StatusList.Keys) {
    $NagiosPerfData = $NagiosPerfData + "${ServiceState}=$($StatusList.Item($ServiceState)) "
}

if ($NagiosStatus -eq "2") {
    Write-Host "CRITICAL:" $NagiosDescription " | " $NagiosPerfData
} elseif ($NagiosStatus -eq "1") {
    Write-Host "WARNING:" $NagiosDescription " | "$NagiosPerfData
} else {
    Write-Host "OK: All Services running | " $NagiosPerfData
}

exit $NagiosStatus
