<#

.SYNOPSIS
This is a Powershell script to check usage of Windows MountPoint.

.DESCRIPTION
This script will check the usage of Windows MountPoint.

.EXAMPLE
./check_mountpoint.ps1 -MountPoint all -Warning 10 -Critical 5
Check All Cluster Groups

.EXAMPLE
./check_mountpoint.ps1 -MountPoint MNTPOINT1 -Warning 10 -Critical 5
Check selected Cluster Groups

.NOTES
Copyright (C) 2003-2026 ITRS Group Ltd. All rights reserved.

.LINK
http://www.opsview.com

#>

param(
[string]$Warning,
[string]$Critical,
[string]$MountPoint
)


$server = $env:computername
$NagiosStatus = "0"
$NagiosDescription = ""
$NagiosPerfData = ""

if (!$Critical -Or !$Warning)
{
        Write-Host "Usage:"
        Write-Host "    check_mountpoint.ps1 -Warning <GB> -Critical <GB> -MountPoint <MountPointLabel>"
        Write-Host "    check_mountpoint.ps1 -Warning 15 -Critical 10 -MountPoint all"
        Write-Host "    check_mountpoint.ps1 -Warning 15 -Critical 10 -MountPoint DATA"
        exit 3
}

if ($Critical -lt $Warning)
{
        Write-Host "Warning [$Warning] can not be more than Critical [$Critical]"
        exit 3
}

if ($MountPoint -eq "all" -Or $MountPoint -eq $null)
{
        $volumes = Get-WmiObject -computer $server win32_volume | Where-object {$_.DriveLetter -eq $null -and $_.Label -notlike "*System Reserved*"} | ForEach-Object {
                $Label = $_.Label
                #Calculate totals in GB, round to 2 decimal places
                $TotalGB = [math]::round(($_.Capacity/ 1073741824),2)
                $FreeGB = [math]::round(($_.FreeSpace / 1073741824),2)
                #Calculate free space as percentage,
                $FreePerc = [math]::round(((($_.FreeSpace / 1073741824)/($_.Capacity / 1073741824)) * 100),0)

                #Check to see if volume free space is less than $Critical
                if ($FreeGB -lt $Critical)
                {
                        #Format for Nagios
                        if ($NagiosDescription -ne "")
                        {
                                $NagiosDescription = $NagiosDescription + ", "
                        }
                        #Add details of failure
                        $NagiosDescription = $NagiosDescription + "Volume: " + $Label + " Total Size:" + $TotalGB + "GB, Free Space:" + $FreeGB + "GB, Free:" + $FreePerc + "%"
                        #Set the status to failed
                        $NagiosStatus = "2"
                }
                #Else check to make sure it's not less than $Warning
                elseif ($FreeGB -lt $Warning)
                {
                        #Format for Nagios
                        if ($NagiosDescription -ne "")
                        {
                                $NagiosDescription = $NagiosDescription + ", "
                        }
                        #Add details of warning
                        $NagiosDescription = $NagiosDescription + "Volume: " + $Label + " Total Size:" + $TotalGB + "GB, Free Space:" + $FreeGB + "GB, Free:" + $FreePerc + "%"
                        #Set the status to warning
                        if ($NagiosStatus -ne "2")
                        {
                                $NagiosStatus = "1"
                        }
                }
                $WarningPercent = [math]::round(((100 * $Warning) / $TotalGB),2)
                $CriticalPercent = [math]::round(((100 * $Critical) / $TotalGB),2)
                $NagiosPerfDataPercent = $NagiosPerfDataPercent + " " + "'" + $Label + "_%'" + "=" + $FreePerc + "%;" + $WarningPercent + ";" + $CriticalPercent + ";"
                $NagiosPerfDataGB = $NagiosPerfDataGB + " " + "'" + $Label + "_GB'" + "=" + $FreeGB + "GB;" + $Warning + ";" + $Critical + ";"
        }
}
else
{
        $volumes = Get-WmiObject -computer $server win32_volume | Where-object {$_.DriveLetter -eq $null -and $_.Label -like "*$MountPoint*"} | ForEach-Object {
                $Label = $_.Label
                #Calculate totals in GB, round to 2 decimal places
                $TotalGB = [math]::round(($_.Capacity/ 1073741824),2)
                $FreeGB = [math]::round(($_.FreeSpace / 1073741824),2)
                #Calculate free space as percentage,
                $FreePerc = [math]::round(((($_.FreeSpace / 1073741824)/($_.Capacity / 1073741824)) * 100),0)

                #Check to see if volume free space is less than $Critical
                if ($FreeGB -lt $Critical)
                {
                        #Format for Nagios
                        if ($NagiosDescription -ne "")
                        {
                                $NagiosDescription = $NagiosDescription + ", "
                        }
                        #Add details of failure
                        $NagiosDescription = $NagiosDescription + "Volume: " + $Label + " Total Size:" + $TotalGB + "GB, Free Space:" + $FreeGB + "GB, Free:" + $FreePerc + "%"
                        #Set the status to failed
                        $NagiosStatus = "2"
                }
                #Else check to make sure it's not less than $Warning
                elseif ($FreeGB -lt $Warning)
                {
                        #Format for Nagios
                        if ($NagiosDescription -ne "")
                        {
                                $NagiosDescription = $NagiosDescription + ", "
                        }
                        #Add details of warning
                        $NagiosDescription = $NagiosDescription + "Volume: " + $Label + " Total Size:" + $TotalGB + "GB, Free Space:" + $FreeGB + "GB, Free:" + $FreePerc + "%"
                        #Set the status to warning
                        if ($NagiosStatus -ne "2")
                        {
                                $NagiosStatus = "1"
                        }
                }
                $WarningPercent = [math]::round(((100 * $Warning) / $TotalGB),2)
                $CriticalPercent = [math]::round(((100 * $Critical) / $TotalGB),2)
                $NagiosPerfDataPercent = $NagiosPerfDataPercent + " " + "'" + $Label + "_%'" + "=" + $FreePerc + "%;" + $WarningPercent + ";" + $CriticalPercent + ";"
                $NagiosPerfDataGB = $NagiosPerfDataGB + " " + "'" + $Label + "_GB'" + "=" + $FreeGB + "GB;" + $Warning + ";" + $Critical + ";"
        }
}



# Output, final text message for Nagios
if ($NagiosStatus -eq "2")
{
        Write-Host "CRITICAL: " $NagiosDescription " | " $NagiosPerfDataPercent $NagiosPerfDataGB
}
elseif ($NagiosStatus -eq "1")
{
        Write-Host "WARNING: " $NagiosDescription " | " $NagiosPerfDataPercent $NagiosPerfDataGB
}
else
{
        Write-Host "OK: All volumes have adequate free space | " $NagiosPerfDataPercent $NagiosPerfDataGB
}

exit $NagiosStatus