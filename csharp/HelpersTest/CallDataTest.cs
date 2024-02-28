// Copyright (C) 2003-2024 ITRS Group Limited. All rights reserved
using NUnit.Framework;
using Helpers;
using System.Runtime.Versioning;
using Newtonsoft.Json;

namespace HelpersTest;

[SupportedOSPlatform("windows")]
[TestFixture]
public class CallDataTest
{
    [TestCase("from call data", "ENV_TEST",
        "{'cmd': ['check_test', '-mode', 'testMode'], 'env': {'ENV_TEST': 'from call data'}}")]
    [TestCase("from env var", "ENV_TEST",
        "{'cmd': ['check_test', '-mode', 'testMode'], 'env': {}}")]
    [TestCase("from env var", "ENV_TEST",
        "{'cmd': []}")]
    [TestCase(null, "NULL_ENV_TEST",
        "{'cmd': []}")]
    public void GivenCallData_WhenGetEnvironmentVariable_ThenValueReturnedFromCallDataElseEnvironment(
        String expected, String varName, String jsonLine)
    {
        Environment.SetEnvironmentVariable("ENV_TEST", "from env var");
        CallData callData = JsonConvert.DeserializeObject<CallData>(jsonLine);
        Assert.AreEqual(expected, callData.GetEnvironmentVariable(varName));
    }

    [TestCase(true, "{'cmd': ['check_test', '-mode', 'testMode']}")]
    [TestCase(false, "{'cmd': []}")]
    public void GivenCallData_WhenHasCmdArgs_ThenArgsExistenceReturned(bool hasArgs, String jsonLine)
    {
        CallData callData = JsonConvert.DeserializeObject<CallData>(jsonLine);
        Assert.AreEqual(hasArgs, callData.HasCmdArgs());
    }
}
