# AUTHORS:
#       Copyright (C) 2003-2018 Opsview Limited.All rights reserved
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


$check = [Plugin]::new("check_microsoft_exchange_counters", "", "Copyright (c) 2003-2023 Opsview Limited. All rights reserved. This plugin monitors the stats for your .", "Plugin Options:`n
     arguments:`n
      -h show this help message and exit,
      -m MODE,`n
            Supported modes:`n
            I/ODatabaseReads: Shows the average length of time, in milliseconds (ms), per database read operation. `n
            I/ODatabaseWrites: Shows the average length of time, in ms, per database write operation.`n
            SMPTSentMessages: Shows the number of messages sent by the SMTP server each second. Determines current load. Compare values to historical baselines.`n
            SMPTReceivedMessages: Shows the number of messages received by the SMTP server each second. Determines current load. Compare values to historical baselines.`n
            DBInstances: Shows the number of active database copies on the server.`n
            MailboxDeliveryQueue: Shows the number of messages queued for delivery in all queues.`n
            UsersOnline: Shows the number of unique users currently logged on to Outlook Web App.`n
            CASLatency: Shows the average latency (ms) of CAS processing time.`n
            MailboxServerFailureRate: Shows the percentage of connectivity related failures between this Client Access Server and MBX servers.`n
            ActiveSyncRequests: Shows the number of HTTP requests received from the client via ASP.NET per second.`n
            LDAPSearchTime: Shows the time (in ms) to send an LDAP search request and receive a response.`n
            RPCAverageLatency: RPC Latency average (msec) is the average latency in milliseconds of RPC requests per database`n
      -w WARNING,
            Value set for warning level`n
      -c CRITICAL,
            Value set for critical level`n
      -l LOCATION,
            The path to the metric`n
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
  Import-PSSession $Session -CommandName Get-ExchangeDiagnosticInfo -DisableNameChecking | Out-Null
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
  'I/ODatabaseReadsWrites' {
    $returnMetric = $check.getCounter("\MSExchange Database ==> Instances($location)\I/O Database Reads (Attached) Average Latency")
    $check.addMetric("$location_I/O_Database_Reads",$returnMetric,"ms",$warning,$critical)
    $returnMetric = $check.getCounter("\MSExchange Database ==> Instances($location)\I/O Database Writes (Attached) Average Latency")
    $check.addMetric("$location_I/O_Database_Writes",$returnMetric,"ms",$warning,$critical)
  }
  'SMPTSentReceivedMessages' {
    $returnMetric = $check.getCounter("\MSExchangeTransport SmtpSend($location)\Messages Sent/sec")
    $check.addMetric("SMPT_Sent_Messages",$returnMetric,"/s",$warning,$critical)
    $returnMetric = $check.getCounter("\MSExchangeTransport SmtpReceive($location)\Messages Received/sec")
    $check.addMetric("SMPT_Received_Messages",$returnMetric,"/s",$warning,$critical)
  }
  'DBInstances' {
    $returnMetric = $check.getCounter("\MSExchange Active Manager($location)\DataBase Mounted")
    $check.addMetric("DB_Instances",$returnMetric,"",$warning,$critical)
  }
  'MailboxDeliveryQueue' {
    $returnMetric = $check.getCounter("\MSExchangeTransport Queues($location)\Active Mailbox Delivery Queue Length")
    $check.addMetric("Active_Mailbox_Delivery_Queue_Length",$returnMetric,"",$warning,$critical)
  }
  'UsersOnline' {
    $returnMetric = $check.getCounter("\MSExchange OWA\Current Unique Users")
    $check.addMetric("Users_Currently_Online",$returnMetric,"",$warning,$critical)
  }
  'CASLatency' {
    $returnMetric = $check.getCounter("\MSExchange HttpProxy($location)\Average ClientAccess Server Processing Latency")
    $check.addMetric("$location_Average_ClientAccess_Server_Processing_Latency",$returnMetric,"ms",$warning,$critical)
  }
  'MailboxServerFailureRate' {
    $returnMetric = $check.getCounter("\MSExchange HttpProxy($location)\Mailbox Server Proxy Failure Rate")
    $check.addMetric("$location_Mailbox_Failure_Rate",$returnMetric,"%",$warning,$critical)
  }
  'ActiveSyncRequests' {
    $returnMetric = $check.getCounter("\MSExchange ActiveSync\Requests/sec")
    $check.addMetric("Active_Sync_Requests",$returnMetric,"/s",$warning,$critical)
  }
  'LDAPSearchTime' {
    $returnMetric = $check.getCounter("\MSExchange ADAccess Domain Controllers($location)\LDAP Search Time")
    $check.addMetric("LDAP_Search_Time",$returnMetric,"ms",$warning,$critical)
  }
  'RPCAverageLatency' {
    $returnMetric = $check.getCounter("\MSExchangeIS Store($location)\RPC Average Latency")
    $check.addMetric("RPC_Average_Latency",$returnMetric,"ms",$warning,$critical)
  }
  default {
    $check.ExitUnknown("Mode not found")
  }
}
$check.final()
