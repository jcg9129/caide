using System;
using System.Linq;
using System.IO;
using System.Collections.Generic;
using System.Text.RegularExpressions;
// Powered by caide (code generator, tester, and library code inliner)

class Solution {
    public void solve(TextReader input, TextWriter output) {
    }
}

class CaideConstants {
    public const string InputFile = null;
    public const string InputFilePattern = null;
    public const string OutputFile = null;
}
public class Program {
    private static string GetInputFile() {
        if (CaideConstants.InputFile != null)
            return CaideConstants.InputFile;
        string f = null;
        DateTime t = DateTime.MinValue;

        var regex = new Regex(CaideConstants.InputFilePattern);

        foreach (string p in Directory.GetFiles(".")) {
            var fileName = Path.GetFileName(p);
            if (!regex.IsMatch(fileName))
                continue;
            var curTime = File.GetLastWriteTime(fileName);
            if (f == null || t < curTime) {
                f = fileName;
                t = curTime;
            }
        }

        if (f == null)
            throw new Exception("Input file not found");
        Console.Error.WriteLine("Using " + f + " as input file");
        return f;
    }

    public static void Main(string[] args) {
        Solution solution = new Solution();
        using (System.IO.TextReader input =
                CaideConstants.InputFile == null ? System.Console.In :
                        new System.IO.StreamReader(GetInputFile()))
        using (System.IO.TextWriter output =
                CaideConstants.OutputFile == null ? System.Console.Out:
                        new System.IO.StreamWriter(CaideConstants.OutputFile))

            solution.solve(input, output);
    }
}
