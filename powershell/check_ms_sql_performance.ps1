# AUTHORS:
#       Copyright (C) 2003-2023 Opsview Limited.All rights reserved
#
#       This file is part of Opsview
#
# This plugin monitors the stats for Microsoft SQL Performance Metrics.

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


$check = [Plugin]::new("check_ms_sql_performance", "", "Copyright (c) 2003-2023 Opsview Limited. All rights reserved. This plugin monitors the stats for your Microsoft SQL Performance Metrics.", "Plugin Options:`n
        -m Metric to Monitor
        -w Warning Threshold
        -c Critical Threshold
        -s Server Name`n
        Default Options:`n
        -h    Show this help message `n `n Microsoft SQL Performance Metrics Monitoring Opspack Plugin supports the following metrics:`n
        active_transactions: Active Transactions
        average_wait: Average Wait Time
        batch_requests: Batch Requests/Sec
        buffer_hit_ratio: Buffer Cache Hit Ratio
        compilation_statistics: SQL Compilations/Sec and SQL Re-Compilations/Sec
        database_size: Database Size
        forwarded_records: Forwarded Records/Sec
        full_scans: Full Scans/sec
        latch_statistics: Average Latch Wait Time, Latch Wait Time, SuperLatch Promotions/Sec and SuperLatch Demotions/Sec
        lazy_writes: Lazy Writes/Sec
        lock_statistics: Deadlocks/Sec, Lock Requests/Sec, Lock Wait Time, Lock Timeouts/Sec and Lock Waits/Sec
        log_statistics: Log Cache Hit Ratio, Log Flush Wait Time, Log Flush Write Time and Log Growths
        paging_statistics: Checkpoint Pages/Sec, Database Pages, Page Life Expectancy, Page Lookups/Sec, Page Reads/Sec, Page Splits/Sec, Page Writes/Sec, Readahead Pages/Sec and Target Pages
        processes_blocked: Processes Blocked
        stolen_server_memory: Stolen Server Memory (Stolen Pages in KB)
        user_connections: User Connections")

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

function retrieveMetric([string] $metric, [string] $instance, [string] $server_name) {

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
    $command.CommandText = "SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name='{0}' AND instance_name='{1}';" -f $metric, $instance

    # Execute query and save result to a reader variable
    $reader = $command.ExecuteReader()

    if($reader.Read()) {
        # If there is a next row, save it to a variable
        $metric = $reader.GetInt64(0)
    } else {
        # Exit unknown if command returns no results
        $($check.exitUnknown("Unable to find metric with this name"))
    }

    return $metric
}

switch ($mode) {
        # Switch statement for metric options and their corresponding name in SQL, whether the query needs an instance, and the UOM
        # Query name, instance and UOM variables are saved depending on which metric is requested
        "active_transactions" {
            $active_transactions = retrieveMetric "Active Transactions" "_Total" $server_name
            $check.AddMetric("active_transactions", $active_transactions, "transactions", $warning, $critical)
            $check.AddMessage("active_transactions is " + $active_transactions)
        }
        "average_wait" {
            $average_wait = retrieveMetric "Average Wait Time (ms)" "_Total" $server_name
            $check.AddMetric("average_wait", $average_wait, "ms", $warning, $critical)
        }
        "batch_requests" {
            $batch_requests = retrieveMetric "Batch Requests/Sec" "" $server_name
            $check.AddMetric("batch_requests", $batch_requests, "rps", $warning, $critical)
        }
        "buffer_hit_ratio" {
            $buffer_hit_ratio = retrieveMetric "Buffer Cache Hit Ratio" "" $server_name
            $check.AddMetric("buffer_hit_ratio", $buffer_hit_ratio, "%", $warning, $critical)
        }
        "compilation_statistics" {
            $compilations = retrieveMetric "SQL Compilations/Sec" "" $server_name
            $check.AddMetric("compilations", $compilations, "cps", $warning, $critical)

            $recompilations = retrieveMetric "SQL Re-Compilations/Sec" "" $server_name
            $check.AddMetric("recompilations", $recompilations, "rcps", $warning, $critical)
        }
        "database_size" {
            $database_size = retrieveMetric "Data File(s) Size (KB)" "_Total" $server_name
            $database_size, $UOM = $check.convertBytes($database_size, "KB", 2)
            $check.AddMetric("database_size", $database_size, $UOM, $warning, $critical)
        }
        "forwarded_records" {
            $forwarded_records = retrieveMetric "Forwarded Records/sec" "" $server_name
            $check.AddMetric("forwarded_records", $forwarded_records, "rps", $warning, $critical)
        }
        "full_scans" {
            $full_scans = retrieveMetric "Full Scans/sec" "" $server_name
            $check.AddMetric("full_scans", $full_scans, "sps", $warning, $critical)
        }
        "latch_statistics" {
            $avg_latch_wait_time = retrieveMetric "Average Latch Wait Time (ms)" "" $server_name
            $check.AddMetric("avg_latch_wait_time", $avg_latch_wait_time, "ms", $warning, $critical)

            $latch_wait_time = retrieveMetric "Total Latch Wait Time (ms)" "" $server_name
            $check.AddMetric("latch_wait_time", $latch_wait_time, "ms", $warning, $critical)

            $superlatch_dem = retrieveMetric "SuperLatch Demotions/sec" "" $server_name
            $check.AddMetric("superlatch_dem", $superlatch_dem, "dps", $warning, $critical)

            $superlatch_prom = retrieveMetric "SuperLatch Promotions/sec" "" $server_name
            $check.AddMetric("superlatch_prom", $superlatch_prom, "pps", $warning, $critical)
        }
        "lazy_writes" {
            $lazy_writes = retrieveMetric "Lazy writes/sec" "" $server_name
            $check.AddMetric("lazy_writes", $lazy_writes, "wps", $warning, $critical)
        }
        "lock_statistics" {
            $dead_locks = retrieveMetric "Number of Deadlocks/sec" "_Total" $server_name
            $check.AddMetric("dead_locks", $dead_locks, "dps", $warning, $critical)

            $lock_requests = retrieveMetric "Lock Requests/sec" "_Total" $server_name
            $check.AddMetric("lock_requests", $lock_requests, "rps", $warning, $critical)

            $lock_wait_time = retrieveMetric "Lock Wait Time (ms)" "_Total" $server_name
            $check.AddMetric("lock_wait_time", $lock_wait_time, "ms", $warning, $critical)

            $lock_timeouts = retrieveMetric "Lock timeouts/sec" "_Total" $server_name
            $check.AddMetric("lock_timeouts", $lock_timeouts, "tps", $warning, $critical)

            $lock_waits = retrieveMetric "Lock Waits/sec" "_Total" $server_name
            $check.AddMetric("lock_waits", $lock_waits, "wps", $warning, $critical)
        }
        "log_statistics" {
            $log_cache_hit_ratio = retrieveMetric "Log cache hit ratio" "_Total" $server_name
            $check.AddMetric("log_cache_hit_ratio", $log_cache_hit_ratio, "%", $warning, $critical)

            $log_flush_wait_time = retrieveMetric "Log Flush Wait Time" "_Total" $server_name
            $check.AddMetric("log_flush_wait_time", $log_flush_wait_time, "ms", $warning, $critical)

            $log_flush_write_time = retrieveMetric "Log Flush Write Time (ms)" "_Total" $server_name
            $check.AddMetric("log_flush_write_time", $log_flush_write_time, "ms", $warning, $critical)

            $log_growths = retrieveMetric "Log Growths" "_Total" $server_name
            $check.AddMetric("log_growths", $log_growths, "growths", $warning, $critical)
        }
        "paging_statistics" {
            $checkpoint_pages = retrieveMetric "Checkpoint Pages/Sec" "" $server_name
            $check.AddMetric("checkpoint_pages", $checkpoint_pages, "cps", $warning, $critical)

            $database_pages = retrieveMetric "Database Pages" "" $server_name
            $check.AddMetric("database_pages", $database_pages, "pages", $warning, $critical)

            $page_life = retrieveMetric "Page Life Expectancy" "" $server_name
            $check.AddMetric("page_life", $page_life, "s", $warning, $critical)

            $page_looks = retrieveMetric "Page lookups/sec" "" $server_name
            $check.AddMetric("page_looks", $page_looks, "lps", $warning, $critical)

            $page_reads = retrieveMetric "Page reads/sec" "" $server_name
            $check.AddMetric("page_reads", $page_reads, "rps", $warning, $critical)

            $page_splits = retrieveMetric "Page Splits/sec" "" $server_name
            $check.AddMetric("page_splits", $page_splits, "sps", $warning, $critical)

            $page_writes = retrieveMetric "Page Writes/sec" "" $server_name
            $check.AddMetric("page_writes", $page_writes, "wps", $warning, $critical)

            $readahead_pages = retrieveMetric "Readahead pages/sec" "" $server_name
            $check.AddMetric("readahead_pages", $readahead_pages, "pps", $warning, $critical)

            $target_pages = retrieveMetric "Target Pages" "" $server_name
            $check.AddMetric("target_pages", $target_pages, "pages", $warning, $critical)
        }
        "processes_blocked" {
            $processes_blocked = retrieveMetric "Processes Blocked" "" $server_name
            $check.AddMetric("processes_blocked", $processes_blocked, "processes", $warning, $critical)
            $check.AddMessage("processes_blocked is " + $processes_blocked)
        }
        "stolen_server_memory" {
            $stolen_server_memory = retrieveMetric "Stolen Server Memory (KB)" "" $server_name
            $stolen_server_memory, $UOM = $check.convertBytes($stolen_server_memory, "KB", 2)
            $check.AddMetric("stolen_server_memory", $stolen_server_memory, $UOM, $warning, $critical)
        }
        "user_connections" {
            $user_connections = retrieveMetric "User Connections" "" $server_name
            $check.AddMetric("user_connections", $user_connections, "connections", $warning, $critical)
            $check.AddMessage("user_connections is " + $user_connections)
        }
        default {
            $check.ExitUnknown("Incorrect mode. Check help text for mode names (-h)")
        }
}

$check.Final()
