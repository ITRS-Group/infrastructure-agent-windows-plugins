// Copyright (C) 2003-2026 ITRS Group Limited. All rights reserved
using System;
using System.Diagnostics;
using System.Collections.Generic;
using System.Linq;
using System.Management;

namespace Helpers
{
    /// <summary>
    /// Represents call data passed to the process.
    /// </summary>
    public class CallData
    {
        public string[] cmd; // The list of command line args
        public Dictionary<string, string> env; // The environment variables

        public bool HasCmdArgs()
        {
            return (this.cmd != null) && (this.cmd.Length > 0);
        }

        /// <summary>
        /// Returns an environment variable, firstly checking the call data, then
        ///  falling back to a standard environment variable.
        /// </summary>
        public string GetEnvironmentVariable(string name)
        {
            string value = null;
            if (this.env != null)
            {
                this.env.TryGetValue(name, out value);
            }
            if (value == null)
            {
                value = Environment.GetEnvironmentVariable(name);
            }
            return value;
        }
    }
}
