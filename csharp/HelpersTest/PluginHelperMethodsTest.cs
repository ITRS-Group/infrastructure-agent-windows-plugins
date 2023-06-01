// Copyright (C) 2003-2023 ITRS Group Limited. All rights reserved
using NUnit.Framework;
using Helpers;
using System.Runtime.Versioning;

namespace HelpersTest;

[SupportedOSPlatform("windows")]
[TestFixture]
public class PluginHelpersTest
{
    [Test]
    public void GivenAValidCounter_WhenGetCounter_ThenPerformanceCounterReturned()
    {
        var result = PluginHelperMethods.GetCounter("Processor", "% Processor Time", "_Total");
        Assert.AreEqual(typeof(System.Diagnostics.PerformanceCounter), result.GetType());
    }

    [Test]
    public void GivenNonExistantCounter_WhenGetCounter_ThenExceptionThrown()
    {
        Assert.That(() => PluginHelperMethods.GetCounter("FantomMetric", "% Processor Time", "_Total"),
            Throws.TypeOf<InvalidOperationException>());
    }

    [Test]
    public void GivenWindowsOs_WhenGetWmiWin32OperatingSystem_ThenManagementObjectReturned()
    {
        var result = PluginHelperMethods.GetWmiWin32OperatingSystem();
        Assert.AreEqual(typeof(System.Management.ManagementObject), result.GetType());
    }

    [Test]
    public void GivenAValidManagementObject_WhenGetFirstManagementObject_ThenManagementObjectReturned()
    {
        var result = PluginHelperMethods.GetFirstMangementObjectSearchResult("select * from Win32_Processor");
        Assert.AreEqual(typeof(System.Management.ManagementObject), result.GetType());
    }

    [Test]
    public void GivenNonExistantManagementObj_WhenGetFirstManagementObject_ThenManagementExceptionThrown()
    {
        Assert.That(() => PluginHelperMethods.GetFirstMangementObjectSearchResult("select * from FantomObject"),
            Throws.TypeOf<System.Management.ManagementException>());
    }
}
