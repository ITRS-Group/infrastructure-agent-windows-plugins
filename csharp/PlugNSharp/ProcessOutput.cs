// Copyright (C) 2003-2026 ITRS Group Limited. All rights reserved

namespace PlugNSharp
{
    /// <summary>
    /// Class <c>ProcessOutput</c> contains standard process output (JSON serialisable).
    /// </summary>
    public class ProcessOutput
    {
        public int exitcode;
        public string stdout;
        public string stderr;

        public ProcessOutput(int exitcode, string stdout, string stderr)
        {
            this.exitcode = exitcode;
            this.stdout = stdout;
            this.stderr = stderr;
        }
    }
}
