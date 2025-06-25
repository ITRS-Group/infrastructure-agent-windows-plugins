// Plugin to check a custom performance counter of a Windows box
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
        const int counterSleepTime = 1000; // 1 Second (Same as default SampleInterval in Powershell's Get-Counter)
        string critThreshold = null;
        string warnThreshold = null;
        string customCounter = null;
        bool legacyMode = false;

        try
        {
            // Allow for '=' delimiter in args
            var args = new List<string>();
            var delim = new char[] { '=' };
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

                        case "counter":
                            customCounter = args[i + 1];
                            i++;
                            break;

                        case "h":
                        case "help":
                            return check.ExitHelp();

                        default:
                            return check.ExitUnknown(String.Format("Unrecognised argument ({0})", args[i]));
                    }
                    i++;
                }
            }
            catch (IndexOutOfRangeException)
            {
                return check.ExitUnknown("Incorrectly formatted arguments");
            }

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
            // The optional \\computer prefix is not supported
            // Wildcards for the overall instance name is not supported, only the special exception below for disk checks
            // Example: Counter=\PhysicalDisk(0 C:)\Avg. Disk Read Queue Length"
            var counterRegex = @"^\\([^(\\]+)(\((\* )?([^*)]*?)\))?\\(.+)$";
            var match = Regex.Match(customCounter, counterRegex);
            if (!match.Success)
            {
                return check.ExitUnknown(
                    string.Format("Incorrectly formatted counter '{0}'", customCounter)
                );
            }

            var category = match.Groups[1].Value;  // object
            var instance = "";
            var counter = match.Groups[5].Value;   // counter
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
                warningThreshold: warnThreshold,
                criticalThreshold: critThreshold
            );
            return check.Final();
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }
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
