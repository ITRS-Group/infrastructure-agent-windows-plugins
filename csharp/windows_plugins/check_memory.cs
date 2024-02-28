// Company Confidential.
// Plugin to check the memory of a Windows box
// Copyright (C) 2003-2024 ITRS Group Limited. All rights reserved

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
using PHM = Helpers.PluginHelperMethods;

static class CheckMemory
{
    public static int Run(CallData callData)
    {
        string minCrit = null;
        string maxCrit = null;
        string minWarn = null;
        string maxWarn = null;
        string type = null;
        bool showAll = false;
        var displayMessage = string.Empty;
        Dictionary<string, string> argsDict;
        var check = new Check(
            "check_memory",
            helpText: "Returns information on system memory\r\n"
                + "Arguments:\r\n"
                + "    MinWarn    Warning level for minimum of free memory available\r\n"
                + "    MaxWarn    Warning level for maximun of free memory available\r\n"
                + "    MinCrit    Critical level for minimum of free memory available \r\n"
                + "    MaxCrit    Critical level for maximum of free memory available \r\n"
                + "    Type       Type of memory (page/physical)\r\n"
                + "    ShowAll    Gives more verbose output"
        );

        try
        {
            argsDict = callData.cmd
                .Select(line => line.Split('='))
                .Skip(1)
                .ToDictionary(
                    x => x[0].Trim(),
                    x => x.ElementAtOrDefault(1) != null ? x[1] : "true"
                );

            var argsCount = argsDict.Count();

            if (argsCount == 0)
            {
                return check.ExitHelp();
            }

            foreach (var arg in argsDict)
            {
                switch (arg.Key.ToLower())
                {
                    case "mincrit":
                    {
                        minCrit = arg.Value.Replace("%", "") + ":";
                        break;
                    }
                    case "maxcrit":
                    {
                        maxCrit = arg.Value.Replace("%", "");
                        break;
                    }
                    case "minwarn":
                    {
                        minWarn = arg.Value.Replace("%", "") + ":";
                        break;
                    }
                    case "maxwarn":
                    {
                        maxWarn = arg.Value.Replace("%", "");
                        break;
                    }
                    case "type":
                    {
                        type = arg.Value;
                        break;
                    }
                    case "showall":
                    {
                        showAll = bool.Parse(arg.Value);
                        break;
                    }
                    case "help":
                    case "-h":
                    {
                        return check.ExitHelp();
                    }
                    default:
                    {
                        return check.ExitUnknown(String.Format("Unrecognised argument ({0})", arg.Key));
                    }
                }
            };
            if (string.IsNullOrEmpty(type))
            {
                return check.ExitUnknown("Missing arguments (type)");
            }
        }
        catch (ExitException) { throw; }  // Standard plugin exit
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }

        try
        {
            var typeDict = new Dictionary<String, String>
            {
                { "page", "FreeVirtualMemory" },
                { "physical", "FreePhysicalMemory" },
            };

            var totalDict = new Dictionary<String, String>
            {
                { "page", "TotalVirtualMemorySize" },
                { "physical", "TotalVisibleMemorySize" }
            };

            if (!typeDict.ContainsKey(type))
            {
                return check.ExitUnknown(String.Format("Type not recognised ({0})", type));
            }
            ManagementObject win32OS = PHM.GetWmiWin32OperatingSystem();
            var memoryCapacityBytes =
                double.Parse(win32OS.Properties[totalDict[type]].Value.ToString()) * 1024;
            var freePhysicalMemoryBytes =
                double.Parse(win32OS.Properties[typeDict[type]].Value.ToString()) * 1024;

            double memoryUsed = memoryCapacityBytes - freePhysicalMemoryBytes;
            double memoryUsage = Math.Round((memoryUsed / memoryCapacityBytes) * 100, 2);

            switch (type)
            {
                case "page":
                    check.AddMetric(
                        name: "page file %",
                        value: memoryUsage,
                        uom: "%",
                        displayName: "Page File Memory Usage",
                        warningThreshold: maxWarn,
                        criticalThreshold: maxCrit
                    );
                    check.AddMetric(
                        name: "page file",
                        value: memoryUsed,
                        uom: "B",
                        displayName: "Page File Memory Used"
                    );
                    break;

                case "physical":
                    check.AddMetric(
                        name: "physical memory %",
                        value: memoryUsage,
                        uom: "%",
                        displayName: "Physical Memory Usage",
                        warningThreshold: maxWarn,
                        criticalThreshold: maxCrit
                    );
                    check.AddMetric(
                        name: "physical memory",
                        value: memoryUsed,
                        uom: "B",
                        displayName: "Physical Memory Used"
                    );
                    break;
            }
            if (check.GetFinalExitCode() != Check.EXIT_STATE_OK)
            {
                showAll = true;
            }
            displayMessage = showAll ? "" : "Memory within bounds";
            return check.Final(displayMessage, Check.EXIT_STATE_OK);
        }
        catch (ExitException) { throw; }  // Standard plugin exit
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }
    }
}
