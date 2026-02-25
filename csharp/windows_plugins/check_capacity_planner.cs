// Plugin for the capacity planner Opspack for a Windows box
// Copyright (C) 2003-2026 ITRS Group Limited. All rights reserved

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management;
using System.Threading;
using Microsoft.Win32;

using PlugNSharp;
using PHM = Helpers.PluginHelperMethods;

class CheckCapacityPlanner
{
    const int NumberOfSamples = 5;
    const int CounterSleepTime = 1000; // 1 Second (Same as default SampleInterval in PowerShell's Get-Counter)

    private const string DescriptionText = @"
Copyright (C) 2003-2026 ITRS Group Limited. All rights reserved.
This plugin produces statistics for capacity planner for your Windows system.";

    private const string VersionNumber = "1.0.0";

    private const string HelpText = @"
Plugin Options:
  -m | --mode  Metric to Monitor
  Default Options:
  -h | --help  Show this help message

Capacity Planner Opspack Plugin supports the following modes:
  * cpu_model - Report the CPU model
  * filesystem_capacity - Report filesystem capacity, filesystems can be
                          by supplying options
  * filesystem_utilization - Report the current filesystem utilization,
                             filesystems can be by supplying options
  * hardware_model - Report the hardware model
  * hardware_vendor - Report the hardware vendor
  * os_version - Report the friendly OS name
  * server_specification - Report the physical cores, logical core, CPU clock
                           speed and memory capacity
  * server_utilization - Report the current CPU and memory utilization

Mode specific Options
  --exclude-filesystem - A comma seperated list of filesystem types to exclude
  --exclude-mount - A comma seperated list of filesystem mounts to exclude";

    private static Check check;
    private static String displayMessage = "";

    /// <summary>
    /// This plugin is designed to be used with the windows infrastructure agent, in
    /// order to use the plugin with the agent the following configuration should be
    /// provided:
    ///
    /// check_cp_cpu_model=scripts\check_capacity_planner.exe --mode cpu_model
    /// check_cp_hardware_model=scripts\check_capacity_planner.exe --mode hardware_model
    /// check_cp_hardware_vendor=scripts\check_capacity_planner.exe --mode hardware_vendor
    /// check_cp_filesystem_capacity=scripts\check_capacity_planner.exe --mode filesystem_capacity $ARG1$
    /// check_cp_filesystem_utilization=scripts\check_capacity_planner.exe --mode filesystem_utilization $ARG1$
    /// check_cp_os=scripts\check_capacity_planner.exe --mode os_version
    /// check_cp_server_specification=scripts\check_capacity_planner.exe --mode server_specification
    /// check_cp_server_utilization=scripts\check_capacity_planner.exe --mode server_utilization
    /// </summary>
    public static int Main(string[] args)
    {
        char[] trimChars = {'\'','"'};
        var mode = string.Empty;
        List<string> excludeFilesystemList = new List<string>();
        List<string> excludeMountList = new List<string>();

        check = new Check("check_capacity_planner", version: VersionNumber, description: DescriptionText, helpText: HelpText);

        if (args.Length == 0)
        {
            check.ExitHelp();
        }

        for (var i = 0; i <= args.Length - 1; i++)
        {
            switch (args[i].ToLower())
            {
                case "--mode":
                case "-m":
                    {
                        mode = args[i + 1];
                        i++;
                        break;
                    }
                case "--exclude-filesystem":
                    {
                        excludeFilesystemList = args[i + 1].Trim(trimChars).Split(',').ToList();
                        i++;
                        break;
                    }
                case "--exclude-mount":
                    {
                        excludeMountList = args[i + 1].Trim(trimChars).Split(',').ToList();
                        i++;
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
                        check.ExitUnknown(string.Format("Unknown option {0}", args[i]));
                        break;
                    }
            }
        }
        try {
            switch (mode)
            {
                case "cpu_model":
                    {
                        CheckCpuModel();
                        break;
                    }
                case "filesystem_capacity":
                    {
                        CheckFilesystemCapacity(excludeFilesystemList, excludeMountList);
                        break;
                    }
                case "filesystem_utilization":
                    {
                        CheckFilesystemUtilization(excludeFilesystemList, excludeMountList);
                        break;
                    }
                case "hardware_model":
                    {
                        CheckHardwareModel();
                        break;
                    }
                case "hardware_vendor":
                    {
                        CheckHardwareVendor();
                        break;
                    }
                case "os_version":
                    {
                        CheckOsVersion();
                        break;
                    }
                case "server_specification":
                    {
                        CheckServerSpecification();
                        break;
                    }
                case "server_utilization":
                    {
                        CheckServerUtilization();
                        break;
                    }
                default:
                    check.ExitUnknown(string.Format("Unknown mode: '{0}'", mode));
                    break;
            }
            check.Final();
        }
        catch (Exception e)
        {
            check.ExitUnknown(e.Message);
        }
        return 0;
    }

    /// <summary>
    /// Process CPU model check.
    /// </summary>
    private static void CheckCpuModel()
    {
        try {
            displayMessage = PHM.GetFirstMangementObjectSearchResult(
                "select * from Win32_Processor")["Name"].ToString();
        } catch {
            check.ExitUnknown("Integration impacted: could not retrieve physical server cpu model");
        }
        check.ExitOK(displayMessage);
    }

    /// <summary>
    /// Process filesystem capacity check.
    /// </summary>
    private static void CheckFilesystemCapacity(
        List<string> excludeFilesystemList,
        List<string> excludeMountList
    )
    {
        try {
            var filteredDrives = GetFilteredDrives(excludeFilesystemList, excludeMountList);

            check.AddMessage("Windows Filesystem Storage Capacity ");
            foreach (var drive in filteredDrives)
            {
                check.AddMetric(
                    name: drive.Name,
                    value: drive.TotalSize,
                    uom: "B",
                    displayName: drive.Name
                );
            }
        } catch {
            check.ExitUnknown("Integration broken: could not retrieve physical server filesystem capacity");
        }
    }

    /// <summary>
    /// Process filesystem utilization check.
    /// </summary>
    private static void CheckFilesystemUtilization(
        List<string> excludeFilesystemList,
        List<string> excludeMountList
    )
    {
        try {
            var filteredDrives = GetFilteredDrives(excludeFilesystemList, excludeMountList);

            check.AddMessage("Windows Filesystem Storage Utilization ");
            foreach (var drive in filteredDrives)
            {
                double freeSpace = drive.TotalFreeSpace;
                double totalSpace = drive.TotalSize;
                double percentUsed = 100.00 - (freeSpace / totalSpace) * 100;
                check.AddMetric(
                    name: drive.Name,
                    value: percentUsed,
                    uom: "%",
                    displayName: drive.Name
                );
            }
        } catch {
            check.ExitUnknown("Integration broken: could not retrieve physical server filesystem utilization");
        }
    }

    /// <summary>
    /// Process hardware model check.
    /// </summary>
    private static void CheckHardwareModel()
    {
        try {
            displayMessage = PHM.GetFirstMangementObjectSearchResult(
                "select * from Win32_ComputerSystem")["Model"].ToString();
        } catch {
            check.ExitUnknown("Integration impacted: could not retrieve physical server hardware model");
        }
        check.ExitOK(displayMessage);
    }

    /// <summary>
    /// Process hardware vendor check.
    /// </summary>
    private static void CheckHardwareVendor()
    {
        try {
            displayMessage = PHM.GetFirstMangementObjectSearchResult(
                "select * from Win32_ComputerSystem")["Manufacturer"].ToString();
        } catch {
            check.ExitUnknown("Integration impacted: could not retrieve physical server hardware vendor");
        }
        check.ExitOK(displayMessage);
    }

    /// <summary>
    /// Process OS version check.
    /// </summary>
    private static void CheckOsVersion()
    {
        try {
            displayMessage = (string)Registry.LocalMachine.OpenSubKey(
                "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion").GetValue("ProductName");
        } catch {
            check.ExitUnknown("Integration impacted: could not retrieve physical server operating system");
        }
        check.ExitOK(displayMessage);
    }

    /// <summary>
    /// Process server specification check.
    /// </summary>
    private static void CheckServerSpecification()
    {
        try {
            var cs = PHM.GetFirstMangementObjectSearchResult("select * from Win32_ComputerSystem");
            check.AddMetric(
                name: "Physical Cores",
                value: double.Parse(cs["NumberOfProcessors"].ToString()),
                uom: "",
                displayName: "Physical Cores"
            );
            check.AddMetric(
                name: "Logical Cores",
                value: double.Parse(cs["NumberOfLogicalProcessors"].ToString()),
                uom: "",
                displayName: "Logical Cores"
            );
            check.AddMetric(
                name: "Memory Capacity",
                value: double.Parse(cs["TotalPhysicalMemory"].ToString()),
                uom: "B",
                displayName: "Memory Capacity"
            );
            var proc = PHM.GetFirstMangementObjectSearchResult("select * from Win32_Processor");
            check.AddMetric(
                name: "CPU Clock Speed",
                value: double.Parse(proc["MaxClockSpeed"].ToString()),
                uom: "MHz",
                displayName: "CPU Clock Speed"
            );
        } catch {
            check.ExitUnknown("Integration broken: could not retrieve physical server specification");
        }
    }

    /// <summary>
    /// Process server utilization check.
    /// </summary>
    private static void CheckServerUtilization()
    {
        try {
            List<float> sampleList = new List<float>();
            float avgValue = 0.00F;
            var cpuInterruptTimeCounter = PHM.GetCounter("Processor", "% Processor Time", "_Total");
            for (int j = 0; j < NumberOfSamples; j++)
            {
                Thread.Sleep(CounterSleepTime);
                sampleList.Add(cpuInterruptTimeCounter.NextValue());
            }
            if (sampleList.Count() > 0)
            {
                avgValue = sampleList.Sum() / sampleList.Count();
            }
            check.AddMetric(
                name: "CPU Utilization",
                value: avgValue,
                uom: "%",
                displayName: "CPU Utilization"
            );

            ManagementObject win32OS = PHM.GetWmiWin32OperatingSystem();
            var memoryCapacityBytes =
                double.Parse(win32OS.Properties["TotalVisibleMemorySize"].Value.ToString()) * 1024;
            var freePhysicalMemoryBytes =
                double.Parse(win32OS.Properties["FreePhysicalMemory"].Value.ToString()) * 1024;

            double memoryUsed = memoryCapacityBytes - freePhysicalMemoryBytes;
            double memoryUsage = Math.Round((memoryUsed / memoryCapacityBytes) * 100, 2);
            check.AddMetric(
                name: "Memory Utilization",
                value: memoryUsage,
                uom: "%",
                displayName: "Memory Utilization"
            );
        } catch {
            check.ExitUnknown("Integration broken: could not retrieve physical server utilization");
        }
    }

    /// <summary>
    /// Produce a list of filtered drive information
    /// </summary>
    private static List<System.IO.DriveInfo> GetFilteredDrives(
        List<string> excludeFilesystemList,
        List<string> excludeMountList
    )
    {
        var drives = DriveInfo.GetDrives();
        var filteredDrives = drives.Where(p =>
            !excludeFilesystemList.Any(x => x == p.DriveType.ToString()) &&
            !excludeMountList.Any(y => y == p.Name)).ToList();
        return filteredDrives;
    }
}
