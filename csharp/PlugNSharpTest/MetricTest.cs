// Copyright (C) 2003-2024 ITRS Group Limited. All rights reserved
using NUnit.Framework;
using PlugNSharp;
using System;
using System.Runtime.Versioning;

namespace PlugNSharpTest
{

    [SupportedOSPlatform("windows")]
    [TestFixture]
    public class MetricTest
    {
        [TestCase("Invalid=Metric Name")]
        [TestCase("Invalid\"Metric Name")]
        [TestCase("Invalid'Metric Name")]
        public void GivenAMetricNameWithInvalidChars_WhenNewMetric_ThenInvalidMetricNameThrown(String metricName)
        {
            String expectedException = "Metric names cannot contain the following characters: '=\"";

            Assert.That(() => new Metric(metricName, "10.1", "B", "Valid metric display name", null, true, "", ""),
                Throws.TypeOf<PlugNSharp.InvalidMetricName>().With.Message.EqualTo(expectedException));
        }

        [Test]
        public void GivenADisplayName_WhenSummaryGenerated_ThenSummaryUsesDisplayName()
        {
            Metric metric = new Metric("Valid metric name", "10.1", "B", "Valid metric display name", null, true, "", "");
            var result = metric.CreateSummary();

            Assert.AreEqual("Valid metric display name is 10.1B", result);
        }

        [Test]
        public void GivenNoDisplayName_WhenSummaryGenerated_ThenSummaryUsesMetricName()
        {
            Metric metric = new Metric("Valid metric name", "10.1", "B", null, null, true, "", "");
            var result = metric.CreateSummary();

            Assert.AreEqual("Valid metric name is 10.1B", result);
        }

        [Test]
        public void GivenDisplayInSummaryIsFalse_WhenSummaryGenerated_ThenSummaryIsEmpty()
        {
            Metric metric = new Metric("Valid metric name", "10.1", "B", null, null, false, "", "");
            var result = metric.CreateSummary();

            Assert.IsEmpty(result);
        }

        [Test]
        public void GivenDisplayFormat_WhenSummaryGenerated_ThenSummaryUsesDisplayFormat()
        {
            Metric metric = new Metric("Valid metric name", "10.1", "B", "Hello", "Custom Display Format", true, "", "");
            var result = metric.CreateSummary();

            Assert.AreEqual("Custom Display Format", result);
        }

        [TestCase("B", "1NaN", "", "Unit 'B' doesn't match 'aN'")]
        [TestCase("B", "1NaNB", "", "Unit 'B' doesn't match 'aNB'")]
        [TestCase("B", "", "1NaN", "Unit 'B' doesn't match 'aN'")]
        [TestCase("B", "", "1NaNB", "Unit 'B' doesn't match 'aNB'")]
        [TestCase("B", "", "5KB:10NaNB", "Unit 'B' doesn't match 'aNB'")]
        public void GivenThresholdWithInvalidUom_WhenNewMetric_ThenInvalidMetricThresholdThrown(
            String uom, String warningThreshold, String criticalThreshold, String expectedException)
        {
            Assert.That(() => new Metric("Test metric", "2048", uom, null, null, true, warningThreshold, criticalThreshold),
                Throws.TypeOf<PlugNSharp.InvalidMetricThreshold>().With.Message.EqualTo(expectedException));
        }

        [TestCase("Hz", "", "KHz", "'' is not a numeric value")]
        [TestCase("B", "", "-5KB:-KB", "'-' is not a numeric value")]
        [TestCase("B", "", "5HB", "UOM 'HB' is not valid")]
        public void GivenInvalidThresholds_WhenNewMetric_ThenInvalidMetricThresholdThrown(
            String uom,
            String warningThreshold,
            String criticalThreshold,
            String expectedException
        )
        {
            Assert.That(() => new Metric("Test metric", "10.1", uom, null, null, true, warningThreshold, criticalThreshold),
                Throws.TypeOf<PlugNSharp.InvalidMetricThreshold>().With.Message.EqualTo(expectedException));
        }

        [TestCase(10, "10", "20", 0)]
        [TestCase(10, "5", "20", 1)]
        [TestCase(10, "5", "10", 1)]
        [TestCase(10, "5", "9", 2)]
        [TestCase(10, "5", "9.9", 2)]
        [TestCase(10.1248, "10.1248", "20", 0)]
        [TestCase(10.1248, "10", "20", 1)]
        [TestCase(10.1248, "10.1247", "20", 1)]
        [TestCase(10.1248, "10", "10.1247", 2)]
        [TestCase(0, "10", "20", 0)]
        [TestCase(10, "5", "", 1)]
        [TestCase(10, "", "5", 2)]
        [TestCase(10, "", "", 0)]
        [TestCase(-10, "20", "", 1)]
        [TestCase(-10, "-8:-5", "", 1)]
        [TestCase(-10, "-20:-5", "", 0)]
        [TestCase(-10, "-5:20", "", 1)]
        [TestCase(10, "5:20", "", 0)]
        [TestCase(10, "5:8", "", 1)]
        [TestCase(10, "@5:20", "", 1)]
        [TestCase(10, "@5:8", "", 0)]
        [TestCase(10, "~:8", "", 1)]
        [TestCase(10, "~:20", "", 0)]
        [TestCase(-10, "~:20", "", 0)]
        [TestCase(-10, "~:-20", "", 1)]
        [TestCase(10, "20:", "", 1)]
        [TestCase(10, "5:", "", 0)]
        [TestCase(-10, "20:", "", 1)]
        [TestCase(-10, "0:", "", 1)]
        [TestCase(-10, "-20:", "", 0)]
        public void GivenThresholds_WhenNewMetric_ThenExitCodeBasedUponThreshold(
            Double metricValue,
            String warningThreshold,
            String criticalThreshold,
            int expectedExitCode
        )
        {
            Metric metric = new Metric("TestName", metricValue, null, null, null, true, warningThreshold, criticalThreshold);
            Assert.AreEqual(expectedExitCode, metric.exitCode);
        }

        [TestCase(2048, "b", "1024", "3072", false, 1)]
        [TestCase(2048, "b", "1Kb", "3Kb", false, 1)]
        [TestCase(2048, "b", "1KB", "3KB", false, 1)]
        [TestCase(2048, "B", "1000B", "3000B", false, 1)]
        [TestCase(2048, "B", "1KB", "3KB", false, 1)]
        [TestCase(2048, "bps", "1Kbps", "3Kbps", false, 1)]
        [TestCase(2048, "Bps", "1KBps", "3KBps", false, 1)]
        [TestCase(2048, "B/s", "1KB/s", "3KB/s", false, 1)]
        [TestCase(2048, "B/min", "1KB/min", "3KB/min", false, 1)]
        [TestCase(2048, "W", "1KW", "3KW", false, 1)]
        [TestCase(2048, "Hz", "1KHz", "3KHz", false, 1)]
        [TestCase(1024, "B", "1KB", "3KB", false, 0)]
        [TestCase(1025, "B", "1KB", "3KB", false, 1)]
        [TestCase(3072, "B", "1KB", "3KB", false, 1)]
        [TestCase(3073, "B", "1KB", "3KB", false, 2)]
        [TestCase(1024.50, "B", "1KB", "3KB", false, 1)]
        [TestCase(1536, "B", "1.5KB", "3KB", false, 0)]
        [TestCase(1537, "B", "1.5KB", "3KB", false, 1)]
        [TestCase(-1537, "B", "1.5KB", "", false, 1)]
        [TestCase(-1535, "B", "-3KB:-1.5KB", "", false, 1)]
        [TestCase(-1535, "B", "@-3KB:-1.5KB", "", false, 0)]
        [TestCase(-1536, "B", "-3KB:-1.5KB", "", false, 0)]
        [TestCase(-3073, "B", "-3KB:-1KB", "", false, 1)]
        [TestCase(-3072, "B", "-3KB:-1KB", "", false, 0)]
        [TestCase(6144, "B", "5KB:10KB", "", false, 0)]
        [TestCase(6144, "B", "@5KB:10KB", "", false, 1)]
        [TestCase(6144, "B", "~:10KB", "", false, 0)]
        [TestCase(6144, "B", "10KB:", "", false, 1)]
        [TestCase(2048, "B", "1MB", "", false, 0)]
        [TestCase(2048, "B", "1GB", "", false, 0)]
        [TestCase(2048, "B", "1PB", "", false, 0)]
        [TestCase(2048, "B", "1EB", "", false, 0)]
        [TestCase(1000, "b", "1Kb", "", true, 0)]
        [TestCase(1001, "b", "1Kb", "", true, 1)]
        [TestCase(1000, "B", "1KB", "", true, 0)]
        [TestCase(1001, "B", "1KB", "", true, 1)]
        [TestCase(1000, "bps", "1Kbps", "", true, 0)]
        [TestCase(1001, "bps", "1Kbps", "", true, 1)]
        [TestCase(1000, "Bps", "1KBps", "", true, 0)]
        [TestCase(1001, "Bps", "1KBps", "", true, 1)]
        [TestCase(1000, "B/s", "1KB/s", "", true, 0)]
        [TestCase(1001, "B/s", "1KB/s", "", true, 1)]
        [TestCase(1000, "B/min", "1KB/min", "", true, 0)]
        [TestCase(1001, "B/min", "1KB/min", "", true, 1)]
        [TestCase(2001, "s", "2Ks", "", false, 1)]
        [TestCase(2001, "s", "2Ks", "", true, 1)]
        public void GivenThresholdsAndConversion_WhenNewMetric_ThenExitCodeBasedUponThreshold(
            Double metricValue,
            String uom,
            String warningThreshold,
            String criticalThreshold,
            bool siBytesConversion,
            int expectedExitCode
        )
        {
            Metric metric = new Metric("TestName", metricValue, uom, null, null, true, warningThreshold, criticalThreshold, siBytesConversion);
            Assert.AreEqual(expectedExitCode, metric.exitCode);
        }

        [TestCase(2048, "B", "2KB", false)]
        [TestCase(2048, "B", "2.05KB", true)]
        [TestCase(2048, "b", "2Kb", false)]
        [TestCase(2048, "b", "2.05Kb", true)]
        [TestCase(2048, "bps", "2Kbps", false)]
        [TestCase(2048, "bps", "2.05Kbps", true)]
        [TestCase(2048, "Bps", "2KBps", false)]
        [TestCase(2048, "Bps", "2.05KBps", true)]
        [TestCase(2048, "B/s", "2KB/s", false)]
        [TestCase(2048, "B/s", "2.05KB/s", true)]
        [TestCase(2048, "B/min", "2KB/min", false)]
        [TestCase(2048, "B/min", "2.05KB/min", true)]
        [TestCase(2048, "W", "2.05KW", false)]
        [TestCase(2048, "W", "2.05KW", true)]
        [TestCase(2048, "Hz", "2.05KHz", false)]
        [TestCase(2048, "Hz", "2.05KHz", true)]
        [TestCase(20482, "s", "5h 41m 22s", false)]
        [TestCase(86400, "s", "1d", false)]
        [TestCase(1, "s", "1s", false)]
        [TestCase(125, "s", "2m 5s", false)]
        [TestCase(3661, "s", "1h 1m 1s", false)]
        [TestCase(93843, "s", "1d 2h 4m 3s", false)]
        [TestCase(0, "s", "0s", false)]
        [TestCase(-2048, "B", "-2KB", false)]
        [TestCase(2048.50, "B", "2KB", false)]
        [TestCase(2048.506, "B", "2KB", false)]
        [TestCase(2048.52, "", "2048.52", false)]
        [TestCase(2048.506, "", "2048.51", false)]
        public void GivenThresholds_WhenNewMetric_ThenSummaryUsesConvertedValues(
            Double metricValue,
            String uom,
            String expectedDisplayValue,
            bool siBytesConversion
        )
        {
            Metric metric = new Metric("Test Metric", metricValue, uom, null, null, true, null, null, siBytesConversion);
            var result = metric.CreateSummary();
            Assert.AreEqual(
                String.Format("Test Metric is {0}", expectedDisplayValue),
                result
            );
        }

        [TestCase(2048, "B", "", "", "{0}{1}")]
        [TestCase(2048, "B", "", "5KB:10KB", "{0}{1};{2};{3}")]
        [TestCase(2048, "B", "", "@5KB:10KB", "{0}{1};{2};{3}")]
        [TestCase(2048, "B", "~:10KB", "20KB", "{0}{1};{2};{3}")]
        [TestCase(2048.34567, "B", "", "1:2500.12", "2048.35{1};{2};{3}")]
        [TestCase(2048, "B", "", "2048.10:2500.50", "{0}{1};{2};{3}")]
        [TestCase(2048, "B", "", "-2:-1", "{0}{1};{2};{3}")]
        [TestCase(2048, "Hz", "-2KHz:-1KHz", ":1KHz", "{0}{1};{2};{3}")]
        [TestCase(2048, "B", "", "@-90KB:-30KB", "{0}{1};{2};{3}")]
        [TestCase(2048, "B", "15", "4000", "{0}{1};{2};{3}")]
        [TestCase(2048, "b", "15", "4000", "{0}{1};{2};{3}")]
        [TestCase(2048, "bps", "15", "4000", "{0}{1};{2};{3}")]
        [TestCase(2048, "Bps", "15", "4000", "{0}{1};{2};{3}")]
        [TestCase(2048, "B/s", "15", "4000", "{0}{1};{2};{3}")]
        [TestCase(2048, "B/min", "15", "4000", "{0}{1};{2};{3}")]
        [TestCase(2048, "W", "15", "4000", "{0}{1};{2};{3}")]
        [TestCase(2048, "Hz", "15", "4000", "{0}{1};{2};{3}")]
        [TestCase(2048, "s", "", "60", "{0}{1};{2};{3}")]
        [TestCase(93843, "s", "120", "3Ks", "{0}{1};{2};{3}")]
        [TestCase(0, "s", "120", "3000", "{0}{1};{2};{3}")]
        [TestCase(-2048, "B", "2KB", "14MB", "{0}{1};{2};{3}")]
        [TestCase(2048, "%", "15", "4000", "{0}{1};{2};{3}")]
        [TestCase(2048, "Engineers", "15", "4000", "{0}{1};{2};{3}")]
        public void GivenConvertableUoms_WhenNewMetric_ThenPerformanceOutputUsesUnconvertedValues(
            Double metricValue,
            String uom,
            String warningThreshold,
            String criticalThreshold,
            String expectedPerformanceMetric
        )
        {
            Metric metric = new Metric("Test Metric", metricValue, uom, null, null, true, warningThreshold, criticalThreshold);
            var result = metric.CreatePerformanceOutput();
            String expectedPerformanceString=String.Format("'Test Metric'={0}", expectedPerformanceMetric);
            Assert.AreEqual(
                String.Format(expectedPerformanceString, metricValue, uom, warningThreshold, criticalThreshold),
                result
            );
        }

        [TestCase(1024, 1, false)]
        [TestCase(1048575, 1024, false)]
        [TestCase(1024, 1.02, true)]
        [TestCase(999999, 1000, true)]
        public void GivenUomB_WhenSummaryGenerated_ThenSummaryConvertsToKB(int bytes, double kbytes, bool siBytesConversion)
        {
            Metric metric = new Metric("Test metric", bytes, "B", null, null, true, "", "", siBytesConversion);
            var result = metric.CreateSummary();

            Assert.AreEqual(String.Format("Test metric is {0}KB", kbytes), result);
        }

        [TestCase(1048576, 1, false)]
        [TestCase(1073741823, 1024, false)]
        [TestCase(1048576, 1.05, true)]
        [TestCase(999999999, 1000, true)]
        public void GivenUomB_WhenSummaryGenerated_ThenSummaryConvertsToMB(int bytes, double mbytes, bool siBytesConversion)
        {
            Metric metric = new Metric("Test metric", bytes, "B", null, null, true, "", "", siBytesConversion);
            var result = metric.CreateSummary();

            Assert.AreEqual(String.Format("Test metric is {0}MB", mbytes), result);
        }

        [TestCase(1073741824, 1, false)]
        [TestCase(1099511627775, 1024, false)]
        [TestCase(1073741824, 1.07, true)]
        [TestCase(999999999999, 1000, true)]
        public void GivenUomB_WhenSummaryGenerated_ThenSummaryConvertsToGB(long bytes, double gbytes, bool siBytesConversion)
        {
            Metric metric = new Metric("Test metric", bytes, "B", null, null, true, "", "", siBytesConversion);
            var result = metric.CreateSummary();

            Assert.AreEqual(String.Format("Test metric is {0}GB", gbytes), result);
        }

        [TestCase(1099511627776, 1, false)]
        [TestCase(1125899906842623, 1024, false)]
        [TestCase(1099511627776, 1.1, true)]
        [TestCase(999999999999999, 1000, true)]
        public void GivenUomB_WhenSummaryGenerated_ThenSummaryConvertsToTB(long bytes, double tbytes, bool siBytesConversion)
        {
            Metric metric = new Metric("Test metric", bytes, "B", null, null, true, "", "", siBytesConversion);
            var result = metric.CreateSummary();

            Assert.AreEqual(String.Format("Test metric is {0}TB", tbytes), result);
        }

        [TestCase(1125899906842624, 1, false)]
        // Current implementation using long and double means the max value 1 below 1EB 1152921504606846975 rounds up,
        // therefore using the last non rounded number of 1152921504606846911
        [TestCase(1152921504606846911, 1024, false)]
        [TestCase(1125899906842624, 1.13, true)]
        // Current implementation using long and double means the max value 1 below 1EB 999999999999999999 rounds up,
        // therefore using the last non rounded number of 999999999999999935
        [TestCase(999999999999999935, 1000, true)]
        public void GivenUomB_WhenSummaryGenerated_ThenSummaryConvertsToPB(long bytes, double pbytes, bool siBytesConversion)
        {
            Metric metric = new Metric("Test metric", bytes, "B", null, null, true, "", "", siBytesConversion);
            var result = metric.CreateSummary();

            Assert.AreEqual(String.Format("Test metric is {0}PB", pbytes), result);
        }

        [TestCase(1152921504606846976, 1, false)]
        [TestCase(1000000000000000000, 1, true)]
        public void GivenUomB_WhenSummaryGenerated_ThenSummaryConvertsToEB(long bytes, double ebytes, bool siBytesConversion)
        {
            Metric metric = new Metric("Test metric", bytes, "B", null, null, true, "", "", siBytesConversion);
            var result = metric.CreateSummary();

            Assert.AreEqual(String.Format("Test metric is {0}EB", ebytes), result);
        }
    }
}
