using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using NAudio.CoreAudioApi;
using NAudio.Dmo;
using NAudio.Wave;

namespace CrazyBatto
{
    public sealed class CapturableWindow
    {
        public long Handle { get; internal set; }
        public string Title { get; internal set; }
        public string ProcessName { get; internal set; }
        public int Width { get; internal set; }
        public int Height { get; internal set; }

        public override string ToString()
        {
            return Title + " — " + ProcessName + ".exe (" + Width + "x" + Height + ")";
        }
    }

    public static class WindowCaptureHelper
    {
        private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hwnd);

        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr hwnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maximumCount);

        [DllImport("user32.dll")]
        private static extern int GetWindowTextLength(IntPtr hwnd);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

        public static CapturableWindow[] GetWindows()
        {
            List<CapturableWindow> windows = new List<CapturableWindow>();
            EnumWindows(delegate(IntPtr hwnd, IntPtr lParam)
            {
                if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return true;
                int titleLength = GetWindowTextLength(hwnd);
                if (titleLength <= 0) return true;

                StringBuilder titleBuilder = new StringBuilder(titleLength + 1);
                if (GetWindowText(hwnd, titleBuilder, titleBuilder.Capacity) <= 0) return true;
                string title = titleBuilder.ToString().Trim();
                if (title.Length == 0) return true;

                Rect rect;
                if (!GetWindowRect(hwnd, out rect)) return true;
                int width = rect.Right - rect.Left;
                int height = rect.Bottom - rect.Top;
                if (width < 160 || height < 120) return true;

                uint processId;
                GetWindowThreadProcessId(hwnd, out processId);
                string processName = "Unbekannt";
                try
                {
                    using (Process process = Process.GetProcessById((int)processId))
                        processName = process.ProcessName;
                }
                catch { }

                windows.Add(new CapturableWindow
                {
                    Handle = hwnd.ToInt64(),
                    Title = title,
                    ProcessName = processName,
                    Width = width,
                    Height = height
                });
                return true;
            }, IntPtr.Zero);

            windows.Sort(delegate(CapturableWindow left, CapturableWindow right)
            {
                int processComparison = StringComparer.CurrentCultureIgnoreCase.Compare(left.ProcessName, right.ProcessName);
                if (processComparison != 0) return processComparison;
                return StringComparer.CurrentCultureIgnoreCase.Compare(left.Title, right.Title);
            });
            return windows.ToArray();
        }
    }

    public sealed class ProcessLogPump : IDisposable
    {
        private readonly Process process;
        private readonly ConcurrentQueue<string> queue;
        private readonly string label;
        private bool attached;
        private bool reading;
        private bool disposed;
        private int srtHelpQueued;

        public bool SrtConnectionFailed
        {
            get { return Interlocked.CompareExchange(ref srtHelpQueued, 0, 0) != 0; }
        }

        public ProcessLogPump(Process process, ConcurrentQueue<string> queue)
            : this(process, queue, "FFmpeg")
        {
        }

        public ProcessLogPump(Process process, ConcurrentQueue<string> queue, string label)
        {
            if (process == null) throw new ArgumentNullException("process");
            if (queue == null) throw new ArgumentNullException("queue");
            this.process = process;
            this.queue = queue;
            this.label = String.IsNullOrWhiteSpace(label) ? "FFmpeg" : label;
        }

        public void Attach()
        {
            if (disposed) throw new ObjectDisposedException("ProcessLogPump");
            if (attached) return;
            process.ErrorDataReceived += OnErrorDataReceived;
            process.Exited += OnExited;
            attached = true;
        }

        public void BeginRead()
        {
            if (disposed) throw new ObjectDisposedException("ProcessLogPump");
            if (!attached) Attach();
            if (reading) return;
            process.BeginErrorReadLine();
            reading = true;
        }

        private void OnErrorDataReceived(object sender, DataReceivedEventArgs e)
        {
            if (!String.IsNullOrWhiteSpace(e.Data))
            {
                string safeLine = Regex.Replace(e.Data, "passphrase=[^&\\s\\\"]+", "passphrase=********", RegexOptions.IgnoreCase);
                queue.Enqueue("[" + label + "] " + safeLine);
                if (safeLine.IndexOf("Connection to srt://", StringComparison.OrdinalIgnoreCase) >= 0 &&
                    safeLine.IndexOf("failed", StringComparison.OrdinalIgnoreCase) >= 0 &&
                    Interlocked.Exchange(ref srtHelpQueued, 1) == 0)
                {
                    queue.Enqueue("[" + label + "] SRT-Empfänger nicht erreichbar: In OBS muss die Medienquelle auf diesem UDP-Port als aktiver Listener warten. Zusätzlich die Windows-Firewall des OBS-PCs prüfen.");
                }
            }
        }

        private void OnExited(object sender, EventArgs e)
        {
            try
            {
                queue.Enqueue("[" + label + "] FFmpeg wurde beendet (Code " + process.ExitCode + ").");
            }
            catch
            {
                queue.Enqueue("[" + label + "] FFmpeg wurde beendet.");
            }
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            if (reading)
            {
                try { process.CancelErrorRead(); }
                catch { }
                reading = false;
            }
            if (attached)
            {
                process.ErrorDataReceived -= OnErrorDataReceived;
                process.Exited -= OnExited;
                attached = false;
            }
        }
    }

    public sealed class AudioPipeCapture : IDisposable
    {
        private readonly MMDeviceEnumerator enumerator;
        private readonly MMDevice device;
        private readonly IWaveIn capture;
        private readonly object writeLock = new object();
        private NamedPipeServerStream pipe;
        private Thread connectorThread;
        private volatile bool stopping;
        private bool started;
        private bool disposed;

        public int SampleRate { get; private set; }
        public int Channels { get; private set; }
        public int BitsPerSample { get; private set; }
        public int AverageBytesPerSecond { get; private set; }
        public int BlockAlign { get; private set; }
        public string SampleFormat { get; private set; }
        public string LastError { get; private set; }

        public AudioPipeCapture(string deviceId, bool loopback)
        {
            if (String.IsNullOrWhiteSpace(deviceId))
                throw new ArgumentException("Eine Windows-Audiogeräte-ID ist erforderlich.", "deviceId");

            enumerator = new MMDeviceEnumerator();
            device = enumerator.GetDevice(deviceId);
            capture = loopback
                ? (IWaveIn)new WasapiLoopbackCapture(device)
                : (IWaveIn)new WasapiCapture(device);

            WaveFormat format = capture.WaveFormat;
            SampleRate = format.SampleRate;
            Channels = format.Channels;
            BitsPerSample = format.BitsPerSample;
            AverageBytesPerSecond = format.AverageBytesPerSecond;
            BlockAlign = format.BlockAlign;
            SampleFormat = GetFfmpegSampleFormat(format);

            capture.DataAvailable += OnDataAvailable;
            capture.RecordingStopped += OnRecordingStopped;
        }

        private static string GetFfmpegSampleFormat(WaveFormat format)
        {
            bool isFloat = format.Encoding == WaveFormatEncoding.IeeeFloat;
            WaveFormatExtensible extensible = format as WaveFormatExtensible;
            if (extensible != null && extensible.SubFormat == AudioMediaSubtypes.MEDIASUBTYPE_IEEE_FLOAT)
                isFloat = true;

            if (isFloat && format.BitsPerSample == 32)
                return "f32le";

            switch (format.BitsPerSample)
            {
                case 8: return "u8";
                case 16: return "s16le";
                case 24: return "s24le";
                case 32: return "s32le";
                default:
                    throw new NotSupportedException("Nicht unterstütztes Windows-Audioformat: " + format);
            }
        }

        public void Start(string pipeName)
        {
            if (disposed) throw new ObjectDisposedException("AudioPipeCapture");
            if (started) throw new InvalidOperationException("Die Tonaufnahme läuft bereits.");
            if (String.IsNullOrWhiteSpace(pipeName)) throw new ArgumentException("Ein Pipe-Name ist erforderlich.", "pipeName");

            pipe = new NamedPipeServerStream(
                pipeName,
                PipeDirection.Out,
                1,
                PipeTransmissionMode.Byte,
                PipeOptions.None,
                65536,
                65536);

            started = true;
            connectorThread = new Thread(ConnectAndStartCapture);
            connectorThread.IsBackground = true;
            connectorThread.Name = "Crazy_Batto NetCapture Audio";
            connectorThread.Start();
        }

        private void ConnectAndStartCapture()
        {
            try
            {
                pipe.WaitForConnection();
                if (stopping) return;

                int silenceLength = Math.Max(BlockAlign, AverageBytesPerSecond / 10);
                silenceLength -= silenceLength % Math.Max(1, BlockAlign);
                byte[] silence = new byte[silenceLength];
                pipe.Write(silence, 0, silence.Length);
                pipe.Flush();

                if (!stopping)
                    capture.StartRecording();
            }
            catch (ObjectDisposedException)
            {
                // Normal when NetCapture is stopped while FFmpeg is connecting.
            }
            catch (Exception ex)
            {
                LastError = ex.Message;
            }
        }

        private void OnDataAvailable(object sender, WaveInEventArgs e)
        {
            if (stopping || e.BytesRecorded <= 0) return;
            try
            {
                lock (writeLock)
                {
                    if (pipe != null && pipe.IsConnected)
                        pipe.Write(e.Buffer, 0, e.BytesRecorded);
                }
            }
            catch (ObjectDisposedException)
            {
                // Normal during shutdown.
            }
            catch (Exception ex)
            {
                LastError = ex.Message;
            }
        }

        private void OnRecordingStopped(object sender, StoppedEventArgs e)
        {
            if (e.Exception != null && !stopping)
                LastError = e.Exception.Message;
        }

        public void Stop()
        {
            if (!started) return;
            stopping = true;

            try { capture.StopRecording(); }
            catch { }

            try
            {
                if (pipe != null)
                    pipe.Dispose();
            }
            catch { }

            if (connectorThread != null && connectorThread != Thread.CurrentThread)
            {
                try { connectorThread.Join(1000); }
                catch { }
            }

            started = false;
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            Stop();

            capture.DataAvailable -= OnDataAvailable;
            capture.RecordingStopped -= OnRecordingStopped;
            IDisposable disposableCapture = capture as IDisposable;
            if (disposableCapture != null) disposableCapture.Dispose();
            device.Dispose();
            enumerator.Dispose();
        }
    }
}
