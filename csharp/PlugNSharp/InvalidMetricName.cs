// Copyright (C) 2003-2023 ITRS Group Limited. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace PlugNSharp
{
    public class InvalidMetricName : Exception
    {
        public InvalidMetricName() { }

        public InvalidMetricName(string message) : base(message) { }

        public InvalidMetricName(string message, Exception inner) : base(message, inner) { }
    }
}
