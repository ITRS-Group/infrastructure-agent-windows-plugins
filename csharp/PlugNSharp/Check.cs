// Copyright (C) 2003-2025 ITRS Group Limited. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace PlugNSharp
{
    public class Check
    {
        /// <summary>
        /// Class for defining and running Opsview Service Checks. Check allows the returning
        /// of arbitrary numbers of metrics through the use of Check.AddMetric().
        /// Exit code and final stdout are calculated when Check.Final() is called. This will also
        /// exit the plugin.
        /// </summary>

        public const int EXIT_STATE_UNKNOWN = 3;
        public const int EXIT_STATE_CRITICAL = 2;
        public const int EXIT_STATE_WARNING = 1;
        public const int EXIT_STATE_OK = 0;
        public const int DEFAULT_MAX_LENGTH = 16384 - 1; // 16kB

        public int MaxLength { get; set; }

        public string stateType;
        private string name;
        private string version;
        private string preamble;
        private string description;
        private string helpText;
        private string sep;
        private bool debug = false;
        private List<Metric> metricArray = new List<Metric>();
        private List<string> messageArray = new List<string>();

        private static readonly Hashtable exitStates = new Hashtable
        {
            { EXIT_STATE_OK, "OK" },
            { EXIT_STATE_WARNING, "WARNING" },
            { EXIT_STATE_CRITICAL, "CRITICAL" },
            { EXIT_STATE_UNKNOWN, "UNKNOWN" }
        };

        public Check(
            string name,
            string version = "",
            string preamble = "",
            string description = "",
            string helpText = "",
            string stateType = "METRIC",
            string sep = ", ",
            bool debug = false
        )
        {
            Console.OutputEncoding = System.Text.Encoding.UTF8;
            this.name = name;
            this.version = version;
            this.preamble = preamble;
            this.description = description;
            this.helpText = helpText;
            this.stateType = stateType;
            this.sep = sep;
            this.debug = debug;
            this.MaxLength = DEFAULT_MAX_LENGTH;
        }

        /// <summary>
        /// Logs 'logMessage' formatted with 'args' if check.debug is True.
        /// Allows for an arbitrary number of args to be passed in but the count must match
        /// the number of {0}, {1}, etc., formatters in the logMessage string.
        /// </summary>
        public void DebugLog(string logMessage, params object[] args)
        {
            if (!debug)
                return;
            try
            {
                var stringList = (from arg in args select arg.ToString()).ToArray();
                Console.WriteLine("[DEBUG] {0}", string.Format(logMessage, stringList));
            }
            catch (Exception e)
            {
                Console.WriteLine("Exception thrown writing debug message '{0}'", logMessage);
                Console.WriteLine(e.ToString());
            }
        }

        /// <summary>
        /// Creates a Metric object from the passed in parameters and stores it in the Check's internal list.
        /// </summary>
        public void AddMetric(
            string name,
            double value,
            string uom,
            string displayName = "",
            string displayFormat = "",
            bool displayInSummary = true,
            string warningThreshold = "",
            string criticalThreshold = ""
        )
        {
            this.metricArray.Add(
                new Metric(
                    name,
                    value,
                    uom,
                    displayName,
                    displayFormat,
                    displayInSummary,
                    warningThreshold,
                    criticalThreshold
                )
            );
        }

        public void AddMessage(string message)
        {
            this.messageArray.Add(message);
        }

        /// <summary>
        /// Finalises the Check by generating the final stdout to print and calculates the final exit code
        /// by finding the highest exit code of its Metric objects.
        /// </summary>
        public int Final(string message = "", int exitCode = EXIT_STATE_OK)
        {
            string humanOutput;

            // Generate final summary output (the human readable bit)
            if (message.Length > 0)
            {
                humanOutput = message;
            }
            else
            {
                var summaries = from metric in metricArray select metric.CreateSummary();
                humanOutput = string.Join(sep, messageArray) + string.Join(sep, summaries);
            }

            // Generate final metric output
            var perfOutputs = from metric in metricArray select metric.CreatePerformanceOutput();
            string performanceOutput = string.Join(" ", perfOutputs);
            int finalExitCode = Math.Max(GetFinalExitCode(), exitCode);

            if (string.IsNullOrEmpty(performanceOutput))
            {
                return Exit(finalExitCode, humanOutput);
            }
            else
            {
                return Exit(finalExitCode, humanOutput,  " | " + performanceOutput);
            }
        }

        public int GetFinalExitCode()
        {
            // Choose final exit code by finding the highest code of a metric in metricArray
            return metricArray.Count() != 0 ? Math.Max(metricArray.Max(m => m.exitCode), EXIT_STATE_OK) : EXIT_STATE_OK;
        }

        /// <summary>
        /// Prints this.helpText and exits with a return code of 0.
        /// </summary>
        public int ExitHelp()
        {
            var output = String.Format("{0}\r\n{1}", description, helpText);
#if LONG_RUNNING
            throw new ExitException(0, stdout: output);
#else
            Console.WriteLine(output);
            Environment.Exit(0);
            return 0;  // Unused
#endif
        }

        /// <summary>
        /// Exits with a return code of 0 (OK) after printing 'message'.
        /// </summary>
        public int ExitOK(string message)
        {
            return Exit(EXIT_STATE_OK, message);
        }

        /// <summary>
        /// Exits with a return code of 1 (WARNING) after printing 'message'.
        /// </summary>
        public int ExitWarning(string message)
        {
            return Exit(EXIT_STATE_WARNING, message);
        }

        /// <summary>
        /// Exits with a return code of 2 (CRITICAL) after printing 'message'.
        /// </summary>
        public int ExitCritical(string message)
        {
            return Exit(EXIT_STATE_CRITICAL, message);
        }

        /// <summary>
        /// Exits with a return code of 3 (UNKNOWN) after printing 'message'.
        /// </summary>
        public int ExitUnknown(string message)
        {
            return Exit(EXIT_STATE_UNKNOWN, message);
        }

        /// <summary>
        /// Exits with a return code of 'exitCode' after printing 'message' prefixed with the exitState string.
        /// </summary>
        internal virtual int Exit(int exitCode, string message, string perfData = "")
        {
            var stateTypeString = "";
            if (stateType.Length > 0)
            {
                stateTypeString = stateType + " ";
            }
            var output = String.Format("{0}{1}: {2}", stateTypeString, exitStates[exitCode], message);
            output = (perfData.Length == 0) ? output : TruncateText(output, perfData);

#if LONG_RUNNING
            throw new ExitException(exitCode, stdout: output);
#else
            Console.WriteLine(output);
            Environment.Exit(exitCode);
            return 0;  // Unused
#endif
        }

        public string TruncateText(string content, string ending, string suffix="...")
        {
            if ((content.Length + ending.Length) <= MaxLength)
            {
                return content + ending;  // No truncation required
            }
            var lenEnding = suffix.Length + ending.Length;
            var truncatedContent = content.Substring(0, Math.Max(MaxLength - lenEnding, 0));
            return truncatedContent + suffix + ending;
        }
    }
}
