// Plugin to check a custom performance counter of a Windows box
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
using System.Text.RegularExpressions;
using PlugNSharp;
using Helpers;
using PHM = Helpers.PluginHelperMethods;

static class CheckCounter
{
    public static int Run(CallData callData)
    {
        var check = new Check(
            "check_counter",
            helpText: "Returns information for a given counter\r\n"
                + "Arguments:\r\n"
                + "    Counter    Defined counter to return information on\r\n"
                + "    MaxWarn    Value to trigger warning level\r\n"
                + "    MaxCrit    Value to trigger critical level"
        );
        const int counterSleepTime = 1000; // 1 Second (Same as default SampleInterval in Powershell's Get-Counter)
        string maxCrit = null;
        string maxWarn = null;
        string customCounter = null;

        try
        {
            var argsDict = callData.cmd
                .Select(line => line.Split('='))
                .Skip(1)
                .ToDictionary(
                    x => x[0].Trim().ToLower(),
                    x => x.ElementAtOrDefault(1) != null ? x[1] : "true"
                );

            var argsCount = argsDict.Count();

            if (argsCount == 0)
            {
                return check.ExitHelp();
            }

            foreach (var arg in argsDict)
            {
                switch(arg.Key)
                {
                    case "maxcrit":
                    {
                        maxCrit = arg.Value;
                        break;
                    }
                    case "maxwarn":
                    {
                        maxWarn = arg.Value;
                        break;
                    }
                    case "counter":
                    {
                        customCounter = arg.Value;
                        break;
                    }
                    case "help":
                    case "-h":
                    {
                        check.ExitHelp();
                        break;
                    }
                    default:
                    {
                       return check.ExitUnknown(String.Format("Unrecognised argument ({0})", arg.Key));                }
                    }
            };

            if (string.IsNullOrEmpty(customCounter))
            {
                return check.ExitUnknown("Missing arguments (Counter)");
            }
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }

        try
        {
            PerformanceCounter performanceCounter = null;
            // Checks if the counter name is formatted as expected
            // \object(parent/instance#index)\counter
            // the optional \\computer prefix is not supported
            // wildcard for the instance name is not supported
            var counterRegex = @"^\\([^(\\]+)(\(([^*)]*?)\))?\\(.+)$";
            var match = Regex.Match(customCounter, counterRegex);
            if(!match.Success)
            {
                return check.ExitUnknown(
                    string.Format("Incorrectly formatted counter '{0}'", customCounter)
                );
            }
            // example: Counter=\PhysicalDisk(0 C:)\Avg. Disk Read Queue Length"
            var category = match.Groups[1].Value;  // object
            var instance = match.Groups[3].Value;  // parent/instance#index
            var counter = match.Groups[4].Value;   // counter

            try
            {
                performanceCounter = PHM.GetCounter(category, counter, instance);
            }
            catch (System.InvalidOperationException e)
            {
                check.DebugLog(e.ToString());
                return check.ExitUnknown(
                    string.Format("Counter '{0}' not found, check path location ", customCounter)
                );
            }

            Thread.Sleep(counterSleepTime);

            check.AddMetric(
                name: customCounter,
                value: performanceCounter.NextValue(),
                uom: "",
                displayName: category + ' ' + counter,
                warningThreshold: maxWarn,
                criticalThreshold: maxCrit
            );
            return check.Final();
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }
    }
}
