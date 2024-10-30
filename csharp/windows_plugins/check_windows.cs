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


static class CheckWindows
{
    const string CHECK_COUNTER = "check_counter";
    const string CHECK_CPU_LOAD = "check_cpu_load";
    const string CHECK_DRIVESIZE = "check_drivesize";
    const string CHECK_EVENTLOG = "check_eventlog";
    const string CHECK_MEMORY = "check_memory";
    const string CHECK_SERVICESTATE = "check_servicestate";
    const string CHECK_HTTP = "check_http";
    const string CHECK_SSL = "check_ssl";
    static readonly string[] CHECKS = {
    	CHECK_COUNTER, CHECK_CPU_LOAD, CHECK_DRIVESIZE, CHECK_EVENTLOG,
    	CHECK_MEMORY, CHECK_SERVICESTATE, CHECK_HTTP, CHECK_SSL,
	};
    const int EXIT_UNKNOWN = 3;
    const string ENV_LONG_RUNNING_PROCESS = "LONG_RUNNING_PROCESS";

    private static void PluginDispatcher(string name, CallData callData)
    {
        switch (name)
        {
            case CHECK_COUNTER:
                CheckCounter.Run(callData);
                break;
            case CHECK_CPU_LOAD:
                CheckCPULoad.Run(callData);
                break;
            case CHECK_DRIVESIZE:
                CheckDriveSize.Run(callData);
                break;
            case CHECK_EVENTLOG:
                CheckEventLog.Run(callData);
                break;
            case CHECK_MEMORY:
                CheckMemory.Run(callData);
                break;
            case CHECK_SERVICESTATE:
                CheckServiceState.Run(callData);
                break;
            case CHECK_HTTP:
                CheckHttp.Run(callData);
                break;
            case CHECK_SSL:
                CheckSsl.Run(callData);
                break;
            default:
                throw new ExitException(EXIT_UNKNOWN, stderr: String.Format("Unknown plugin '{0}'", name));
        }
    }

    private static void ExitWrapperCheck(string errorText = null)
    {
    	var pluginList = String.Join(", ", CHECKS);
        var check = new Check(
            "check_windows",
            helpText: "Executes Windows plugins from a long running process.\r\n\r\n"
                + "    Launch without command line args then pass plugin arguments via STDIN.\r\n"
                + "    The first argument should be the name of the plugin to execute.\r\n"
                + "    Available plugins are:\r\n    " + pluginList
        );
        if (string.IsNullOrEmpty(errorText)) {
            check.ExitHelp();
        } else {
            check.ExitUnknown(errorText);
        }
    }

    public static int Main()
    {
        try
        {
            Console.OutputEncoding = System.Text.Encoding.UTF8;
            var arguments = Environment.GetCommandLineArgs();
            if (arguments.Length > 1) ExitWrapperCheck();

            var serializer = new JavaScriptSerializer();
            string jsonLine;
            while ((jsonLine = Console.ReadLine()) != null) {
                CallData callData = serializer.Deserialize<CallData>(jsonLine);
                try
                {
                    if (!callData.HasCmdArgs()) throw new ExitException(EXIT_UNKNOWN, stderr: "Missing plugin argument.");
                    var pluginKey = callData.cmd[0];
                    PluginDispatcher(pluginKey, callData);
                    throw new ExitException(EXIT_UNKNOWN, stderr: String.Format("Plugin '{0}' did not exit correctly", pluginKey));
                }
                catch (ExitException e)
                {
                    // Plugin exit point
                    string outputJson = serializer.Serialize(e.output);
                    Console.WriteLine(outputJson);
                }
                if (callData.GetEnvironmentVariable(ENV_LONG_RUNNING_PROCESS) != "1") break;
            }
            return 0;
        }
        catch (ExitException e)
        {
            // Wrapper exit point
            var output = e.output;
            if (!string.IsNullOrEmpty(output.stdout)) Console.WriteLine(output.stdout);
            if (!string.IsNullOrEmpty(output.stderr)) Console.Error.WriteLine(output.stderr);
            return output.exitcode;
        }
        catch (Exception e)
        {
            Console.Error.WriteLine(e);
            return EXIT_UNKNOWN;
        }
    }
}
