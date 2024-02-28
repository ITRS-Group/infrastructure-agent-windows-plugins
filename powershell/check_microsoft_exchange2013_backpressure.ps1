# AUTHORS:
#       Copyright (C) 2003-2024 ITRS Group Ltd. All rights reserved
#
#       This file is part of Opsview
#
# This plugin monitors your Exchange server

param (
  [alias("m")]
  [string]$mode,
  [alias("w")]
  [int]$warning,
  [alias("c")]
  [int]$critical,
  [alias("p")]
  [string]$password,
  [alias("l")]
  [string]$location,
  [alias("u")]
  [string]$username,
  [alias("s")]
  [string]$server,
  [alias("f")]
  [string]$fqdn,
  [alias("h")]
  [switch]$help,
  [Parameter(ValueFromRemainingArguments = $true)] $remainingArguments
)
class Plugin {

    [string] $Name
    [string] $Version
    [string] $Preamble
    [string] $Description

    Plugin ([String] $Name, [string] $Version, [string] $Preamble, [string] $Description) {
        $Global:metric = @()
        $Global:miniumExitCode = 0
        $Global:incre = -1

        $this.Name = $Name
        $this.Version = $Version
        $this.Preamble = $Preamble
        $this.Description = $Description
    }

    [void] helpText([Plugin] $check) {
        Write-Host "$($check.Name) $($check.Version) `n"
        Write-Host "$($check.Preamble) `n"

        Write-Host "Usage:
        $($check.Name) [OPTIONS] `n"
        Write-Host "Default Options:
         -h	Show this help message `n"
        Write-Host "$($check.Description) `n"

        exit 3
    }

    [void]addMetric([string] $name, [float]$value,[string] $UOM, $warning,$critical){
        $Global:incre ++
        if ($warning -eq $null -and $critical -eq $null){
            $exitCode = 0
        }else{
            $exitCode = $this.evaluate($value,$warning,$critical)
        }

        [string] $boundaryMessage = ""
        if ($exitCode -eq 1){
            $boundaryMessage = "(outside $warning)"
        }elseif ($exitCode -eq 2) {
            $boundaryMessage = "(outside $critical)"
        }
        if ($Global:incre -eq 0){
            $Global:metric = New-Object 'object[,]' 10,9
        }

        $Global:metric[$Global:incre,0] = $name
        $Global:metric[$Global:incre,1] = $value
        $Global:metric[$Global:incre,2] = $UOM
        $Global:metric[$Global:incre,3] = $warning
        $Global:metric[$Global:incre,4] = $critical
        $Global:metric[$Global:incre,6] = $exitCode
        $Global:metric[$Global:incre,7] = $boundaryMessage

    }
    [void]addMetric([string] $name,[float] $value){
        $this.addMetric($name,$value,$null,$null,$null)
    }
    [void]addMetric([string] $name,[float] $value,[string] $UOM){
        $this.addMetric($name,$value,$UOM,$null,$null)
    }

    [void] addMessage([string]$message){
        $Global:metric[$Global:incre,8] = $message
    }

    [float] getCounter([string] $metricLocation) {
	$proc = ""
        try{
            $proc = Get-Counter $metricLocation -ErrorAction Stop
        }catch{
            $this.ExitUnknown("Counter not found check path location")
        }
	$returnMetric = [math]::Round(($proc.readings -split ":")[-1],2)
	return $returnMetric
    }

    [void]Final(){
        $worstCode = $this.overallStatus()
        [String]$Output = $this.getStatus($worstCode)+ ": "

        for ($i=0; $i -le $Global:incre; $i++){
            if ($Global:metric[$i,8] -eq $null){
                $Output = $Output + ($Global:metric[$i,0]+" is " + $Global:metric[$i,1] + $Global:metric[$i,2] + $Global:metric[$i,7])
            }else{
                $Output = $Output + $Global:metric[$i,8]
            }
            if ($i -le $Global:incre-1){
                $Output = $Output + ", "
            }
        }
        $Output = $Output + " | "
        for ($i=0; $i -le $Global:incre; $i++){
            $Output = $Output + ($Global:metric[$i,0] + "="+$Global:metric[$i,1]+$Global:metric[$i,2]+";"+$Global:metric[$i,3]+";"+$Global:metric[$i,4]+";")
            if ($i -le $Global:incre-1){
                $Output = $Output + ", "
            }
        }
        $Global:incre = -1
        Write-Host $Output
        exit $worstCode
    }

    [int]overallStatus(){
        [int]$worstStatus= $Global:miniumExitCode
        for ($i=0; $i -le $Global:incre; $i++){
            if ($Global:metric[$i,6] -gt $worstStatus){
                $worstStatus = $Global:metric[$i,6]
            }
        }
        return $worstStatus
    }

    [string]evaluate([int] $value, $warning, $critical) {
        $returnCode=0
        try{
	        if (($warning -ne 0) -And ($value -gt $warning)) {
		        $returnCode=1
	        }
        }catch{
          $this.ExitUnknown("Invalid warning argument. Please check that the warning arugment is a valid int")
        }
        try{
	        if (($critical -ne 0) -And ($value -gt $critical)) {
		        $returnCode=2
	        }
        }catch{
          $this.ExitUnknown("Invalid critical argument. Please check that the critical arugment is a valid int")
        }
	      return $returnCode
    }

    [int]setExitCode ([string] $returnCode){

        if($returnCode -eq "OK") {
            $exitCode = 0
        } elseif($returnCode -eq "WARNING") {
            $exitCode = 1
        } elseif($returnCode -eq "CRITICAL") {
            $exitCode = 2
        } else {
            $exitCode = 3
        }
        return $exitCode
    }

    [string]getStatus([int]$exitCode) {
        $Status = ""
        if ($exitCode -eq 0){
            $Status = "OK"
        }elseif ($exitCode -eq 1){
            $Status = "WARNING"
        }elseif ($exitCode -eq 2){
            $Status = "CRITICAL"
        }elseif ($exitCode -eq 3){
            $Status = "UNKOWN"
        }else{
            $this.ExitUnknown("Something has gone wrong, check getStatus method")
        }
        return $Status
    }

    [void] ExitOK([string] $errorMessage) {
        Write-Host "OK: $errorMessage"
        exit 0
    }

    [void] ExitUnknown([string] $errorMessage) {
        Write-Host "UNKNOWN: $errorMessage"
        exit 3
    }

    [void] ExitCritical([string] $errorMessage) {
        Write-Host "CRITICAL: $errorMessage"
        exit 2
    }

    [void] ExitWarning([string] $errorMessage) {
        Write-Host "WARNING: $errorMessage"
        exit 1
    }

    [void]Warning() {
        $Global:miniumExitCode = 1
    }

    [void]Critical() {
        $Global:miniumExitCode = 2
    }

}


$check = [Plugin]::new("check_microsoft_exchange2013_backpressure", "", "Copyright (C) 2003-2024 ITRS Group Ltd. All rights reserved. This plugin monitors the pressure stats for your Microsoft Exchange 2013 Server.", "Plugin Options:`n
    arguments:`n
      -h show this help message and exit,
      -m MODE,`n
            Supported modes:
            DatabaseMonitor: Hard drive utilisation of the drive that stores message queue database.`n
            DatabaseLoggingFolderMonitor: Hard drive utilisation of the drive that stores the message queue database transaction logs.`n
            DiskSpaceMonitor: Hard drive utilisation of the drive that stores temp files. `n
            VersionBucketsMonitor: The number of uncommitted message queue database transactions that exist in memory.`n
            MemoryPrivateBytesMonitor`: Percentage of the total memory that's used by the EdgeTransport.exe process.`n
            MemoryTotalBytesMonitor`: Memory utilization by all processes.`n
            SubmissionQueueMonitor`: Number of messages in the Submission queue.`n
      -w WARNING,
            Value set for warning level`n
      -c CRITICAL,
            Value set for critical level`n
      -u USERNAME
            Username to Exchange server`n
      -p PASSWORD
            Password to Exchange server`n
      -s SERVER
            Name of your Exchange server`n
      -f FQDN
            Fully qualified domain name for you Exchange server")

function makeConnection {
  $secstr = New-Object -TypeName System.Security.SecureString
  $password.ToCharArray() | ForEach-Object { $secstr.AppendChar($_) }
  try {
    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username,$secstr
  } catch {
    $check.ExitUnknown('Error: Incorrect login credientials. Please check -u or -p flag.')
  }
  try {
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://$fqdn/PowerShell/ -Authentication Kerberos -Credential $cred -ErrorAction Stop
  } catch {
    $check.ExitUnknown('Error: Could not connect to MSExchange please check credientials')
  }
  Import-PSSession $Session -CommandName Get-ExchangeDiagnosticInfo,Get-ExchangeServer -DisableNameChecking | Out-Null
}

function checkConnection {
  $Session = Get-PSSession
  for ($i = 0; $i -le $Session.Length; $i++) {
    if ($Session -eq $null) {
      makeConnection
    }
    elseif ($Session[$i].ComputerName -eq $fqdn -and $Session[$i].State -ne "Opened") {
      Remove-PSSession -Session (Get-PSSession)
      makeConnection
    }
  }
}

function getPressureStatus ([string]$name) {
  try {
    [xml]$diag = Get-ExchangeDiagnosticInfo -Server $server -Process EdgeTransport -Component ResourceManager -Argument basic -ErrorAction Stop
    [array[]]$table = $diag.Diagnostics.Components.ResourceManager.ResourceMonitors.ResourceMonitor
  } catch {
    $check.ExitUnknown('Error: Could not find server. Please check -s flag.')
  }
  if ($table -eq $null) {
    $check.ExitUnknown("Error: Could not locate back pressure metrics")
  }
  for ($i = 0; $i -le $table.Length; $i++) {
    if ($table[$i].type -eq $name) {
      $pressureState = $table[$i].resourceuses
      $returnCurrentPressure = $table[$i].currentPressure
      $returnLowPressureLimit = $table[$i].lowPressureLimit
      $returnMediumPressureLimit = $table[$i].MediumPressureLimit
      $returnHighPressureLimit = $table[$i].HighPressureLimit
    }
  }
  [int]$returnCurrentPressure
  [int]$returnLowPressureLimit
  [int]$returnMediumPressureLimit
  [int]$returnHighPressureLimit
  [string]$pressureState
}

function evaluatePressure ([string]$pressure) {
  if ($pressure -eq "Medium") {
    $check.Warning()
  }
  if ($pressure -eq "High") {
    $check.Critical()
  }
  $returnCode
}

if ($help) {
  $check.helpText($check)
  exit 3
}

if ($remainingArguments) {
  $check.ExitUnknown("Unknown arguments: $remaingArguments")
}

checkConnection

switch ($mode)
{
  'DatabaseMonitor' {
    $CurrentPressure,$LowPressureLimit,$MediumPressureLimit,$HighPressureLimit,$pressureState = getPressureStatus ("DatabaseMonitor")
    evaluatePressure ($pressureState)
    $check.addMetric("Queue_Database_and_Disk_Space_Pressure",$CurrentPressure,"",$warning,$critical)
    $check.addMessage("Queue Database and Disk Space Pressure is $pressureState [Current = $CurrentPressure, Normal = $LowPressureLimit, Medium = $MediumPressureLimit, High = $HighPressureLimit]")
  }
  'DatabaseLoggingFolderMonitor' {
    $CurrentPressure,$LowPressureLimit,$MediumPressureLimit,$HighPressureLimit,$pressureState = getPressureStatus ("DatabaseLoggingFolderMonitor")
    evaluatePressure ($pressureState)
    $check.addMetric("Queue_Database_Logging_Disk_Space_Pressure",$CurrentPressure,"",$warning,$critical)
    $check.addMessage("Queue Database Logging Disk Space Pressure is $pressureState [Current = $CurrentPressure, Normal = $LowPressureLimit, Medium = $MediumPressureLimit, High = $HighPressureLimit]")
  }
  'DiskSpaceMonitor' {
    $CurrentPressure,$LowPressureLimit,$MediumPressureLimit,$HighPressureLimit,$pressureState = getPressureStatus ("DiskSpaceMonitor")
    evaluatePressure ($pressureState)
    $check.addMetric("Temporary_Storage_Disk_Space_Pressure",$CurrentPressure,"",$warning,$critical)
    $check.addMessage("Temporary Storage Disk Space Pressure is $pressureState [Current = $CurrentPressure, Normal = $LowPressureLimit, Medium = $MediumPressureLimit, High = $HighPressureLimit]")
  }
  'VersionBucketsMonitor' {
    $CurrentPressure,$LowPressureLimit,$MediumPressureLimit,$HighPressureLimit,$pressureState = getPressureStatus ("VersionBucketsMonitor")
    evaluatePressure ($pressureState)
    $check.addMetric("Version_Buckets_Pressure",$CurrentPressure,"",$warning,$critical)
    $check.addMessage("Version Buckets Pressure is $pressureState [Current = $CurrentPressure, Normal = $LowPressureLimit, Medium = $MediumPressureLimit, High = $HighPressureLimit]")
  }
  'MemoryPrivateBytesMonitor' {
    $CurrentPressure,$LowPressureLimit,$MediumPressureLimit,$HighPressureLimit,$pressureState = getPressureStatus ("MemoryPrivateBytesMonitor")
    evaluatePressure ($pressureState)
    $check.addMetric("Memory_Private_Bytes_Pressure",$CurrentPressure,"",$warning,$critical)
    $check.addMessage("Memory Private Bytes Pressure is $pressureState [Current = $CurrentPressure, Normal = $LowPressureLimit, Medium = $MediumPressureLimit, High = $HighPressureLimit]")
  }
  'MemoryTotalBytesMonitor' {
    $CurrentPressure,$LowPressureLimit,$MediumPressureLimit,$HighPressureLimit,$pressureState = getPressureStatus ("MemoryTotalBytesMonitor")
    evaluatePressure ($pressureState)
    $check.addMetric("Memory_Total_Bytes_Pressure",$CurrentPressure,"",$warning,$critical)
    $check.addMessage("Memory Total Bytes Pressure is $pressureState [Current = $CurrentPressure, Normal = $LowPressureLimit, Medium = $MediumPressureLimit, High = $HighPressureLimit]")
  }
  'SubmissionQueueMonitor' {
    $CurrentPressure,$LowPressureLimit,$MediumPressureLimit,$HighPressureLimit,$pressureState = getPressureStatus ("SubmissionQueueMonitor")
    evaluatePressure ($pressureState)
    $check.addMetric("Submission_Queue_Pressure",$CurrentPressure,"",$warning,$critical)
    $check.addMessage("Submission Queue Pressure is $pressureState [Current = $CurrentPressure, Normal = $LowPressureLimit, Medium = $MediumPressureLimit, High = $HighPressureLimit]")
  }
  default {
    $check.ExitUnknown("Mode not found")
  }
}
$check.final()
