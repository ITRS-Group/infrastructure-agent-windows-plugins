// Plugin to check the eventlog of a Windows box
// Copyright (C) 2003-2025 ITRS Group Limited. All rights reserved

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Text;
using PlugNSharp;
using System.Text.RegularExpressions;
using Helpers;

/// <summary>
/// The base class of all Filters.
/// </summary>
abstract class FilterBase
{
    /// <summary>
    /// Stores the mode of the filter ("+", "-" or ".").
    /// </summary>
    public char mode;

    /// <summary>
    /// Creates a new instance of FilterBase.
    /// </summary>
    protected FilterBase(char mode)
    {
        this.mode = mode;
    }

    /// <summary>
    /// Determines if the EventLogEntry matches the filter.
    /// </summary>
    public abstract bool IsMatched(EventLogEntry entry);
}

/// <summary>
/// Represents the Filter for comparing against generated dates.
/// </summary>
class GeneratedFilter : FilterBase
{
    private static readonly Regex ReTime = new Regex(@"^([><=]{1,2})(\d+)([mshdw])$");

    /// <summary>
    /// The compare operation (e.g. "<", ">")
    /// </summary>
    public string compareOp;

    private int secs;

    /// <summary>
    /// Creates a new instance of a GeneratedFilter.
    /// </summary>
    public GeneratedFilter(char mode, int secs, string compareOp) : base(mode)
    {
        this.secs = secs;
        this.compareOp = compareOp;
    }

    /// <summary>
    /// Determines if the EventLog entry was generated within the time period.
    /// </summary>
    public override bool IsMatched(EventLogEntry entry)
    {
        var logOffsetSecs = (int)(DateTime.Now - entry.TimeGenerated).TotalSeconds;
        switch (this.compareOp)
        {
            case "<":
                return logOffsetSecs < this.secs;
            case ">":
                return logOffsetSecs > this.secs;
            default:
                throw new Exception(String.Format("Compare operator '{0}' not implemented", this.compareOp));
        }
    }

    /// <summary>
    /// Parses a new GeneratedFilter from a time string.
    ///  For example: "<1h"
    /// </summary>
    public static GeneratedFilter Parse(char mode, string timeStr)
    {
        var match = ReTime.Match(timeStr);
        if (!match.Success)
            throw new Exception(String.Format("Invalid time expression '{0}'", timeStr));
        var compareOp = match.Groups[1].Value;
        var generatedSecs = int.Parse(match.Groups[2].Value);
        var unit = char.Parse(match.Groups[3].Value);
        switch (unit)
        {
            case 'm':
                generatedSecs *= 60;  // Seconds in minute
                break;
            case 'h':
                generatedSecs *= 3600;  // Seconds in hour
                break;
            case 'd':
                generatedSecs *= 86400;  // Seconds in day
                break;
            case 'w':
                generatedSecs *= 604800;  // Seconds in week
                break;
        }
        switch (compareOp)
        {
            case "<":
            case ">":
            case "<>":
            case "=":
                // Future - add additional pre-processing here
                break;
            default:
                throw new Exception(String.Format("Invalid time comparison '{0}'", timeStr));
        }
        return new GeneratedFilter(mode, generatedSecs, compareOp);
    }
}

class EventTypeFilter : FilterBase
{
    private EventLogEntryType eventType;

    /// <summary>
    /// Creates a new instance of an EventTypeFilter.
    /// </summary>
    public EventTypeFilter(char mode, EventLogEntryType eventType) : base(mode)
    {
        this.eventType = eventType;
    }

    /// <summary>
    /// Determines if the EventLog entry has the required Entry Type.
    /// </summary>
    public override bool IsMatched(EventLogEntry entry)
    {
        return entry.EntryType == this.eventType;
    }

    /// <summary>
    /// Parses a new EventTypeFilter from an EventType
    ///   e.g. "=info" (The "=" is optional, but required by the original check)
    /// </summary>
    public static EventTypeFilter Parse(char mode, string eventTypeStr)
    {
        EventLogEntryType eventType;
        string cleanEventTypeStr = eventTypeStr.StartsWith("=") ? eventTypeStr.Substring(1) : eventTypeStr;
        switch (cleanEventTypeStr.ToLower())
        {
            case "auditsuccess":
                eventType = EventLogEntryType.SuccessAudit;
                break;
            case "auditfailure":
                eventType = EventLogEntryType.FailureAudit;
                break;
            case "error":
                eventType = EventLogEntryType.Error;
                break;
            case "info":
                eventType = EventLogEntryType.Information;
                break;
            case "warning":
                eventType = EventLogEntryType.Warning;
                break;
            default:
                throw new Exception(String.Format("Invalid event-type '{0}'", eventTypeStr));
        }
        return new EventTypeFilter(mode, eventType);
    }
}

/// <summary>
/// Represents a store for Event Log entries.
/// </summary>
class LogItemRecorder
{
    private const string IsoTimeFormat = "yyyy-MM-ddTHH:mm:ssZ";

    protected string formatPattern;
    protected List<EventLogEntry> entries;

    private readonly Regex FormatMatcher = new Regex(@"%[a-z]+%");

    /// <summary>
    /// Creates a new LogItemRecorder instance.
    /// </summary>
    /// <param name="formatPattern">The pattern to format indivisual EventLog entries</param>
    public LogItemRecorder(string formatPattern)
    {
        this.formatPattern = formatPattern;
        this.entries = new List<EventLogEntry>();
    }

    /// <summary>
    /// Add a new Event Log entry to the store.
    /// </summary>
    public virtual void AddItem(EventLogEntry entry)
    {
        this.entries.Add(entry);
    }

    /// <summary>
    /// Returns the number of items in the store.
    /// </summary>
    public virtual int Count
    {
        get { return this.entries.Count; }
    }

    /// <summary>
    /// Returns a string of the combined stored items
    ///  (stops after a certain maxLength for efficiency)
    /// </summary>
    public virtual string Join(string seperator, int maxLength)
    {
        var sb = new StringBuilder();
        foreach (EventLogEntry entry in this.entries)
        {
            string message = FormatMessage(entry, 1);
            if (sb.Length > 0) sb.Append(seperator);
            sb.Append(message);
            if (sb.Length >= maxLength) break;
        }
        return sb.ToString();
    }

    /// <summary>
    /// Formats an EventLog entry according to a "formatPattern".
    ///  A "count" can also be passed in for formatting.
    /// </summary>
    protected string FormatMessage(EventLogEntry entry, int count)
    {
        return FormatMatcher.Replace(this.formatPattern, delegate(Match match) {
            string key = match.ToString();
            switch (key)
            {
                case "%count%":
                    return count.ToString();
                case "%description%":
                    return entry.Message;
                case "%generated%":
                    return entry.TimeGenerated.ToString(IsoTimeFormat, CultureInfo.InvariantCulture);
                case "%id%":
                    return entry.InstanceId.ToString();  // EventID has been deprecated
                case "%severity%":
                    return entry.EntryType.ToString();  // Mapping to "EntryType" for now
                case "%source%":
                    return entry.Source;
                case "%type%":
                    return entry.EntryType.ToString();
                case "%written%":
                    return entry.TimeWritten.ToString(IsoTimeFormat, CultureInfo.InvariantCulture);
                default:
                    return key;
            }
        });
    }
}

/// <summary>
/// Represents a uniqe log item with a representative
///  EventLog "entry" and an associated "count".
/// </summary>
class UniqueLogItem
{
    public int count;
    public EventLogEntry entry;
}

/// <summary>
/// Represents a store for Event Log entries that can group related entries.
/// </summary>
class UniqueLogItemRecorder : LogItemRecorder
{
    private Dictionary<string, UniqueLogItem> itemCounts;

    /// <summary>
    /// Create a new instance of "UniqueLogItemRecorder"
    /// </summary>
    /// <param name="formatPattern">Pattern passed to the base "LogItemRecorder"</param>
    public UniqueLogItemRecorder(string formatPattern) : base(formatPattern)
    {
        this.itemCounts = new Dictionary<string, UniqueLogItem>();
    }

    /// <summary>
    /// Add a new Event Log entry to the store.
    /// </summary>
    public override void AddItem(EventLogEntry entry)
    {
        string key = this.FormatUniqueKey(entry);

        UniqueLogItem item;
        if (this.itemCounts.TryGetValue(key, out item))
        {
            item.count++;
        }
        else
        {
            item = new UniqueLogItem() { count=1, entry=entry };
            this.itemCounts[key] = item;
        }
    }

    /// <summary>
    /// Returns the number of unqiue items in the store.
    /// </summary>
    public override int Count
    {
        get { return this.itemCounts.Count; }
    }

    /// <summary>
    /// Returns a string of the combined stored items
    ///  (stops after a certain maxLength for efficiency)
    /// </summary>
    public override string Join(string seperator, int maxLength)
    {
        var sb = new StringBuilder();
        foreach (UniqueLogItem item in this.itemCounts.Values)
        {
            string message = FormatMessage(item.entry, item.count);
            if (sb.Length > 0) sb.Append(seperator);
            sb.Append(message);
            if (sb.Length >= maxLength) break;
        }
        return sb.ToString();
    }

    private string FormatUniqueKey(EventLogEntry entry)
    {
        // This is a combination of fields, but just return the message for now
        //  Fields: log-file, event-id, event-type and event-category
        return entry.Message;
    }
}

/// <summary>
/// Represets the main operation of Check Event Log
/// </summary>
static class CheckEventLog
{
    const int SummaryInfoLength = 128;  // Should be enough for Summary + Performance data
    const int MaxTruncateLength = (16 * 1024) - SummaryInfoLength;  // 16K max output, allowing for summary info
    const string FilterPrefix = "filter";
    const string DefaultFormatPattern = "%source% %description%";
    const string DefaultUniqueFormatPattern = DefaultFormatPattern + " (%count%)";

    /// <summary>
    /// Main entry point for the plugin
    /// </summary>
    public static int Run(CallData callData)
    {
        var filterPrefixLen = FilterPrefix.Length;
        var filterIn = true;
        string maxWarn = null;
        string maxCrit = null;
        var requiredEventLog = "Application";
        int maxLength = MaxTruncateLength;
        var filterList = new List<FilterBase>();
        var unique = false;
        var formatPattern = string.Empty;
        var filterRecentPast = false;
        var check = new Check(
            "check_eventlog",
            helpText: "Returns EventLog events over the last 1h\r\n"
                + "Arguments:\r\n"
                + "    Filter              Determines the type of filtering (out/in/all/new)\r\n"
                + "     filter=in would include all items matched in the defined filters \r\n"
                + "     filter=out would exclude all items matched in the defined filters\r\n"
                + "    Filter+             Prefix to filter in (to be followed with generated or eventtype)\r\n"
                + "    Filter-             Prefix to filter out (to be followed with generated or eventtype)\r\n"
                + "     Examples:                               \r\n"
                + "       Filter+generated    Period of time to capture events in.(e.g filter+generated=<1h)\r\n"
                + "       Filter-eventtype    Type of event to filter out (e.g filter-eventtype=auditSuccess)\r\n"
                + "    File                Type of eventfile (e.g system/application/security)\r\n"
                + "    Truncate            Size of the output message (e.g 1023 chars)\r\n"
                + "    Descriptions        Deprecated\r\n"
                + "    Unique              Stops duplication of messages\r\n"
                + "    MaxCrit             Maximum number of events before Critical level\r\n"
                + "    MaxWarn             Maximum number of events before Warning level\r\n"
        );
        try
        {
            var clArgList = callData.cmd
                .Select(a => a.Split(new Char[] {'='}, 2))
                .Skip(1)
                .Select(
                    x =>
                        new Tuple<string, string>(
                            x[0].Trim(),
                            x.ElementAtOrDefault(1) != null ? x[1] : "true"
                        )
                ).ToList();

            if (clArgList.Count() == 0)
            {
                return check.ExitHelp();
            }
            clArgList.ForEach(argTuple =>
            {
                string argName = argTuple.Item1.ToLower();
                string argValue = argTuple.Item2;
                switch (argTuple.Item1.ToLower())
                {
                    case "descriptions":
                    {
                        // Deprecated (assumed on)
                        break;
                    }
                    case "filter":
                    {
                        // Values may include "new", "all", "in", "out".
                        switch (argValue)
                        {
                            case "in":
                                filterIn = true;
                                break;
                            case "out":
                                filterIn = false;
                                break;
                            case "new":
                            case "all":
                                // Not used, assumed set
                                break;
                            default:
                                throw new Exception(String.Format("Invalid 'filter' value '{0}'", argValue));
                        }
                        break;
                    }
                    case "file":
                    {
                        TextInfo textInfo = new CultureInfo("en-US", false).TextInfo;
                        requiredEventLog = textInfo.ToTitleCase(argValue);
                        break;
                    }
                    case "help":
                    case "-h":
                    {
                        check.ExitHelp();
                        break;
                    }
                    case "maxcrit":
                    {
                        maxCrit = argValue;
                        break;
                    }
                    case "maxwarn":
                    {
                        maxWarn = argValue;
                        break;
                    }
                    case "syntax":
                    {
                        formatPattern = argValue;
                        break;
                    }
                    case "truncate":
                    {
                        var tempMaxLength = Int32.Parse(argValue);
                        if ((tempMaxLength <= 0) || (tempMaxLength > MaxTruncateLength))
                        {
                            throw new Exception(String.Format("Invalid truncate value '{0}'", tempMaxLength));
                        }
                        maxLength = tempMaxLength;
                        break;
                    }
                    case "unique":
                    {
                        unique = bool.Parse(argValue);
                        break;
                    }
                    default:
                    {
                        // Any filter will need at least 1 char for the op and 1 char for the arg
                        if ((argName.StartsWith("filter")) && (argName.Length >= filterPrefixLen + 2))
                        {
                            var op = argName[filterPrefixLen];
                            var arg = argName.Substring(filterPrefixLen + 1);
                            FilterBase filter;
                            switch (arg.ToLower())
                            {
                                case "generated":
                                    filter = GeneratedFilter.Parse(op, argValue);
                                    if (filter.mode == '+' && ((GeneratedFilter)filter).compareOp == "<")
                                    {
                                        // Can help with performance boost later
                                        filterRecentPast = true;
                                    }
                                    break;

                                case "eventtype":
                                    filter = EventTypeFilter.Parse(op, argValue);
                                    break;

                                default:
                                    throw new Exception(String.Format("Unrecognised filter argument '{0}'", arg));
                            }
                            filterList.Add(filter);
                        }
                        else
                        {
                            throw new Exception(String.Format("Unrecognised argument '{0}'", argName));
                        }
                        break;
                    }
                }
            });
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
            return check.ExitUnknown(e.Message);
        }

        try
        {
            if (filterList.Count == 0)
            {
                throw new Exception("No filters specified, try adding: filter+generated=<1d");
            }
            if (String.IsNullOrEmpty(formatPattern))
            {
                formatPattern = unique ? DefaultUniqueFormatPattern : DefaultFormatPattern;
            }
            var eventLogs = EventLog.GetEventLogs().ToList();
            EventLog selectedLog = eventLogs.Find(e => e.Log == requiredEventLog);
            if (selectedLog == null)
            {
                throw new Exception(String.Format("Invalid file '{0}'", requiredEventLog));
            }

            LogItemRecorder itemRecorder = LogItemRecorderFactory(unique, formatPattern);
            for (int i = selectedLog.Entries.Count - 1; i > 0; i--)
            {
                var entry = selectedLog.Entries[i];
                var isMatch = !filterIn;
                var generatedFilterFailed = false;
                foreach (var filter in filterList)
                {
                    var isTempMatched = filter.IsMatched(entry);
                    if (!isTempMatched && filterRecentPast && (filter.GetType() == typeof(GeneratedFilter)))
                    {
                        generatedFilterFailed = true;
                    }
                    if ((filter.mode == '-') && isTempMatched)
                    {
                        isMatch = false;
                        break;
                    }
                    else if ((filter.mode == '+') && !isTempMatched)
                    {
                        isMatch = false;
                        break;
                    }
                    else if (isTempMatched)
                    {
                        isMatch = true;
                    }
                }
                if (isMatch)
                {
                    itemRecorder.AddItem(entry);
                }
                else if (filterIn && filterRecentPast && generatedFilterFailed)
                {
                    // Performance boost for recent past standard filters (filter-in).
                    //  Don't bother looking at items older than generated filter.
                    break;
                }
            }
            check.MaxLength = maxLength;
            check.AddMessage(itemRecorder.Join(", ", maxLength) + "\r\n");
            check.AddMetric(
                name: selectedLog.Log,
                value: itemRecorder.Count,
                uom: "",
                displayName: selectedLog.LogDisplayName,
                warningThreshold: maxWarn,
                criticalThreshold: maxCrit
            );
            return check.Final();
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
           return check.ExitUnknown(e.Message);
        }
    }

    /// <summary>
    /// Creates a LogItemRecorder derivative instance based on the "unique" flag.
    /// </summary>
    private static LogItemRecorder LogItemRecorderFactory(bool unique, string formatPattern)
    {
        if (unique)
            return new UniqueLogItemRecorder(formatPattern);
        return new LogItemRecorder(formatPattern);
    }
}
