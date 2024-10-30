// Plugin to check the memory of a Windows box
// Copyright (C) 2003-2024 ITRS Group Ltd. All rights reserved

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
using System.Web.Script.Serialization;
using PlugNSharp;
using Helpers;
using PHM = Helpers.PluginHelperMethods;

static class CheckCPULoad
{
    const string EnvAgentPollerExec = "AGENT_POLLER_EXEC";
    const string EnvAgentPollerData = "AGENT_POLLER_DATA";
    const int PollIntervalSecs = 10;
    const int SecsPerMin = 60;
    const int SamplesIn1m = 1 * SecsPerMin / PollIntervalSecs;
    const int SamplesIn10m = 10 * SecsPerMin / PollIntervalSecs;
    const int MaxHistorySamples = SamplesIn10m;
    const int CounterSleepTime = 1000; // 1 Second (Same as default SampleInterval in Powershell's Get-Counter)

    public static int Run(CallData callData)
    {
        try
        {
            var execEnv = callData.GetEnvironmentVariable(EnvAgentPollerExec);
            var dataEnv = callData.GetEnvironmentVariable(EnvAgentPollerData);

            var serializer = new JavaScriptSerializer();
            List<float> sampleList;
            if (!String.IsNullOrEmpty(dataEnv))
            {
                // Parse the historic data
                sampleList = serializer.Deserialize<List<float>>(dataEnv);
            }
            else
            {
                // There is no historic data
                sampleList = new List<float>();
            }

            int retValue = 0;
            if (!String.IsNullOrEmpty(execEnv))
            {
                // Main path when being called by the Poller
                retValue = HandleDataPolling(sampleList);
                if (retValue == 0)
                {
                    var jsonData = serializer.Serialize(sampleList);
                    throw new ExitException(0, jsonData, "");
                }
            }
            else
            {
                // Main path when being called directly
                retValue = HandleDataAggregation(callData.cmd, sampleList);
            }
            return retValue;
        }
        catch (ExitException) { throw; }  // Standard plugin exit
        catch (Exception e)
        {
            throw new ExitException(1, "", e.ToString());
        }
    }

    /// <summary>
    /// Polls data for later aggregation. New values are appended to the passed in list of samples.
    /// </summary>
    private static int HandleDataPolling(List<float> sampleList)
    {
        var polledValue = PollCurrentData();

        sampleList.Add(polledValue);
        while (sampleList.Count() > MaxHistorySamples)
        {
            sampleList.RemoveAt(0);
        }
        return 0;
    }

    /// <summary>
    /// Returns latest polled data.
    /// </summary>
    private static float PollCurrentData()
    {
        var cpuInterruptTimeCounter = PHM.GetCounter("Processor", "% Processor Time", "_Total");
        Thread.Sleep(CounterSleepTime);
        var polledValue = cpuInterruptTimeCounter.NextValue();
        return polledValue;
    }

    /// <summary>
    /// Calculates and outputs the plugin results based on the previously recorded data
    /// </summary>
    private static int HandleDataAggregation(string[] cmdArgs, List<float> sampleList)
    {
        var check = new Check(
            "check_cpu_load",
            helpText: "Returns CPU load information over the last 1m/10m\r\n"
                + "Arguments:\r\n"
                + "    Warn     Value to trigger warning level\r\n"
                + "    Crit     Value to trigger critical level\r\n"
                + "    Time     Time interval (can have both time=1m and time=10m)\r\n"
                + "    ShowAll  Gives more verbose output"
        );
        string maxCrit = null;
        string maxWarn = null;
        string customCounter = string.Empty;
        try
        {
            // var arguments = Environment.GetCommandLineArgs();
            var arguments = cmdArgs;
            var clArgs = arguments
                .Select(a => a.Split('='))
                .Select(x => new Tuple<string, string>(x[0], x.ElementAtOrDefault(1)));

            var clArgList = clArgs.Skip(1).ToList();
            if (clArgList.Count() == 0)
            {
                return check.ExitHelp();
            }

            bool isLong = false;
            bool time1m = false;
            bool time10m = false;
            clArgList.ForEach(argTuple =>
            {
                var argValue = argTuple.Item2;
                switch (argTuple.Item1.ToLower())
                {
                    case "help":
                    case "-h":
                        check.ExitHelp();
                        break;

                    case "warn":
                        maxWarn = argValue;
                        break;

                    case "crit":
                        maxCrit = argValue;
                        break;

                    case "time":
                        if (argValue == "1m")
                        {
                            time1m = true;
                        }
                        else if (argValue == "10m")
                        {
                            time10m = true;
                        }
                        else
                        {
                            throw new Exception(
                                String.Format("Invalid time value: '{0}'", argValue)
                            );
                        }
                        break;

                    case "showall":
                        if (argValue == "long")
                        {
                            isLong = true;
                        }
                        else if (argValue != "short")
                        {
                            throw new Exception(
                                String.Format("Invalid ShowAll value: '{0}'", argValue)
                            );
                        }
                        break;

                    default:
                        throw new Exception(
                            String.Format("Unrecognised argument: '{0}'", argTuple.Item1)
                        );
                }
            });
            if (!time1m && !time10m)
            {
                throw new Exception("Missing 'time' arguments");
            }

            if (sampleList.Count() == 0)
            {
                // No previous values (probably because the poller hasn't run yet),
                //  so let's just poll for one now
                var polledValue = PollCurrentData();
                sampleList.Add(polledValue);
            }

            float avgValue = 0.0F;
            int sampleListLen = sampleList.Count();
            if (time10m)
            {
                if (sampleListLen > 0)
                {
                    // Use all the samples for the calculation
                    avgValue = sampleList.Sum() / sampleListLen;
                }
                var displayName = isLong ? "10m: average load" : "";
                check.AddMetric(
                    name: "10m",
                    value: avgValue,
                    uom: "%",
                    displayName: displayName,
                    displayFormat: "",
                    warningThreshold: maxWarn,
                    criticalThreshold: maxCrit
                );
            }

            if (time1m)
            {
                if (sampleListLen > 0)
                {
                    // Only use the samples from the last minute for the calculation
                    List<float> list1m = sampleList
                        .Skip(Math.Max(0, sampleListLen - SamplesIn1m))
                        .ToList();
                    avgValue = list1m.Sum() / list1m.Count();
                }
                var displayName = isLong ? "1m: average load" : "";
                check.AddMetric(
                    name: "1m",
                    value: avgValue,
                    uom: "%",
                    displayName: displayName,
                    displayFormat: "",
                    warningThreshold: maxWarn,
                    criticalThreshold: maxCrit
                );
            }
            return check.Final();
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }
    }
}
