using System;
using System.Linq;
using System.Web.Script.Serialization;
// Disposable process fixture. Never invokes a package manager or publisher installer.
public static class Fixture
{
    public static int Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        if (args.Contains("Fixture.SlowFailure")) { System.IO.File.WriteAllText(System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"started.flag"),"fixture"); System.Threading.Thread.Sleep(750); return 1603; }
        if (args.Contains("pipes")) { Console.Out.Write(new string('o', 200000)); Console.Error.Write(new string('e', 200000)); return 0; }
        Console.Write(new JavaScriptSerializer().Serialize(args));
        if (args.Contains("Fixture.Failure")) return 1603;
        if (args.Contains("Fixture.Restart")) return 3010;
        if (args.Contains("Fixture.Cancelled")) return 1602;
        if (args.Contains("Fixture.Offline")) return unchecked((int)0x8A150107);
        return 0;
    }
}
