// Plugin to check http calls from a Windows machine
// Copyright (C) 2003-2025 ITRS Group Ltd. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Linq;
using System.Management;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.IO;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using System.ServiceProcess;
using System.Threading;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using PlugNSharp;
using Helpers;
using PHM = Helpers.PluginHelperMethods;

static class CheckSsl
{
    const int DEFAULT_TIMEOUT = 10;
    const int MILLISECS_FACTOR = 1000;

    static X509Certificate2 remoteCert = null;

    public static int Run(CallData callData)
    {
        Stream networkStream = null;
        SslStream sslStream = null;
        Socket socket = null;
        TcpClient client = null;
        try
        {
            var check = new Check(
                "check_ssl",
                helpText: "Checks SSL certificates.\r\n"
                    + "Positional arguments:\r\n"
                    + "    domain\r\n"
                    + "Optional arguments:\r\n"
                    + "    -h   help     Returns help information\r\n"
                    + "    -w --warning  Response time warning level (seconds)\r\n"
                    + "    -c --critical Response time critical level (seconds)\r\n"
                    + "    -t --timeout  Timeout in seconds (default 10)\r\n"
                    + "    -p --proxy    Proxy to use (e.g. http://user:pass@proxy:port)\r\n"
            );

            var clArgs = callData.cmd
                .Select(a => a.Split('='))
                .Select(x => new Tuple<string, string>(x[0], x.ElementAtOrDefault(1)));

            var clArgList = clArgs.Skip(1).ToList();
            if (clArgList.Count() == 0)
            {
                check.ExitHelp();
            }

            int warningDays = 0;
            int criticalDays = 0;
            string domain = null;
            int timeout = DEFAULT_TIMEOUT;
            int port = 443;
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
                        warningDays = int.Parse(argValue);
                        break;

                    case "-c":
                    case "--critical":
                        criticalDays = int.Parse(argValue);
                        break;

                    case "-P":
                    case "--port":
                        port = int.Parse(argValue);
                        break;

                    case "-p":
                    case "--proxy":
                        var proxyUri = new Uri(FixProxyPrefix(argValue));
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
                        if (String.IsNullOrEmpty(argValue) && String.IsNullOrEmpty(domain))
                        {
                            domain = argTuple.Item1;
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
            if (String.IsNullOrEmpty(domain))
            {
                return check.ExitHelp();
            }

            client = new TcpClient();
            if (proxy != null)
            {
                // Unfortunately, we can't use the WebProxy directly on the TcpClient, so
                //  need to connect manually to the proxy
                client.Connect(proxy.Address.Host, proxy.Address.Port);
                var proxyAuth = "";
                if (proxy.Credentials != null)
                {
                    var creds = (NetworkCredential)proxy.Credentials;
                    var rawAuthStr = String.Format("{0}:{1}", creds.UserName, creds.Password);
                    var base64AuthStr = Convert.ToBase64String(Encoding.UTF8.GetBytes(rawAuthStr));
                    proxyAuth = String.Format("Proxy-Authorization: Basic {0}\r\n", base64AuthStr);
                }
                var connectStr = String.Format("CONNECT {0}:{1} HTTP/1.0\r\n{2}Connection: close\r\n\r\n", domain, port, proxyAuth);
                var connectBytes = Encoding.ASCII.GetBytes(connectStr);
                networkStream = client.GetStream();
                // Console.WriteLine("Connecting via proxy: {0}", proxy.Address);
                networkStream.Write(connectBytes, 0, connectBytes.Length);
                var rawStream = new StreamReader(networkStream);
                rawStream.ReadLine();
            }
            else
            {
                client.Connect(domain, port);
                networkStream = client.GetStream();
            }

            sslStream = new SslStream(
                networkStream,
                false,
                new RemoteCertificateValidationCallback(ValidateServerCertificate),
                null
            );
            sslStream.ReadTimeout = timeout * MILLISECS_FACTOR;

            try
            {
                sslStream.AuthenticateAsClient(domain);
            }
            catch (AuthenticationException)
            {
                if (remoteCert == null)
                {
                    return check.ExitCritical(String.Format("Domain '{0}' does not have a certificate, or it is invalid", domain));
                }
            }
            var expires = remoteCert.NotAfter.ToUniversalTime();
            var now = DateTime.UtcNow;
            var commonName = remoteCert.GetNameInfo(X509NameType.SimpleName, false);

            if (expires <= now)
            {
                return check.ExitCritical(String.Format("Certificate '{0}' expired on {1} UTC", commonName, expires));
            }
            if ((criticalDays > 0) && (expires <= now.AddDays(criticalDays)))
            {
                return check.ExitCritical(String.Format("Certificate '{0}' will expire on {1} UTC", commonName, expires));
            }
            if ((warningDays > 0) && (expires <= now.AddDays(warningDays)))
            {
                return check.ExitWarning(String.Format("Certificate '{0}' will expire on {1} UTC", commonName, expires));
            }

            return check.Final(String.Format("Certificate '{0}' is valid until {1} UTC", commonName, expires));
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
        finally
        {
            if (sslStream != null) sslStream.Close();
            if (networkStream != null) networkStream.Close();
            if (socket != null) socket.Close();
        }
    }

    public static bool ValidateServerCertificate(
        object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors)
    {
        // Capture the remote certificate
        remoteCert = new X509Certificate2(certificate.GetRawCertData());
        return sslPolicyErrors == SslPolicyErrors.None;
    }

    private static String FixProxyPrefix(String proxy)
    {
        if (proxy.StartsWith("http")) return proxy;
        return proxy.Contains("443") ? "https://" + proxy : "http://" + proxy;
    }
}
