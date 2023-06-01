# AUTHORS:
#       Copyright (C) 2003-2023 Opsview Limited.All rights reserved
#
#       This file is part of Opsview
#
# This plugin monitors the stats for your Windows system.

param(
    [alias("m")] [string]$mode,
    [alias("w")] $warning ,
    [alias("c")] $critical,
    [alias("h")] [switch]$help,
    [Parameter(ValueFromRemainingArguments=$true)] $remainingArguments, # Used to handle invalid parameters
    [alias("d")] [string]$drive,
    [alias("l")] [string]$location,
    [alias("f")] [string]$file,
    [alias("p")] [string]$process
)

class Plugin {

  [string]$Name
  [string]$Version
  [string]$Preamble
  [string]$Description

  Plugin ([string]$Name,[string]$Version,[string]$Preamble,[string]$Description) {
    $Global:metric = @()
    $Global:arrayMessages = @()
    $Global:miniumExitCode = 0
    $Global:incre = -1

    $this.Name = $Name
    $this.Version = $Version
    $this.Preamble = $Preamble
    $this.Description = $Description
  }

  [void] helpText ([plugin]$check) {
    Write-Host "$($check.Name) $($check.Version) `n"
    Write-Host "$($check.Preamble) `n"

    Write-Host "Usage:
        $($check.Name) [OPTIONS] `n"
    Write-Host "Default Options:
         -h	Show this help message `n"
    Write-Host "$($check.Description) `n"

    exit 3
  }

  [void] addMetric ([string]$name,[float]$value,[string]$UOM,$warning,$critical) {
    $Global:incre++
    if ($warning -eq $null -and $critical -eq $null) {
      $exitCode = 0
    } else {
      $exitCode = $this.evaluate($value,$warning,$critical)
    }

    [string]$boundaryMessage = ""
    if ($exitCode -eq 1) {
      $boundaryMessage = "(outside $warning)"
    } elseif ($exitCode -eq 2) {
      $boundaryMessage = "(outside $critical)"
    }
    if ($Global:incre -eq 0) {
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
  [void] addMetric ([string]$name,[float]$value) {
    $this.addMetric($name,$value,$null,$null,$null)
  }
  [void] addMetric ([string]$name,[float]$value,[string]$UOM) {
    $this.addMetric($name,$value,$UOM,$null,$null)
  }

  [void] addStatus ([string]$state,[string]$message) {
    $Global:incre++
    if ($Global:incre -eq 0) {
      $Global:metric = New-Object 'object[,]' 10,9
    }
    $Global:metric[$Global:incre,6] = $this.setExitCode($state)
    $Global:arrayMessages += $message
  }

  [void] addMessage ([string]$message) {
    $Global:metric[$Global:incre,8] = $message
  }

  [float] getCounter ([string]$metricLocation) {
    $proc = ""
    try {
      $proc = Get-Counter $metricLocation -ErrorAction Stop
    } catch {
      $this.ExitUnknown("Counter not found check path location")
    }
    $returnMetric = [math]::Round(($proc.readings -split ":")[-1],2)
    return $returnMetric
  }

  [void] Final () {
    $worstCode = $this.overallStatus()
    [string]$Output = $this.getStatus($worstCode) + ": "
    if ($Global:arrayMessages.Length -eq 0) {
      for ($i = 0; $i -le $Global:incre; $i++) {
        if ($Global:metric[$i,8] -eq $null) {
          $Output = $Output + ($Global:metric[$i,0] + " is " + $Global:metric[$i,1] + $Global:metric[$i,2] + $Global:metric[$i,7])
        } else {
          $Output = $Output + $Global:metric[$i,8]
        }
        if ($i -le $Global:incre - 1) {
          $Output = $Output + ", "
        }
      }
      $Output = $Output + " | "
      for ($i = 0; $i -le $Global:incre; $i++) {
        $Output = $Output + ($Global:metric[$i,0] + "=" + $Global:metric[$i,1] + $Global:metric[$i,2] + ";" + $Global:metric[$i,3] + ";" + $Global:metric[$i,4] + ";")
        if ($i -le $Global:incre - 1) {
          $Output = $Output + ", "
        }
      }
    } else {
      for ($i = 0; $i -le $Global:incre; $i++) {
        $Output = $Output + $Global:arrayMessages[$i]
        if ($i -le $Global:incre - 1) {
          $Output = $Output + ", "
        }
      }
    }
    $Global:incre = -1
    Write-Host $Output
    exit $worstCode
  }

  [int] overallStatus () {
    [int]$worstStatus = $Global:miniumExitCode
    for ($i = 0; $i -le $Global:incre; $i++) {
      if ($Global:metric[$i,6] -gt $worstStatus) {
        $worstStatus = $Global:metric[$i,6]
      }
    }
    return $worstStatus
  }

  [string] evaluate ([int]$value,$warning,$critical) {
    $returnCode = 0
    try {
      if (($warning -ne 0) -and ($value -gt $warning)) {
        $returnCode = 1
      }
    } catch {
      $this.ExitUnknown("Invalid warning argument. Please check that the warning arugment is a valid int")
    }
    try {
      if (($critical -ne 0) -and ($value -gt $critical)) {
        $returnCode = 2
      }
    } catch {
      $this.ExitUnknown("Invalid critical argument. Please check that the critical arugment is a valid int")
    }
    return $returnCode
  }

  [int] setExitCode ([string]$returnCode) {
    if ($returnCode -eq "OK") {
      $exitCode = 0
    } elseif ($returnCode -eq "WARNING") {
      $exitCode = 1
    } elseif ($returnCode -eq "CRITICAL") {
      $exitCode = 2
    } else {
      $exitCode = 3
    }
    return $exitCode
  }

  [string] getStatus ([int]$exitCode) {
    $Status = ""
    if ($exitCode -eq 0) {
      $Status = "OK"
    } elseif ($exitCode -eq 1) {
      $Status = "WARNING"
    } elseif ($exitCode -eq 2) {
      $Status = "CRITICAL"
    } elseif ($exitCode -eq 3) {
      $Status = "UNKOWN"
    } else {
      $this.ExitUnknown("Something has gone wrong, check getStatus method")
    }
    return $Status
  }

  [void] ExitOK ([string]$errorMessage) {
    Write-Host "OK: $errorMessage"
    exit 0
  }

  [void] ExitUnknown ([string]$errorMessage) {
    Write-Host "UNKNOWN: $errorMessage"
    exit 3
  }

  [void] ExitCritical ([string]$errorMessage) {
    Write-Host "CRITICAL: $errorMessage"
    exit 2
  }

  [void] ExitWarning ([string]$errorMessage) {
    Write-Host "WARNING: $errorMessage"
    exit 1
  }

  [void] OK () {
    $Global:miniumExitCode = 0
  }

  [void] Warning () {
    $Global:miniumExitCode = 1
  }

  [void] Critical () {
    $Global:miniumExitCode = 2
  }

  [array] convertBytes ([float]$numberToConvert,[string]$startingUOM,[int]$precision) {
    # Takes in a number that needs converting, the bytes UOM it is already in and requested precision of new value
    # Returns value and UOM, in form of lowest UOM needed

    $units = @( "b","KB","MB","GB","TB","PB","EB","ZB","YB")

    $result = @( $numberToConvert,$startingUOM) # Result starts as input so may just return itself

    $startingPoint = 0 # Assume number is in bytes to begin with

    for ($i = 0; $i -lt $units.Length; $i++) {
      # For all bytes units, find the index of the one that the value is already in

      if ($startingUOM -eq $units[$i]) {
        $startingPoint = $i
      }
    }

    foreach ($unit in $units[$startingPoint..$units.Length]) {
      # Starting at the index of the UOM the value is already in
      # Iterate over each UOM and divide by 1024 each time if needed

      if ($numberToConvert -ge 1024) {
        # If >= 1024 then it can be shown in a smaller UOM, so divide it
        $numberToConvert /= 1024
      } else {
        # If < 1024, then lowest UOM needed is found, so break out of loop and return value + UOM
        $newValue = [math]::Round($numberToConvert,$precision)
        $result = @( $newValue,$unit)
        return $result
      }
    }
    return $result
  }

}


$check = [Plugin]::new("check_windows_base", "", "Copyright (c) 2003-2023 Opsview Limited. All rights reserved. This plugin monitors the stats for your Windows system.", "Plugin Options:`n
        -m Metric to Monitor
        -w Warning Threshold
        -c Critical Threshold`n
        -p Process Name`n
        -l Folder Location`n
        -f File Location`n
        Default Options:`n
        -h    Show this help message `n `nWindows Base Monitoring Opspack Plugin supports the following metrics:`n`n
        cpu_statistics - Percentage of time CPU is executing processes, Percentage of time CPU recieves interrupts, Number of processes queued but not able to use the CPU, Percentage of time CPU is in user mode
        disk_statistics - Number of reads and writes to disk per second, Number of disk requests outstanding, Percentage of time the disk is serving read or write requests
        disk_space_used_unique - Disk space for the given drive
        disk_usage - Percentage of free disk space
        file_size_unique - The size of a given file
        folder_size_unique - The size of a given folder
        memory_pages_per_sec - Number of pages per second that had to be read from disk instead of RAM
        memory_usage - Percentage of memory available
        network_in_out - Rate of packets received and sent on the network interface
        os_details - Displays the name of the operating system being monitored
        process_count - Number of instances for the given process
        process_cpu_time - Percentage of CPU time the given process uses
        system_in_out - Rate of file system read and write requests
        uptime - Uptime of the operating system. Time since last bootup
        users_count - Number of users currently on the system.")

if ($help) {
    $check.helpText($check)
    exit(0)
}

if($psboundparameters.Count -eq 0) {
    $($check.exitUnknown("No arguments entered"))
}

if($remainingArguments) {
    # Incorrect arguments saved to this variable, if there are any exit unknown
    $($check.exitUnknown("Unknown arguments $remainingArguments"))
}

switch ($mode) {
    'cpu_statistics' {
        $cpu_interrupt_time = $check.getCounter("\Processor(_Total)\% Interrupt Time")
        $check.addMetric("cpu_interrupt_time", $cpu_interrupt_time, "%", $warning, $critical)

        $cpu_queue_length = $check.getCounter("\System\Processor Queue Length")
        $check.addMetric("cpu_queue_length", $cpu_queue_length, "", $warning, $critical)

        $cpuUsage = $check.getCounter("\Processor(_Total)\% Processor Time")
        $check.addMetric("cpu_usage", $cpuUsage, "%", $warning, $critical)

        $cpu_user_time = $check.getCounter("\Processor(_Total)\% User Time")
        $check.addMetric("cpu_user_time", $cpu_user_time, "%", $warning, $critical)
    }
    'disk_statistics' {
        $reads_per_sec = $check.getCounter("\LogicalDisk(_Total)\Disk Read Bytes/sec")
        $check.addMetric("disk_reads_per_sec", $reads_per_sec, "rps", $warning, $critical)

        $writes_per_sec = $check.getCounter("\LogicalDisk(_Total)\Disk Write Bytes/sec")
        $check.addMetric("disk_writes_per_sec", $writes_per_sec, "wps", $warning, $critical)

        $disk_queue_length = $check.getCounter("\LogicalDisk(_Total)\Current Disk Queue Length")
        $check.addMetric("disk_queue_length", $disk_queue_length, "", $warning, $critical)

        $disk_time = $check.getCounter("\LogicalDisk(_Total)\% Disk Time")
        $check.addMetric("disk_time", $disk_time, "%", $warning, $critical)
    }
    'disk_space_used_unique'{
        if((!$drive) -or ($drive.Length -eq 0)) {
            $check.ExitUnknown("No Drive Name Provided. Please specify in variables.")
        }
        $drive_usage = 100 - $check.getCounter("\LogicalDisk(" + $drive + ")\% Free Space")
        $check.addMetric($drive + " Drive Used Space", $drive_usage, "%", $warning, $critical)
    }
    'disk_usage' {
        $disks = Get-WmiObject Win32_LogicalDisk
        $diskCapacity = [math]::Round($disks.Size / 1024 / 1024 / 1024,2)
        $diskFree = [math]::Round(($disks.FreeSpace / 1024 / 1024 / 1024),2)
        $diskUsed = [math]::Round($diskCapacity - $diskFree,2)
        $diskUsage = [math]::Round(($diskUsed/$diskCapacity) * 100, 2)

        $check.addMetric("disk_usage", $diskUsage, "%", $warning, $critical)
        $check.addMetric("disk_used", $diskUsed, "GB")
        $check.addMetric("disk_free", $diskFree, "GB")
        $check.addMetric("disk_capacity", $diskCapacity, "GB")
    }
    'file_size_unique' {
        if((!$file) -or ($file.Length -eq 0)) {
            $check.ExitUnknown("No File Provided. Please specify in variables.")
        }
        $file = $file.Substring(0,1) + ':' + $file.Substring(1)
        $file_size = ((Get-Item $file).length) / 1MB
        $check.addMetric($file + " file_size", $file_size, "MB", $warning, $critical)
    }
    'folder_size_unique'{
        if((!$location) -or ($location.Length -eq 0))  {
            $check.ExitUnknown("No Folder Path Provided. Please specify in variables.")
        }
        $location = $location.Substring(0,1) + ':' + $location.Substring(1)
        $folder_size = "{0:N2}" -f ((Get-ChildItem -path $location -recurse | Measure-Object -property length -sum ).sum /1MB)
        $check.addMetric($location + " folder_size", $folder_size, "MB", $warning, $critical)
    }
    'memory_pages_per_sec'{
        $memory_pages_per_sec = $check.getCounter("\Memory\Pages/sec")
        $check.addMetric($mode, $memory_pages_per_sec, "mps", $warning, $critical)
    }
    'memory_usage' {
        $operatingSystem = Get-WmiObject win32_OperatingSystem
        $memoryCapacity = [math]::Round($operatingSystem.TotalVisibleMemorySize, 2)
        $memoryUsed = [math]::Round($memoryCapacity - ($OperatingSystem.FreePhysicalMemory), 2)
        $memoryUsage = [math]::Round(($memoryUsed/$memoryCapacity) * 100, 2)

        $memoryCapacity, $memoryCapacityUOM = $check.convertBytes($memoryCapacity, "KB", 2)
        $memoryUsed, $memoryUsedUOM = $check.convertBytes($memoryUsed, "KB", 2)

        $check.addMetric("memory_usage", $memoryUsage, "%", $warning, $critical)
        $check.addMetric("memory_used", [math]::Round($memoryUsed,2), $memoryUsedUOM)
        $check.addMetric("memory_capacity", [math]::Round($memoryCapacity,2), $memoryCapacityUOM)
    }
    'network_in_out' {
        $network_packets_in_per_sec = $check.getCounter("\Network Interface(*)\Packets Received/sec")
        $network_packets_out_per_sec = $check.getCounter("\Network Interface(*)\Packets Sent/sec")
        $check.addMetric("network_packets_in_per_sec", $network_packets_in_per_sec, "pps", $warning, $critical)
        $check.addMetric("network_packets_out_per_sec", $network_packets_out_per_sec, "pps", $warning, $critical)
    }
    'os_details'{
        $os = Get-WmiObject Win32_OperatingSystem;
        $os_name = $os.caption;
        $check.exitOK("Operating System: " + $os_name)
    }
    'process_count' {
        if((!$process) -or ($process.Length -eq 0))  {
            $check.ExitUnknown("No Process Name Provided. Please specify in variables.")
        }
        $process_count = (Get-Process -ProcessName $process).Count
        $check.addMetric($process + " process_count", $process_count, "instances", $warning, $critical)
        $check.addMessage($process + " process_count is " + $process_count + " instances")
    }
    'process_cpu_time' {
        if((!$process) -or ($process.Length -eq 0))  {
            $check.ExitUnknown("No Process Name Provided. Please specify in variables.")
        }
        $process_cpu_time = $check.getCounter("\Process(" + $process + ")\% Processor Time")
        $check.addMetric($process + " processor_time", $process_cpu_time, "%", $warning, $critical)
    }
    'system_in_out' {
        $read_per_sec = $check.getCounter("\System\File Read Operations/sec")
        $writes_per_sec = $check.getCounter("\System\File Write Operations/sec")
        $check.addMetric("file_reads_per_sec", $read_per_sec, "rps", $warning, $critical)
        $check.addMetric("file_writes_per_sec", $writes_per_sec, "wps", $warning, $critical)
    }
    'uptime'{
        $os = Get-WmiObject win32_operatingsystem
        $uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)

        $uptimeMinutes = ([TimeSpan]::Parse($uptime)).TotalMinutes
        $uptimeMessage = "Uptime is " + $uptime.Days + " Days " + $uptime.Hours + " Hours " + $uptime.Minutes + " Minutes"

        $check.addMetric($mode, $uptimeMinutes, "mins", $warning, $critical)
        $check.addMessage($uptimeMessage)
    }
    'users_count'{
        $users_count = (Get-WmiObject -Class Win32_UserAccount).Count
        $check.addMetric($mode, $users_count, "users", $warning, $critical)
        $check.addMessage("users_count is " + $users_count + " users")
    }
    default {
        $($check.exitUnknown("Unknown mode: $mode"))
    }
}

$check.Final()
