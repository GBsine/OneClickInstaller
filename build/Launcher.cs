using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        try
        {
            string baseDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "OneClickInstaller");
            string appDir = Path.Combine(baseDir, "app");
            string stampFile = Path.Combine(baseDir, "stamp.txt");

            string exePath = Assembly.GetExecutingAssembly().Location;
            string stamp = File.Exists(exePath)
                ? File.GetLastWriteTimeUtc(exePath).Ticks.ToString()
                : "0";

            bool ready = Directory.Exists(appDir)
                && File.Exists(Path.Combine(appDir, "OneClickInstaller.ps1"))
                && File.Exists(stampFile)
                && File.ReadAllText(stampFile).Trim() == stamp;

            if (!ready)
            {
                Directory.CreateDirectory(baseDir);
                string zipPath = Path.Combine(baseDir, "payload.zip");
                using (Stream res = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
                {
                    if (res == null) throw new Exception("Payload resource is missing.");
                    using (FileStream fs = File.Create(zipPath)) res.CopyTo(fs);
                }

                string tmpDir = Path.Combine(baseDir, "app.new");
                if (Directory.Exists(tmpDir)) Directory.Delete(tmpDir, true);
                ZipFile.ExtractToDirectory(zipPath, tmpDir);

                Directory.CreateDirectory(appDir);
                CopyTree(tmpDir, appDir);
                Directory.Delete(tmpDir, true);

                File.WriteAllText(stampFile, stamp);
                try { File.Delete(zipPath); } catch { }
            }

            string ps1 = Path.Combine(appDir, "OneClickInstaller.ps1");
            string argLine = "-NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File \"" + ps1 + "\"";
            foreach (string a in args)
                argLine += " \"" + a.Replace("\"", "\\\"") + "\"";

            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", argLine);
            psi.UseShellExecute = false;
            psi.WorkingDirectory = appDir;

            Process p = Process.Start(psi);
            p.WaitForExit();
            Environment.Exit(p.ExitCode);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "OneClickInstaller",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    static void CopyTree(string from, string to)
    {
        foreach (string dir in Directory.GetDirectories(from, "*", SearchOption.AllDirectories))
        {
            Directory.CreateDirectory(dir.Replace(from, to));
        }
        foreach (string file in Directory.GetFiles(from, "*", SearchOption.AllDirectories))
        {
            File.Copy(file, file.Replace(from, to), true);
        }
    }
}
