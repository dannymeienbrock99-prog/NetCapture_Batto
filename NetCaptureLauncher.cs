using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace CrazyBatto
{
    internal static class NetCaptureLauncher
    {
        private static readonly object LogLock = new object();

        private static void AppendLog(string logPath, string text)
        {
            if (string.IsNullOrWhiteSpace(text))
                return;

            lock (LogLock)
            {
                File.AppendAllText(
                    logPath,
                    "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + text + Environment.NewLine,
                    Encoding.UTF8);
            }
        }

        [STAThread]
        private static int Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string logPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CrazyBatto",
                "NetCapture",
                "launcher.log");

            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logPath));
                string applicationDirectory = AppDomain.CurrentDomain.BaseDirectory;
                string scriptPath = Path.Combine(applicationDirectory, "NetCapture.ps1");
                string windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                string powershellPath = Path.Combine(
                    windowsDirectory,
                    "System32",
                    "WindowsPowerShell",
                    "v1.0",
                    "powershell.exe");

                AppendLog(logPath, "Launcher gestartet: " + Application.ExecutablePath);
                AppendLog(logPath, "Installationsordner: " + applicationDirectory);

                if (!File.Exists(scriptPath))
                {
                    MessageBox.Show(
                        "NetCapture.ps1 wurde im Installationsordner nicht gefunden. Bitte NetCapture neu installieren.",
                        "Crazy_Batto NetCapture",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return 2;
                }
                if (!File.Exists(powershellPath))
                    throw new FileNotFoundException("Windows PowerShell 5.1 wurde nicht gefunden.", powershellPath);

                ProcessStartInfo startInfo = new ProcessStartInfo
                {
                    FileName = powershellPath,
                    Arguments = "-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + scriptPath.Replace("\"", "\\\"") + "\"",
                    WorkingDirectory = applicationDirectory,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                using (Process process = new Process())
                {
                    process.StartInfo = startInfo;
                    process.OutputDataReceived += (sender, args) => AppendLog(logPath, "PowerShell: " + args.Data);
                    process.ErrorDataReceived += (sender, args) => AppendLog(logPath, "PowerShell-Fehler: " + args.Data);

                    if (!process.Start())
                        throw new InvalidOperationException("Windows PowerShell konnte nicht gestartet werden.");

                    AppendLog(logPath, "Windows PowerShell wurde gestartet (PID " + process.Id + ").");
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    process.WaitForExit();
                    process.WaitForExit();

                    int exitCode = process.ExitCode;
                    AppendLog(logPath, "Windows PowerShell wurde beendet (Code " + exitCode + ").");
                    if (exitCode != 0)
                    {
                        MessageBox.Show(
                            "NetCapture wurde beim Start beendet (Code " + exitCode + ").\r\n\r\n" +
                            "Die genaue Ursache steht hier:\r\n" + logPath,
                            "Crazy_Batto NetCapture - Startfehler",
                            MessageBoxButtons.OK,
                            MessageBoxIcon.Error);
                    }
                    return exitCode;
                }
            }
            catch (Exception exception)
            {
                try { AppendLog(logPath, "Launcher-Fehler: " + exception); } catch { }
                MessageBox.Show(
                    "NetCapture konnte nicht gestartet werden:\r\n\r\n" + exception.Message +
                    "\r\n\r\nDiagnoseprotokoll:\r\n" + logPath,
                    "Crazy_Batto NetCapture - Startfehler",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
