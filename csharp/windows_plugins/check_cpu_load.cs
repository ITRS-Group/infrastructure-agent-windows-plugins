// Plugin to check the memory of a Windows box
// Company Confidential.
// Copyright (C) 2003-2026 ITRS Group Ltd. All rights reserved

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
    const string EnvAgentPollerSchedule = "POLLER_INTERVAL";
    const int SecsPerMin = 60;
    const int MaxMin = 60;
    const int MaxSec = MaxMin * SecsPerMin;
    const int CounterSleepTime = 1000; // 1 Second (Same as default SampleInterval in Powershell's Get-Counter)
    static int PollIntervalSecs = 1; // if no poller_schedule set, default to 1 second?
    static int MaxHistorySamples = 1; // since if no poller schedule set, we only keep 1 sample or no historic data
    
    public static int Run(CallData callData)
    {
        try
        {
            var execEnv = callData.GetEnvironmentVariable(EnvAgentPollerExec);
            var dataEnv = callData.GetEnvironmentVariable(EnvAgentPollerData);
            var pollerEnv = callData.GetEnvironmentVariable(EnvAgentPollerSchedule);

            var serializer = new JavaScriptSerializer();
            List<float> sampleList;

            // Set the poll interval based on the environment variable
            if (!String.IsNullOrEmpty(pollerEnv) && int.TryParse(pollerEnv, out PollIntervalSecs))
            {
                PollIntervalSecs = Math.Max(PollIntervalSecs, 1);
                MaxHistorySamples = MaxSec / PollIntervalSecs;
            }

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
            helpText: "Returns CPU load information for a specified time interval in an hour\r\n"
                + "Arguments:\r\n"
                + "    Warn     Value to trigger warning level\r\n"
                + "    Crit     Value to trigger critical level\r\n"
                + "    Time     Time interval (can have multiple, in seconds [s] or minutes [m] format)\r\n"
                + "    ShowAll  Gives more verbose output\r\n\n"
                + "Notes: \r\n"
                + "    Results are polled every " + PollIntervalSecs + " seconds.\r\n"
                + "    Time allows maximum of 1hr equivalent (60m | 3600s). For seconds, time should be no less than " +  PollIntervalSecs + "s.\r\n"
                + "    If no unit is provided, Time is assumed to be in minutes."
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
            int samples = 0;
            int timeVal = 0;
            char timeUnit = '0';
            List<KeyValuePair<string, int>> timeSamples = new List<KeyValuePair<string, int>>();
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
                        // check if time is not empty, null
                        if (string.IsNullOrEmpty(argValue))
                        {
                            throw new ArgumentException("Time value cannot be null or empty.");
                        }
                        
                        // check if number and set time unit
                        timeUnit = char.ToLower(argValue[argValue.Length - 1]);
                        try  
                        { 
                            if (char.IsDigit(timeUnit)) //no time unit specified
                            {
                                timeVal = int.Parse(argValue);
                                timeUnit = 'm'; //assume minutes
                            }
                            else
                            {
                                timeVal = int.Parse(argValue.Substring(0, argValue.Length-1));
                            }
                        }
                        catch (Exception ex)
                        {
                            throw new Exception(
                                String.Format("Invalid time value: '{0}'\r\n\n{1}", argValue, ex.Message)
                            );
                        }

                        // check if time is greater than 0
                        if (timeVal <= 0)
                        {
                             throw new Exception(
                                String.Format("Invalid time value: '{0}'", argValue)
                            );
                        }

                        // check if time is minutes or seconds, and if it is within valid range
                        // samples can't be 0 to avoid issues when computing for the avgValue for the metrics
                        if (timeUnit == 'm' && timeVal <= MaxMin && (timeVal * SecsPerMin) >= PollIntervalSecs)
                        {
                            samples = timeVal * SecsPerMin / PollIntervalSecs;
                        }
                        else if (timeUnit == 's' && timeVal <= MaxSec && timeVal >= PollIntervalSecs)
                        {
                            samples = timeVal / PollIntervalSecs;
                        }
                        else
                        {
                            throw new Exception(
                                String.Format("Invalid time value: '{0}'", argValue)
                            );
                        }

                        timeSamples.Add(new KeyValuePair<string, int>(argValue, samples));
                        
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

            if (!timeSamples.Any())
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
            var displayName = "";
            
            if (sampleListLen > 0)
            {
                foreach (KeyValuePair<string, int> ts in timeSamples)
                {
                    if (ts.Value == MaxHistorySamples)
                    {
                        // Use all the samples for the calculation
                        avgValue = sampleList.Sum() / sampleListLen;
                    }
                    else
                    {
                        // Only use the samples from the specified time for the calculation
                        List<float> customList = sampleList
                            .Skip(Math.Max(0, sampleListLen - ts.Value))
                            .ToList();

                        if (!customList.Any())
                        {
                            throw new Exception("No data available for the specified time period");
                        }

                        avgValue = customList.Sum() / customList.Count();
                    }

                    displayName = isLong ? ts.Key + ": average load" : "";
                    avgValue = (float)Math.Round(avgValue, 2);
                    
                    check.AddMetric(
                        name: ts.Key,
                        value: avgValue,
                        uom: "%",
                        displayName: displayName,
                        displayFormat: "",
                        warningThreshold: maxWarn,
                        criticalThreshold: maxCrit
                    );
                }
            }
            else
            {
                foreach (KeyValuePair<string, int> ts in timeSamples)
                {
                    displayName = isLong ? ts.Key + ": average load" : "";
                    check.AddMetric(
                        name: ts.Key,
                        value: avgValue, // No data collected, so value is 0
                        uom: "%",
                        displayName: displayName,
                        displayFormat: "",
                        warningThreshold: maxWarn,
                        criticalThreshold: maxCrit
                    );
                }
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
