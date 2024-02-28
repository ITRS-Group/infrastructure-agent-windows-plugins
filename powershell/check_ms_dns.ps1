# AUTHORS:
#       Copyright (C) 2003-2024 ITRS Group Ltd. All rights reserved
#
#       This file is part of Opsview
#
# This plugin monitors the stats for Microsoft DNS Server.

param(
    [alias("m")] [string]$mode,
    [alias("w")] $warning ,
    [alias("c")] $critical,
    [alias("h")] [switch]$help,
    [Parameter(ValueFromRemainingArguments=$true)] $remainingArguments # Used to handle invalid parameters
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


$check = [Plugin]::new("check_ms_dns", "", "Copyright (C) 2003-2024 ITRS Group Ltd. All rights reserved. This plugin monitors the stats for your Microsoft DNS Server.", "Plugin Options:`n
        -m Metric to Monitor
        -w Warning Threshold
        -c Critical Threshold`n
        Default Options:`n
        -h    Show this help message `n `nMicrosoft DNS Server Monitoring Opspack Plugin supports the following metrics:`n
        caching_memory - Shows the total amount of caching memory used by the DNS server
        recursive_queries_statistics - Shows the rate at which recursive queries are received, failed and timeout by the DNS server
        requests_statistics - Shows the rate at which queries are received and responses are sent by the DNS serverr")

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
    'caching_memory'{
	    $caching_memory = $check.getCounter("\DNS\Caching Memory")
        $check.addMetric("caching_memory", $caching_memory, "b", $warning, $critical)
    }
    'recursive_queries_statistics'{
        $recursive_queries_sec = $check.getCounter("\DNS\Recursive Queries/sec")
        $check.addMetric("recursive_queries_per_sec", $recursive_queries_sec, "queries", $warning, $critical)
        $check.addMessage("recursive_queries is " + $recursive_queries_sec + " queries per second")

        $recursive_queries_failure_sec = $check.getCounter("\DNS\Recursive Query Failure/sec")
        $check.addMetric("recursive_queries_failure_per_sec", $recursive_queries_failure_sec, "queries", $warning, $critical)
        $check.addMessage("recursive_queries_failed is " + $recursive_queries_failure_sec + " queries per second")

        $recursive_timeout_sec = $check.getCounter("\DNS\Recursive TimeOut/sec")
        $check.addMetric("recursive_timeouts_per_sec", $recursive_timeout_sec, "queries", $warning, $critical)
        $check.addMessage("recursive_timeouts is " + $recursive_timeout_sec + " queries per second")
    }
    'requests_statistics'{
        $total_query_received_sec = $check.getCounter("\DNS\Total Query Received/sec")
        $check.addMetric("queries_received_per_sec", $total_query_received_sec, "queries", $warning, $critical)
        $check.addMessage("queries_received is " + $total_query_received_sec + " queries per second")

        $total_response_sent_sec = $check.getCounter("\DNS\Total Response Sent/sec")
        $check.addMetric("responses_sent_per_sec", $total_response_sent_sec, "responses", $warning, $critical)
        $check.addMessage("responses_sent is " + $total_response_sent_sec + " responses per second")
    }
    default {
        $($check.exitUnknown("Unknown mode: $mode"))
    }
}

$check.Final()
