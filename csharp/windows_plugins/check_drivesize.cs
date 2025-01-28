// Plugin to check the drive size of a Windows box
// Copyright (C) 2003-2025 ITRS Group Limited. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Linq;
using System.Management;
using System.IO;
using System.ServiceProcess;
using System.Threading;
using PlugNSharp;
using Helpers;

static class CheckDriveSize
{
    enum DriveMode
    {
        Single,
        All,
        Others
    }

    enum MetricMode
    {
        Used,
        Free
    }

    private static void ParseThreshold(Check check, string name, string value, bool isMax, ref string threshold, ref string thresholdPct)
    {
        if (string.IsNullOrEmpty(value))
        {
            throw new Exception(String.Format("Incorrectly formatted arguments ({0})", name));
        }
        string template = isMax ? "~:{0}" : "{0}:";
        if (value.Last() == '%')
        {
            thresholdPct = String.Format(template, value.Replace("%", ""));
        }
        else
        {
            threshold = String.Format(template, value);
        }
    }

    private static uint ParseFilterType(string filterType)
    {
        switch (filterType)
        {
            case "REMOVABLE":
                return 2;
            case "FIXED":
                return 3;
            case "REMOTE":
                return 4;
            case "CDROM":
                return 5;
            default:
                throw new Exception(String.Format("Invalid FilterType ({0})", filterType));
        }
    }

    public static int Run(CallData callData)
    {
        string drive = null;
        var driveMode = DriveMode.Single;
        var metricMode = MetricMode.Used;

        string warnThreshold = null;
        string critThreshold = null;
        string warnThresholdPct = null;
        string critThresholdPct = null;
        uint driveTypeFilter = 0;

        Dictionary<string, string> argsDict;
        var check = new Check(
            "check_drivesize",
            helpText: "Returns size information on the specified drive\r\n"
                + "Arguments:\r\n"
                + "    (Min|Max)(Warn|Crit)(Free|Used)\r\n"
                + "                   Threshold levels for % OR total space (B, KB, MB, etc.)\r\n"
                + "                     (e.g. MinCritFree=1GB, MaxWarnUsed=80%)\r\n"
                + "    Drive          The drive to return size information for\r\n"
                + "    CheckAll       Checks all drives\r\n"
                + "    CheckAllOthers Checks all drives, but turns the Drive option into an exclude option\r\n"
                + "    FilterType     The type of drives to check (FIXED, CDROM, REMOTE or REMOVABLE)"
        );
        try
        {
            argsDict = callData.cmd
                .Select(line => line.Split('='))
                .Skip(1)
                .ToDictionary(x => x[0].Trim(), x => x.ElementAtOrDefault(1) != null ? x[1] : "true");
        }
        catch (System.ArgumentException)
        {
            return check.ExitUnknown("Incorrectly formatted arguments");
        }

        var argsCount = argsDict.Count();

        if (argsCount == 0)
        {
            return check.ExitHelp();
        }

        try
        {
            foreach (var arg in argsDict)
            {
                switch (arg.Key.ToLower())
                {
                    case "minwarnfree":
                    {
                        ParseThreshold(check, "MinWarnFree", arg.Value, false, ref warnThreshold, ref warnThresholdPct);
                        metricMode = MetricMode.Free;
                        break;
                    }
                    case "mincritfree":
                    {
                        ParseThreshold(check, "MinCritFree", arg.Value, false, ref critThreshold, ref critThresholdPct);
                        metricMode = MetricMode.Free;
                        break;
                    }
                    case "maxwarnfree":
                    {
                        ParseThreshold(check, "MaxWarnFree", arg.Value, true, ref warnThreshold, ref warnThresholdPct);
                        metricMode = MetricMode.Free;
                        break;
                    }
                    case "maxcritfree":
                    {
                        ParseThreshold(check, "MaxCritFree", arg.Value, true, ref critThreshold, ref critThresholdPct);
                        metricMode = MetricMode.Free;
                        break;
                    }

                    case "minwarnused":
                    {
                        ParseThreshold(check, "MinWarnUsed", arg.Value, false, ref warnThreshold, ref warnThresholdPct);
                        metricMode = MetricMode.Used;
                        break;
                    }
                    case "mincritused":
                    {
                        ParseThreshold(check, "MinCritUsed", arg.Value, false, ref critThreshold, ref critThresholdPct);
                        metricMode = MetricMode.Used;
                        break;
                    }
                    case "maxwarnused":
                    {
                        ParseThreshold(check, "MaxWarnUsed", arg.Value, true, ref warnThreshold, ref warnThresholdPct);
                        metricMode = MetricMode.Used;
                        break;
                    }
                    case "maxcritused":
                    {
                        ParseThreshold(check, "MaxCritUsed", arg.Value, true, ref critThreshold, ref critThresholdPct);
                        metricMode = MetricMode.Used;
                        break;
                    }

                    case "drive":
                    {
                        drive = arg.Value;
                        break;
                    }
                    case "checkall":
                    {
                        driveMode = DriveMode.All;
                        break;
                    }
                    case "checkallothers":
                    {
                        driveMode = DriveMode.Others;
                        break;
                    }
                    case "filtertype":
                    {
                        driveTypeFilter = ParseFilterType(arg.Value);
                        break;
                    }
                    case "showall":
                    {
                        // Unused option, since we always show the long output
                        break;
                    }
                    case "-h":
                    case "help":
                    {
                        return check.ExitHelp();
                    }
                    default:
                    {
                        return check.ExitUnknown(String.Format("Unrecognised argument ({0})", arg.Key));
                    }
                }
            };
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }

        try
        {
            var namespaceScope = new ManagementScope("\\\\.\\ROOT\\CIMV2");
            string formattedQuery;
            if (string.IsNullOrEmpty(drive) || (driveMode == DriveMode.All))
            {
                if (driveMode == DriveMode.Single)
                {
                    return check.ExitUnknown("Missing Drive or CheckAll[Others] argument");
                }
                formattedQuery = "SELECT * FROM Win32_LogicalDisk";
            }
            else if (driveMode == DriveMode.Single)
            {
                formattedQuery = string.Format(
                    "SELECT * FROM Win32_LogicalDisk WHERE DeviceId = '{0}'", drive
                );
            }
            else
            {
                // Must be DriveMode.Others
                formattedQuery = string.Format(
                    "SELECT * FROM Win32_LogicalDisk WHERE DeviceId != '{0}'", drive
                );
            }
            var diskQuery = new ObjectQuery(formattedQuery);
            var mgmtObjSearcher = new ManagementObjectSearcher(namespaceScope, diskQuery);
            ManagementObjectCollection colDisks = mgmtObjSearcher.Get();
            if ((driveMode == DriveMode.Single) && (colDisks.Count == 0)) {
                return check.ExitUnknown("No matching drives found");
            }

            foreach (ManagementObject selectedDisk in colDisks)
            {
                var driveType = (uint)selectedDisk["DriveType"];
                if ((driveTypeFilter > 0) && (driveType != driveTypeFilter))
                {
                    continue;
                }

                drive = (string)selectedDisk["Name"];
                var diskSize = (ulong)selectedDisk["Size"];
                var diskFree = (ulong)selectedDisk["FreeSpace"];

                if (metricMode == MetricMode.Free)
                {
                    var diskFreepct = diskFree * (1.0 / diskSize) * 100;
                    check.AddMetric(
                        name: drive + " %",
                        value: diskFreepct,
                        uom: "%",
                        displayName: String.Format("{0} % Disk Free", drive),
                        warningThreshold: warnThresholdPct,
                        criticalThreshold: critThresholdPct
                    );
                    check.AddMetric(
                        name: drive,
                        value: diskFree,
                        uom: "B",
                        displayName: String.Format("{0} Disk Free", drive),
                        warningThreshold: warnThreshold,
                        criticalThreshold: critThreshold
                    );
                }
                else
                {
                    var diskUsed = diskSize - diskFree;
                    var diskUsedPct = diskUsed * (1.0 / diskSize) * 100;
                    check.AddMetric(
                        name: drive + " %",
                        value: diskUsedPct,
                        uom: "%",
                        displayName: String.Format("{0} % Disk Used", drive),
                        warningThreshold: warnThresholdPct,
                        criticalThreshold: critThresholdPct
                    );
                    check.AddMetric(
                        name: drive,
                        value: diskUsed,
                        uom: "B",
                        displayName: String.Format("{0} Disk Used", drive),
                        warningThreshold: warnThreshold,
                        criticalThreshold: critThreshold
                    );
                }
            }
            return check.Final();
        }
        catch (ExitException) { throw; }  // Standard plugin exit
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }
    }
}
