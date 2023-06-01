<#
Opsview Monitor check_active_directory plugin.

Copyright (C) 2003 - 2023 Opsview Limited. All rights reserved

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#>



param(
    [Alias("h")][Switch] $help,
    [Alias("m")][string] $mode,
    [Alias("w")][string] $warning,
    [Alias("c")][string] $critical,
    [Alias("n")][string] $hostname,
    [string] $Username,
    [string] $Password,
    [string] $Authentication,
    [Parameter(ValueFromRemainingArguments = $true)] $remainingArguments
)

Import-Module -Name 'C:\Program Files\Infrastructure Agent\plugins\lib\powershell\PlugNpshell'

[Check] $Check
[Metric] $Metric

Function CreateCheckObj() {
    $description = "Monitors Microsoft Active Directory."


    $script:check = [Check]::New("check_active_directory", "",
        "Copyright (C) 2003 - 2023 Opsview Limited. All rights reserved.`n$description",
        "Optional arguments:
        -v, -Verbose
            Verbose mode - always display all output
        -w, -Warning
            The warning levels (comma separated)
        -c, -Critical
            The critical levels (comma separated)

        Mode specific arguments:
            -Username
                Username for remote windows host e.g user@DOMAIN.COM
            -Password
                Password for remote windows host
            -Authentication
                Authentication type to use

        Supported modes:
            - AD.Replication.IOBytesRate
            - AD.Replication.IOObjectsRate
            - AD.Replication.IOValuesRate
            - AD.Replication.Synchronizations
            - AD.Services.ClientBindsRate
            - AD.Services.DirectoryIORate
            - AD.Services.DirectorySearches
            - AD.Services.LDAPBindTime
            - AD.Services.LDAPClientSessions
            - AD.Services.LDAPSearches
            - AD.Services.LDAPSearchesRate
            - AD.Services.LDAPSuccessfulBindsRate
            - AD.Services.LDAPWrites
            - AD.Services.LDAPWritesRate
            - AD.Services.KC.IO
            - AD.Services.LSA.IO
            - AD.Services.NSPI.IO
            - AD.Services.ADWS
            - AD.Threads.AsynchronousThreadQueue
            - AD.Threads.LDAPAsynchronousThreadQueue
            - AD.AddressBook.ClientSessions
            - AD.AddressBook.BrowsesRate
            - AD.AddressBook.LookupsRate
            - AD.AddressBook.PropertyReadsRate
            - AD.AddressBook.SearchesRate
            - AD.SAM.ReadsWrites
            - AD.SAM.ComputerCreationsRate
            - AD.SAM.MachineCreationAttemptsRate
            - AD.SAM.PasswordChangesRate
            - AD.SAM.UserCreationsRate
            - AD.SAM.GlobalCatalogEvaluationsRate
            - AD.SAM.UserCreationAttemptsRate
            - AD.DNS.TotalQueries
            - AD.DNS.QueriesRate
            - AD.DNS.RecursiveQueriesRate
            - AD.Database.DiskUsage
            - AD.Database.OperationalStatus
            - AD.Database.HealthStatus
            - AD.Database.FileSize
","METRIC")
}

function Get-NTDS-Data {
    $key = 'SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
    $valueName = 'DSA Database file'
    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $env:COMPUTERNAME)
    $regKey = $reg.OpenSubKey($key)
    $NTDSPath = $regKey.GetValue($valueName)
    $NTDSSize = (Get-Item $NTDSPath).length
    $NTDSSize = $NTDSSize / 1MB
    $NTDSSize = '{0:N2} MB' -f $NTDSSize
    return @($NTDSPath, $NTDSSize)
}


class ActiveDirectoryAPI {
    [string] $Hostname
    [string] $Authentication
    [System.Management.Automation.PSCredential] $Credentials
    [System.Management.Automation.Runspaces.PSSession] $Session
    [System.Management.Automation.Remoting.PSSessionOption] $Options

    ActiveDirectoryAPI([string]$Hostname, [string]$Username, [string]$Password, [string]$Authentication) {
        $this.Hostname = $Hostname
        $this.Options = New-PSSessionOption -SkipCACheck -SkipCNCheck
        $this.Session = $null
    }

    [void] CreateSession() {
        try {
            $this.Session = New-PSSession -ComputerName $this.Hostname -Credential $this.Credentials `
                                -Authentication $this.Authentication -UseSSL -SessionOption $this.Options

        } catch {
            throw "Unable to connect to remote host: {0}" -f $this.Hostname
        }
    }

    [System.Object] GetPerfMetric([string] $Counter) {
        return Get-Counter $Counter  -ErrorAction SilentlyContinue
    }

    [System.Object] GetDBVolumeData() {
        return Get-Volume -Driveletter C | Select-Object Size, SizeRemaining
    }

    [System.Object] GetDiskHealthStatus() {
        return Get-Volume -Driveletter C | Select-Object HealthStatus, OperationalStatus
    }

    [System.Object] GetADServiceStatus() {
        return Get-Service -name "ADWS" -ComputerName $this.Hostname | Select Machinename, Status
    }

    [System.Object] GetDBFileSize() {
        return Get-NTDS-Data
    }
}


Class ActiveDirectory {
    [System.Object[]] $MetricsArr
    [boolean] $Verbose
    [string] $Unit
    [string] $MetricMethod
    [string[]] $Warning
    [string[]] $Critical
    [HashTable] $DefaultWarning
    [HashTable] $DefaultCritical
    [HashTable] $ModeArgs
    [HashTable] $MetricInfo
    [int] $NumThresholds
    [ActiveDirectoryAPI] $API
    [string] $Output = $null
    [string] $OK_STATUS = "OK"
    [string] $WARNING_STATUS = "WARNING"
    [string] $CRITICAL_STATUS = "CRITICAL"
    [string] $UNKNOWN_STATUS = "UNKNOWN"

    ActiveDirectory([boolean]$Verbose, [string] $Hostname, [HashTable]$ThresholdsWarning, [HashTable]$ThresholdsCritical, [string]$Unit,
                    [string]$MetricType, [string]$MetricInfo, [HashTable]$ModeArgs) {

        $this.Verbose = $Verbose
        $this.ModeArgs = $ModeArgs
        $this.Unit = $Unit
        $this.API = [ActiveDirectoryAPI]::New($Hostname, $ModeArgs.Username, $ModeArgs.Password, $ModeArgs.Authentication)
        $this.NumThresholds = 0

        switch ($metricType) {
            'perf'{
                $this.MetricMethod = 'ActiveDirectoryPerf'
                $this.MetricInfo = $this.ParseMetricInfo($MetricInfo)
                $this.NumThresholds = $this.MetricInfo.labels.Count

             }
            'custom'{
                $this.MetricInfo = $this.ParseMetricInfo($MetricInfo)
                $this.MetricMethod = $this.MetricInfo.labels[0]
                try {
                    $this.NumThresholds = [int] $this.MetricInfo.counters[0]
                } catch [System.InvalidCastException] {
                    throw "Metric info counters for custom methods should be numeric values."
                }

             }
            Default { throw "$MetricType not implemented" }
        }

        $this.DefaultWarning = $ThresholdsWarning
        $this.DefaultCritical = $ThresholdsCritical

        if ($ModeArgs.warning) {
            $this.Warning = $ModeArgs.warning.Split(',') | ForEach-Object { $_.Trim() }
            if ($this.Warning.Length -ne $this.NumThresholds) {
                throw "Number of warning thresholds provided must match number of metrics"
            }
        }
        if ($ModeArgs.critical) {
            $this.Critical = $ModeArgs.critical.Split(',') | ForEach-Object { $_.Trim() }
            if ($this.Critical.Length -ne $this.NumThresholds) {
                throw "Number of critical thresholds provided must match number of metrics"
            }
        }
    }

    # Currently Powershell does not allow you to import Module class definitions inside classes
    # therefore we need a global "Check" object to access the the methods provided by PlugNpshell.
    [void] Check() {
        CreateCheckObj
        $this.($this.MetricMethod)()
        $script:check.final()
    }

    [HashTable] ParseMetricInfo($MetricInfo) {
        $metrics = @{}

        [string[]] $info = $MetricInfo.Split(';')
        if ($info.Length -ne 2) {
            throw "Malformed metric info string: '$MetricInfo'"
        }
        [string[]] $labels = $info[0].Split(',') | ForEach-Object {$_.Trim() }
        [string[]] $counters = $info[1].Split(',') | ForEach-Object { $_.Trim() }

        $metrics.labels = $labels
        $metrics.counters = $counters

        return $metrics
    }

    [HashTable] GetThresholds($Position, $Label) {
        $thresholds = @{}
        $thresholds.warning = $null
        if ($this.Warning) {
            $thresholds.warning = $this.Warning[$Position]
        } elseif ($this.DefaultWarning.ContainsKey($Label)) {
            $thresholds.warning = $this.DefaultWarning[$Label]
        }

        $thresholds.critical = $null
        if ($this.Critical) {
            $thresholds.critical = $this.Critical[$Position]
        } elseif ($this.DefaultCritical.ContainsKey($Label)) {
            $thresholds.critical = $this.DefaultCritical[$Label]
        }

        return $thresholds
    }


    [void] CheckExit($MetricStatus, $Label, $Value) {
        $this.Output = 'METRIC {0} - {1} is {2}' -f $MetricStatus, $Label, $Value
        $script:Check."Exit$MetricStatus"($this.Output)
    }

    [string] ConvertLabel([string]$Label) {
        return $Label.ToLower().Replace(' ', '_')
    }

    [System.Object] CallActiveDirectoryAPI([string]$Method, [string]$Counter ) {
        if ($Counter) {
            return $this.API.$Method($Counter)
        }
        return $this.API.$Method()
    }

    [double] ConvertValue([string] $Value) {
        try{
           $convertedValue = iex $value
        } catch [System.InvalidCastException] {
            throw "Invalid '$value'. The Value should be in this format \d+(\.\d+)?[bytes]"
        }
        return $convertedValue
    }

    [void] ActiveDirectoryPerf() {
        for ($i=0; $i -lt $this.MetricInfo.labels.Length; $i++) {
            $label = $this.MetricInfo.labels[$i].trim()
            $counter = $this.MetricInfo.counters[$i].trim()
            $counterObj = $this.CallActiveDirectoryAPI('GetPerfMetric', $counter)
            if (!$counterObj) {
                throw "Unable to retrieve data. Ensure all required services are running."
            }
            $value =  $counterObj.Readings.split(':')[-1].trim()
            $convertedLabel = $this.ConvertLabel($label)
            $thresholds = $this.GetThresholds($i, $label)
            if ($this.Unit -eq 'per_second'){
                $displayFormat = "{name} is {value} {unit}"
            } else {
                $displayFormat = "{name} is {value}{unit}"
            }
            $script:check.AddMetric(@{Name =  $convertedLabel; Value = $value; UOM = $this.Unit;
                WarningThreshold = $thresholds['warning']; CriticalThreshold = $thresholds['critical'];
                DisplayName = $label; DisplayFormat = $displayFormat})
            }
    }

    [void] GetVolumeSize() {
        $label = "Database Disk Usage"
        $volumeData = $this.CallActiveDirectoryAPI('GetDBVolumeData', $null)
        if (!$volumeData) {
            throw "Unable to retrieve data. Ensure all required services are running."
        }
        $usedData = $volumeData.Size - $volumeData.SizeRemaining
        $usage = $usedData / $volumeData.Size * 100
        $usedData = Get-ConvertedMetric($usedData)
        $size = Get-ConvertedMetric($volumeData.Size)
        $convertedLabel = $this.ConvertLabel($label)
        $thresholds = $this.GetThresholds(0, $convertedLabel)
        $usageOutput = "({0}{1}/{2}{3})" -f $usedData.Value, $usedData.UOM, $size.Value, $size.UOM
        $script:check.AddMetric(@{Name =  $convertedLabel; Value = $usage; UOM = $this.Unit;
            WarningThreshold = $thresholds['warning']; CriticalThreshold = $thresholds['critical'];
            DisplayName = $label; DisplayFormat = "{name} is {value}{unit} $usageOutput"})
    }

    [void] GetHealthStatus() {
        $metricStatus = $this.UNKNOWN_STATUS
        $label = "Disk Health Status"
        $status = $this.CallActiveDirectoryAPI('GetDiskHealthStatus', $null)
        $status = $status.HealthStatus
        if (!$status) {
            throw "Unable to retrieve data. Ensure all required services are running."
        }
        switch ($status) {
            'Healthy' {$metricStatus = $this.OK_STATUS}
            'Warning' {$metricStatus = $this.WARNING_STATUS}
            'Unhealthy' {$metricStatus = $this.CRITICAL_STATUS}
        }
        $this.CheckExit($metricStatus, $label, $status)
    }

    [void] GetOperationalStatus() {
        $metricStatus = $this.UNKNOWN_STATUS
        $label = 'Disk Operational Status'
        $status = $this.CallActiveDirectoryAPI('GetDiskHealthStatus', $null)
        $status = $status.OperationalStatus
        if (!$status) {
            throw "Unable to retrieve data. Database disk operational status check is not supported on AD versions 2012 and below."
        }
        switch ($status) {
            'OK' {$metricStatus = $this.OK_STATUS}
            'Degraded' {$metricStatus = $this.WARNING_STATUS}
            'Read-only' {$metricStatus = $this.CRITICAL_STATUS}
        }
        $this.CheckExit($metricStatus, $label, $status)
    }

    [void] GetServiceStatus() {
        $metricStatus = $this.UNKNOWN_STATUS
        $label = "Active Directory Services Status"
        $status = $this.CallActiveDirectoryAPI('GetADServiceStatus', $null)
        if (!$status) {
            throw "Unable to retrieve data. Ensure all required services are running."
        }
        $status = $status.Status.toString()
        switch ($status) {
            'Running' {$metricStatus = $this.OK_STATUS}
            'Stopped' {$metricStatus = $this.CRITICAL_STATUS}
        }
        $this.CheckExit($metricStatus, $label, $status)
    }

    [void] GetFileSize() {
        $label = "File Size"
        $fileSizeData = $this.CallActiveDirectoryAPI('GetDBFileSize', $null)
        if (!$fileSizeData -or $fileSizeData.Length -lt 1) {
            throw "Unable to retrieve data. Ensure all required services are running."
        }
        $size = $fileSizeData[1].replace(' ', '')
        $name = $fileSizeData[0].split('\')[-1]
        $size = $this.ConvertValue($size)
        $convertedLabel = $this.ConvertLabel($label)
        $thresholds = $this.GetThresholds(0, $convertedLabel)
        $script:Check.AddMetric(@{Name =  $convertedLabel; Value = $size; UOM = $this.Unit;
            WarningThreshold = $thresholds['warning']; CriticalThreshold = $thresholds['critical'];
            DisplayName = $label; DisplayFormat = "Active Directory Database File ($name), {name} is {value}{unit}"})
    }
}

Function Get-ConvertedMetric($Value) {
    return [Metric]::ConvertValue($Value, 'B', 2, $false)
}


class ModeUsage {
    [string] $MetricType
    [string] $MetricInfo
    [string[]] $ArgumentsOptional
    [string[]] $ArgumentsRequired
    [string] $Unit
    [string] $Interval
    [string] $PluginClass
    [HashTable] $ThresholdsWarnings
    [HashTable] $ThresholdsCritical

    ModeUsage ($MetricType, $MetricInfo, $ArgumentsOptionalList, $ArgumentsRequiredList, $Unit, $Interval,
        $PluginClass, $ThresholdsWarningsDict, $ThresholdsCriticalDict) {
        $this.MetricType = $MetricType
        $this.MetricInfo = $MetricInfo
        $this.ArgumentsOptional = $ArgumentsOptionalList
        $this.ArgumentsRequired = $ArgumentsRequiredList
        $this.Unit = $Unit
        $this.Interval = $Interval
        $this.PluginClass = $PluginClass
        $this.ThresholdsWarnings = $ThresholdsWarningsDict
        $this.ThresholdsCritical = $ThresholdsCriticalDict
    }
}


class ResourceVariable {
    [string] $Name
    [string] $DefaultValue
    [ResourceArgument[]] $Arguments

    ResourceVariable ($Name, $DefaultValue, $Arguments) {
        $this.name = $Name
        $this.defaultValue = $DefaultValue
        $this.arguments = $Arguments
    }
}


class ResourceArgument {
    [string] $LongParam
    [string] $Help
    [string] $ResourceKey
    [string] $Value
    [boolean] $IsRequired

    ResourceArgument ($LongParam, $Help, $ResourceKey) {
        $this.LongParam = $LongParam
        $this.Help = $Help
        $this.ResourceKey = $ResourceKey
    }
}

$MODE_MAPPING = @{
    'AD.Replication.IOBytesRate' = [ModeUsage]::New(
        'perf', 'Inbound Bytes Rate,Outbound Bytes Rate;\DirectoryServices(*)\DRA Inbound Bytes Total/sec,\DirectoryServices(*)\DRA Outbound Bytes Total/sec',
        @(''), @(''),
        'Bps', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Replication.IOObjectsRate' = [ModeUsage]::New(
        'perf', 'Inbound Objects Rate,Outbound Objects Rate;\DirectoryServices(*)\DRA Inbound Objects Applied/sec,\DirectoryServices(*)\DRA Outbound Objects/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Replication.IOValuesRate' = [ModeUsage]::New(
        'perf', 'Inbound Values Rate,Outbound Values Rate;\DirectoryServices(*)\DRA Inbound Values Total/sec,\DirectoryServices(*)\DRA Outbound Values Total/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Replication.Synchronizations' = [ModeUsage]::New(
        'perf', 'Pending Replication Synchronizations;\DirectoryServices(*)\DRA Pending Replication Synchronizations',
        @(''), @(''),
        '', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.ClientBindsRate' = [ModeUsage]::New(
        'perf', 'Client Binds Rate;\DirectoryServices(*)\DS Client Binds/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.DirectoryIORate' = [ModeUsage]::New(
        'perf', 'Directory Reads Rate,Directory Writes Rate;\DirectoryServices(*)\DS Directory Reads/sec,\DirectoryServices(*)\DS Directory Writes/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.DirectorySearches' = [ModeUsage]::New(
        'perf', 'Directory Searches Rate;\DirectoryServices(*)\DS Directory Searches/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.LDAPBindTime' = [ModeUsage]::New(
        'perf', 'LDAP Bind Time;\DirectoryServices(*)\LDAP Bind Time',
        @(''), @(''),
        'ms', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.LDAPClientSessions' = [ModeUsage]::New(
        'perf', 'LDAP Client Sessions;\DirectoryServices(*)\LDAP Client Sessions',
        @(''), @(''),
        '', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.LDAPSearches' = [ModeUsage]::New(
        'perf', 'LDAP Searches;\DirectoryServices(*)\DS % Searches from LDAP',
        @(''), @(''),
        '%', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.LDAPSearchesRate' = [ModeUsage]::New(
        'perf', 'LDAP Searches Rate;\DirectoryServices(*)\LDAP Searches/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.LDAPSuccessfulBindsRate' = [ModeUsage]::New(
        'perf', 'LDAP Successful Binds Rate;\DirectoryServices(*)\LDAP Successful Binds/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.LDAPWrites' = [ModeUsage]::New(
        'perf', 'LDAP Writes;\DirectoryServices(*)\DS % Writes from LDAP',
        @(''), @(''),
        '%', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.LDAPWritesRate' = [ModeUsage]::New(
        'perf', 'LDAP Writes Rate;\DirectoryServices(*)\LDAP Writes/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.KC.IO' = [ModeUsage]::New(
        'perf', 'KCC Directory Reads,KCC Directory Writes;\DirectoryServices(*)\DS % Reads from KCC,\DirectoryServices(*)\DS % Writes from KCC',
        @(''), @(''),
        '%', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.LSA.IO' = [ModeUsage]::New(
        'perf', 'LSA Directory Reads,LSA Directory Writes;\DirectoryServices(*)\DS % Reads from LSA,\DirectoryServices(*)\DS % Writes from LSA',
        @(''), @(''),
        '%', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.NSPI.IO' = [ModeUsage]::New(
        'perf', 'NSPI Directory Reads, NSPI Directory Writes;\DirectoryServices(*)\DS % Reads from NSPI,\DirectoryServices(*)\DS % Writes from NSPI',
        @(''), @(''),
        '%', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Services.ADWS' = [ModeUsage]::New(
        'custom', 'GetServiceStatus;1',
        @(''), @(''),
        '', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Threads.AsynchronousThreadQueue' = [ModeUsage]::New(
        'perf', 'Total Threads;\DirectoryServices(*)\ATQ Threads Total',
        @(''), @(''),
        '', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Threads.LDAPAsynchronousThreadQueue' = [ModeUsage]::New(
        'perf', 'LDAP Threads;\DirectoryServices(*)\ATQ Threads LDAP',
        @(''), @(''),
        '', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.AddressBook.ClientSessions' = [ModeUsage]::New(
        'perf', 'Client Sessions;\DirectoryServices(*)\AB Client Sessions',
        @(''), @(''),
        '', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.AddressBook.BrowsesRate' = [ModeUsage]::New(
        'perf', 'Browses Rate;\DirectoryServices(*)\AB Browses/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.AddressBook.LookupsRate' = [ModeUsage]::New(
        'perf', 'Lookups Rate;\DirectoryServices(*)\AB Proxy Lookups/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.AddressBook.PropertyReadsRate' = [ModeUsage]::New(
        'perf', 'Reads Rate;\DirectoryServices(*)\AB Property Reads/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.AddressBook.SearchesRate' = [ModeUsage]::New(
        'perf', 'Searches Rate;\DirectoryServices(*)\AB Searches/sec',
        @(''), @(),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.SAM.ReadsWrites' = [ModeUsage]::New(
        'perf', 'Directory Reads,Directory Writes;\DirectoryServices(*)\DS % Reads from SAM,\DirectoryServices(*)\DS % Writes from SAM',
        @(''), @(''),
        '%', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.SAM.ComputerCreationsRate' = [ModeUsage]::New(
        'perf', 'Successful Computer Creations Rate;\DirectoryServices(*)\SAM Successful Computer Creations/sec: Includes all requests',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.SAM.MachineCreationAttemptsRate' = [ModeUsage]::New(
        'perf', 'Machine Creation Attempts Rate;\DirectoryServices(*)\SAM Machine Creation Attempts/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.SAM.PasswordChangesRate' = [ModeUsage]::New(
        'perf', 'Password Changes Rate;\DirectoryServices(*)\SAM Password Changes/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.SAM.UserCreationsRate' = [ModeUsage]::New(
        'perf', 'Successful User Creations Rate;\DirectoryServices(*)\SAM Successful User Creations/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.SAM.GlobalCatalogEvaluationsRate' = [ModeUsage]::New(
        'perf', 'GC Evaluations Rate;\DirectoryServices(*)\SAM GC Evaluations/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.SAM.UserCreationAttemptsRate' = [ModeUsage]::New(
        'perf', 'User Creation Attempts Rate;\DirectoryServices(*)\SAM User Creation Attempts/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.DNS.TotalQueries' = [ModeUsage]::New(
        'perf', 'Total,Total UDP, Total TCP;\DNS\Total Query Received,\DNS\UDP Query Received,\DNS\TCP Query Received',
        @(''), @(''),
        '', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.DNS.QueriesRate' = [ModeUsage]::New(
        'perf', 'Total Queries Rate,UDP Rate,TCP Rate;\DNS\Total Query Received/sec,\DNS\UDP Query Received/sec,\DNS\TCP Query Received/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.DNS.RecursiveQueriesRate' = [ModeUsage]::New(
        'perf', 'Recursive Queries Rate,Timeout Rate,Failure Rate;\DNS\Recursive Queries/sec,\DNS\Recursive TimeOut/sec,\DNS\Recursive Query Failure/sec',
        @(''), @(''),
        'per_second', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Database.DiskUsage' = [ModeUsage]::New(
        'custom', 'GetVolumeSize;1',
        @(''), @(''),
        '%', '300', 'ActiveDirectory',
        @{  'database_disk_usage' = '70';  },
        @{  'database_disk_usage' = '90';  }
    )
    'AD.Database.OperationalStatus' = [ModeUsage]::New(
        'custom', 'GetOperationalStatus;1',
        @(''), @(''),
        '', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Database.HealthStatus' = [ModeUsage]::New(
        'custom', 'GetHealthStatus;1',
        @(''), @(''),
        '', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
    'AD.Database.FileSize' = [ModeUsage]::New(
        'custom', 'GetFileSize;1',
        @(''), @(''),
        'B', '300', 'ActiveDirectory',
        @{  },
        @{  }
    )
}

$RESOURCE_VARIABLES = @(
    [ResourceVariable]::New('KERBEROS_REALM', '', @(
        )),
    [ResourceVariable]::New('AD_CREDENTIALS', '', @(
            [ResourceArgument]::New('Username',
                'Username for remote windows host e.g user@DOMAIN.COM',
                'AD_USERNAME'),
            [ResourceArgument]::New('Password',
                'Password for remote windows host',
                'AD_PASSWORD'),
            [ResourceArgument]::New('Authentication',
                'Authentication type to use',
                'AD_AUTHENTICATION')
        )) 
)

function RunCheck([boolean] $Verbose, [string] $Hostname, [Modeusage] $ModeUsage, [HashTable] $ModeArgs) {
    try {
        $checkClass = New-Object -Type $ModeUsage.PluginClass -ArgumentList $Verbose, $Hostname, $ModeUsage.ThresholdsWarnings,
                            $ModeUsage.ThresholdsCritical, $modeUsage.Unit, $ModeUsage.MetricType, $ModeUsage.MetricInfo, $ModeArgs
    } catch {
        throw $_.Exception.InnerException.InnerException
    }
    $checkClass.check()
}

function GetModeUsage() {
    $modeUsage = $MODE_MAPPING[$Mode]
    if (!$modeUsage) {
        throw [ParamError]::New(("Unknown mode: {0}`nValid modes:`n`t{1}" -f $Mode,
                ($MODE_MAPPING.Keys -join "`n`t")))
    }
    return $modeUsage
}

function GetModeArgs([ModeUsage] $ModeUsage) {
    $allVariableArgs = @()
    foreach ($variable in $RESOURCE_VARIABLES) {
        foreach ($arg in $variable.arguments) {
            $allVariableArgs += $arg
        }
    }
    $modeArgs = @()
    foreach ($arg in $allVariableArgs) {
        if ($ModeUsage.argumentsRequired.Contains($arg.resourceKey)) {
            $arg.isRequired = $true
            $modeArgs += $arg
        } elseif ($ModeUsage.argumentsOptional.Contains($arg.resourceKey)) {
            $arg.isRequired = $false
            $modeArgs += $arg
        }
    }
    return $modeArgs
}

function GetArgs($ModeArgs, $Warning, $Critical) {
    $arguments = @{}
    foreach ($arg in $ModeArgs) {
        $value = (Get-Variable $arg.longParam -ErrorAction 'Ignore').Value
        if ($arg.isRequired -and !$value) {
            throw [ParamError]::New(("Error parsing arguments: the required flag '-{0}' was not specified" -f $arg.longParam))
        }
        $arguments.Add($arg.longParam, $value)
    }

    if ($Warning) {
        $arguments.warning = $Warning
    }
    if ($Critical) {
        $arguments.critical = $Critical
    }
    return $arguments
}

function Main {
    if ($help) {
        CreateCheckObj
        if ($mode) {
            $modeUsage = GetModeUsage
            $modeArgs = GetModeArgs $modeUsage

            $optional = "Optional arguments:
        -v, -Verbose
            Verbose mode - always display all output
        -w, -Warning
            The warning levels (comma separated)
        -c, -Critical
            The critical levels (comma separated) `n"

            $required = "Required arguments:
            -n, -Hostname
                Hostname of the host to monitor"

            foreach ($arg in $modeArgs) {
                $text = "-{0}`n`t{1}`n    " -f $arg.longParam, $arg.help
                if ($arg.isRequired) {
                    $required += $text
                } else {
                    $optional += $text
                }
            }
            $description = "{0} mode arguments:`n`n{1}`n{2}`n" -f $mode, $optional, $required
            $script:check.HelpText($description)
        } else {
            $script:check.HelpText()
        }
    }

    $verbose = $VerbosePreference -ne [System.Management.Automation.ActionPreference]::SilentlyContinue

    if (!$mode) {
        throw [ParamError]::new("Error parsing arguments: the required flag '-m/-Mode' was not specified")
    }
    #if (!$hostname) {
    #    throw [ParamError]::new("Error parsing arguments: the required flag '-n/-Hostname' was not specified")
    #}

    $modeUsage = GetModeUsage
    $modeArgs = GetModeArgs $modeUsage
    $arguments = GetArgs -ModeArgs $modeArgs -Warning $warning -Critical $critical

    RunCheck -Verbose $verbose -Hostname $hostname -ModeUsage $modeUsage -ModeArgs $arguments
}

try {
    Main
}catch [ParamError] {
    Write-Output $_.Exception.ErrorMessage
    exit(3)
}catch {
    Write-Output  $_.Exception.Message
    exit(3)
}
