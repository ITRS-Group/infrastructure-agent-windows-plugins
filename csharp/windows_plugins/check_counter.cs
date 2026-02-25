// Plugin to check a custom performance counter of a Windows box
// Copyright (C) 2003-2026 ITRS Group Limited. All rights reserved

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

public class Counter
{
    public string name;
    public string alias;

    public Counter(string name, string alias = "")
    {
        this.name = name;
        this.alias = alias;
    }
}

static class CheckCounter
{
    // Regex to check if the counter name is formatted as expected
    // \object(parent/instance#index)\counter
    // The optional \\computer prefix is not supported
    // Wildcard for the overall instance name is not supported, only the special exception for disk checks
    // Example: Counter=\PhysicalDisk(0 C:)\Avg. Disk Read Queue Length"
    private const string counterRegex = @"^\\([^(\\]+)(\((\* )?([^*)]*?)\))?\\(.+)$";

    // 1 Second (Same as default SampleInterval in Powershell's Get-Counter)
    private const int counterSleepTime = 1000;

    public static int Run(CallData callData)
    {
        var check = new Check(
            "check_counter",
            helpText: "Returns information for a given counter\r\n"
                + "Arguments:\r\n"
                + "    Counter    Defined counter to return information on\r\n"
                + "    Warn       Warning threshold (supports nagios threshold syntax)\r\n"
                + "    MinWarn    Trigger warning if counter < than this value (numeric)\r\n"
                + "    MaxWarn    Trigger warning if counter > than this value (numeric)\r\n"
                + "    Crit       Critical threshold (supports nagios threshold syntax)\r\n"
                + "    MinCrit    Trigger critical if counter < than this value (numeric)\r\n"
                + "    MaxCrit    Trigger critical if counter > than this value (numeric)\r\n"
                + "    Legacy     Causes MinWarn/MinCrit to trigger if counter <= their value, and MaxWarn/MaxCrit to trigger if counter >= their value\r\n"
                + "\r\n"
                + "Only one of (Warn, MinWarn, MaxWarn) and/or (Crit, MinCrit, MaxCrit) can be set if using thresholds.\r\n"
                + "Use Warn or Crit for more complex thresholds.\r\n"
                + "\r\n"
                + "Nagios threshold syntax: https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT\r\n"
        );
        string critThreshold = null;
        string warnThreshold = null;
        var counters = new List<Counter>();
        bool legacyMode = false;
        bool averages = true;
        int invalidStatus = Check.EXIT_STATE_UNKNOWN;

        try
        {
            // Allow for '=' delimiter in args
            var args = new List<string>();
            var delim = new char[] { '=' };
            var counterDelim = new char[] { ':' };
            foreach (string arg in callData.cmd)
            {
                var items = arg.Split(delim, 2, StringSplitOptions.None);
                args.AddRange(items);
            }

            // First arg will be the command name, so don't consider it
            if (args.Count <= 1)
            {
                return check.ExitHelp();
            }

            // Parse args
            try
            {
                // Do a first pass through args for legacy mode as this affects processing of threshold args later
                legacyMode = args.Select(a => a.TrimStart('-').ToLower()).Contains("legacy");

                // Now parse the rest of the args for everything else
                var i = 1;
                while (i < args.Count)
                {
                    switch (args[i].TrimStart('-').ToLower())
                    {
                        // See threshold format docs here:
                        // https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
                        //
                        // We currently support nagios style thresholds as well as some simpler min/max thresholds,
                        // plus a hidden "legacy" mode which switches min/max to "inclusive" rather than "exclusive",
                        // created to make migrating easier for Cloudwave. This MUST be the first argument set, if used.
                        case "legacy":
                            break;  // Already handled above

                        case "showall":
                            break;  // Backwards compatability

                        case "averages":
                            var avge = args[i + 1].ToLower();
                            i++;
                            if (avge == "false" || avge == "0")
                            {
                                averages = false;
                            }
                            break;  // Backwards compatability

                        case "crit":
                            critThreshold = ValidateAndGetThreshold(check, critThreshold, args[i + 1], false);
                            i++;
                            break;

                        case "mincrit":
                            critThreshold = ValidateAndGetThreshold(check, critThreshold, args[i + 1], true);
                            i++;
                            if (legacyMode)
                            {
                                // In legacy mode, this should be inclusive - this syntax means: trigger if <= value
                                critThreshold = string.Format("@~:{0}", critThreshold);
                            }
                            else
                            {
                                // otherwise this should be exclusive - this syntax means: trigger if < value
                                critThreshold = string.Format("{0}:", critThreshold);
                            }
                            break;

                        case "maxcrit":
                            critThreshold = ValidateAndGetThreshold(check, critThreshold, args[i + 1], true);
                            i++;
                            if (legacyMode)
                            {
                                // In legacy mode, this should be inclusive - this syntax means: trigger if >= value
                                critThreshold = string.Format("@{0}:", critThreshold);
                            }
                            // otherwise this should be exclusive, trigger if > value,
                            // which is the default behaviour for a lone value anyway
                            break;
    
                        case "warn":
                            warnThreshold = ValidateAndGetThreshold(check, warnThreshold, args[i + 1], false);
                            i++;
                            break;
    
                        case "minwarn":
                            warnThreshold = ValidateAndGetThreshold(check, warnThreshold, args[i + 1], true);
                            i++;
                            if (legacyMode)
                            {
                                // In legacy mode, this should be inclusive - this syntax means: trigger if <= value
                                warnThreshold = string.Format("@~:{0}", warnThreshold);
                            }
                            else
                            {
                                // otherwise this should be exclusive - this syntax means: trigger if < value
                                warnThreshold = string.Format("{0}:", warnThreshold);
                            }
                            break;
    
                        case "maxwarn":
                            warnThreshold = ValidateAndGetThreshold(check, warnThreshold, args[i + 1], true);
                            i++;
                            if (legacyMode)
                            {
                                // In legacy mode, this should be inclusive - this syntax means: trigger if >= value
                                warnThreshold = string.Format("@{0}:", warnThreshold);
                            }
                            // otherwise this should be exclusive, trigger if > value,
                            // which is the default behaviour for a lone value anyway
                            break;

                        case "invalidstatus":
                            // The status to be returned if an invalid counter was requested
                            switch (args[i + 1].TrimStart('-').ToLower())
                            {
                                case "ok":
                                    invalidStatus = Check.EXIT_STATE_OK;
                                    break;
                                case "warning":
                                    invalidStatus = Check.EXIT_STATE_WARNING;
                                    break;
                                case "critical":
                                    invalidStatus = Check.EXIT_STATE_CRITICAL;
                                    break;
                                case "unknown":
                                    invalidStatus = Check.EXIT_STATE_UNKNOWN;
                                    break;
                                default:
                                    if (!Int32.TryParse(args[i + 1], out invalidStatus))
                                    {
                                        return check.ExitUnknown(String.Format("Invalid InvalidStatus ({0})", args[i + 1]));
                                    }
                                    break;
                            }
                            i++;
                            break;

                        case "counter":
                            counters.Add(new Counter(args[i + 1], ""));
                            i++;
                            break;

                        case "h":
                        case "help":
                            return check.ExitHelp();

                        default:
                            // check for counter:name
                            var parts = args[i].Split(counterDelim, 2, StringSplitOptions.None);
                            if ((parts.Length == 2) && (parts[0].TrimStart('-').ToLower() == "counter"))
                            {
                                counters.Add(new Counter(args[i + 1], parts[1]));
                                i++;
                                break;
                            }
                            return check.ExitUnknown(String.Format("Unrecognised argument ({0})", args[i]));
                    }
                    i++;
                }
            }
            catch (IndexOutOfRangeException)
            {
                return check.ExitUnknown("Incorrectly formatted arguments");
            }

            if (counters.Count() == 0)
            {
                return check.ExitUnknown("Missing arguments (Counter)");
            }
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }

        foreach (var counter in counters)
        {
            try
            {
                PerformanceCounter performanceCounter = null;
                var match = Regex.Match(counter.name, counterRegex);
                if (!match.Success)
                {
                    return check.ExitUnknown(
                        string.Format("Incorrectly formatted counter '{0}'", counter.name)
                    );
                }

                var category = match.Groups[1].Value;  // object
                var instance = "";
                var counterName = match.Groups[5].Value;   // counter
                if (match.Groups[3].Value == "* ")
                {
                    // Contains a wildcard
                    // This implementation is for backwards compatibility on customer disk checks only,
                    // to match the disk index, and will return only the first match found
                    // Example: Counter=\PhysicalDisk(* C:)\Avg. Disk Read Queue Length"
                    instance = match.Groups[3].Value + match.Groups[4].Value;  // parent/instance#index
                    var pattern = instance.Replace("* ", "^.* ") + "$";
                    PerformanceCounterCategory pcc = new PerformanceCounterCategory(category);
                    string[] categoryInstances = pcc.GetInstanceNames();
                    foreach (string inst in categoryInstances)
                    {
                        var found = Regex.Match(inst, pattern);
                        if (found.Success)
                        {
                            instance = inst;
                            break;
                        }
                    }
                }
                else
                {
                    instance = match.Groups[4].Value;  // parent/instance#index
                }

                try
                {
                    performanceCounter = PHM.GetCounter(category, counterName, instance);
                }
                catch (System.InvalidOperationException e)
                {
                    check.DebugLog(e.ToString());
                    return check.Exit(
                        invalidStatus,
                        string.Format("Counter '{0}' not found, check path location ", counter.name)
                    );
                }

                if (averages)
                {
                    // This sleep is required before the call to NextValue() for values that are averages
                    Thread.Sleep(counterSleepTime);
                }

                check.AddMetric(
                    name: counter.alias == "" ? counter.name : counter.alias,
                    value: performanceCounter.NextValue(),
                    uom: "",
                    displayName: counter.alias == "" ? category + ' ' + counterName : counter.alias,
                    warningThreshold: warnThreshold,
                    criticalThreshold: critThreshold
                );

                if (averages)
                {
                    Thread.Sleep(counterSleepTime);
                }
            }
            catch (ExitException) { throw; }
            catch (Exception e)
            {
                return check.ExitUnknown(e.Message);
            }
        }

        return check.Final();
    }

    /// <summary>
    /// Validates threshold arguments - no more than one type of warning or critical threshold should be set,
    /// and min/max thresholds should be numeric
    /// </summary>
    private static string ValidateAndGetThreshold(Check check, string currentThreshold, string newThreshold, bool validateIsNumeric)
    {
        if (String.IsNullOrEmpty(newThreshold))
        {
            check.ExitUnknown("Invalid empty threshold.");
        }

        if (currentThreshold != null)
        {
            check.ExitUnknown(
                "Only one of (Crit, MinCrit, MaxCrit) or (Warn, MinWarn, MaxWarn) can be set if using thresholds "
                + "(use Crit/Warn for more complex thresholds)."
            );
        }

        if (validateIsNumeric)
        {
            // Check if numeric - accept int/double-like values, but not using TryParse to avoid weirdness like NaN etc.
            var numericRegex = @"^\d+(\.\d+)?$";
            var match = Regex.Match(newThreshold, numericRegex);
            if (!match.Success)
            {
                check.ExitUnknown(
                    "Min/Max thresholds must be numeric and cannot be negative "
                    + "(use Crit/Warn for more complex thresholds)."
                );
            }
        }

        return newThreshold;
    }
}
