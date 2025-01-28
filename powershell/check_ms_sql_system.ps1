# AUTHORS:
#       Copyright (C) 2003-2025 ITRS Group Ltd. All rights reserved
#
#       This file is part of Opsview
#
# This plugin monitors the stats for Microsoft SQL System.

param(
    [alias("m")] [string]$mode,
    [alias("w")] $warning ,
    [alias("c")] $critical,
    [alias("h")] [switch]$help,
    [Parameter(ValueFromRemainingArguments=$true)] $remainingArguments, # Used to handle invalid parameters
    [alias("s")] [string]$server_name
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


$check = [Plugin]::new("check_ms_sql_system", "", "Copyright (C) 2003-2025 ITRS Group Ltd. All rights reserved. This plugin monitors the stats for your Microsoft SQL System.", "Plugin Options:`n
        -m Metric to Monitor
        -w Warning Threshold
        -c Critical Threshold
        -s Server Name`n
        Default Options:`n
        -h    Show this help message `n `nMS SQL System Monitoring Opspack Plugin supports the following metrics:`n
        kernel_pool_statistics: Kernel Paged Pool Size and Kernel Non Paged Pool Size
        memory_utilization: Memory Utilization Percentage
        paging_statistics: Total Page File Size, Page Fault Count, Locked Page Allocations Size and Available Page File Size
        physical_memory_statistics: Available Physical Memory, Physical Memory In Use and Total Physical Memory Size
        process_physical_memory_status: Low Physical Memory Notification
        process_virtual_memory_status: Low Virtual Memory Notification
        server_listener: Server Listener
        system_cache_size: System Cache Size
        system_memory_state_description: Memory state defined from High Memory/Low Memory Resource Notifications
        virtual_address_space_statistics: Total Virtual Address Space, Virtual Address Space Available, Virtual Address Space Committed and Virtual Address Space Reserved")

function retrieveMetric([string] $mode, [string] $table_name, [string] $server_name) {

    # Create the SQL connection object with the applicable connection string
    $connection = New-Object System.Data.SqlClient.SQLConnection

    # Connection string is by default localhost, but add custom server name if needed
    $connection.ConnectionString = "Server=localhost" + $server_name + ";Database=master;Trusted_Connection=True;"

    try {
        $connection.open()
    }
    catch {
        # Exit unknown if unable to connect to the server
        $($check.exitUnknown("Unable to connect to SQL server"))
    }

    # Create the SQL command object on the SQL connection
    $command = New-Object System.Data.SQLClient.SQLCommand
    $command.Connection = $connection

    # Set the SQL command object to applicable SQL query
    if($mode -eq "server_listener") {
        # Different SQL query for the server_listener metric
        $command.CommandText = "SELECT state_desc FROM sys.dm_tcp_listener_states;"
    } else {
        # Normal SQL query for retrieving metrics
        $command.CommandText = "SELECT {0} FROM {1};" -f $mode, $table_name
    }

    try {
        # Execute query and save result to a reader variable
        $reader = $command.ExecuteReader()
    }
    catch {
        $($check.exitUnknown("Unable to find metric with this name"))
    }

    if($reader.Read()) {
        # If there is a next row, save it to a variable

        # Check data type of the retrieved value, use different get functions depending on this type
        $dataType = $reader.GetDataTypeName(0)

        try {
            $metric = $reader.GetInt64(0)
        }
        catch [InvalidCastException] {
        # If not int64, try retrieving value with applicable get functions
            if($dataType -eq "int") {
                $metric = $reader.GetInt32(0)
            }

            if($dataType -eq "bit") {
                $metric = $reader.GetBoolean(0)
            }

            if($dataType -eq "nvarchar") {
                $metric = $reader.GetString(0)
            }
        }
    } else {
        # Exit unknown if command returns no results
        $($check.exitUnknown("Unable to find metric with this name"))
    }

    return $metric
}

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
    # Switch statement for metric options and their corresponding name in SQL, its SQL table and the UOM
    # Table name and UOM variables are saved depending on which metric is requested
    "kernel_pool_statistics" {
        $kernel_nonpaged_pool_size = retrieveMetric "kernel_nonpaged_pool_kb" "sys.dm_os_sys_memory" $server_name
        $kernel_nonpaged_pool_size, $UOM = $check.convertBytes($kernel_nonpaged_pool_size, "KB", 2)
        $check.AddMetric("kernel_nonpaged_pool_size", $kernel_nonpaged_pool_size, $UOM, $warning, $critical)

        $kernel_paged_pool_size = retrieveMetric "kernel_paged_pool_kb" "sys.dm_os_sys_memory" $server_name
        $kernel_paged_pool_size, $UOM = $check.convertBytes($kernel_paged_pool_size, "KB", 2)
        $check.AddMetric("kernel_paged_pool_size", $kernel_paged_pool_size, $UOM, $warning, $critical)
    }
    "memory_utilization" {
        $memory_utilization = retrieveMetric "memory_utilization_percentage" "sys.dm_os_process_memory" $server_name
        $check.AddMetric("memory_utilization", $memory_utilization, "%", $warning, $critical)
    }
    "paging_statistics" {
        $total_page_file_size = retrieveMetric "total_page_file_kb" "sys.dm_os_sys_memory" $server_name
        $total_page_file_size, $UOM = $check.convertBytes($total_page_file_size, "KB", 2)
        $check.AddMetric("total_page_file_size", $total_page_file_size, $UOM, $warning, $critical)

        $page_fault_count = retrieveMetric "page_fault_count" "sys.dm_os_process_memory" $server_name
        $check.AddMetric("page_fault_count", $page_fault_count, "pages", $warning, $critical)

        $locked_page_allocations_size = retrieveMetric "locked_page_allocations_kb" "sys.dm_os_process_memory" $server_name
        $locked_page_allocations_size, $UOM = $check.convertBytes($locked_page_allocations_size, "KB", 2)
        $check.AddMetric("locked_page_allocations_size", $locked_page_allocations_size, $UOM, $warning, $critical)

        $available_page_file_size = retrieveMetric "available_page_file_kb" "sys.dm_os_sys_memory" $server_name
        $available_page_file_size, $UOM = $check.convertBytes($available_page_file_size, "KB", 2)
        $check.AddMetric("available_page_file_size", $available_page_file_size, $UOM, $warning, $critical)
    }
    "physical_memory_statistics" {
        $used_physical_memory = retrieveMetric "physical_memory_in_use_kb" "sys.dm_os_process_memory" $server_name
        $used_physical_memory, $UOM = $check.convertBytes($used_physical_memory, "KB", 2)
        $check.AddMetric("used_physical_memory", $used_physical_memory, $UOM, $warning, $critical)

        $available_physical_memory = retrieveMetric "available_physical_memory_kb" "sys.dm_os_sys_memory" $server_name
        $available_physical_memory, $UOM = $check.convertBytes($available_physical_memory, "KB", 2)
        $check.AddMetric("available_physical_memory", $available_physical_memory, $UOM, $warning, $critical)

        $total_physical_memory = retrieveMetric "total_physical_memory_kb" "sys.dm_os_sys_memory" $server_name
        $total_physical_memory, $UOM = $check.convertBytes($total_physical_memory, "KB", 2)
        $check.AddMetric("total_physical_memory", $total_physical_memory, $UOM, $warning, $critical)
    }
    "process_physical_memory_status" {
        $process_physical_memory_status = retrieveMetric "process_physical_memory_low" "sys.dm_os_process_memory" $server_name

        if($process_physical_memory_status -eq "False") {
            $check.ExitOK("Physical Memory is OK")
        } else {
            $check.ExitCritical("Physical Memory is Low")
        }
    }
    "process_virtual_memory_status" {
        $process_virtual_memory_status = retrieveMetric "process_virtual_memory_low" "sys.dm_os_process_memory" $server_name

        if($process_virtual_memory_status -eq "False") {
            $check.ExitOK("Virtual Memory is OK")
        } else {
            $check.ExitCritical("Virtual Memory is Low")
        }
    }
    "server_listener" {
        $server_listener = retrieveMetric "server_listener" "sys.dm_tcp_listener_states" $server_name

        if($server_listener -eq "ONLINE") {
            $check.ExitOK("Server Listener is ONLINE")
        } else {
            $check.ExitCritical("Server Listener on port 1434 is OFFLINE")
        }
    }
    "system_cache_size" {
        $system_cache_size = retrieveMetric "total_physical_memory_kb" "sys.dm_os_sys_memory" $server_name
        $system_cache_size, $UOM = $check.convertBytes($system_cache_size, "KB", 2)
        $check.AddMetric("system_cache_size", $system_cache_size, $UOM, $warning, $critical)
    }
    "system_memory_state_description" {
        $system_memory_state_description = retrieveMetric "system_memory_state_desc" "sys.dm_os_sys_memory" $server_name

        switch($system_memory_state_description) {
            "Available physical memory is high" {
                 $check.ExitOK("Available physical memory is high")
            }
            "Available physical memory is low" {
                 $check.ExitCritical("Available physical memory is low")
            }
            "Physical memory usage is steady" {
                 $check.ExitOK("Physical memory usage is steady")
            }
            "Physical memory state is transitioning" {
                 $check.ExitWarning("Physical memory state is transitioning")
            }
            default {
                 $check.ExitUnknown("No description currently available")
            }
        }
    }
    "virtual_address_space_statistics" {
        $available_virtual_address_space = retrieveMetric "virtual_address_space_available_kb" "sys.dm_os_process_memory" $server_name
        $available_virtual_address_space, $UOM = $check.convertBytes($available_virtual_address_space, "KB", 2)
        $check.AddMetric("available_virtual_address_space", $available_virtual_address_space, $UOM, $warning, $critical)

        $committed_virtual_address_space = retrieveMetric "virtual_address_space_committed_kb" "sys.dm_os_process_memory" $server_name
        $committed_virtual_address_space, $UOM = $check.convertBytes($committed_virtual_address_space, "KB", 2)
        $check.AddMetric("committed_virtual_address_space", $committed_virtual_address_space, $UOM, $warning, $critical)

        $reserved_virtual_address_space = retrieveMetric "virtual_address_space_reserved_kb" "sys.dm_os_process_memory" $server_name
        $reserved_virtual_address_space, $UOM = $check.convertBytes($reserved_virtual_address_space, "KB", 2)
        $check.AddMetric("reserved_virtual_address_space", $reserved_virtual_address_space, $UOM, $warning, $critical)

        $total_virtual_address_space = retrieveMetric "total_virtual_address_space_kb" "sys.dm_os_process_memory" $server_name
        $total_virtual_address_space, $UOM = $check.convertBytes($total_virtual_address_space, "KB", 2)
        $check.AddMetric("total_virtual_address_space", $total_virtual_address_space, $UOM, $warning, $critical)
    }
    default {
        $check.ExitUnknown("Incorrect mode. Check help text for mode names (-h)")
    }
}

$check.Final()
