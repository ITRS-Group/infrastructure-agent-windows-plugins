// Company Confidential.
// Plugin to check the status of services running on a Windows box
// Rewrite of check_services.ps1 in C#
// Copyright (C) 2003-2023 ITRS Group Limited. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Linq;
using System.Management;
using System.Text.RegularExpressions;
using PlugNSharp;
using Helpers;
using PHM = Helpers.PluginHelperMethods;

static class CheckServiceState
{

    public static int Run(CallData callData)
    {
        bool showAll = false;
        var serviceState = string.Empty;
        var servicesDict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        int exitState = Check.EXIT_STATE_OK;
        var displayMessage = "";
        Dictionary<string, string> argsDict;
        var check = new Check(
            "check_servicestate",
            helpText: "Returns state of specified services\r\n"
                + "Arguments:\r\n"
                + "    <service-name>=<service-state> \r\n"
                + "        Specified service and its expected state\r\n"
                + "    <service-name>=<service-state> <service-name2>=<service-state> <service-name3>=<service-state>\r\n"
                + "        This check can take in a list of services and expected states by separating them with spaces\r\n"
                + "    State can be either started (default) or stopped\r\n"
                + "    ShowAll gives more verbose output"
        );
        try {
            argsDict = callData.cmd
            .Select(line => line.Split('='))
            .Skip(1)
            .ToDictionary(x => x[0].Trim(), x => x.ElementAtOrDefault(1) != null ? x[1].ToLower() : "true");
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
            var keyLower = arg.Key.ToLower();
            switch(keyLower)
            {
                case "help":
                case "-h":
                {
                    check.ExitHelp();
                    break;
                }
                case "showall":
                {
                    showAll = bool.Parse(arg.Value);
                    if (argsCount == 1)
                    {
                        return check.ExitUnknown("No services passed in");
                    }
                    break;
                }
                default:
                { 
                    // if it's a service
                    if ((arg.Value == "true") || (arg.Value == "started"))
                    // when no state is given
                    {
                        serviceState = "running";
                    }
                    else
                    // when a state is given
                    // (we don't bother to validate it as it will be compared with true state and fail)
                    {
                        serviceState = arg.Value;
                    }
                    servicesDict.Add(arg.Key, serviceState);
                    break;
                }
            }
        };

        ManagementObjectCollection win32Services = GetWMIWin32Services();
        foreach (var service in servicesDict)
        {
            var searcher = new ManagementObjectSearcher(string.Format(
                "SELECT * FROM Win32_Service WHERE Name = '{0}' OR DisplayName = '{0}'", service.Key
            ));
            var myService = searcher.Get().OfType<ManagementObject>().SingleOrDefault();
            if (myService == null)
            {
                displayMessage += service.Key + ": not found";
                exitState = Check.EXIT_STATE_CRITICAL;
            }
            else
            {
                var isCorrectState = myService["State"].ToString().ToLower().Equals(service.Value);
                if (showAll || !isCorrectState)
                {
                    displayMessage = string.Format(
                        "{0} {1}: {2} ",
                        displayMessage,
                        service.Key,
                        myService["State"].ToString().ToLower()
                    );
                    if (!isCorrectState)
                    {
                        exitState = Check.EXIT_STATE_CRITICAL;
                    }
                }
            }
        };
        if ((exitState == Check.EXIT_STATE_OK) && (!showAll))
        {
            displayMessage = "All services are in their appropriate state.";
        }
        else if (exitState == Check.EXIT_STATE_CRITICAL)
        {
            displayMessage += " (critical)";
        }
        return check.Final(displayMessage, exitState);
    }

    private static ManagementObjectCollection GetWMIWin32Services()
    {
        var osClass = new ManagementClass("Win32_Service");
        return osClass.GetInstances();
    }
}
