param(
    [Alias("h")][Switch] $help,
    [Alias("m")][String] $mode,
    [Alias("w")][String] $warning,
    [Alias("c")][String] $critical,
    [Alias("n")][String] $hostname,
    [String] $Queue,
    [String] $InactiveComponents,
    [String] $InactiveServices,
    [String] $Transport,
    [String] $Username,
    [String] $Password,
    [String] $Scheme,
    [Parameter(ValueFromRemainingArguments = $true)] $remainingArguments
)

class Metric {
    [string] $Name
    [string] $Value
    [string] $UOM
    [string] $Warning
    [string] $Critical
    [string] $ExitCode
    [string] $BoundaryMessage
    [string] $Summary
    [boolean] $DisplayInPerf

    [void] Init ($Name, $Value, $UOM, $Warning, $Critical, $DisplayInPerf, $ExitCode, $BoundaryMessage, $Summary) {
        $this.Name = $Name
        $this.Value = $Value
        $this.UOM = $UOM
        $this.Warning = $Warning
        $this.Critical = $Critical
        $this.ExitCode = $ExitCode
        $this.BoundaryMessage = $BoundaryMessage
        $this.Summary = $Summary
        $this.DisplayInPerf = $DisplayInPerf
    }

    Metric ($Name, $Value, $UOM, $Warning, $Critical, $DisplayInPerf, $ExitCode, $BoundaryMessage, $Summary) {
        $this.Init($Name, $Value, $UOM, $Warning, $Critical, $DisplayInPerf, $ExitCode, $BoundaryMessage, $Summary)
    }

    Metric ($Name, $Value, $UOM, $Warning, $Critical, $DisplayInPerf, $ExitCode, $BoundaryMessage) {
        $this.Init($Name, $Value, $UOM, $Warning, $Critical, $DisplayInPerf, $ExitCode, $BoundaryMessage, $null)
    }

    Metric ($Name, $Value, $UOM, $Warning, $Critical, $DisplayInPerf) {
        $this.Init($Name, $Value, $UOM, $Warning, $Critical, $DisplayInPerf, $null, $null, $null)
    }

    Metric ($Name, $Value, $UOM, $Warning, $Critical) {
        $this.Init($Name, $Value, $UOM, $Warning, $Critical, $true, $null, $null, $null)
    }
}

class Plugin {
    [string] $Name
    [string] $Version
    [string] $Preamble
    [string] $Description
    [string] $StateType

    [System.Collections.ArrayList] $metric
    [int] $minimumExitCode
    [int] $incre

    [void] Init ([string]$Name, [string]$Version, [string]$Preamble, [string]$Description, [string]$StateType) {
        $this.metric = @()
        $this.minimumExitCode = 0
        $this.incre = -1

        $this.Name = $Name
        $this.Version = $Version
        $this.Preamble = $Preamble
        $this.Description = $Description
        $this.StateType = $StateType
    }

    Plugin ([string]$Name, [string]$Version, [string]$Preamble, [string]$Description, [string]$StateType) {
        $this.Init($Name, $Version, $Preamble, $Description, $StateType)
    }

    Plugin ([string]$Name, [string]$Version, [string]$Preamble, [string]$Description) {
        $this.Init($Name, $Version, $Preamble, $Description, "METRIC")
    }

    [void] HelpText ($description) {
        Write-Host "$($this.Name) $($this.Version)`n"
        Write-Host "$($this.Preamble)`n"
        Write-Host "Usage:`n`t$($this.Name) [OPTIONS]`n"
        Write-Host "Default Options:`n`t-h`tShow this help message`n"
        Write-Host "$description`n"
        exit 3
    }

    [void] HelpText () {
        $this.helpText($this.Description)
    }

    [void] AddMetric ($name, $value, $UOM, $warning, $critical, $displayInPerf) {
        $this.incre++
        if ([string]::IsNullOrEmpty($warning) -and [string]::IsNullOrEmpty($critical)) {
            $exitCode = 0
        }
        else {
            $exitCode = $this.evaluate($value, $warning, $critical)
        }

        [string]$boundaryMessage = ""
        if ($exitCode -eq 1) {
            $boundaryMessage = " (outside $warning)"
        }
        elseif ($exitCode -eq 2) {
            $boundaryMessage = " (outside $critical)"
        }
        if ($this.incre -eq 0) {
            $this.metric = New-Object System.Collections.ArrayList
        }

        $metric_data = [Metric]::new($name, $value, $UOM, $warning, $critical, $displayInPerf, $exitCode, `
                                     $boundaryMessage)
        $this.metric.Add($metric_data)
    }

    [void] AddMessage ([string]$message) {
        $this.metric[$this.incre].Summary = $message
    }

    [float] GetCounter ([string]$metricLocation) {
        $proc = ""
        try {
            $proc = Get-Counter $metricLocation -ErrorAction Stop
        }
        catch {
            $this.exitUnknown("Counter not found check path location")
        }
        $returnMetric = [math]::Round(($proc.readings -split ":")[-1], 2)
        return $returnMetric
    }

    [Object] GetCounterObject ([string]$metricLocation) {
        $proc = ''
        try {
            $proc = Get-Counter $metricLocation -ErrorAction SilentlyContinue
        }
        catch {
            $this.exitUnknown("Counter not found check path location")
        }
        return $proc
    }

    [Object] GetCounterObject ([string]$metricLocation, [int]$max_samples, [int]$sample_interval) {
        $proc = ''
        try {
            $proc = Get-Counter $metricLocation -ErrorAction SilentlyContinue -MaxSamples $max_samples `
                                                -SampleInterval $sample_interval
        }
        catch {
            $this.exitUnknown("Counter not found check path location")
        }
        return $proc
    }

    [void] Final () {
        $worstCode = $this.overallStatus()
        [string]$Output = $this.StateType + " " + $this.getStatus($worstCode) + " - "

        for ($i = 0; $i -le $this.incre; $i++) {
            if ($this.metric[$i].Summary) {
                $Output += $this.metric[$i].Summary
            }
            else {
                $Output += ($this.metric[$i].Name + " is " + $this.metric[$i].Value + $this.metric[$i].UOM `
                        + $this.metric[$i].BoundaryMessage)
            }
            if ($i -le $this.incre - 1) {
                $Output += ", "
            }
        }

        $Output += " | "
        for ($i = 0; $i -le $this.incre; $i++) {
            if (!$this.metric[$i].DisplayInPerf) {
                continue
            }
            $MetricName = $this.metric[$i].Name.Replace(' ', '_').Replace("'", '').ToLower()
            $Output += ($MetricName + "=" + $this.metric[$i].Value + $this.metric[$i].UOM + ";" `
                    + $this.metric[$i].Warning + ";" + $this.metric[$i].Critical)
            if ($i -le $this.incre - 1) {
                $Output += " "
            }
        }
        $this.incre = -1
        Write-Host $Output
        exit $worstCode
    }

    [int] OverallStatus () {
        [int]$worstStatus = $this.minimumExitCode
        for ($i = 0; $i -le $this.incre; $i++) {
            if ($this.metric[$i].ExitCode -gt $worstStatus) {
                $worstStatus = $this.metric[$i].ExitCode
            }
        }
        return $worstStatus
    }

    [string] Evaluate ([float] $value, $warning, $critical) {
        $returnCode = 0
        if ($warning) {
            $warningThreshold = $this.ParseThreshold($warning)
            if ($this.EvaluateThreshold($value, $warningThreshold.start, $warningThreshold.end,
                                        $warningThreshold.checkOutsideRange)) {
                $returnCode = 1
            }
        }

        if ($critical) {
            $criticalThreshold = $this.ParseThreshold($critical)
            if ($this.EvaluateThreshold($value, $criticalThreshold.start, $criticalThreshold.end,
                                        $criticalThreshold.checkOutsideRange)) {
                $returnCode = 2
            }
        }
        return $returnCode
    }

    [boolean] EvaluateThreshold ($value, $start, $end, $checkOutsideRange) {
        try {
            $value = [float]::Parse($value)
            $start = [float]::Parse($start)
            $end = [float]::Parse($end)
        } catch {
            $this.exitUnknown("Invalid metric threshold")
        }
        $isOutsideRange = $value -lt $start -or $value -gt $end
        if ($checkOutsideRange) {
            return $isOutsideRange
        }
        return !$isOutsideRange
    }

    [HashTable] ParseThreshold ($threshold) {
        # Parse threshold and return the range and whether we alert if value is out of range or in the range.
        # See: https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
        $return = @{ }
        $return.checkOutsideRange = $true
        try {
            if ($threshold.StartsWith('@')) {
                $return.checkOutsideRange = $false
                $threshold = $threshold.Substring(1)
            }
            if (!$threshold.Contains(':')) {
                $return.start = 0
                $return.end = if ($threshold -eq '~') { [int]::MaxValue } else { $threshold }
            } elseif ($threshold.EndsWith(':')) {
                $threshold = $threshold.Substring(0, $threshold.Length - 1)
                $return.start = if ($threshold -eq '~') { [int]::MinValue } else { $threshold }
                $return.end = [int]::MaxValue
            } else {
                $start, $end = $threshold.Split(':')
                $return.start = if ($start -eq '~') { [int]::MinValue } else { $start }
                $return.end = if ($end -eq '~') { [int]::MaxValue } else { $end }
            }
        } catch {
            $this.exitUnknown("Invalid metric threshold: '$threshold'")
        }
        return $return
    }

    [int] SetExitCode ([string]$returnCode) {
        if ($returnCode -eq "OK") {
            $exitCode = 0
        }
        elseif ($returnCode -eq "WARNING") {
            $exitCode = 1
        }
        elseif ($returnCode -eq "CRITICAL") {
            $exitCode = 2
        }
        else {
            $exitCode = 3
        }
        return $exitCode
    }

    [string] GetStatus ([int]$exitCode) {
        $Status = ""
        if ($exitCode -eq 0) {
            $Status = "OK"
        }
        elseif ($exitCode -eq 1) {
            $Status = "WARNING"
        }
        elseif ($exitCode -eq 2) {
            $Status = "CRITICAL"
        }
        elseif ($exitCode -eq 3) {
            $Status = "UNKNOWN"
        }
        else {
            $this.exitUnknown("Something has gone wrong, check getStatus method")
        }
        return $Status
    }

    [void] ExitOK ([string]$errorMessage) {
        Write-Host "$($this.StateType) OK - $errorMessage"
        exit 0
    }

    [void] ExitWarning ([string]$errorMessage) {
        Write-Host "$($this.StateType) WARNING - $errorMessage"
        exit 1
    }

    [void] ExitCritical ([string]$errorMessage) {
        Write-Host "$($this.StateType) CRITICAL - $errorMessage"
        exit 2
    }

    [void] ExitUnknown ([string]$errorMessage) {
        Write-Host "$($this.StateType) UNKNOWN - $errorMessage"
        exit 3
    }

    [void] Warning () {
        $this.minimumExitCode = 1
    }

    [void] Critical () {
        $this.minimumExitCode = 2
    }

}

$ErrorActionPreference = "Stop"

class Exchange {

    [Plugin] $Check
    [boolean] $verbose
    [System.Management.Automation.Runspaces.PSSession] $Session
    [string] $Hostname
    [string] $Unit
    [string] $MetricMethod
    [Array] $Warning
    [Array] $Critical
    [HashTable] $DefaultWarning
    [HashTable] $DefaultCritical
    [HashTable] $ModeArgs
    [HashTable] $MetricInfo
    [int] $NumThresholds

    Exchange([Plugin]$check, [boolean]$verbose, [string]$hostname,
             [System.Management.Automation.Runspaces.PSSession]$session,
             [HashTable]$thresholdsWarning, [HashTable]$thresholdsCritical, [string]$unit,
             [string]$metricType, [string]$metricInfo, [HashTable]$modeArgs) {

        $this.Check = $check
        $this.Verbose = $verbose
        $this.Hostname = $hostname
        $this.Session = $session
        $this.ModeArgs = $modeArgs
        $this.Unit = $unit

        $this.NumThresholds = 0
        if ($metricType -eq 'custom') {
            $this.MetricMethod = $metricInfo
            switch ($this.MetricMethod) {
                'MSExchangeDatabaseDiskSpace' {
                    $this.NumThresholds = 1
                    break
                }
                'MSExchangeLdapSearchTime' {
                    $this.NumThresholds = 1
                    break
                }
                'MSExchangeMailflowMessageLatency' {
                    $this.NumThresholds = 1
                    break
                }
                default {
                    $this.NumThresholds = 0
                }
            }
        } elseif ($metricType -eq 'connectivity') {
            $this.MetricMethod = 'MSExchangeConnectivityStatus'
            $this.MetricInfo = $this.ParseMetricInfo($metricInfo)
        } elseif ($metricType -eq 'perf') {
            $this.MetricMethod = 'MSExchangePerf'
            $this.MetricInfo = $this.ParseMetricInfo($metricInfo)
            $this.NumThresholds = $this.metricInfo.labels.Count
        } elseif ($metricType -eq 'multiperf') {
            $this.MetricMethod = 'MSExchangeMultiPerf'
            $this.MetricInfo = $this.ParseMetricInfo($metricInfo)
            $this.NumThresholds = $this.metricInfo.labels.Count
        } else {
            throw [CheckExitUnknown]::New("$metricType not implemented")
        }

        $this.DefaultWarning = $thresholdsWarning
        $this.DefaultCritical = $thresholdsCritical

        if ($modeArgs.warning) {
            $this.Warning = $modeArgs.warning.Split(',') | ForEach-Object { $_.Trim() }
            if ($this.Warning.Length -ne $this.NumThresholds) {
                throw [CheckExitUnknown]::New("Number of warning thresholds provided must match number of metrics")
            }
        }
        if ($modeArgs.critical) {
            $this.Critical = $modeArgs.critical.Split(',') | ForEach-Object { $_.Trim() }
            if ($this.Critical.Length -ne $this.NumThresholds) {
                throw [CheckExitUnknown]::New("Number of critical thresholds provided must match number of metrics")
            }
        }
    }

    [HashTable] ParseMetricInfo ($metricInfo) {
        $metrics = @{}

        [Array] $info = $metricInfo.Split(';')
        if ($info.Length -ne 2) {
            throw [CheckExitUnknown]::New("Malformed metric info string: '$metricInfo'")
        }

        [Array] $labels = $info[0].Split(',') | ForEach-Object {$_.Trim() }
        [Array] $counters = $info[1].Split(',') | ForEach-Object { $_.Trim() }

        $metrics.labels = $labels
        $metrics.counters = $counters

        return $metrics
    }

    [HashTable] GetThresholds($position, $label) {
        $thresholds = @{}

        $thresholds.warning = ''
        if ($this.Warning) {
            $thresholds.warning = $this.Warning[$position]
        } elseif ($this.DefaultWarning.ContainsKey($label)) {
            $thresholds.warning = $this.DefaultWarning[$label]
        }

        $thresholds.critical = ''
        if ($this.Critical) {
            $thresholds.critical = $this.Critical[$position]
        } elseif ($this.DefaultCritical.ContainsKey($label)) {
            $thresholds.critical = $this.DefaultCritical[$label]
        }

        return $thresholds
    }

    [string] ConvertLabel([string]$label) {
        return $label.ToLower().Replace(' ', '_').Replace("'", '')
    }

    [string] ConvertCamelCaseToPerfLabel([string]$string) {
        $newString = ""
        $stringChars = $string.GetEnumerator()
        $charIndex = 0
        foreach ($char in $stringChars) {
            if ([char]::IsUpper($char) -and $charIndex -gt 0) {
                $newString = $newString + "_" + $char.ToString().ToLower()
            } elseif ($charIndex -eq 0) {
                $newString = $newString + $char.ToString().ToLower()
            } else {
                $newString = $newString + $char.ToString()
            }
            $charIndex++
        }
        return $newString.Replace(' ', '')
    }

    [string] ConvertTo2DP($num) {
        return [Math]::Round($num, 2)
    }

    [string] GetLatency($latency) {
        if ($latency -isnot [int64] -and $latency -isnot [int32]) {
            $latency = ([TimeSpan] $latency).TotalMilliseconds
        }
        return $latency
    }

    [string] GetPerfDataString($metrics) {
        $perf = New-Object System.Collections.ArrayList
        foreach ($metric in $metrics) {
            $convertedLabel = $this.ConvertLabel($metric.Name)
            $warningString = ""
            $criticalString = ""
            if ($metric.Warning) {
                $warningString = ";{0}" -f $metric.Warning
            }
            if ($metric.Critical) {
                $criticalString = ";{0}" -f $metric.Critical
            }
            $perf.Add(("{0}={1}{2}{3}{4}" -f $convertedLabel, $metric.Value, $metric.UOM, `
                                             $warningString, $criticalString))
        }
        return $perf -join " "
    }

    [void] MSExchangeServiceStates() {
        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010
        $servicesHealth = Test-ServiceHealth

        [array] $expectedInactives = @()
        if ($this.ModeArgs.inactiveServices) {
            [array] $expectedInactives = $this.ModeArgs.inactiveServices.ToLower().Replace(' ', '').Split(',')
        }

        $services = @{
            'active' = @{}
            'inactive' = @{}
            'expected' = @{}
        }

        foreach ($item in $servicesHealth) {
            foreach ($service in $item.ServicesNotRunning) {
                if ($expectedInactives.Contains($service.ToLower())) {
                    if (!$services.expected.ContainsKey($item.Role)) {
                        $services.expected.Add($item.Role, (New-Object System.Collections.ArrayList))
                    }
                    $services.expected[$item.Role].Add($service) > $null
                } else {
                    if (!$services.inactive.ContainsKey($item.Role)){
                        $services.inactive.Add($item.Role, (New-Object System.Collections.ArrayList))
                    }
                    $services.inactive[$item.Role].Add($service) > $null
                }
            }
            foreach ($service in $item.ServicesRunning) {
                if (!$services.active.ContainsKey($item.Role)){
                    $services.active.Add($item.Role, (New-Object System.Collections.ArrayList))
                }
                $services.active[$item.Role].Add($service) > $null
            }
        }

        $counts = @{
            'active' = 0
            'inactive' = 0
            'expected' = 0
        }

        $summaries = @{
            'active' = "`n`nActive services:"
            'inactive' = "`n`nInactive services:"
            'expected' = "`n`nExpected inactive services:"
        }

        foreach ($serviceHealthType in $services.Keys) {
            $list = New-Object System.Collections.ArrayList
            foreach ($role in $services[$serviceHealthType].Keys) {
                $list += ($services[$serviceHealthType][$role])
                $summaries[$serviceHealthType] += "`n {0}: {1}" -f $role,
                                                                   ($services[$serviceHealthType][$role] -join ', ')
            }
            $counts[$serviceHealthType] = ($list | Sort-Object | Get-Unique | Measure-Object).Count
        }

        if ($counts.expected -eq 0) {
            $summaries.expected = ""
        }
        if ($counts.active -eq 0) {
            $summaries.active = ""
        }

        if ($counts.inactive) {
            $totalInactive = $counts.inactive + $counts.expected
            $summary = "{0} required services are not running" -f $totalInactive
            if ($counts.expected -gt 0) {
                $summary += " ({0} expected inactive)" -f $counts.inactive
            }
            if ($this.verbose) {
                $summary += ", {0} required services are running: {1}{2}{3}" -f $counts.active,
                                                                                $summaries.inactive,
                                                                                $summaries.expected,
                                                                                $summaries.active
            } else {
                $summary += ": {0}" -f $summaries.inactive
            }
            throw [CheckExitCritical]::New($summary)
        }

        $summary = "All required services are running"
        if ($counts.expected -gt 0) {
            $summary += " ({0} expected inactive)" -f $counts.expected
        }
        if ($this.verbose) {
            $summary += ": {0}{1}" -f $summaries.expected, $summaries.active
        }
        throw [CheckExitOK]::New($summary)
    }

    [void] MSExchangeComponentStates() {
        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010
        $componentStates = Get-ServerComponentState -Identity $this.hostname
        $components = @{
            'active' = New-Object System.Collections.ArrayList
            'inactive' = New-Object System.Collections.ArrayList
            'expected' = New-Object System.Collections.ArrayList
        }

        [array] $expectedInactives = @()
        if ($this.ModeArgs.inactiveComponents) {
            [array] $expectedInactives = $this.ModeArgs.inactiveComponents.ToLower().Replace(' ', '').Split(',')
        }

        foreach ($component in $componentStates) {
            if ($component.State -eq 'Inactive') {
                if ($expectedInactives.Contains($component.Component.ToLower())) {
                    $components.expected.Add($component) > $null
                } else {
                    $components.inactive.Add($component) > $null
                }
            } else {
                $components.active.Add($component) > $null
            }
        }

        $summaries = @{
            'active' = "`n`nActive components: {0}" -f ($components.active.Component -join ', ')
            'inactive' = "`n`nInactive components: {0}" -f ($components.inactive.Component -join ', ')
            'expected' = "`n`nExpected inactive components: {0}" -f ($components.expected.Component -join ', ')
        }

        if ($components.expected.Count -eq 0) {
            $summaries.expected = ""
        }
        if ($components.active.Count -eq 0) {
            $summaries.active = ""
        }

        $summary = ""
        if ($components.inactive) {
            $totalInactive = $components.inactive.Count + $components.expected.Count
            $summary = "{0} components are inactive" -f $totalInactive
            if ($components.expected.Count -gt 0) {
                $summary += " ({0} expected inactive)" -f $components.expected.count
            }
            if ($this.verbose) {
                $summary += ", {0} components are active: {1}{2}{3}" -f $components.active.Count, $summaries.inactive,
                                                                        $summaries.expected, $summaries.active
            } else {
                $summary += " ({0})" -f ($components.inactive.Component -join ', ')
            }
            throw [CheckExitCritical]::New($summary)
        }

        $summary = "All expected components are active"
        if ($components.expected.Count -gt 0) {
            $summary += " ($($components.expected.Count) expected inactive)"
        }
        if ($this.verbose) {
            $summary += ": {0}{1}" -f $summaries.expected, $summaries.active
        }
        throw [CheckExitOK]::New($summary)
    }

    [void] MSExchangeMailflowStatus() {
        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010
        $result = Test-Mailflow -TargetMailboxServer $this.hostname -ExecutionTimeout:60 
        if ($result.TestMailflowResult -ne 'Success') {
            $summary = "Mailflow test failed"
            throw [CheckExitCritical]::New($summary)
        }

        $summary = "Mailflow test successful"
        throw [CheckExitOK]::New($summary)
    }

    [Array] MSExchangeMailflowMessageLatency() {
        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010
        $result = Test-Mailflow -TargetMailboxServer $this.hostname -ExecutionTimeout:60

        if ($result.TestMailflowResult -ne 'Success') {
            $summary = "Mailflow test failed"
            throw [CheckExitUnknown]::New($summary)
        }
        $messageLatency = ([TimeSpan]$result.MessageLatencyTime).TotalSeconds
        $value = $this.ConvertTo2DP($messageLatency)

        $label = "Message Latency"
        $convertedLabel = $this.ConvertLabel($label)
        $thresholds = $this.GetThresholds(0, $convertedLabel)
        $metric = [Metric]::New($label, $value, $this.Unit, $thresholds.warning, $thresholds.critical)
        return @($metric)
    }

    [void] MSExchangeSmtpConnectivityStatus() {
        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010
        $connectors = Test-SmtpConnectivity $this.hostname

        $failed = New-Object System.Collections.ArrayList
        foreach ($connector in $connectors) {
            if ($connector.StatusCode -ne 'Success') {
                $failed.Add($connector) > $null
            }
        }

        $failedConnectors = $failed.ReceiveConnector | Get-Unique
        if ($failedConnectors) {
            $summary = "Connection failed to {0} receive connectors ({1})" -f $failedConnectors.Count,
                                                                              ($failedConnectors -join ', ')
            throw [CheckExitCritical]::New($summary)
        }

        $summary = "Connection successful to all receive connectors"
        throw [CheckExitOK]::New($summary)
    }

    [Array] MSExchangeMailboxQueue() {
        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010
        $metrics = New-Object System.Collections.ArrayList
        $q = if ($this.ModeArgs.queue) { $this.ModeArgs.queue } else { '.' }

        if ($q -eq '.') {
            $queues =  Get-Queue
            if ($queues -and @($queues).Count -ge 1) {
                $queues | ForEach-Object {
                    $queueName = $_.Identity
                    $metrics.Add([Metric]::New("'$queueName' Status", $_.Status, $null, $null, $null, $false))
                    $metrics.Add(
                        [Metric]::New("'$queueName' Message Count",
                                      $this.ConvertTo2DP($_.MessageCount), $null, $null, $null))
                    $metrics.Add(
                        [Metric]::New("'$queueName' Incoming Rate",
                                      $this.ConvertTo2DP($_.IncomingRate), $null, $null, $null))
                    $metrics.Add(
                        [Metric]::New("'$queueName' Outgoing Rate",
                                      $this.ConvertTo2DP($_.OutgoingRate), $null, $null, $null))
                    $metrics.Add(
                        [Metric]::New("'$queueName' Velocity", $this.ConvertTo2DP($_.Velocity), $null, $null, $null))
                }
            } else {
                throw [CheckExitUnknown]::New("No queues were found")
            }
        } else {
            $queue = Get-Queue -Identity $this.ModeArgs.queue
            if ($queue) {
                $metrics.Add([Metric]::New("Status", $queue.Status, $null, $null, $null, $false))
                $metrics.Add(
                    [Metric]::New("Message Count", $this.ConvertTo2DP($queue.MessageCount), $null, $null, $null))
                $metrics.Add(
                    [Metric]::New("Incoming Rate", $this.ConvertTo2DP($queue.IncomingRate), $null, $null, $null))
                $metrics.Add(
                    [Metric]::New("Outgoing Rate", $this.ConvertTo2DP($queue.OutgoingRate), $null, $null, $null))
                $metrics.Add([Metric]::New("Velocity", $this.ConvertTo2DP($queue.Velocity), $null, $null, $null))
            } else {
                throw [CheckExitUnknown]::New("Queue '$($this.ModeArgs.queue)' was not found")
            }
        }

        return $metrics.ToArray()
    }

    [void] MSExchangeBackPressureStatus() {
        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010

        $info = Get-ExchangeDiagnosticInfo -Server $this.hostname -Process EdgeTransport

        try {
            $diag = [xml] $info.Result
        } catch {
            throw [CheckExitUnknown]::New("Failed to parse response")
        }

        $results = $diag.Diagnostics.Components.ResourceThrottling.ResourceTracker.ResourceMeter
        if (!$results) {
            throw [CheckExitUnknown]::New("Unable to get diagnostic information")
        }

        [array] $highPressure = $results | Where-Object {$_.CurrentResourceUse -eq 'High'}
        [array] $mediumPressure = $results | Where-Object {$_.CurrentResourceUse -eq 'Medium'}

        $summary = ""
        if (!$highPressure -and !$mediumPressure) {
            $summary = "All resources have normal pressure"
            throw [CheckExitOK]::New($summary)
        }

        if ($highPressure) {
            $summary += "{0} resources have high pressure" -f $highPressure.Count
        }

        if ($mediumPressure) {
            if ($highPressure) {
                $summary += ", "
            }
            $summary += "{0} resources have medium pressure" -f $mediumPressure.Count
        }

        if ($highPressure) {
            $resources = $highPressure | ForEach-Object { "{0} Pressure is {1}" -f $_.Resource, $_.Pressure }
            $summary += "`n`nResources with high pressure:`n {0}" -f ($resources -join "`n")
        }

        if ($mediumPressure) {
            $resources = $mediumPressure | ForEach-Object { "{0} Pressure is {1}" -f $_.Resource, $_.Pressure }
            $summary += "`n`nResources with medium pressure:`n{0}" -f ($resources -join "`n")
        }

        if ($highPressure) {
            throw [CheckExitCritical]::New($summary)
        }

        # medium pressure
        throw [CheckExitWarning]::New($summary)
    }

    [void] MSExchangeDatabaseDiskSpace() {
        $metrics = New-Object System.Collections.ArrayList
        $extras = New-Object System.Collections.ArrayList

        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010

        $databases = Get-MailboxDatabase -Server $this.hostname

        if (!$databases) {
            throw [CheckExitUnknown]::New("No databases found")
        }

        foreach ($database in $databases) {
            $db = $database.Name
            $status = Get-MailboxDatabaseCopyStatus -Identity $db | Select Name,Status,CopyQueueLength,ReplayQueueLength,LastInspectedLogTime,ContentIndexState,DiskFreeSpace,DiskTotalSpace,DiskFreeSpacePercent 
            $label = "Disk Free Space"
            $convertedLabel = $this.ConvertLabel($label)
            $thresholds = $this.GetThresholds(0, $convertedLabel)
            $value = $this.ConvertTo2DP($status.DiskFreeSpacePercent)
            $diskFreeSpace = [Metric]::New("'$db' Disk Free Space", $value, $this.Unit, `
                                           $thresholds.warning, $thresholds.critical)

            $freeSpace = ''
            $totalSpace = ''
            $parts = $status.DiskFreeSpace | Out-String
            $parts = $parts.Split()
            if ($parts.Length -eq 6){
                $value = $this.ConvertTo2DP($parts[0])
                $uom = $parts[1]
                $freeSpace = "${value}${uom}"
            } else {
                throw [CheckExitUnknown]::New("Unable to retrieve disk free space.")
            }

            $parts = $status.DiskTotalSpace | Out-String
            $parts = $parts.Split()
            if ($parts.Length -eq 6) {
                $value = $this.ConvertTo2DP($parts[0])
                $uom = $parts[1]
                $totalSpace = "${value}${uom}"
            } else {
                throw [CheckExitUnknown]::New("Unable to retrieve total free space.")
            }

            $metrics.Add($diskFreeSpace)
            $extras.Add("($freeSpace/$totalSpace)")
        }

        $perf = $this.GetPerfDataString($metrics)

        $maxStatus = 0
        $metricSummaries = New-Object System.Collections.ArrayList
        for ($i=0; $i -lt $metrics.Count; $i++) {
            $metric = $metrics[$i]
            $extra = $extras[$i]
            $status = $this.Check.Evaluate($metric.Value, $metric.warning, $metric.critical)
            $maxStatus = ($maxStatus, $status | Measure-Object -Maximum).Maximum
            $metricSummaries.Add(("{0} is {1}{2} {3}" -f $metric.Name, $metric.Value, $metric.UOM, $extra))
        }
        $output = $metricSummaries -join ', '
        $summary += "{0} | {1}" -f $output, $perf

        switch ($maxStatus) {
            0 { throw [CheckExitOK]::New($summary) }
            1 { throw [CheckExitWarning]::New($summary) }
            2 { throw [CheckExitCritical]::New($summary) }
        }
        throw [CheckExitUnknown]::New($summary)
    }

    [void] MSExchangeDatabaseBackupStatus() {

        function GetSummary($db) {
            $summary = "`n{0}" -f $db.Name
            if (!$db.LastFullBackup -and !$db.LastIncrementalBackup -and `
                !$db.LastDifferentialBackup -and !$db.LastCopyBackup) {
                $summary += "`n"
            } else {
                $summary += ":`n"
                $fullBackup = if ($db.LastFullBackup) { $db.LastFullBackup } else { "N/A" }
                $incBackup = if ($db.LastIncrementalBackup) { $db.LastIncrementalBackup } else { "N/A" }
                $diffBackup = if ($db.LastDifferentialBackup) { $db.LastDifferentialBackup } else { "N/A" }
                $copyBackup = if ($db.LastCopyBackup) { $db.LastCopyBackup } else { "N/A" }
                $summary += ("Last Full Backup: {0}`n" -f $fullBackup)
                $summary += ("Last Incremental Backup: {0}`n" -f $incBackup)
                $summary += ("Last Differential Backup: {0}`n" -f $diffBackup)
                $summary += ("Last Copy Backup: {0}`n`n" -f $copyBackup)
            }
            return $summary
        }

        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010

        $databases = Get-MailboxDatabase -Server $this.hostname

        if (!$databases) {
            throw [CheckExitUnknown]::New("No databases found")
        }

        $backedUp = New-Object System.Collections.ArrayList
        $notBackedUp = New-Object System.Collections.ArrayList

        foreach ($database in $databases) {
            if (!$database.LastFullBackup -and !$database.LastIncrementalBackup -and `
                !$database.LastDifferentialBackup -and !$database.LastCopyBackup) {
                $notBackedUp.Add($database)
            } else {
                $backedUp.Add($database)
            }
        }

        if ($notBackedUp) {
            $summary = "{0} databases not backed up" -f $notBackedUp.Count
            if ($this.verbose -and $backedUp) {
                $summary += ", {0} databases backed up" -f $backedUp.Count
            }
            $summary += ":`n`nDatabases not backed up:`n"
            foreach ($db in $notBackedUp) {
                $summary += GetSummary($db)

            }
            if ($this.verbose -and $backedUp) {
                $summary += "`n`nDatabases backed up:`n"
                foreach ($db in $backedUp) {
                    $summary += GetSummary($db)
                }
            }
            throw [CheckExitCritical]::New($summary)
        }

        $summary = "All databases backed up"
        if ($this.verbose) {
            $summary += ":`n"
            foreach ($db in $backedUp) {
                $summary += GetSummary($db)
            }
        }

        throw [CheckExitOK]::New($summary)
    }

    [void] MSExchangeReplicationHealthStatus() {

        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010
        
        $results = Test-ReplicationHealth $this.hostname

        $summary = ""
        $numFailed = ($results.Result -ne 'Passed').Count
        $count = 0
        if ($numFailed) {
            $summary = "{0} checks failed: `n`n" -f $numFailed
            foreach ($result in $results) {
                if ($result.Result -ne 'Passed') {
                    $count += 1
                    $summary += "{0}) {1}:`n" -f $count, $result.Check
                    $summary += "`tDescription: {0}`n" -f $result.CheckDescription
                    $summary += "`t{0}`n" -f $result.Error
                }
            }
            throw [CheckExitCritical]::New($summary)
        }

        $summary = "All checks passed"
        throw [CheckExitOK]::New($summary)
    }

    [void] MSExchangeConnectivityStatus() {

        function GetMapiSummary($result) {
            $latency = $this.GetLatency($result.Latency)
            $summary = "'{0}' Status: '{1}', Latency: {2}{3}" -f $result.Database, $result.Result, $latency,
                                                                   $this.Unit
            if ($result.Result -ne 'Success') {
                $summary += ", Error: {0}" -f $($result.Error)
            }
            return $summary
        }

        function GetSummary($result) {
            $latency = $this.GetLatency($result.Latency)
            $value =  $this.ConvertTo2DP($latency)
            $summary = " Client Access Server: {0}," -f $result.ClientAccessServerShortName
            $summary += " Scenario: {0}," -f $result.Scenario
            $summary += " Result: {0}," -f $result.Result
            if ($result.Result -ne 'Success') {
                $summary += " Error: {0}" -f $result.Error
            } else {
                $summary += " Latency: {0}{1}" -f $value, $this.Unit
            }
            return $summary
        }

        add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010

        $cmdlet = $this.MetricInfo.counters[0]
        
        $getSummary = if ($cmdlet -eq 'Test-MapiConnectivity') { 'GetMapiSummary' } else { 'GetSummary' }
        #if ($cmdlet -eq 'Test-ActiveSyncConnectivity') {
        #    $results = & $cmdlet -WarningAction SilentlyContinue | Select ClientAccessServerName,Scenario,ScenarioDescription,UserName,PerformanceCounterName,Result,Site,Latency,SecureAccess,ConnectionType,Port,'Latency(ms)',VirtualDirectoryName,URL,URLType
        #} else {
            $results = & $cmdlet -WarningAction SilentlyContinue
        #}
        $successes = New-Object System.Collections.ArrayList
        $failures = New-Object System.Collections.ArrayList
        $perf = New-Object System.Collections.ArrayList
        foreach ($result in $results) {
            $status = $result.Result
            if ("$status" -ne "Success") {
                $failures.Add($result) > $null
            } else {
                $successes.Add($result) > $null
            }
            $latency = $this.GetLatency($result.Latency)

            $label = ""
            if ($result.Scenario) {
                $label = $this.ConvertCamelCaseToPerfLabel($result.Scenario)
            } else {
                $label = $this.ConvertLabel($result.Database)
            }
            $label += "_latency"
            $perf.Add(("{0}={1}{2}" -f $label, $latency, $this.Unit))
        }
        $perf = $perf -join " "

        if ($failures) {
            $summary = "{0} connectivity tests failed" -f $failures.Count
            if ($this.verbose -and $successes) {
                $summary += ", {0} connectivity tests successful" -f $successes.Count
            }
            $summary += ": Failures: "
            foreach ($result in $failures) {
                $summary += & $getSummary $result
            }
            if ($this.verbose -and $successes) {
                $summary += "` Successes: "
                foreach ($result in $successes) {
                    $summary += & $getSummary $result
                }
            }

            $summary += " | {0}" -f $perf
            throw [CheckExitCritical]::New($summary)
        }

        $summary = "All connectivity tests successful"
        if ($this.verbose) {
            $summary += ": "
            foreach ($result in $successes) {
                $summary += & $getSummary $result
            }
        }

        $summary += " | {0}" -f $perf
        throw [CheckExitOK]::New($summary)
    }

    [void] MSExchangeLdapSearchTime() {
        $label = "LDAP Search Time"
        $convertedLabel = $this.ConvertLabel($label)
        $counter = '\MSExchange ADAccess Processes(*)\LDAP Search Time'
        $counterObj = Get-Counter $counter -ErrorAction SilentlyContinue
        if (!$counterObj) {
            throw [CheckExitUnknown]::New("Unable to retrieve data. Ensure all required services are running.")
        }

        $thresholds = $this.GetThresholds(0, $convertedLabel)

        $metrics = @{
            'CRITICAL' = New-Object System.Collections.ArrayList
            'WARNING' = New-Object System.Collections.ArrayList
            'OK' = New-Object System.Collections.ArrayList
        }

        $counterObj.CounterSamples | ForEach-Object {
            $value = $this.ConvertTo2DP($_.CookedValue)
            $status = $this.Check.Evaluate($value, $thresholds.warning, $thresholds.critical)
            $metric = [Metric]::New("'$($_.InstanceName)' $label", $value, $this.Unit, `
                                    $thresholds.warning, $thresholds.critical)
            switch ($status) {
                0 { $metrics.OK.Add($metric) }
                1 { $metrics.WARNING.Add($metric) }
                2 { $metrics.CRITICAL.Add($metric) }
            }
        }

        $allMetrics = $metrics.OK + $metrics.WARNING + $metrics.CRITICAL
        $perf = $this.GetPerfDataString($allMetrics)
        $summary = "All LDAP Search Times are within the defined thresholds"
        if ($this.verbose -or $metrics.WARNING -or $metrics.CRITICAL) {
            $summary += ": "
            foreach ($key in $metrics.Keys) {
                if ($metrics[$key]) {
                    $summary += "LDAP Search Times {0}:" -f $key
                    foreach ($metric in $metrics[$key]) {
                        $summary += " {0} is {1}{2}" -f $metric.Name, $metric.Value, $metric.UOM
                    }
                }
            }

            $summary += " | {0}" -f $perf

            if ($metrics.CRITICAL) {
                $summary = "Some LDAP Search Times are not within the defined critical thresholds: {0}" -f $summary
                throw [CheckExitCritical]::New($summary)
            }
            if ($metrics.WARNING) {
                $summary = "Some LDAP Search Times are not within the defined warning thresholds: {0}" -f $summary
                throw [CheckExitWarning]::New($summary)
            }
        }

        throw [CheckExitOK]::New($summary)
    }

    [Array] MSExchangePerf() {
        $metrics = New-Object System.Collections.ArrayList
        for ($i=0; $i -lt $this.MetricInfo.labels.Length; $i++) {
            $label = $this.MetricInfo.labels[$i]
            $counter = $this.MetricInfo.counters[$i]

            $counterObj = Get-Counter $counter -ErrorAction SilentlyContinue
            if (!$counterObj) {
                throw [CheckExitUnknown]::New("Unable to retrieve data. Ensure all required services are running.")
            }
            $value = $this.ConvertTo2DP($counterObj.CounterSamples.CookedValue)
            $convertedLabel = $this.ConvertLabel($label)
            $thresholds = $this.GetThresholds($i, $convertedLabel)
            $metric = [Metric]::New($label, $value, $this.Unit, $thresholds.warning, $thresholds.critical)
            $metrics.Add($metric)
        }
        return $metrics.ToArray()
    }

    [void] MSExchangeMultiPerf() {
        $metrics = New-Object System.Collections.ArrayList
        for ($i=0; $i -lt $this.MetricInfo.labels.Length; $i++) {
            $label = $this.MetricInfo.labels[$i]
            $counter = $this.MetricInfo.counters[$i]
            $counterObj = Get-Counter $counter -ErrorAction SilentlyContinue
            if (!$counterObj) {
                throw [CheckExitUnknown]::New("Unable to retrieve data. Ensure all required services are running.")
            }
            $convertedLabel = $this.ConvertLabel($label)
            $thresholds = $this.GetThresholds(0, $convertedLabel)
            $counterObj.CounterSamples | ForEach-Object {
                $value = $this.ConvertTo2DP($_.CookedValue)
                $startIdx = $_.Path.IndexOf('(') + 1
                $endIdx = $_.Path.IndexOf(')')
                $name = $_.InstanceName
                if ($startIdx -gt 0 -and $endIdx -gt 0 -and $endIdx -gt $startIdx) {
                    $name = $_.Path.Substring($startIdx, $endIdx-$startIdx).Replace(' - ', ' ').Replace('/', '')
                }
                $metric = [Metric]::New("'$name' $label", $value, $this.Unit, $thresholds.warning, $thresholds.critical)
                $metrics.Add($metric)
            }
        }

        $perf = $this.GetPerfDataString($metrics)

        $maxStatus = 0
        $metricSummaries = New-Object System.Collections.ArrayList
        foreach ($metric in $metrics) {
            $status = $this.Check.Evaluate($metric.Value, $metric.warning, $metric.critical)
            $maxStatus = ($maxStatus, $status | Measure-Object -Maximum).Maximum
            $metricSummaries.Add(("{0} is {1}{2}" -f $metric.Name, $metric.Value, $metric.UOM))
        }
        $summary = "{0} | {1}" -f ($metricSummaries -join ", "), $perf

        switch ($maxStatus) {
            0 {
                $shortSummary = "All values are within the defined thresholds"
                if ($this.verbose) {
                    $summary = "{0}: {1}" -f $shortSummary, $summary
                } else {
                    $summary = "{0} | {1}" -f $shortSummary, $perf
                }
                throw [CheckExitOK]::New($summary)
            }
            1 {
                $shortSummary = "Some values are not within the defined warning thresholds"
                $summary = "{0}: {1}" -f $shortSummary, $summary
                throw [CheckExitWarning]::New($summary)
            }
            2 {
                $shortSummary = "Some values are not within the defined critical thresholds"
                $summary = "{0}: {1}" -f $shortSummary, $summary
                throw [CheckExitCritical]::New($summary)
            }
        }
        throw [CheckExitUnknown]::New("Unable to retrieve data.")
    }

    [void] RunCheck() {
        [Array] $metrics = $this.($this.MetricMethod)()
        $metrics | ForEach-Object {
            $this.Check.addMetric($_.Name, $_.Value, $_.UOM, $_.Warning, $_.Critical, $_.DisplayInPerf)
        }
        $this.Check.final()
    }
}

enum ExitCode {
    OK = 0
    WARNING = 1
    CRITICAL = 2
    UNKNOWN = 3
}

class CheckExit: System.Exception {
    [ExitCode] $Status
    [string] $Message
    CheckExit([ExitCode] $status, [string] $message){
        $this.Status = $status
        $this.Message = $Message
    }
}

class CheckExitOK: CheckExit {
    CheckExitOK([string] $message) : base([ExitCode]::OK, $message) { }
}

class CheckExitWarning: CheckExit {
    CheckExitWarning([string] $message) : base([ExitCode]::WARNING, $message) { }
}

class CheckExitCritical: CheckExit {
    CheckExitCritical([string] $message) : base([ExitCode]::CRITICAL, $message) { }
}

class CheckExitUnknown: CheckExit {
    CheckExitUnknown([string] $message) : base([ExitCode]::UNKNOWN, $message) { }
}

class ModeUsage {
    [string] $metricType
    [string] $metricInfo
    [string[]] $argumentsOptional
    [string[]] $argumentsRequired
    [string] $unit
    [string] $interval
    [string] $pluginClass
    [HashTable] $thresholdsWarnings
    [HashTable] $thresholdsCritical

    ModeUsage ($metricType, $metricInfo, $argumentsOptionalList, $argumentsRequiredList, $unit, $interval,
               $pluginClass, $thresholdsWarningsDict, $thresholdsCriticalDict) {
        $this.metricType = $metricType
        $this.metricInfo = $metricInfo
        $this.argumentsOptional = $argumentsOptionalList
        $this.argumentsRequired = $argumentsRequiredList
        $this.unit = $unit
        $this.interval = $interval
        $this.pluginClass = $pluginClass
        $this.thresholdsWarnings = $thresholdsWarningsDict
        $this.thresholdsCritical = $thresholdsCriticalDict
    }
}

class ResourceVariable {
    [string] $name
    [string] $defaultValue
    [ResourceArgument[]] $arguments

    ResourceVariable ($name, $defaultValue, $arguments) {
        $this.name = $name
        $this.defaultValue = $defaultValue
        $this.arguments = $arguments
    }
}

class ResourceArgument {
    [string] $longParam
    [string] $help
    [string] $resourceKey
    [string] $value
    [boolean] $isRequired

    ResourceArgument ($longParam, $help, $resourceKey) {
        $this.longParam = $longParam
        $this.help = $help
        $this.resourceKey = $resourceKey
    }
}

$MODE_MAPPING = @{
'MSExStatus.Service.States' = [ModeUsage]::New(
    'custom', 'MSExchangeServiceStates',
    @('WINRM_EXTRA_ARGS', 'MS_EXCHANGE_INACTIVE_SERVICES'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExStatus.Component.States' = [ModeUsage]::New(
    'custom', 'MSExchangeComponentStates',
    @('WINRM_EXTRA_ARGS', 'MS_EXCHANGE_INACTIVE_COMPONENTS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExMailflow.Status' = [ModeUsage]::New(
    'custom', 'MSExchangeMailflowStatus',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExMailflow.Message.Latency' = [ModeUsage]::New(
    'custom', 'MSExchangeMailflowMessageLatency',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    's', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExMailflow.SMTP.Connectivity' = [ModeUsage]::New(
    'custom', 'MSExchangeSmtpConnectivityStatus',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExMailflow.SMTP.Message.Count' = [ModeUsage]::New(
    'perf', 'Messages Sent Per Second,Messages Received Per Second;\MSExchangeTransport SmtpSend(_total)\Messages Sent/sec,\MSExchangeTransport SmtpReceive(_total)\Messages Received/sec',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExMailflow.Mailbox.Failure.Rate' = [ModeUsage]::New(
    'multiperf', 'Failure Rate;\MSExchange HttpProxy(*)\Mailbox Server Proxy Failure Rate',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '%', '300', 'Exchange',
    @{  'failure_rate' = '0';  },
    @{  'failure_rate' = '10';  }
    )
'MSExMailflow.Mailbox.Queue' = [ModeUsage]::New(
    'custom', 'MSExchangeMailboxQueue',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME', 'MS_EXCHANGE_QUEUE_NAME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExMailflow.Back.Pressure.Status' = [ModeUsage]::New(
    'custom', 'MSExchangeBackPressureStatus',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExDatabase.Disk.Space' = [ModeUsage]::New(
    'custom', 'MSExchangeDatabaseDiskSpace',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '%', '300', 'Exchange',
    @{  'disk_free_space' = '30:';  },
    @{  'disk_free_space' = '10:';  }
    )
'MSExDatabase.Backup.Status' = [ModeUsage]::New(
    'custom', 'MSExchangeDatabaseBackupStatus',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExDatabase.Replication.Health' = [ModeUsage]::New(
    'custom', 'MSExchangeReplicationHealthStatus',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExDatabase.MAPI.Connectivity' = [ModeUsage]::New(
    'connectivity', 'MAPI Connectivity; Test-MapiConnectivity',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExDatabase.IO' = [ModeUsage]::New(
    'multiperf', 'Database Reads,Database Writes;\MSExchange Database ==> Instances(*)\I/O Database Reads (Attached) Average Latency,\MSExchange Database ==> Instances(*)\I/O Database Writes (Attached) Average Latency',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  'database_reads' = '20';  'database_writes' = '50';  },
    @{  'database_reads' = '40';  'database_writes' = '100';  }
    )
'MSExDatabase.Instances' = [ModeUsage]::New(
    'perf', 'Database Instances;\MSExchange Active Manager(_total)\Database Mounted',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExDatabase.RPC.Latency' = [ModeUsage]::New(
    'multiperf', 'RPC Average Latency;\MSExchangeIS Store(*)\RPC Average Latency',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  'rpc_latency' = '50';  },
    @{  'rpc_latency' = '100';  }
    )
'MSExDatabase.LDAP.Search.Time' = [ModeUsage]::New(
    'custom', 'MSExchangeLdapSearchTime',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  'ldap_search_time' = '50';  },
    @{  'ldap_search_time' = '100';  }
    )
'MSExConnectivity.ActiveSync' = [ModeUsage]::New(
    'connectivity', 'ActiveSync Connectivity; Test-ActiveSyncConnectivity',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExConnectivity.ECP' = [ModeUsage]::New(
    'connectivity', 'ECP Connectivity; Test-EcpConnectivity',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExConnectivity.IMAP' = [ModeUsage]::New(
    'connectivity', 'IMAP Connectivity; Test-ImapConnectivity',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExConnectivity.Web.Service' = [ModeUsage]::New(
    'connectivity', 'Web Services Connectivity; Test-WebServicesConnectivity',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExConnectivity.POP' = [ModeUsage]::New(
    'connectivity', 'POP Connectivity; Test-PopConnectivity',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExConnectivity.Connected.Users' = [ModeUsage]::New(
    'perf', 'Current Unique Users; \MSExchange OWA\Current Unique Users',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
'MSExConnectivity.CAS.Latency' = [ModeUsage]::New(
    'multiperf', 'CAS Latency; \MSExchange HttpProxy(*)\Average ClientAccess Server Processing Latency',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    'ms', '300', 'Exchange',
    @{  'cas_latency' = '2000';  },
    @{  'cas_latency' = '4000';  }
    )
'MSExConnectivity.ActiveSync.Requests' = [ModeUsage]::New(
    'perf', 'ActiveSync Requests; \MSExchange ActiveSync\Requests/sec',
    @('WINRM_EXTRA_ARGS'), @('WINRM_AUTHENTICATION', 'WINRM_USERNAME', 'WINRM_PASSWORD', 'WINRM_SCHEME'),
    '', '300', 'Exchange',
    @{  },
    @{  }
    )
}

$RESOURCE_VARIABLES = @(
    [ResourceVariable]::New('MS_EXCHANGE_QUEUE_NAME', '.', @(
        [ResourceArgument]::New('Queue',
                         'Mailbox queue to monitor',
                         'MS_EXCHANGE_QUEUE_NAME')
    )),
    [ResourceVariable]::New('KERBEROS_REALM', '', @(
    )),
    [ResourceVariable]::New('MS_EXCHANGE_EXPECTED_INACTIVE', 'Expected Inactive Components and Services', @(
        [ResourceArgument]::New('InactiveComponents',
                         'Comma separated list of components which are expected to be inactive',
                         'MS_EXCHANGE_INACTIVE_COMPONENTS'),
        [ResourceArgument]::New('InactiveServices',
                         'Comma separated list of services which are not expected to be running',
                         'MS_EXCHANGE_INACTIVE_SERVICES')
    ))
)

function RunCheck([Plugin] $check, [boolean] $verbose, [String] $hostname,
                  [System.Management.Automation.Runspaces.PSSession] $session,
                  [Modeusage] $modeUsage, [HashTable] $modeArgs) {
    try {
        $checkClass = New-Object -Type $modeUsage.pluginClass -ArgumentList $check, $verbose, $hostname, $session,
                                                                            $modeUsage.thresholdsWarnings,
                                                                            $modeUsage.thresholdsCritical,
                                                                            $modeUsage.unit, $modeUsage.metricType,
                                                                            $modeUsage.metricInfo, $modeArgs
    } catch {
        if ($_.Exception.Message.Contains('CheckExit')){
            throw $_.Exception.InnerException.InnerException
        }
    }
    $checkClass.RunCheck()
}

function GetModeUsage() {
    $modeUsage = $MODE_MAPPING[$mode]
    if (!$modeUsage) {
        throw [CheckExitUnknown]::New(("Unknown mode: {0}`nValid modes:`n`t{1}" -f $mode,
                                                                                   ($MODE_MAPPING.Keys -join "`n`t")))
    }
    return $modeUsage
}

function GetModeArgs([ModeUsage] $modeUsage) {
    $allVariableArgs = @()
    foreach ($variable in $RESOURCE_VARIABLES) {
        foreach ($arg in $variable.arguments) {
            $allVariableArgs += $arg
        }
    }

    $modeArgs = @()
    foreach ($arg in $allVariableArgs) {
        if ($modeUsage.argumentsRequired.Contains($arg.resourceKey)) {
            $arg.isRequired = $true
            $modeArgs += $arg
        } elseif ($modeUsage.argumentsOptional.Contains($arg.resourceKey)) {
            $arg.isRequired = $false
            $modeArgs += $arg
        }
    }
    return $modeArgs
}

function GetArgs($modeArgs, $warning, $critical) {
    $arguments = @{}
    foreach ($arg in $modeArgs) {
        $value = (Get-Variable $arg.longParam -ErrorAction 'Ignore').Value
        if ($arg.isRequired -and !$value) {
            throw [CheckExitUnknown]::New(
                "Error parsing arguments: the required flag '-{0}' was not specified" -f $arg.longParam)
        }
        $arguments.Add($arg.longParam, $value)
    }

    if ($warning) {
        $arguments.warning = $warning
    }
    if ($critical) {
        $arguments.critical = $critical
    }
    return $arguments
}

function Main {
    $description = "Monitors Microsoft Agentless."

    $check = [Plugin]::New("check_microsoft_exchange", "",
                           "Copyright (C) 2003 - 2023 Opsview Limited. All rights reserved.`n$description",
                           "Optional arguments:
    -v, -Verbose
        Verbose mode - always display all output
    -w, -Warning
        The warning levels (comma separated)
    -c, -Critical
        The critical levels (comma separated)

Required arguments:
    -n, -Hostname
        Hostname of the host to monitor
    -m, -Mode
        Mode for the plugin to run (the service check). See below for a full list of supported modes.

Mode specific arguments:
    -Queue
        Mailbox queue to monitor
    -InactiveComponents
        Comma separated list of components which are expected to be inactive
    -InactiveServices
        Comma separated list of services which are not expected to be running
    -Transport
        Authentication type to use
    -Username
        Username for remote windows host
    -Password
        Password for remote windows host
    -Scheme
        Scheme for connecting to remote windows host

Supported modes:
    - MSExStatus.Service.States
    - MSExStatus.Component.States
    - MSExMailflow.Status
    - MSExMailflow.Message.Latency
    - MSExMailflow.SMTP.Connectivity
    - MSExMailflow.SMTP.Message.Count
    - MSExMailflow.Mailbox.Failure.Rate
    - MSExMailflow.Mailbox.Queue
    - MSExMailflow.Back.Pressure.Status
    - MSExDatabase.Disk.Space
    - MSExDatabase.Backup.Status
    - MSExDatabase.Replication.Health
    - MSExDatabase.MAPI.Connectivity
    - MSExDatabase.IO
    - MSExDatabase.Instances
    - MSExDatabase.RPC.Latency
    - MSExDatabase.LDAP.Search.Time
    - MSExConnectivity.ActiveSync
    - MSExConnectivity.ECP
    - MSExConnectivity.IMAP
    - MSExConnectivity.Web.Service
    - MSExConnectivity.POP
    - MSExConnectivity.Connected.Users
    - MSExConnectivity.CAS.Latency
    - MSExConnectivity.ActiveSync.Requests
")

    if ($help) {
        if ($mode) {
            $modeUsage = GetModeUsage
            $modeArgs = GetModeArgs $modeUsage

            $optional = "Optional arguments:
    -v, -Verbose
        Verbose mode - always display all output
    -w, -Warning
        The warning levels (comma separated)
    -c, -Critical
        The critical levels (comma separated)
    "

            $required = "Required arguments:
    -n, -Hostname
        Hostname of the host to monitor
    "

            foreach ($arg in $modeArgs) {
                $text = "-{0}`n`t{1}`n    " -f $arg.longParam, $arg.help
                if ($arg.isRequired) {
                    $required += $text
                } else {
                    $optional += $text
                }
            }

            $description = "{0} mode arguments:`n`n{1}`n{2}`n" -f $mode, $optional, $required
            $check.HelpText($description)
        } else {
            $check.HelpText()
        }
    }

    $verbose = $VerbosePreference -ne [System.Management.Automation.ActionPreference]::SilentlyContinue

    if ($remainingArguments) {
        $check.ExitUnknown("Error parsing arguments: unknown flag {0}" -f $remainingArguments)
    }
    if (!$mode) {
        $check.ExitUnknown("Error parsing arguments: the required flag '-m/-Mode' was not specified")
    }
    $modeUsage = GetModeUsage


    $modeArgs = GetModeArgs $modeUsage
    $arguments = GetArgs -ModeArgs $modeArgs -Warning $warning -Critical $critical

    #Write-Host "-Check $check -Verbose $verbose -Hostname $hostname -Session $session -ModeUsage $modeUsage -ModeArgs $arguments"
    RunCheck -Check $check -Verbose $verbose -Hostname $hostname -Session $session `
             -ModeUsage $modeUsage -ModeArgs $arguments
}

try {
    Main
} catch [CheckExit] {
    $message = $_.Exception.Message
    switch ($_.Exception.Status) {
        OK {
            Write-Host "METRIC OK - $message"
            exit 0
        }
        WARNING {
            Write-Host "METRIC WARNING - $message"
            exit 1
        }
        CRITICAL {
            Write-Host "METRIC CRITICAL - $message"
            exit 2
        }
        UNKNOWN {
            Write-Host "METRIC UNKNOWN - $message"
            exit 3
        }
    }
} catch {
    Write-Host "METRIC UNKNOWN - $($_.Exception.message)"
    exit 3
} 
