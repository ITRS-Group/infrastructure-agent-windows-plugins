// Copyright (C) 2003-2024 ITRS Group Limited. All rights reserved
using System.Diagnostics;
using System.Linq;
using System.Management;

namespace Helpers
{
    public class PluginHelperMethods
    {
        /// <summary>
        /// Returns the requested PerformanceCounter object, catching any errors exiting UNKNOWN
        /// if the counter cannot be found.
        /// </summary>
        public static PerformanceCounter GetCounter(
            string category,
            string counter,
            string instanceName = ""
        )
        {
            var performanceCounter = new PerformanceCounter(category, counter);
            if (!string.IsNullOrEmpty(instanceName))
            {
                performanceCounter.InstanceName = instanceName;
            }
            performanceCounter.NextValue();

            return performanceCounter;
        }

        /// <summary>
        /// Returns a "Win32_OperatingSystem" ManagementObject
        /// </summary>
        public static ManagementObject GetWmiWin32OperatingSystem()
        {
            // This should be possible using some LINQ magic `return osClass.GetInstances().Single()`
            // But ManagementObjectCollection doesn't implement IEnumerable
            // (See: https://github.com/dotnet/runtime/issues/34803)
            var managementObject = new ManagementObject();
            var osClass = new ManagementClass("Win32_OperatingSystem");
            foreach (ManagementObject queryObj in osClass.GetInstances())
            {
                managementObject = queryObj;
                break;
            }
            return managementObject;
        }

        /// <summary>
        /// Returns the first result from a management object search
        /// </summary>
        public static ManagementObject GetFirstMangementObjectSearchResult(
            string searchString = ""
        )
        {
            var searchResult = new ManagementObjectSearcher( searchString )
                                .Get()
                                .Cast<ManagementObject>()
                                .First();
            return searchResult;
        }
    }
}
