// Copyright (C) 2003-2026 ITRS Group Limited. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace PlugNSharp
{
    public class InvalidMetricThreshold : Exception
    {
        public InvalidMetricThreshold() { }

        public InvalidMetricThreshold(string message) : base(message) { }

        public InvalidMetricThreshold(string message, Exception inner) : base(message, inner) { }
    }
}
