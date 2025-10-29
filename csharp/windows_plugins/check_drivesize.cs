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
        string template = isMax ? "~:{0}" : "{0}:";
        if (value.Last() == '%')
        {
            thresholdPct = String.Format(template, value.Replace("%", ""));
        }
        else
        {
            if (!value.EndsWith("B", StringComparison.OrdinalIgnoreCase))
            {
                value += "B";
            }
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
                + "                   Threshold levels for % OR total space B, (K or KB), (M or MB), etc.\r\n"
                + "                     (e.g. MinCritFree=1GB, MaxWarnUsed=80%)\r\n"
                + "                     Max thresholds will trigger if the space value is > than the level set\r\n"
                + "                     Min thresholds will trigger if the space value is < than the level set\r\n"
                + "    Drive          The drive to return size information for (e.g Drive=C or Drive=C:)\r\n"
                + "    CheckAll       Checks all drives\r\n"
                + "    CheckAllOthers Checks all drives, but turns the Drive option into an exclude option\r\n"
                + "    FilterType     The type of drives to check (FIXED, CDROM, REMOTE or REMOVABLE)"
        );
        try
        {
            var tempDict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (var line in callData.cmd.Skip(1))
            {
                var parts = line.Split('=');
                var key = parts[0].Trim();
                var value = parts.ElementAtOrDefault(1) ?? "true";

                if (key.Equals("drive", StringComparison.OrdinalIgnoreCase))
                {
                    string existing;
                    if (!value.EndsWith(":"))
                    {
                        value += ":";
                    }
                    if (tempDict.TryGetValue("drive", out existing))
                    {
                        // Append new drive value to existing, comma-separated
                        tempDict["drive"] = existing + "," + value;
                    }
                    else
                    {
                        tempDict["drive"] = value;
                    }
                }
                else
                {
                    if (tempDict.ContainsKey(key))
                    {
                        throw new ArgumentException(string.Format("Duplicate argument '{0}'", key));
                    }

                    tempDict[key] = value;
                }
            }

            argsDict = tempDict;

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
                    //OP-74152: Thresholds Min|Max(Warn|Crit)(Free|Used) are ignored if the value is empty for backwards
                    // compatibility with the Opsview Windows Agent. Revisit this in the future if we should remove.
                    case "minwarnfree":
                    {
                        if (string.IsNullOrEmpty(arg.Value))
                            break;
                        ParseThreshold(check, "MinWarnFree", arg.Value, false, ref warnThreshold, ref warnThresholdPct);
                        metricMode = MetricMode.Free;
                        break;
                    }
                    case "mincritfree":
                    {
                        if (string.IsNullOrEmpty(arg.Value))
                            break;
                        ParseThreshold(check, "MinCritFree", arg.Value, false, ref critThreshold, ref critThresholdPct);
                        metricMode = MetricMode.Free;
                        break;
                    }
                    case "maxwarnfree":
                    {
                        if (string.IsNullOrEmpty(arg.Value))
                            break;
                        ParseThreshold(check, "MaxWarnFree", arg.Value, true, ref warnThreshold, ref warnThresholdPct);
                        metricMode = MetricMode.Free;
                        break;
                    }
                    case "maxcritfree":
                    {
                        if (string.IsNullOrEmpty(arg.Value))
                            break;
                        ParseThreshold(check, "MaxCritFree", arg.Value, true, ref critThreshold, ref critThresholdPct);
                        metricMode = MetricMode.Free;
                        break;
                    }

                    case "minwarnused":
                    {
                        if (string.IsNullOrEmpty(arg.Value))
                            break;
                        ParseThreshold(check, "MinWarnUsed", arg.Value, false, ref warnThreshold, ref warnThresholdPct);
                        metricMode = MetricMode.Used;
                        break;
                    }
                    case "mincritused":
                    {
                        if (string.IsNullOrEmpty(arg.Value))
                            break;
                        ParseThreshold(check, "MinCritUsed", arg.Value, false, ref critThreshold, ref critThresholdPct);
                        metricMode = MetricMode.Used;
                        break;
                    }
                    case "maxwarnused":
                    {
                        if (string.IsNullOrEmpty(arg.Value))
                            break;
                        ParseThreshold(check, "MaxWarnUsed", arg.Value, true, ref warnThreshold, ref warnThresholdPct);
                        metricMode = MetricMode.Used;
                        break;
                    }
                    case "maxcritused":
                    {
                        if (string.IsNullOrEmpty(arg.Value))
                            break;
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
                var drives = drive
                    .Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(d => String.Format("DeviceId = '{0}'", d.Trim().ToUpper()));

                string whereClause = string.Join(" OR ", drives);

                formattedQuery = String.Format("SELECT * FROM Win32_LogicalDisk WHERE {0}", whereClause);
            }
            else
            {
                // Must be DriveMode.Others
                var drives = drive
                    .Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(d => String.Format("DeviceId != '{0}'", d.Trim().ToUpper()));

                string whereClause = string.Join(" AND ", drives);

                formattedQuery = String.Format("SELECT * FROM Win32_LogicalDisk WHERE {0}", whereClause);
            }
            var diskQuery = new ObjectQuery(formattedQuery);
            var mgmtObjSearcher = new ManagementObjectSearcher(namespaceScope, diskQuery);
            ManagementObjectCollection colDisks = mgmtObjSearcher.Get();
            if ((driveMode == DriveMode.Single) && (colDisks.Count == 0))
            {
                return check.ExitUnknown("No matching drives found");
            }
            else if ((driveMode == DriveMode.Others) && (colDisks.Count == 0))
            {
                // In this case, there are no other drives except those specifically excluded
                return check.ExitOK("No other drives found");
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
