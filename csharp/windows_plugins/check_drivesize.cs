// Company Confidential.
// Plugin to check the drive size of a Windows box
// Copyright (C) 2003-2023 ITRS Group Limited. All rights reserved

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
    public static int Run(CallData callData)
    {
        var drive = string.Empty;
        string minWarnFree = null;
        string minCritFree = null;
        Dictionary<string, string> argsDict;
        var check = new Check(
            "check_drivesize",
            helpText: "Returns size information on the specified drive\r\n"
                + "Arguments:\r\n"
                + "    MinWarnFree    Warning level for minimum % of free space available\r\n"
                + "    MinCritFree    Critical level for minimum % of free space available \r\n"
                + "    Drive          The drive to return size information about"
                
        );
        try{
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

        foreach (var arg in argsDict)
        {
            switch (arg.Key.ToLower())
            {
                case "minwarnfree":
                {
                    minWarnFree = arg.Value.Replace("%", "") + ":";
                    break;
                }
                case "mincritfree":
                {
                    minCritFree = arg.Value.Replace("%", "") + ":";
                    break;
                }
                case "drive":
                {
                    drive = arg.Value;
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
        if (string.IsNullOrEmpty(drive))
        {
            return check.ExitUnknown("Missing arguments (Drive)");
        }

        try
        {
            var namespaceScope = new ManagementScope("\\\\.\\ROOT\\CIMV2");
            string formattedQuery = string.Format(
                "SELECT * FROM Win32_LogicalDisk WHERE DeviceId = '{0}'",
                drive
            );
            var diskQuery = new ObjectQuery(formattedQuery);
            var mgmtObjSearcher = new ManagementObjectSearcher(namespaceScope, diskQuery);
            ManagementObjectCollection colDisks = mgmtObjSearcher.Get();
            ManagementObject selectedDisk = colDisks.OfType<ManagementObject>().FirstOrDefault();

            var diskSize = (ulong)selectedDisk["Size"];
            var diskFree = (ulong)selectedDisk["FreeSpace"];
            var diskUsed = diskSize - diskFree;
            var diskFreepct = diskFree * (1.0 / diskSize) * 100;

            check.AddMetric(
                name: drive + " %",
                value: diskFreepct,
                uom: "%",
                displayName: "% Disk Free",
                warningThreshold: minWarnFree,
                criticalThreshold: minCritFree
            );
            check.AddMetric(
                name: drive,
                value: diskUsed,
                uom: "B",
                displayName: string.Format("{0} Disk Used", drive),
                warningThreshold: minWarnFree,
                criticalThreshold: minCritFree
            );
            return check.Final();
        }
        catch (NullReferenceException)
        {
            return check.ExitUnknown(String.Format("Drive not recognised ({0})", drive));
        }
        catch (ExitException) { throw; }  // Standard plugin exit
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }
    }
}
