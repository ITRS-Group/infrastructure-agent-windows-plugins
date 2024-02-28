<#

.SYNOPSIS
This is a Powershell script to check status of Windows Services

.DESCRIPTION
This script will check the status of the Windows Services. When you do not specify services using -ServiceName parameter script will check all Services. You can exclude Services (-ExcludeService), Service State (-ExcludeService-State), Service Status (-ExcludeStatus) and ServiceStartMode (ExcludeStartMode).

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
Copyright (C) 2003-2024 ITRS Group Ltd. All rights reserved.

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
$StatusList = [ordered]@{"OK" = "0"; "Error" = "0"; "Degraded" = "0"; "Unknown" = "0"; "Pred_Fail" = "0"; "Starting" = "0"; "Stopping" = "0"; "Service" = "0"; "Stressed" = "0"; "NonRecover" = "0"; "No_Contact" = "0"; "Lost_Comm" = "0"}

if (!$StartMode)
{
    $StartMode = @("Boot", "System", "Auto", "Manual", "Disabled", "Unknown")
}

if ($help)
{
    Get-Help $MyInvocation.MyCommand.Definition 
    exit 3
}

if ($ExcludeService -ne $null){
    $excludeList = $ExcludeService.split(",")
}



if (!$ServiceName)
{
    Get-WmiObject win32_Service | Select-Object Name, State, Status, StartMode | Sort-Object -Property Name | ForEach-Object {
        
        $wildcardMatched = $false
        foreach ($wildcardservice in $excludeList) {
            if($wildcardservice -match "\*") {
                if($_.Name -like $wildcardservice){
                    $wildcardMatched = $true
                }
            }
        }

        #Write-Output "Service: $($_.name) wilcardstatus: $wilcard"
        
        if (!$wildcardMatched) {
            if ($ExcludeService -notcontains $_.Name -and $ExcludeState -notcontains $_.State -and $StartMode -contains $_.StartMode -and $ExcludeStatus -notcontains $_.Status)
            {
                if ($_.State -ne "Running")
                {
                    if ($NagiosDescription)
                    {
                        $NagiosDescription = $NagiosDescription + ", "
                    }
                    $NagiosDescription = $NagiosDescription + $_.Name + " (" + $_.State + ", Status: " + $_.Status + ")"
                    $NagiosStatus = "2"
                }
                elseif ($_.State -eq "Running" -and $_.Status -ne "OK")
                {
                    if ($NagiosDescription)
                    {
                        $NagiosDescription = $NagiosDescription + ", "
                    }
                    $NagiosDescription = $NagiosDescription + $_.Name + " (" + $_.State + ", Status: " + $_.Status + ")"
                    if ($NagiosStatus -ne "2")
                    {
                    $NagiosStatus = "1"
                    }
                }
                $SStatus = $_.Status -replace '\s','_'
                $Old = $StatusList[$SStatus]
                $StatusList[$SStatus] = [int]$Old + 1;
            }
        }
    }
}
else
{
    Get-WmiObject win32_Service| Select-Object Name, State, Status, StartMode | ForEach-Object {

        $matchedService=$false
        foreach ($singleService in $ServiceName){
            if ($_.Name -like $singleService){
                $matchedService=$true
            }
        }

        $matchedExcludeService=$false
        foreach ($excludeService in $excludeList){
            if ($_.Name -like $excludeService){
                $matchedExcludeService=$true
            }
        }



        if ($matchedService -and !$matchedExcludeService -and $ExcludeService -notcontains $_.Name -and $ExcludeState -notcontains $_.State -and $StartMode -contains $_.StartMode -and $ExcludeStatus -notcontains $_.Status)
        {
            if ($_.State -ne "Running")
            {
                if ($NagiosDescription)
                {
                    $NagiosDescription = $NagiosDescription + ", "
                }
                $NagiosDescription = $NagiosDescription + $_.Name + " (" + $_.State + ", Status: " + $_.Status + ")"
                $NagiosStatus = "2"
            }
            elseif ($_.State -eq "Running" -and $_.Status -ne "OK")
            {
                if ($NagiosDescription)
                {
                    $NagiosDescription = $NagiosDescription + ", "
                }
                $NagiosDescription = $NagiosDescription + $_.Name + " (" + $_.State + ", Status: " + $_.Status + ")"
                if ($NagiosStatus -ne "2")
                {
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

if ($NagiosStatus -eq "2")
{
    Write-Host "CRITICAL:" $NagiosDescription " | " $NagiosPerfData
}
elseif ($NagiosStatus -eq "1")
{
    Write-Host "WARNING:" $NagiosDescription " | "$NagiosPerfData
}
else
{
    Write-Host "OK: All Services running | " $NagiosPerfData
}

exit $NagiosStatus
