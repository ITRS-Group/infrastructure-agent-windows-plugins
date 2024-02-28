// Copyright (C) 2003-2024 ITRS Group Limited. All rights reserved

using System;

namespace PlugNSharp
{
    /// <summary>
    /// Class <c>ExitException</c> represents the end of plugin operations
    ///  and contains the process output.
    /// </summary>
    public class ExitException : Exception
    {
        public ProcessOutput output;

        public ExitException(int exitcode = 0, string stdout = "", string stderr = "")
        {
            this.output = new ProcessOutput(exitcode, stdout, stderr);
        }
    }
}
