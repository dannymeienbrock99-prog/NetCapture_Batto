using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace CrazyBatto
{
    internal static class NetCaptureLauncher
    {
        [STAThread]
        private static int Main()
        {
            try
            {
                string applicationDirectory = AppDomain.CurrentDomain.BaseDirectory;
                string scriptPath = Path.Combine(applicationDirectory, "NetCapture.ps1");
                if (!File.Exists(scriptPath))
                {
                    MessageBox.Show(
                        "NetCapture.ps1 wurde im Installationsordner nicht gefunden. Bitte NetCapture neu installieren.",
                        "Crazy_Batto NetCapture",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return 2;
                }

                ProcessStartInfo startInfo = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = "-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + scriptPath.Replace("\"", "\\\"") + "\"",
                    WorkingDirectory = applicationDirectory,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };

                Process process = Process.Start(startInfo);
                if (process == null)
                    throw new InvalidOperationException("PowerShell konnte nicht gestartet werden.");
                process.Dispose();
                return 0;
            }
            catch (Exception exception)
            {
                MessageBox.Show(
                    "NetCapture konnte nicht gestartet werden:\r\n\r\n" + exception.Message,
                    "Crazy_Batto NetCapture",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
