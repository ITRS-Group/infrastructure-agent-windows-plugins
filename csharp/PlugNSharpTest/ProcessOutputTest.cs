// Copyright (C) 2003-2025 ITRS Group Limited. All rights reserved
using NUnit.Framework;
using PlugNSharp;
using System;
using System.Runtime.Versioning;

namespace PlugNSharpTest
{

    [SupportedOSPlatform("windows")]
    [TestFixture]
    public class ProcessOutputTest
    {
        [Test]
        public void GivenADisplayName_WhenSummaryGenerated_ThenSummaryUsesDisplayName()
        {
            ProcessOutput processOutput = new ProcessOutput(0, "Some standard out content", "Some standard error content");

            Assert.AreEqual(0, processOutput.exitcode);
            Assert.AreEqual("Some standard out content", processOutput.stdout);
            Assert.AreEqual("Some standard error content", processOutput.stderr);
        }

    }
}
