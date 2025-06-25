// Plugin to check the eventlog of a Windows box
// Copyright (C) 2003-2025 ITRS Group Limited. All rights reserved

using System;
using System.Collections.Generic;
using System.Diagnostics.Eventing.Reader;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using PlugNSharp;
using Helpers;
using System.ComponentModel;

/// <summary>
/// Represents the mode of the filter.
/// </summary>
enum FilterMode { plus, minus }

/// <summary>
/// Parses a FilterMode from a string.
/// </summary>
static class FilterModeParser
{
    public static FilterMode Parse(char mode)
    {
        switch (mode)
        {
            case '+':
                return FilterMode.plus;
            case '-':
                return FilterMode.minus;
            default:
                throw new Exception(String.Format("Invalid filter mode '{0}'", mode));
        }
    }
}


/// <summary>
/// The base class of all Filters.
/// </summary>
abstract class FilterBase
{
    /// <summary>
    /// Stores the xpath for the filter.
    /// </summary>
    public string xpath;

    /// <summary>
    /// Determines if the filter matches when performing code filtering.
    /// </summary>
    public virtual bool Matches(EventRecord eventInstance)
    {
        return true;
    }

    // <summary>
    // Joins terms together with an OR, adding brackets when having multiple terms.
    // </summary>
    protected string JoinOrTerms(IEnumerable<string> terms)
    {
        var joined = String.Join(" or ", terms);
        return terms.Count() > 1 ? String.Format("({0})", joined) : joined;
    }
}

/// <summary>
/// Represents the Filter for comparing against generated dates.
/// </summary>
class GeneratedFilter : FilterBase
{
    private static readonly Regex ReTime = new Regex(@"^(\-?)(\d+)([mshdw])$");

    private static readonly HashSet<string> ValidOps = new HashSet<string>
    {
        "<", "<=", ">", ">=", "="
    };

    /// <summary>
    /// Creates a new instance of a GeneratedFilter.
    /// </summary>
    public GeneratedFilter(long milliseconds, string op)
    {
        this.xpath = String.Format("TimeCreated[timediff(@SystemTime) {0} {1}]", op, milliseconds);
    }

    /// <summary>
    /// Parses a new GeneratedFilter from a time string.
    ///  For example: "<1h"
    /// </summary>
    public static GeneratedFilter Parse(string timeStr, string op)
    {
        if (!ValidOps.Contains(op))
            throw new Exception(String.Format("Invalid time comparison '{0}'", op));
        var match = ReTime.Match(timeStr);
        if (!match.Success)
            throw new Exception(String.Format("Invalid time expression '{0}'. Should be <time><unit[smhdw]>", timeStr));
        var isNegative = match.Groups[1].Value.Equals("-");
        long generatedMillisecs = long.Parse(match.Groups[2].Value);

        var unit = char.Parse(match.Groups[3].Value);
        switch (unit)
        {
            case 's':
                generatedMillisecs *= 1000;  // Milliseconds in second
                break;
            case 'm':
                generatedMillisecs *= 60000;  // Milliseconds in minute
                break;
            case 'h':
                generatedMillisecs *= 3600000;  // Milliseconds in hour
                break;
            case 'd':
                generatedMillisecs *= 86400000;  // Milliseconds in day
                break;
            case 'w':
                generatedMillisecs *= 604800000;  // Milliseconds in week
                break;
        }
        if (isNegative)
        {
            switch (op)
            {
                case "<":
                    op = ">";
                    break;
                case "<=":
                    op = ">=";
                    break;
                case ">":
                    op = "<";
                    break;
                case ">=":
                    op = "<=";
                    break;
            }
        }
        return new GeneratedFilter(generatedMillisecs, op);
    }
}

class EventIdFilter : FilterBase
{
    /// <summary>
    /// Creates a new instance of an EventIdFilter.
    /// </summary>
    public EventIdFilter(List<int> eventIdList)
    {
        this.xpath = JoinOrTerms(eventIdList.Select(
            eventId => String.Format("EventID={0}", eventId)
        ));
    }

    /// <summary>
    /// Parses a new EventIdFilter
    /// </summary>
    public static EventIdFilter Parse(List<string> eventIdStrList, string op)
    {
        var eventIdList = new List<int>();
        switch (op)
        {
            case "=":
            case "in":
                foreach (var idStr in eventIdStrList)
                {
                    eventIdList.Add(int.Parse(idStr));
                }
                break;
            default:
                throw new Exception(String.Format("Invalid event-id operator '{0}'", op));
        }
        return new EventIdFilter(eventIdList);
    }
}

class EventSourceFilter : FilterBase
{
    /// <summary>
    /// Creates a new instance of an EventSourceFilter.
    /// </summary>
    public EventSourceFilter(List<string> eventSourceList)
    {
        this.xpath = JoinOrTerms(eventSourceList.Select(
            eventId => String.Format("Provider[@Name='{0}']", eventId)
        ));
    }

    /// <summary>
    /// Parses a new EventSourceFilter
    /// </summary>
    public static EventSourceFilter Parse(List<string> eventSourceList, string op)
    {
        switch (op)
        {
            case "=":
            case "in":
                break;
            default:
                throw new Exception(String.Format("Invalid event-source operator '{0}'", op));
        }
        return new EventSourceFilter(eventSourceList);
    }
}

class EventTypeFilter : FilterBase
{
    /// <summary>
    /// Creates a new instance of an EventTypeFilter.
    /// </summary>
    public EventTypeFilter(List<StandardEventLevel> eventTypeList, string op)
    {
        this.xpath = JoinOrTerms(eventTypeList.Select(
            eventType => String.Format("Level {0} {1}", op, (int)eventType)
        ));
    }

    /// <summary>
    /// Parses a single EventType entry.
    /// See https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.standardeventlevel?view=netframework-4.8.1
    /// </summary>
    private static StandardEventLevel ParseSingle(string eventTypeStr)
    {
        switch (eventTypeStr.ToLower())
        {
            case "logalways":
            case "0":
                return StandardEventLevel.LogAlways;
            case "critical":
            case "1":
                return StandardEventLevel.Critical;
            case "error":
            case "2":
                return StandardEventLevel.Error;
            case "warn":
            case "warning":
            case "3":
                return StandardEventLevel.Warning;
            case "info":
            case "information":
            case "informational":
            case "4":
                return StandardEventLevel.Informational;
            case "verbose":
            case "5":
                return StandardEventLevel.Verbose;
            case "auditsuccess":
            case "auditfailure":
                throw new Exception(String.Format("EventType '{0}' is now supported through the 'keywords' filter", eventTypeStr));
            default:
                throw new Exception(String.Format("Invalid EventType '{0}'", eventTypeStr));
        }
    }

    /// <summary>
    /// Parses a new EventTypeFilter
    /// </summary>
    public static EventTypeFilter Parse(List<string> eventTypeStrList, string op)
    {
        var eventTypeList = new List<StandardEventLevel>();
        switch (op)
        {
            case "<":
            case ">":
            case "<=":
            case ">=":
            case "=":
            case "in":
                foreach (var type in eventTypeStrList)
                {
                    eventTypeList.Add(ParseSingle(type));
                }
                break;
            default:
                throw new Exception(String.Format("Invalid event-type operator '{0}'", op));
        }
        if (op.Equals("in")) op = "=";
        return new EventTypeFilter(eventTypeList, op);
    }
}

class KeywordsFilter : FilterBase
{
    private List<long> keywords;

    private static Int64Converter longParser = new Int64Converter();

    /// <summary>
    /// Creates a new instance of an KeywordsFilter.
    /// </summary>
    public KeywordsFilter(List<long> keywords)
    {
        this.keywords = keywords;
    }

    /// <summary>
    /// Parses a single Keywords entry.
    /// See https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.eventing.reader.standardeventkeywords?view=netframework-4.8.1
    /// </summary>
    private static long ParseSingle(string keywordsStr)
    {
        switch (keywordsStr.ToLower())
        {
            case "auditfailure":
                return (long) StandardEventKeywords.AuditFailure;
            case "auditsuccess":
                return (long) StandardEventKeywords.AuditSuccess;
            case "correlationhint2":
                return (long) StandardEventKeywords.CorrelationHint2;
            case "eventlogclassic":
            case "classic":
                return (long)StandardEventKeywords.EventLogClassic;
            case "responsetime":
                return (long) StandardEventKeywords.ResponseTime;
            case "sqm":
                return (long) StandardEventKeywords.Sqm;
            case "wdicontext":
                return (long) StandardEventKeywords.WdiContext;
            case "wdidiagnostic":
                return (long) StandardEventKeywords.WdiDiagnostic;
            default:
                try
                {
                    long value = (long)longParser.ConvertFromString(keywordsStr);
                    return value;
                }
                catch (Exception)
                {
                    throw new Exception(String.Format("Invalid keywords '{0}'", keywordsStr));
                }
        }
    }

    /// <summary>
    /// Parses a new KeywordsFilter
    /// </summary>
    public static KeywordsFilter Parse(List<string> keywordsStrList, string op)
    {
        var keywordsList = new List<long>();
        switch (op)
        {
            case "=":
            case "in":
                foreach (var keyword in keywordsStrList)
                {
                    keywordsList.Add(ParseSingle(keyword));
                }
                break;
            default:
                throw new Exception(String.Format("Invalid keywords operator '{0}'", op));
        }
        return new KeywordsFilter(keywordsList);
    }

    public override bool Matches(EventRecord eventInstance)
    {
        return keywords.Any(keyword => (eventInstance.Keywords & keyword) != 0);
    }
}

/// <summary>
/// Represents a store for Event Log entries.
/// </summary>
class LogItemRecorder
{
    private const string RFC1123TimeFormat = "R";

    protected string formatPattern;
    protected List<EventRecord> entries;

    private readonly Regex FormatMatcher = new Regex(@"%([a-z]+)(?:[-]([A-Za-z]))?%");

    /// <summary>
    /// Creates a new LogItemRecorder instance.
    /// </summary>
    /// <param name="formatPattern">The pattern to format indivisual EventLog entries</param>
    public LogItemRecorder(string formatPattern)
    {
        this.formatPattern = formatPattern;
        this.entries = new List<EventRecord>();
    }

    /// <summary>
    /// Add a new Event Log entry to the store.
    /// </summary>
    public virtual void AddItem(EventRecord entry)
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
        foreach (EventRecord entry in this.entries)
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
    protected string FormatMessage(EventRecord entry, int count)
    {
        return FormatMatcher.Replace(this.formatPattern, delegate (Match match)
        {
            string key = match.Groups[1].Value.ToLower();
            string arg = match.Groups[2].Value;
            switch (key)
            {
                case "count":
                    return count.ToString();
                case "description":
                case "message":
                    var description = entry.FormatDescription() ?? FormatProperties(entry);
                    return Regex.Replace(description, "\\r|\\n|\\t|  ", " ");
                case "generated":
                case "written":
                    if (!entry.TimeCreated.HasValue) return string.Empty;
                    string[] formatsToTry = { arg, RFC1123TimeFormat };
                    foreach (var format in formatsToTry)
                    {
                        if (String.IsNullOrEmpty(format)) continue;
                        try
                        {
                            return ((DateTime)entry.TimeCreated).ToString(format, CultureInfo.InvariantCulture);
                        }
                        catch (FormatException) {}
                    }
                    return entry.TimeCreated.ToString();  // We should never get here
                case "id":
                    return entry.Id.ToString();
                case "level":
                case "severity":
                case "type":
                    try
                    {
                        return entry.LevelDisplayName;
                    }
                    catch (EventLogNotFoundException)
                    {
                        StandardEventLevel level = (StandardEventLevel)entry.Level;
                        return level.ToString();
                    }
                case "source":
                    return entry.ProviderName;
                default:
                    return String.Format("%{0}%", key);
            }
        });
    }

    /// <summary>
    /// Formats EventRecord properties into a string.
    /// </summary>
    string FormatProperties(EventRecord entry)
    {
        var stringBuilder = new StringBuilder();
        foreach (var item in entry.Properties)
        {
            stringBuilder.AppendLine(item.Value.ToString().Trim());
        }
        return stringBuilder.Length > 0 ? stringBuilder.ToString() : entry.ToString();
    }
}

/// <summary>
/// Represents a uniqe log item with a representative
///  EventLog "entry" and an associated "count".
/// </summary>
class UniqueLogItem
{
    public int count;
    public EventRecord entry;
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
    public override void AddItem(EventRecord entry)
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
    /// Returns the number of unique items in the store.
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

    /// <summary>
    /// Creates a unique key for the Event based on log-file, event-id,
    ///  level (event-type) and task (category).
    /// </summary>
    private string FormatUniqueKey(EventRecord entry)
    {
        return String.Format("{0}:{1}:{2}:{3}", entry.LogName, entry.Id, entry.Level.ToString(), entry.Task.ToString());
    }
}

/// <summary>
/// Represets the main operation of Check Event Log
/// </summary>
static class CheckEventLog
{
    private const int SummaryInfoLength = 128;  // Should be enough for Summary + Performance data
    private const int MaxTruncateLength = (16 * 1024) - SummaryInfoLength;  // 16K max output, allowing for summary info
    private const string FilterPrefix = "filter";
    private const string DefaultFormatPattern = "%source% %description%";
    private const string DefaultUniqueFormatPattern = DefaultFormatPattern + " (%count%)";

    private static readonly Regex ReValidFilterOpStart = new Regex(@"^([<>=]|in[ (])");
    private static readonly Regex ReFilterName = new Regex(@"^[A-Za-z]+$");
    private static readonly char[] CommandTrimChars = new char[] { '-' };

    /// <summary>
    /// Main entry point for the plugin
    /// </summary>
    public static int Run(CallData callData)
    {
        var filterPrefixLen = FilterPrefix.Length;
        var filterIn = true;
        var filterPlusList = new List<String>();
        var filterMinusList = new List<String>();
        int maxWarn = -1;
        int maxCrit = -1;
        string warnExpression = null;
        string critExpression = null;
        var requiredEventLog = "Application";
        int maxLength = MaxTruncateLength;
        int maxEvents = -1;  // No limit
        var unique = false;
        var debugMode = false;  // Hidden option (DebugMode) to show the full exception stack trace
        var debugQuery = false;  // Hidden option (DebugQuery) to show the XPath query in the output
        var formatPattern = String.Empty;
        var codeFilterPlusList = new List<FilterBase>();
        var codeFilterMinusList = new List<FilterBase>();
        var maxWarnCritFormat = "{0}";
        var check = new Check(
            "check_eventlog",
            helpText: "Returns events filtered from the EventLog\r\n"
                + "Arguments:\r\n"
                + "    Filter              Sets a filter or filter mode (out/in/all/new/filter query)\r\n"
                + "     Examples:\r\n"
                + "       filter=in              Include all items matched in the defined filters\r\n"
                + "       filter=out             Exclude all items matched in the defined filters\r\n"
                + "       filter=new             Maintained for compatibility, but deprecated and does nothing\r\n"
                + "       filter=all             Maintained for compatibility, but deprecated and does nothing\r\n"
                + "       filter=Generated <1d AND EventType = info AND (id=146 OR id = 145)\r\n"
                + "       filter=EventID in (145, 146)\r\n"
                + "    Filter+             Prefix to filter in (followed by one of eventid, eventsource, eventtype, generated, id, source, written, keywords)\r\n"
                + "    Filter-             Prefix to filter out (followed by one of eventid, eventsource, eventtype, generated, id, source, written, keywords)\r\n"
                + "     Examples:\r\n"
                + "       Filter+generated       Period of time to capture events in (e.g filter+generated=<1h)\r\n"
                + "         Supports the following time units: s,m,h,d,w (i.e. seconds, minutes, hours, days, weeks)\r\n"
                + "         Supports both +ve and -ve values\r\n"
                + "           For example, generated>-6h (since 6 hours ago) is the same as generated<6h (in the last 6 hours)\r\n"
                + "       Filter+eventid         Event ID to filter in (e.g filter+eventid=145)\r\n"
                + "       Filter-eventtype       Type of event to filter out (e.g filter-eventtype=warning)\r\n"
                + "       Filter+keywords        Named Keyword to filter in (e.g filter+keywords=auditSuccess)\r\n"
                + "       Filter-keywords        Numeric Keyword to filter out (e.g filter-keywords=0x4000)\r\n"
                + "         Note: Keywords can ONLY be used in filter[+/-] expressions and cannot be mixed with other filters in a single expression\r\n"
                + "    File                Event log name or path (e.g Microsoft-Windows-Ntfs/Operational)\r\n"
                + "    Truncate            Max number of chars in the output message (e.g 1023)\r\n"
                + "    Descriptions        Maintained for compatibility, but deprecated and does nothing\r\n"
                + "    Unique              Stops duplication of messages\r\n"
                + "    MaxCrit             Trigger Critical if number of filtered events > this value\r\n"
                + "    MaxWarn             Trigger Warning if number of filtered events > this value\r\n"
                + "    Legacy              Causes MaxWarn/MaxCrit to trigger if >= their value\r\n"
                + "    Warn                Warning event trigger level (nagios format, replaces MaxWarn)\r\n"
                + "    Crit                Critical event trigger level (nagios format, replaces MaxCrit)\r\n"
                + "    MaxEvents           Maximum number of events to return (does not affect counts)\r\n"
                + "    Syntax              Format for event display\r\n"
                + "      Can use macros using '%<macro>%' format\r\n"
                + "      Macros: (description, count, message, generated, written, id, level, severity, type, source)\r\n"
                + "      'generated' or 'written' date format:\r\n"
                + "        Uses optional single char standard date format %generated-<format>% with InvariantCulture\r\n"
                + "          See https://learn.microsoft.com/en-us/dotnet/standard/base-types/standard-date-and-time-format-strings\r\n"
                + "        Examples:\r\n"
                + "          %generated%   (uses default date format of 'R')\r\n"
                + "          %generated-D% (uses 'D' date format)\r\n"
        );
        try
        {
            var clArgList = callData.cmd
                .Select(a => a.Split(new Char[] { '=' }, 2))
                .Skip(1)
                .Select(
                    x =>
                        new Tuple<string, string>(
                            x[0].Trim(),
                            x.ElementAtOrDefault(1) != null ? x[1] : String.Empty
                        )
                ).ToList();
            if (clArgList.Count() == 0)
            {
                return check.ExitHelp();
            }
            clArgList.ForEach(argTuple =>
            {
                string argName = argTuple.Item1.ToLower().TrimStart(CommandTrimChars);
                string argValue = argTuple.Item2;
                try
                {
                    switch (argName)
                    {
                        case "crit":
                            critExpression = argValue;
                            break;
                        case "descriptions":
                            // Deprecated (assumed on)
                            break;
                        case "debugquery":
                            debugQuery = ParseBooleanArg(argValue, true);
                            break;
                        case "debugmode":
                            debugMode = ParseBooleanArg(argValue, true);
                            break;
                        case "filter":
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
                                    filterPlusList.Add(ParseFilterString(argValue));
                                    break;
                            }
                            break;
                        case "file":
                            requiredEventLog = argValue;
                            break;
                        case "help":
                        case "h":
                            check.ExitHelp();
                            break;
                        case "legacy":
                            maxWarnCritFormat = "@{0}:";  // Uses nagios (>=) format
                            break;
                        case "maxcrit":
                            maxCrit = Int32.Parse(argValue);
                            break;
                        case "maxevents":
                            maxEvents = Int32.Parse(argValue);
                            break;
                        case "maxwarn":
                            maxWarn = Int32.Parse(argValue);
                            break;
                        case "syntax":
                            formatPattern = argValue;
                            break;
                        case "truncate":
                            var tempMaxLength = Int32.Parse(argValue);
                            if ((tempMaxLength <= 0) || (tempMaxLength > MaxTruncateLength))
                            {
                                throw new Exception(String.Format("Invalid truncate value '{0}'", tempMaxLength));
                            }
                            maxLength = tempMaxLength;
                            break;
                        case "unique":
                            unique = ParseBooleanArg(argValue, true);
                            break;
                        case "warn":
                            warnExpression = argValue;
                            break;
                        default:
                            var transribedArgName = TranscribeEventType(argName, argValue);
                            if (transribedArgName.StartsWith("filter") && (argName.Length >= filterPrefixLen + 2))
                            {
                                // Any filter will need at least 1 char for the op and 1 char for the arg
                                var mode = FilterModeParser.Parse(transribedArgName[filterPrefixLen]);
                                var filterName = transribedArgName.Substring(filterPrefixLen + 1);
                                if (!ReFilterName.IsMatch(filterName))
                                    throw new Exception(String.Format("Invalid filter name: '{0}'", filterName));
                                var arg = String.Format("{0} {1}", filterName, EnsureStartOp(argValue.Trim()));
                                if (filterName.Equals("keywords"))
                                {
                                    var keywordsFilter = ParseKeywordsString(arg);
                                    if (mode == FilterMode.plus)
                                    {
                                        codeFilterPlusList.Add(keywordsFilter);
                                    }
                                    else
                                    {
                                        codeFilterMinusList.Add(keywordsFilter);
                                    }
                                }
                                else
                                {
                                    var queryFilter = ParseFilterString(arg);
                                    if (mode == FilterMode.plus)
                                    {
                                        filterPlusList.Add(queryFilter);
                                    }
                                    else
                                    {
                                        filterMinusList.Add(queryFilter);
                                    }
                                }
                            }
                            else
                            {
                                check.ExitUnknown(String.Format("Unrecognised argument '{0}'", argTuple.Item1));
                            }
                            break;
                    }
                }
                catch (ExitException) { throw; }
                catch (Exception e)
                {
                    throw new Exception(String.Format("{0} (when evaluating arg='{1}')", e.Message, argName));
                }
            });
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
            if (debugMode) return check.ExitUnknown(e.ToString());
            return check.ExitUnknown(e.Message);
        }

        try
        {
            if ((filterPlusList.Count == 0) && (filterMinusList.Count == 0) && (codeFilterPlusList.Count == 0) && (codeFilterMinusList.Count == 0))
            {
                throw new Exception("No filters specified, try adding: filter+generated=<1d");
            }
            if (String.IsNullOrEmpty(formatPattern))
            {
                formatPattern = unique ? DefaultUniqueFormatPattern : DefaultFormatPattern;
            }

            var effectiveFilterPlusList = filterIn ? filterPlusList : filterMinusList;
            var effectiveFilterMinusList = filterIn ? filterMinusList : filterPlusList;

            string selectQueryString = effectiveFilterPlusList.Count > 0 ? String.Format("*[System[{0}]]", string.Join(" and ", effectiveFilterPlusList)) : "*";
            string suppressQueryString = effectiveFilterMinusList.Count > 0 ? String.Format("*[System[{0}]]", string.Join(" or ", effectiveFilterMinusList)) : null;

            XElement query = new XElement("QueryList",
                new XElement("Query",
                    new XAttribute("Id", "0"),
                    new XElement("Select",
                            new XAttribute("Path", requiredEventLog),
                            selectQueryString
                        ),
                    !string.IsNullOrEmpty(suppressQueryString)
                        ? new XElement("Suppress",
                            new XAttribute("Path", requiredEventLog),
                            suppressQueryString
                        )
                        : null
                )
            );

            var effectiveCodeFilterPlusList = filterIn ? codeFilterPlusList : codeFilterMinusList;
            var effectiveCodeFilterMinusList = filterIn ? codeFilterMinusList : codeFilterPlusList;

            EventLogQuery eventsQuery = new EventLogQuery(requiredEventLog, PathType.LogName, query.ToString());
            EventLogReader logReader;
            try
            {
                logReader = new EventLogReader(eventsQuery);
            }
            catch (EventLogNotFoundException)
            {
                throw new Exception(String.Format("Invalid file: '{0}'", requiredEventLog));
            }

            LogItemRecorder itemRecorder = LogItemRecorderFactory(unique, formatPattern);
            int eventCount = 0;
            bool hasCodeFilters = (effectiveCodeFilterPlusList.Count > 0) || (effectiveCodeFilterMinusList.Count > 0);
            for (EventRecord eventInstance = logReader.ReadEvent();
                null != eventInstance; eventInstance = logReader.ReadEvent())
            {
                if (hasCodeFilters)
                {
                    if (effectiveCodeFilterPlusList.Any(filter => !filter.Matches(eventInstance))
                    || effectiveCodeFilterMinusList.Any(filter => filter.Matches(eventInstance)))
                    {
                        continue;
                    }
                }
                if ((maxEvents < 0) || (eventCount < maxEvents))
                {
                    itemRecorder.AddItem(eventInstance);
                }
                eventCount++;
            }

            check.MaxLength = maxLength;
            var messageBuilder = new StringBuilder();
            if (debugQuery)
            {
                messageBuilder.AppendFormat("Query: {0}\r\n", query.ToString());
            }
            if (itemRecorder.Count > 0)
            {
                messageBuilder.Append(itemRecorder.Join(", ", maxLength) + "\r\n");
            }
            if (messageBuilder.Length > 0)
            {
                check.AddMessage(messageBuilder.ToString());
            }

            // Calculate the warn/crit expression
            if (String.IsNullOrEmpty(warnExpression) && (maxWarn >= 0))
            {
                warnExpression = String.Format(maxWarnCritFormat, maxWarn);
            }
            if (String.IsNullOrEmpty(critExpression) && (maxCrit >= 0))
            {
                critExpression = String.Format(maxWarnCritFormat, maxCrit);
            }

            check.AddMetric(
                name: "eventlog",
                value: eventCount,
                uom: "",
                displayName: requiredEventLog,
                warningThreshold: warnExpression,
                criticalThreshold: critExpression
            );
            return check.Final();
        }
        catch (ExitException) { throw; }
        catch (Exception e)
        {
            if (debugMode) return check.ExitUnknown(e.ToString());
            return check.ExitUnknown(e.Message);
        }
    }

    // <summary>
    // Parses a boolean using a selection of standard representations.
    // </summary>
    private static bool ParseBooleanArg(string argValue, bool defaultValue)
    {
        if (String.IsNullOrEmpty(argValue)) return defaultValue;
        switch (argValue.Trim().ToLower())
        {
            case "true":
            case "1":
            case "yes":
                return true;
            case "false":
            case "0":
            case "no":
                return false;
            default:
                throw new Exception(String.Format("Invalid boolean value: '{0}' (try using 'true' or 'false')", argValue));
        }
    }

    // <summary>
    // Transcribe AuditSuccess/AuditFailure EventTypes into Keywords filter string.
    // This is only done for backwards compatibility and only for basic '=' filters.
    // Example: 'filter+eventType=auditSuccess' will become 'filter+keywords=auditSuccess'
    // </summary>
    private static string TranscribeEventType(string argName, string argValue)
    {
        var argValueL = argValue.ToLower().TrimStart('=');
        if (argValueL.Equals("auditsuccess") || argValueL.Equals("auditfailure"))
        {
            switch (argName.ToLower())
            {
                case "filter+eventtype":
                    return "filter+keywords";
                case "filter-eventtype":
                    return "filter-keywords";
            }
        }
        return argName;  // No transcribing required
    }

    /// <summary>
    /// Ensures that the string starts with a valid operator.
    /// </summary>
    private static string EnsureStartOp(string opAndValue)
    {
        return ReValidFilterOpStart.IsMatch(opAndValue) ? opAndValue : "=" + opAndValue;
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

    /// <summary>
    /// Parses a filter argument returns a filter.
    /// </summary>
    private static FilterBase ParseFilter(string argName, List<string> argValues, string op)
    {
        FilterBase filter;
        switch (argName.ToLower())
        {
            case "eventid":
            case "id":
                filter = EventIdFilter.Parse(argValues, op);
                break;

            case "eventsource":
            case "source":
                filter = EventSourceFilter.Parse(argValues, op);
                break;

            case "eventtype":
            case "type":
            case "severity":
            case "level":
                filter = EventTypeFilter.Parse(argValues, op);
                break;

            case "generated":
            case "written":
                filter = GeneratedFilter.Parse(argValues[0], op);
                break;

            case "keywords":
                throw new Exception("'Keywords' are only supported via separate filter+keywords or filter-keywords args");

            default:
                throw new Exception(String.Format("Unrecognised filter argument '{0}'", argName));
        }
        return filter;
    }

    /// <summary>
    /// Parses a filter expression into an XPath filter.
    /// </summary>
    private static string ParseFilterString(string argValue)
    {
        var filterList = new List<string>();
        var tokeniser = new Tokeniser();
        try
        {
            List<string> tokens = tokeniser.Tokenise(argValue);
            List<Statement> statements = Lexer.AnalyseFilters(tokens);
            foreach (var statement in statements)
            {
                if (statement is OpStatement)
                {
                    var opStatement = (OpStatement)statement;
                    filterList.Add(ParseFilter(opStatement.name, opStatement.values, opStatement.op).xpath);
                }
                else
                {
                    filterList.Add(statement.name.ToLower());
                }
            }
        }
        catch (Exception e)
        {
            throw new Exception(String.Format("{0} - when evaluating filter '{1}'", e.Message, argValue), e);
        }
        var xPathFilterStr = string.Join(" ", filterList);
        return xPathFilterStr;
    }

    // <summary>
    // Parse a keywords filter expression
    // </summary>
    private static KeywordsFilter ParseKeywordsString(string argValue)
    {
        var tokeniser = new Tokeniser();
        try
        {
            List<string> tokens = tokeniser.Tokenise(argValue);
            var statements = Lexer.AnalyseFilters(tokens);
            if (statements.Count != 1) throw new Exception("Keywords filter only supports a single operation");
            var opStatement = (OpStatement)statements[0];
            return KeywordsFilter.Parse(opStatement.values, opStatement.op);
        }
        catch (Exception e)
        {
            throw new Exception(String.Format("{0} - when evaluating filter '{1}'", e.Message, argValue), e);
        }
    }
}

/// <summary>
/// Represents a basic statement: <name>.
/// Examples could be "and", "or" and "("
/// Also forms the base class for OpStatement.
/// </summary>
class Statement
{
    public string name;

    public Statement(string name)
    {
        this.name = name;
    }
}

/// <summary>
/// Represents a filter statement: <name> <op> <value>
/// </summary>
class OpStatement : Statement
{
    public string op;
    public List<string> values;

    public OpStatement(string name, string op, string value) : base(name)
    {
        this.op = op;
        this.values = new List<string> { value };
    }

    public OpStatement(string name, string op, List<string> values) : base(name)
    {
        this.op = op;
        this.values = new List<string>(values);
    }
}

/// <summary>
/// Parses a list of filter tokens into a list of filter statements.
/// Statements can be either basic (e.g. '(', 'and'), which will be rendered as-is,
///  or an operation, which get indivdiually parsed and rendered.
/// </summary>
static class Lexer
{
    /// <summary>
    /// Parses a list of filter tokens into a list of filter statements.
    /// Statements can be either basic (e.g. '(', 'and'), which will be rendered as-is,
    ///  or an operation, which get individually parsed and rendered.
    /// </summary>
    public static List<Statement> AnalyseFilters(List<string> tokenList)
    {
        var statementList = new List<Statement>();
        var parts = new List<string>();
        var consumingList = false;
        var listItems = new List<string>();
        var bracketCount = 0;

        foreach (string token in tokenList)
        {
            if (consumingList)
            {
                switch (token)
                {
                    case ")":
                        bracketCount--;
                        consumingList = false;
                        statementList.Add(new OpStatement(parts[0], "in", listItems));
                        listItems.Clear();
                        parts.Clear();
                        break;
                    case ",":
                        break;
                    case "(":
                        bracketCount++;
                        break;
                    default:
                        listItems.Add(token);
                        break;
                }
            }
            else
            {
                switch (token)
                {
                    case "(":
                        bracketCount++;
                        break;
                    case ")":
                        bracketCount--;
                        if (bracketCount < 0) throw new Exception("Lexer: Unbalanced brackets in expression");
                        break;
                }
                var tokenLower = token.ToLower();
                switch (tokenLower)
                {
                    case "and":
                    case "or":
                    case "(":
                    case ")":
                        if (parts.Count > 0) throw new Exception(String.Format("Lexer: Unexpected token: '{0}'", token));
                        statementList.Add(new Statement(token));
                        parts.Clear();
                        break;
                    case ",":
                        throw new Exception("Lexer: Unexpected comma found outside of an 'in(<item1>, <item2>)' statement");
                    default:
                        // Attempt to build up a statement (name, op, value)
                        parts.Add(token);
                        if ((parts.Count == 2) && tokenLower.Equals("in"))
                        {
                            consumingList = true;
                        }
                        else if (parts.Count == 3)
                        {
                            var name = parts[0];
                            var op = parts[1];
                            var value = parts[2];
                            statementList.Add(new OpStatement(name, op, value));
                            parts.Clear();
                        }
                        break;
                }
            }
        }
        if (bracketCount > 0) throw new Exception("Lexer: Unbalanced brackets in expression");
        if (parts.Count > 0) throw new Exception(String.Format("Lexer: Incomplete statement: '{0}'", String.Join(" ", parts)));
        return statementList;
    }
}

// <summary>
// Splits a string into filter tokens, based on whitespace and special characters.
// </summary>
class Tokeniser
{
    private readonly Regex ReValidToken = new Regex(@"^([\w-]+)|'([\w- ]+)'$");

    private readonly StringBuilder tokenBuilder = new StringBuilder();
    private readonly List<string> tokenList = new List<string>();

    public List<string> Tokenise(string argValue)
    {
        bool inSingleQuotes = false;
        string lastToken;
        foreach (char c in argValue)
        {
            switch (c)
            {
                case ' ':
                    if (inSingleQuotes)
                    {
                        tokenBuilder.Append(c);
                    }
                    else
                    {
                        AddTokenFromBuilder();
                    }
                    break;
                case '\t':
                    AddTokenFromBuilder();
                    break;
                case '=':
                    lastToken = (tokenList.Count > 0) ? tokenList.Last() : "";
                    if (lastToken.Equals("<") || lastToken.Equals(">"))
                    {
                        // Ensure "<=" or ">=" is a single token
                        tokenList[tokenList.Count - 1] = lastToken + c;
                    }
                    else
                    {
                        AddTokenFromBuilder();
                        tokenList.Add(c.ToString());
                    }
                    break;
                case '\'':
                    tokenBuilder.Append(c);
                    inSingleQuotes = !inSingleQuotes;
                    break;
                case '<':
                case '>':
                case '(':
                case ')':
                case ',':
                    if (c.Equals('>'))
                    {
                        lastToken = (tokenList.Count > 0) ? tokenList.Last() : "";
                        if (lastToken.Equals("<")) throw new Exception("Tokeniser: Invalid operation '<>'");
                    }
                    AddTokenFromBuilder();
                    tokenList.Add(c.ToString());
                    break;
                default:
                    tokenBuilder.Append(c);
                    break;
            }
        }
        AddTokenFromBuilder();
        if (inSingleQuotes)
        {
            throw new Exception("Tokeniser: Unbalanced quotes in expression");
        }
        return tokenList;
    }

    private void AddTokenFromBuilder()
    {
        if (tokenBuilder.Length == 0) return;
        var tokenStr = tokenBuilder.ToString();
        if (!ReValidToken.IsMatch(tokenStr)) throw new Exception(String.Format("Invalid token: '{0}'", tokenStr));
        tokenList.Add(tokenStr.Trim('\''));
        tokenBuilder.Clear();
    }
}
