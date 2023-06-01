<#

.SYNOPSIS
This is a Powershell script to check state of Windows ClusterGroup Status
You need the FailOverCluster feature installed on your Windows server for this check to work

.DESCRIPTION
This script will check the state of the Windows ClusterGroup Status.

.EXAMPLE
./check_clustergroup.ps1
Check All Cluster Groups

.EXAMPLE
./check_clustergroup.ps1 -ClusterGroup CLGRP1,CLGRP2,CLGRP3
Check selected Cluster Groups

.NOTES
Copyright (C) 2023 Opsview Limited. All rights reserved.

.LINK
http://www.opsview.com

#>


param(
    [alias("h")] [switch]$help,
    [string[]]$ClusterGroup
)

$NagiosStatus = "0"

if ($help)
{
    Get-Help $MyInvocation.MyCommand.Definition -detailed
    exit 3
}

import-module failoverclusters

if (!$ClusterGroup)
{
    Get-ClusterGroup | Select-Object Name,OwnerNode,State | Sort-Object -Property Name | ForEach-Object {
        if ($_.State -ne "Online") 
        {
            if ($NagiosDescriptionCritical)
            {
                $NagiosDescriptionCritical = $NagiosDescriptionCritical + ", "
            }
            $NagiosDescriptionCritical = $NagiosDescriptionCritical + $_.Name + " (Status: " + $_.State + ")"
            $NagiosStatus = "2"
        }
        else 
        {
            if ($NagiosDescription)
            {
                $NagiosDescription = $NagiosDescription + ", "
            }
            $NagiosDescription = $NagiosDescription + $_.Name + " (Status: " + $_.State + ")"
        }
    }
}
else
{
    Get-ClusterGroup | Select-Object Name,OwnerNode,State | Sort-Object -Property Name | ForEach-Object {
        if ($ClusterGroup -contains $_.Name) 
        {
            if ($_.State -ne "Online")
            {
                if ($NagiosDescriptionCritical)
                {
                    $NagiosDescriptionCritical = $NagiosDescriptionCritical + ", "
                }
                $NagiosDescriptionCritical = $NagiosDescriptionCritical + $_.Name + " (Status: " + $_.State + ")"
                $NagiosStatus = "2"
            }
            else
            {
                if ($NagiosDescription)
                {
                    $NagiosDescription = $NagiosDescription + ", "
                }
                $NagiosDescription = $NagiosDescription + $_.Name + " (Status: " + $_.State + ")"
            }
        }
    }
}

if ($NagiosStatus -eq "2")
{
    Write-Host "CRITICAL:" $NagiosDescriptionCritical
}
else
{
    Write-Host "OK: All ClusterGroups are online -" $NagiosDescription
}

exit $NagiosStatus
