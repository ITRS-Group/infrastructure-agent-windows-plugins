// Copyright (C) 2003-2026 ITRS Group Limited. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace PlugNSharp
{
    public class Metric
    {
        /// <summary>
        /// Metric Class used to store service check result metric details (value, uom, thresholds)
        /// and calculate exit code and both a performance and summary string for the check's final stdout.
        /// </summary>
        private string name;
        private object value;
        private string uom;
        private string displayName;
        private string displayFormat;
        private bool displayInSummary = true;
        private string warningThreshold;
        private string criticalThreshold;
        public int exitCode;
        private bool siBytesConversion = false;
        private bool ConvertMetric = true;

        private const string defaultFormatter = "{name} is {value}{unit}";
        private static readonly char[] forbiddenNameChars = { '=', '"', '\'' };

        private static double secondsInMinute = 60;
        private static double secondsInHour = 3600;
        private static double secondsInDay = 86400;

        // Units of Measure
        private static string[] byteUnits = { "b", "B", "bps", "Bps", "B/s", "B/min" };
        private static string[] convertableUnits = new [] { "s", "Hz", "W" }
            .Concat(byteUnits)
            .ToArray();

        private static readonly int Precision = 2;
        private static readonly int PerfDataPrecision = 2;
        private static readonly int SummaryPrecision = 2;

        private static readonly UnitCollection[] binaryConversionValues = new UnitCollection[]
        {
            new UnitCollection("ExbiByte", "E", Math.Pow(1024, 6)),
            new UnitCollection("PebiByte", "P", Math.Pow(1024, 5)),
            new UnitCollection("TebiByte", "T", Math.Pow(1024, 4)),
            new UnitCollection("GibiByte", "G", Math.Pow(1024, 3)),
            new UnitCollection("MebiByte", "M", Math.Pow(1024, 2)),
            new UnitCollection("KibiByte", "K", 1024),
            new UnitCollection("Byte", "", 1)
        };

        private static readonly UnitCollection[] decimalConversionValues = new UnitCollection[]
        {
            new UnitCollection("ExaByte", "E", 1e18),
            new UnitCollection("PetaByte", "P", 1e15),
            new UnitCollection("TeraByte", "T", 1e12),
            new UnitCollection("GigaByte", "G", 1e9),
            new UnitCollection("MegaByte", "M", 1e6),
            new UnitCollection("KiloByte", "K", 1000),
            new UnitCollection("Pico", "p", Math.Pow(0.001, 4)),
            new UnitCollection("Nano", "n", Math.Pow(0.001, 3)),
            new UnitCollection("Micro", "u", Math.Pow(0.001, 2)),
            new UnitCollection("Milli", "m", 0.001)
        };

        public Metric(
            string name,
            object value,
            string uom,
            string displayName = "",
            string displayFormat = "",
            bool displayInSummary = true,
            string warningThreshold = "",
            string criticalThreshold = "",
            bool siBytesConversion = false
        )
        {
            // Setup attributes
            this.name = name;
            this.value = value;
            this.uom = uom;
            this.displayName = string.IsNullOrEmpty(displayName) ? name : displayName; // use displayName if present
            this.displayFormat = string.IsNullOrEmpty(displayFormat)
                ? defaultFormatter
                : displayFormat;
            this.displayInSummary = displayInSummary;
            this.warningThreshold = warningThreshold;
            this.criticalThreshold = criticalThreshold;
            this.siBytesConversion = siBytesConversion;

            ValidateName();
            this.exitCode = Evaluate(this.value.ToString(), warningThreshold, criticalThreshold);
        }

        private void ValidateName()
        {
            // "Metric names cannot contain the following characters: = and ' and "
            if (forbiddenNameChars.Any(forbiddenChar => name.Contains(forbiddenChar)))
            {
                throw new InvalidMetricName(
                    "Metric names cannot contain the following characters: '=\""
                );
            }
        }

        /// <summary>
        /// Evaluates a threshold (metricValue) by checking if it is inside the range start -> end.
        /// </summary>
        private static bool EvaluateThreshold(
            string metricValue,
            double start,
            double end,
            bool checkOutsideRange
        )
        {
            double doubleMetricValue = double.Parse(metricValue);
            bool isOutsideRange = (doubleMetricValue < start || doubleMetricValue > end);
            return checkOutsideRange ? isOutsideRange : !isOutsideRange;
        }

        /// <summary>
        /// Returns a summary string generated from the Metrics value, name and unit of measure.
        /// Attempts to convert the unit to a higher one (e.g. B -> KB) if it is appropriate.
        /// </summary>
        public string CreateSummary()
        {
            // Creates the summary data output string for the Check
            if (!displayInSummary)
            {
                return "";
            }
            string finalValue = value.ToString();
            string finalUOM = uom;

            if (ConvertMetric)
            {
                Hashtable convertedMetric = ConvertValue(
                    double.Parse(value.ToString()),
                    uom,
                    SummaryPrecision,
                    siBytesConversion
                );
                finalValue = convertedMetric["value"].ToString();
                finalUOM = convertedMetric["uom"].ToString();
            }

            finalUOM = (finalUOM == "per_second") ? "/s" : finalUOM;
            String finalString = displayFormat.Replace("{name}", displayName);
            finalString = finalString.Replace("{unit}", finalUOM);
            finalString = finalString.Replace("{value}", finalValue);

            return finalString;
        }

        /// <summary>
        /// Returns a performance metrics string generated from the Metrics value, unit of measure and thresholds.
        /// </summary>
        public string CreatePerformanceOutput()
        {
            string metricName = name.Contains(' ') ? string.Format("'{0}'", name) : name;
            double metricValue = Math.Round(double.Parse(value.ToString()), PerfDataPrecision);
            bool hasThresholds = !(
                string.IsNullOrEmpty(warningThreshold) && string.IsNullOrEmpty(criticalThreshold)
            ); // NAND
            return string.Format(
                "{0}={1}{2}{3}{4}{5}{6}",
                metricName,
                metricValue,
                uom,
                hasThresholds ? ";" : "",
                warningThreshold,
                hasThresholds ? ";" : "",
                criticalThreshold
            );
        }

        /// <summary>
        /// Evaluates the metric by comparing it's value to the warning and critical thresholds (if they're set).
        /// </summary>
        private int Evaluate(object argValue, string warningThreshold, string criticalThreshold)
        {
            string strValue = argValue.ToString();
            int returnCode = 0; // default to OK
            if (!string.IsNullOrEmpty(warningThreshold))
            {
                Hashtable warningThresh = ParseThreshold(warningThreshold);

                if (
                    EvaluateThreshold(
                        strValue,
                        double.Parse(warningThresh["start"].ToString()),
                        double.Parse(warningThresh["end"].ToString()),
                        (bool)warningThresh["checkOutsideRange"]
                    )
                )
                {
                    returnCode = 1; // WARNING
                }
            }
            if (!string.IsNullOrEmpty(criticalThreshold))
            {
                Hashtable criticalThresh = ParseThreshold(criticalThreshold);
                if (
                    EvaluateThreshold(
                        strValue,
                        double.Parse(criticalThresh["start"].ToString()),
                        double.Parse(criticalThresh["end"].ToString()),
                        (bool)criticalThresh["checkOutsideRange"]
                    )
                )
                {
                    returnCode = 2; // CRITICAL
                }
            }
            return returnCode;
        }

        /// <summary>
        /// Parses the threshold and return the range and whether or not we need to alert if the
        /// value is out of range or in the range.
        /// See: https://nagios-plugins.org/doc/guidelines.html
        /// </summary>
        private Hashtable ParseThreshold(string threshold)
        {
            Hashtable returnHash = new Hashtable { { "checkOutsideRange", true } };

            if (threshold.StartsWith("@"))
            {
                returnHash["checkOutsideRange"] = false;
                threshold = threshold.Substring(1);
            }

            if (!threshold.Contains(":"))
            {
                returnHash["start"] = 0;
                returnHash["end"] = ParseThresholdLimit(threshold, false);
            }
            else if (threshold.EndsWith(":"))
            {
                threshold = threshold.Substring(0, threshold.Length - 1);
                returnHash["start"] = ParseThresholdLimit(threshold, true);
                returnHash["end"] = long.MaxValue;
            }
            else if (threshold.StartsWith(":"))
            {
                returnHash["start"] = 0;
                returnHash["end"] = ParseThresholdLimit(threshold.Substring(1), false);
            }
            else
            {
                string[] words = threshold.Split(':');
                string start = words[0];
                string end = words[1];
                returnHash["start"] = ParseThresholdLimit(start, true);
                returnHash["end"] = ParseThresholdLimit(end, false);
            }
            return returnHash;
        }

        /// <summary>
        /// Parses a threshold value, converting it from a higher uom to a lower one (e.g. GB -> B) so that
        /// comparisons can be done on the lowest unit.
        /// </summary>
        private double ParseThresholdLimit(string argValue, bool isStart)
        {
            if (argValue == "~")
            {
                return isStart ? long.MinValue : long.MaxValue;
            }

            double doubleValue;
            bool canConvert = double.TryParse(argValue, out doubleValue);
            return canConvert ? doubleValue : ConvertThreshold(argValue, uom, siBytesConversion); // [Metric]::ConvertThreshold($Val, $this.UOM, $this.SiBytesConversion);
        }

        /// <summary>
        /// Converts a threshold value from higher units (e.g. TB) to lower ones (e.g. B) so that comparisons can be
        /// done against the value in the lowest form.
        /// </summary>
        private double ConvertThreshold(string threshold, string uom, bool siConversion)
        {
            double convertVal = 1;
            string parsedunit = Regex.Replace(threshold, "\\d|\\.|-", ""); // Threshold -replace ('\d|\.', '')
            string parsedValue = Regex.Replace(threshold, "([^\\d.-])+", ""); // $Threshold -replace ('([^\d.])+','')
            string unitPrefix = parsedunit.Substring(0, 1);
            string unit = parsedunit.Substring(1);
            if(parsedunit.Length == 1)
            {
                unitPrefix = "";
                unit = parsedunit.Last().ToString();
            }

            if (!string.Equals(uom, unit, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidMetricThreshold(
                    string.Format("Unit '{0}' doesn't match '{1}'", uom, unit)
                );
            }

            double numericValue;
            bool canParse = double.TryParse(parsedValue, out numericValue);
            if (!canParse)
            {
                throw new InvalidMetricThreshold(
                    string.Format("'{0}' is not a numeric value", parsedValue)
                );
            }

            UnitCollection[] conversionArr = GetConvertableUnitsArr(
                numericValue,
                uom,
                siConversion
            );
            if (conversionArr.Any(c => c.UnitPrefix == unitPrefix))
            {
                convertVal = conversionArr.Single(c => c.UnitPrefix == unitPrefix).Value;
            }
            else
            {
                throw new InvalidMetricThreshold(
                    string.Format("UOM '{0}' is not valid", parsedunit)
                );
            }

            return numericValue * convertVal;
        }

        /// <summary>
        /// Retrieves the UnitCollection array to be used in the conversion of value to a higher
        /// unit (e.g. B -> PB).
        /// If an appropriate array isn't found then an empty UnitCollection[] is returned.
        /// </summary>
        private static UnitCollection[] GetConvertableUnitsArr(
            double value,
            string unit,
            bool siConversion
        )
        {
            UnitCollection[] conversionArr = { };
            if (convertableUnits.Contains(unit))
            {
                conversionArr = (byteUnits.Contains(unit) && !siConversion) ? binaryConversionValues : decimalConversionValues;
            }
            return conversionArr;
        }

        /// <summary>
        /// Converts a value to a new higher UOM by calling GetConvertableUnitsArr and ConvertValueMethod.
        /// </summary>
        private Hashtable ConvertValue(
            double value,
            string unit,
            int summaryPrecision,
            bool siConversion
        )
        {
            UnitCollection[] convertableUnitsArr = GetConvertableUnitsArr(
                value,
                unit,
                siConversion
            );
            if (unit.Equals("s"))
            {
                return ConvertSeconds(value);
            }
            else
            {
                return ConvertValueMethod(value, unit, convertableUnitsArr, summaryPrecision);
            }
        }

        /// <summary>
        /// Uses a passed in list of UnitCollection objects to convert oldValue into a higher unit of measure.
        /// </summary>
        private static Hashtable ConvertValueMethod(
            double oldValue,
            string unit,
            IEnumerable<UnitCollection> conversionTable,
            int summaryPrecision
        )
        {
            string uomPrefix = "";
            double newValue = oldValue;
            foreach (var t in conversionTable)
            {
                if (oldValue >= t.Value || oldValue * -1 >= t.Value)
                {
                    newValue = oldValue / t.Value;
                    uomPrefix = t.UnitPrefix;
                    break;
                }
            }
            return new Hashtable
            {
                { "value", Math.Round(newValue, Precision).ToString() },
                { "uom", uomPrefix + unit }
            };
        }

        /// <summary>
        /// Convert a number in seconds into a human readable format.
        /// </summary>
        private static Hashtable ConvertSeconds(
            double countSeconds
        )
        {
            var days = Math.Floor(countSeconds / secondsInDay);
            var hours = Math.Floor(countSeconds % secondsInDay / secondsInHour);
            var minutes = Math.Floor(countSeconds % secondsInHour / secondsInMinute);
            var seconds = countSeconds % secondsInMinute;
            var summary = new List<string>();
            if (days != 0d) {
                summary.Add(string.Format("{0}d", days));
            }
            if (hours != 0d) {
                summary.Add(string.Format("{0}h", hours));
            }
            if (minutes != 0d) {
                summary.Add(string.Format("{0}m", minutes));
            }
            if (seconds != 0d) {
                summary.Add(string.Format("{0}s", seconds));
            }

            return new Hashtable
            {
                { "value", summary.Count == 0 ? "0s" : string.Join(" ", summary) },
                { "uom", "" }
            };
        }
    }
}
