// Company Confidential.
// Plugin to check the status of services running on a Windows box
// Rewrite of OpsviewAgent check_services.ps1, when running in >= Windows V10 mode
// Copyright (C) 2003-2025 ITRS Group Ltd. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.ServiceProcess;
using System.Diagnostics;
using System.Linq;
using System.Management;
using System.Text.RegularExpressions;
using Helpers;
using PlugNSharp;

static class CheckServices
{
    private const string StatusRunning = "Running";

    public static int Run(CallData callData)
    {
        var statusDict = new OrderedDictionary {
            {StatusRunning, 0},
            {"Stopped", 0},
            {"Paused", 0},
            {"ContinuePending", 0},
            {"PausePending", 0},
            {"StartPending", 0},
            {"StopPending", 0},
        };
        var statusList = statusDict.Keys.Cast<string>().ToList();

        var check = new Check(
            "check_services",
            helpText: "Checks the status of Windows Services.\r\n\r\n"
                + "Returns CRITICAL if any matched Services are not running.\r\n"
                + "By default, all Services are matched.\r\n"
                + "\r\nArguments:\r\n"
                + "  ServiceName     CSV list of name patterns to match\r\n"
                + "  ExcludeService  CSV list of name patterns to exclude\r\n"
                + "  ExcludeStatus   CSV list of statuses to exclude\r\n"
                + "      from (" + string.Join(", ", statusList) + ")\r\n"
                + "  StartMode       CSV list of start-modes to match\r\n"
                + "      from (Boot, System, Automatic, Manual, Disabled)\r\n"
                + "  Verbose         Display statuses for all matched Services\r\n"
                + "  Help\r\n"
                + "Name patterns can use wildcards (* and ?)."
        );

        List<Regex> serviceNameList = null;
        List<Regex> excludeServiceList = null;
        HashSet<string> excludeStatusList = null;
        HashSet<string> startModeList = null;

        var verbose = false;

        // Allow for '=' delimiter in args
        var args = new List<string>();
        var delim = new char[] { '=' };
        foreach (string arg in callData.cmd)
        {
            var items = arg.Split(delim, 2, StringSplitOptions.None);
            args.AddRange(items);
        }

        // Parse args
        var i = 1;
        try
        {
            while (i < args.Count)
            {
                switch (args[i].TrimStart('-').ToLower())
                {
                    case "servicename":
                        serviceNameList = args[i + 1].ToLower().Split(',').Select(p => SearchPatternToRegex(p)).ToList();
                        i++;
                        break;
                    case "excludeservice":
                        excludeServiceList = args[i + 1].ToLower().Split(',').Select(p => SearchPatternToRegex(p)).ToList();
                        i++;
                        break;
                    case "excludestatus":
                        excludeStatusList = new HashSet<string>(args[i + 1].ToLower().Split(','));
                        i++;
                        break;
                    case "startmode":
                        startModeList = new HashSet<string>(
                            args[i + 1].ToLower().Split(',').Select(sm => sm.Equals("auto") ? "automatic" : sm)
                        );
                        i++;
                        break;
                    case "verbose":
                        verbose = true;
                        break;
                    case "h":
                    case "help":
                        return check.ExitHelp();
                    default:
                        return check.ExitUnknown(string.Format("Unknown option {0}", args[i]));
                }
                i++;
            }
        }
        catch (IndexOutOfRangeException)
        {
            return check.ExitUnknown("Incorrectly formatted arguments");
        }

        var exitState = 0;
        var displayMessage = "";
        try
        {
            var serviceList = ServiceController.GetServices();
            var matchedServiceCount = 0;
            foreach (ServiceController svc in serviceList)
            {
                var svcNameL = svc.ServiceName.ToLower();
                var svcStatus = svc.Status.ToString();
                var svcStatusL = svcStatus.ToLower();
                var svcStartTypeL = svc.StartType.ToString().ToLower();
                if (
                    ((serviceNameList == null) || RegexListMatchesString(serviceNameList, svcNameL)) &&
                    ((excludeServiceList == null) || !RegexListMatchesString(excludeServiceList, svcNameL)) &&
                    ((excludeStatusList == null) || !excludeStatusList.Contains(svcStatusL)) &&
                    ((startModeList == null) || startModeList.Contains(svcStartTypeL))
                )
                {
                    if (!svcStatus.Equals(StatusRunning))
                    {
                        exitState = Check.EXIT_STATE_CRITICAL;
                        displayMessage = string.Format("{0} {1} (Status: {2}),", displayMessage, svc.ServiceName, svc.Status);
                    }
                    else if (verbose)
                    {
                        displayMessage = string.Format("{0} {1} (Status: {2}),", displayMessage, svc.ServiceName, svc.Status);
                    }
                    statusDict[svcStatus] = (int)statusDict[svcStatus] + 1;
                    matchedServiceCount++;
                }
            }

            if (matchedServiceCount == 0)
            {
                return check.ExitUnknown("No Services matching criteria");
            }

            // Add performance metrics
            foreach (DictionaryEntry item in statusDict)
            {
                check.AddMetric(name: item.Key.ToString(), value: Convert.ToDouble(item.Value), uom: "", displayInSummary: false);
            }
            if ((exitState == Check.EXIT_STATE_OK) && !verbose)
            {
                displayMessage = "All Services running";
            }
            else
            {
                displayMessage = displayMessage.TrimEnd(',');
            }
        }
        catch (ExitException) { throw; }  // Standard plugin exit
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }
        return check.Final(displayMessage, exitState);
    }

    private static Regex SearchPatternToRegex(string searchPattern)
    {
        // Convert wildcard (using "?" or "*") search pattern to regex
        var rePattern = Regex.Replace(searchPattern, @"([\\\+\|\{\}\[\]\(\)\^\$\.\#])", @"\$1")
            .Replace("?", ".")
            .Replace("*", ".*");
        return new Regex('^' + rePattern + '$', RegexOptions.IgnoreCase);
    }

    private static bool RegexListMatchesString(IEnumerable<Regex> regexList, string value)
    {
        return regexList.Any(re => re.IsMatch(value));
    }
}
