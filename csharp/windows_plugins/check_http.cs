// Company Confidential.
// Plugin to check http calls from a Windows machine
// Copyright (C) 2003-2023 ITRS Group Ltd. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Linq;
using System.Management;
using System.Net;
using System.IO;
using System.ServiceProcess;
using System.Threading;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using PlugNSharp;
using Helpers;
using PHM = Helpers.PluginHelperMethods;

static class CheckHttp
{
    const int DEFAULT_TIMEOUT = 10;
    const int MILLISECS_FACTOR = 1000;

    public static int Run(CallData callData)
    {
        try
        {
            var check = new Check(
                "check_http",
                helpText: "Checks HTTP content\r\n"
                    + "Arguments:\r\n"
                    + "    -h   help     Returns help information\r\n"
                    + "    -w --warning  Response time warning level (seconds)\r\n"
                    + "    -c --critical Response time critical level (seconds)\r\n"
                    + "    -t --timeout  Timeout in seconds (default 10)\r\n"
                    + "    -r --regex    Regex to search for in content\r\n"
                    + "    -s --size     Min and max size of content (chars)\r\n"
                    + "    -p --proxy    Proxy to use (e.g. http://user:pass@proxy:port)\r\n"
                    + "    <url>         The url to check\r\n"
            );

            var clArgs = callData.cmd
                .Select(a => a.Split('='))
                .Select(x => new Tuple<string, string>(x[0], x.ElementAtOrDefault(1)));

            var clArgList = clArgs.Skip(1).ToList();
            if (clArgList.Count() == 0)
            {
                return check.ExitHelp();
            }

            float warningTime = 0.0F;
            float criticalTime = 0.0F;
            string url = null;
            int timeout = DEFAULT_TIMEOUT;
            Regex contentPattern = null;
            int minSize = 0;
            int maxSize = 0;
            WebProxy proxy = null;

            clArgList.ForEach(argTuple =>
            {
                var argValue = argTuple.Item2;
                switch (argTuple.Item1)
                {
                    case "-h":
                    case "help":
                        check.ExitHelp();
                        break;

                    case "-w":
                    case "--warning":
                        warningTime = float.Parse(argValue);
                        break;

                    case "-c":
                    case "--critical":
                        criticalTime = float.Parse(argValue);
                        break;

                    case "-r":
                    case "--regex":
                        contentPattern = new Regex(argValue);
                        break;

                    case "-s":
                    case "--size":
                        try
                        {
                            var parts = argValue.Split(',');
                            minSize = int.Parse(parts[0]);
                            maxSize = int.Parse(parts[1]);
                        }
                        catch (IndexOutOfRangeException)
                        {
                            check.ExitUnknown("Invalid min,max size");
                        }
                        break;

                    case "-p":
                    case "--proxy":
                        var proxyUri = new Uri(argValue);
                        proxy = new WebProxy(proxyUri);
                        var proxyCreds = proxyUri.UserInfo.Split(new char[] {':'}, 2);
                        if (proxyCreds.Length >= 2)
                        {
                            proxy.Credentials = new NetworkCredential(proxyCreds[0], proxyCreds[1]);
                        }
                        break;

                    case "-t":
                    case "--timeout":
                        timeout = int.Parse(argValue);
                        break;

                    default:
                        if (String.IsNullOrEmpty(argValue) && String.IsNullOrEmpty(url))
                        {
                            url = argTuple.Item1;
                        }
                        else
                        {
                            check.ExitUnknown(
                                String.Format("Incorrect argument: '{0}'", argTuple.Item1)
                            );
                        }
                        break;
                }
            });
            if (String.IsNullOrEmpty(url))
            {
                return check.ExitHelp();
            }

            HttpWebRequest http = (HttpWebRequest)HttpWebRequest.Create(url);
            http.Timeout = timeout * MILLISECS_FACTOR;
            if (proxy != null)
            {
                http.Proxy = proxy;
            }

            System.Diagnostics.Stopwatch timer = new Stopwatch();
            timer.Start();
            HttpWebResponse response = (HttpWebResponse)http.GetResponse();
            timer.Stop();

            if ((criticalTime > 0.0) && (timer.ElapsedMilliseconds > (criticalTime * MILLISECS_FACTOR)))
            {
                response.Close();
                return check.ExitCritical("Response too slow");
            }

            string contents;
            using (StreamReader rdr = new StreamReader(response.GetResponseStream()))
            {
                contents = rdr.ReadToEnd();
            }
            response.Close();
            int contentLength = contents.Length;

            if ((minSize > 0) && (contentLength < minSize))
            {
                return check.ExitCritical("Response too small");
            }
            if ((maxSize > 0) && (contentLength > maxSize))
            {
                return check.ExitCritical("Response too large");
            }

            if ((contentPattern != null) && !contentPattern.IsMatch(contents))
            {
                return check.ExitCritical("Pattern not found");
            }

            if ((warningTime > 0.0) && (timer.ElapsedMilliseconds > (warningTime * MILLISECS_FACTOR)))
            {
                return check.ExitWarning("Response too slow");
            }

            return check.Final("OK");
        }
        catch (ExitException) { throw; }  // Standard plugin exit
        catch (WebException e)
        {
            throw new ExitException(3, "", e.Message);
        }
        catch (Exception e)
        {
            throw new ExitException(1, "", e.ToString());
        }
    }
}
