// Copyright (C) 2003-2023 ITRS Group Limited. All rights reserved

using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace PlugNSharp
{
    public class UnitCollection
    {
        public readonly string Name;
        public readonly string UnitPrefix;
        public readonly double Value;

        public UnitCollection(string name, string unitPrefix, double value)
        {
            this.Name = name;
            this.UnitPrefix = unitPrefix;
            this.Value = value;
        }
    }
}
