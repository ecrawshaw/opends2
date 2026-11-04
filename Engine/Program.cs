using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using EdiabasLib;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace OpenDS2;

// Diagnostic engine for the Mac app. Reads one JSON request per line on stdin and writes JSON lines on
// stdout: {"event":"progress",...} while working, then {"id":..,"ok":true,"data":..} or {"id":..,"ok":false,"error":..}.
//
// Requests:
//   {"cmd":"ports"}                                    serial ports that look like a K+DCAN cable
//   {"cmd":"config","ecuPath":"/…/Ecu","port":"/dev/cu.usbserial-…"}
//   {"cmd":"scan"}                                     find every module that answers (DS2 group files)
//   {"cmd":"read","sgbd":"mss54ds0"}                   ident, fault memory and every no-argument STATUS job
//   {"cmd":"jobs","sgbd":"mss54ds0"}                   job list with comments (no car needed)
//   {"cmd":"job","sgbd":"…","job":"…","args":"…"}      run any job
//   {"cmd":"poll","sgbd":"…","jobs":["STATUS_…",…]}     first result set of each job, for live data
public static class Program
{
    // Address-based group files used by E-series cars (DS2/KWP over the K-line), from Deep OBD's list
    static readonly string[] Ds2Groups = DetectGroups();

    static string _ecuPath;
    static string _port;
    static string _iface = "obd";      // "obd" = K+DCAN cable (E-series), "enet" = Ethernet (F/G-series)
    static string _remoteHost;          // ENET vehicle IP, or null for auto-discovery
    static EdiabasNet _ediabas;

    public static int Main()
    {
        // SGBD files are Windows-1252 text, which .NET on macOS only has once the code-page provider is registered
        System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        WatchParent();
        // The app's Stop button sends SIGINT: finish the current EDIABAS job, then stop the scan/read.
        _stopSignal = System.Runtime.InteropServices.PosixSignalRegistration.Create(
            System.Runtime.InteropServices.PosixSignal.SIGINT, ctx => { ctx.Cancel = true; _stop = true; });
        string line;
        while ((line = Console.ReadLine()) != null)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            JObject req;
            try { req = JObject.Parse(line); }
            catch (Exception ex) { Write(new { ok = false, error = "bad request: " + ex.Message }); continue; }
            var id = req["id"];
            try
            {
                object data = (string)req["cmd"] switch
                {
                    "ports" => Ports(),
                    "config" => Configure((string)req["ecuPath"], (string)req["port"], (string)req["iface"], (string)req["host"]),
                    "scan" => Scan((string)req["set"], req["groups"]?.ToObject<string[]>()),
                    "read" => ReadModule((string)req["sgbd"], (bool?)req["values"] ?? true),
                    "jobs" => Jobs((string)req["sgbd"]),
                    "job" => RunJob((string)req["sgbd"], (string)req["job"], (string)req["args"] ?? "", HexBytes((string)req["argbin"])),
                    "poll" => Poll((string)req["sgbd"], req["jobs"]?.ToObject<string[]>() ?? []),
                    "codewrite" => CodeWrite((string)req["sgbd"], (int?)req["block"] ?? -1, HexBytes((string)req["data"]), HexBytes((string)req["expect"])),
                    "dsccodewrite" => DscCodeWrite((string)req["sgbd"], HexBytes((string)req["data"]), HexBytes((string)req["expect"])),
                    "clustercode" => ClusterCode((string)req["sgbd"], HexBytes((string)req["data"]), HexBytes((string)req["expect"])),
                    "clusterread" => ClusterRead((string)req["sgbd"], (int?)req["wordAddr"] ?? -1, (int?)req["words"] ?? 0),
                    "clusterrawprobe" => ClusterRawProbe((string)req["sgbd"], (int?)req["wordAddr"] ?? -1, (int?)req["words"] ?? 1),
                    "clustervin" => ClusterVinWrite((string)req["sgbd"], (int?)req["wordAddr"] ?? -1, HexBytes((string)req["data"]), HexBytes((string)req["expect"])),
                    "clearstop" => _stop = false,
                    "trace" => SetTrace((string)req["path"]),
                    "quit" => null,
                    var c => throw new InvalidOperationException($"unknown command {c}"),
                };
                Write(new { id, ok = true, data });
                if ((string)req["cmd"] == "quit") break;
            }
            catch (Exception ex)
            {
                Write(new { id, ok = false, error = Describe(ex) });
            }
        }
        _ediabas?.Dispose();
        return 0;
    }

    // Traffic recording: every frame sent to / received from the car goes to <path>/ifh.trc, so
    // module definitions for our own protocol code can be written from real captures.
    static string _tracePath;

    static object SetTrace(string path)
    {
        _tracePath = string.IsNullOrWhiteSpace(path) ? null : path;
        if (_tracePath != null) Directory.CreateDirectory(_tracePath);
        if (_ediabas != null) ApplyTrace(_ediabas);
        return new { tracing = _tracePath != null, path = _tracePath };
    }

    static void ApplyTrace(EdiabasNet ediabas)
    {
        ediabas.SetConfigProperty("TracePath", _tracePath ?? "");
        ediabas.SetConfigProperty("IfhTrace", _tracePath == null ? "0" : "3");
        ediabas.SetConfigProperty("ApiTrace", _tracePath == null ? "0" : "1");
        ediabas.SetConfigProperty("AppendTrace", "1");
    }

    static volatile bool _stop;
    static System.Runtime.InteropServices.PosixSignalRegistration _stopSignal;

    sealed class StoppedException() : Exception("Stopped");

    // Called between jobs; the flag stays set until the app sends "clearstop" after the operation ends
    static void CheckStop() { if (_stop) throw new StoppedException(); }

    [System.Runtime.InteropServices.DllImport("libc")]
    static extern int getppid();

    // If the app goes away without closing our stdin (a crash, or an inherited pipe handle), we get
    // reparented to launchd; exit rather than linger holding the serial port.
    static void WatchParent()
    {
        int parent = getppid();
        new System.Threading.Thread(() =>
        {
            while (true)
            {
                System.Threading.Thread.Sleep(1000);
                if (getppid() != parent) Environment.Exit(0);
            }
        }) { IsBackground = true }.Start();
    }

    static readonly object WriteLock = new();
    static void Write(object o)
    {
        lock (WriteLock) Console.Out.WriteLine(JsonConvert.SerializeObject(o, Formatting.None));
        Console.Out.Flush();
    }

    static void Progress(string message, int? percent = null) => Write(new { @event = "progress", message, percent });

    static string Describe(Exception ex)
    {
        string text = EdiabasNet.GetExceptionText(ex);
        if (_ediabas != null && _ediabas.ErrorCodeLast != EdiabasNet.ErrorCodes.EDIABAS_ERR_NONE)
            text += $" ({EdiabasNet.GetErrorDescription(_ediabas.ErrorCodeLast)})";
        return text;
    }

    // macOS names FTDI-based cables /dev/cu.usbserial-XXXX
    static object Ports() =>
        Directory.GetFiles("/dev", "cu.*").Where(p => !p.Contains("Bluetooth") && !p.EndsWith("debug-console")).OrderBy(p => p).ToList();

    static object Configure(string ecuPath, string port, string iface, string host)
    {
        if (string.IsNullOrEmpty(ecuPath) || !Directory.Exists(ecuPath)) throw new DirectoryNotFoundException($"ECU folder not found: {ecuPath}");
        _ecuPath = ecuPath;
        _port = port;
        _iface = string.IsNullOrWhiteSpace(iface) ? "obd" : iface.ToLowerInvariant();
        _remoteHost = string.IsNullOrWhiteSpace(host) ? null : host.Trim();
        _ediabas?.Dispose();
        _ediabas = null;
        return new { ecuPath, port, iface = _iface, host = _remoteHost, groups = Ds2Groups.Count(g => File.Exists(Path.Combine(ecuPath, g + ".grp"))) };
    }

    static EdiabasNet Ediabas()
    {
        if (_ecuPath == null) throw new InvalidOperationException("Not configured: choose the ECU folder first");
        if (_ediabas != null) return _ediabas;
        var ediabas = new EdiabasNet();
        EdInterfaceBase iface;
        if (_iface == "enet")
        {
            // Ethernet (ENET) for F/G-series and later cars. RemoteHost null → EdiabasLib auto-discovers.
            var enet = new EdInterfaceEnet { ApplicationName = "OpenDS2" };
            if (!string.IsNullOrEmpty(_remoteHost)) enet.RemoteHost = _remoteHost;
            iface = enet;
        }
        else
        {
            // K+DCAN cable (E-series K-line / D-CAN).
            var obd = new EdInterfaceObd { IfhName = "STD:OBD", ApplicationName = "OpenDS2" };
            if (!string.IsNullOrEmpty(_port)) obd.ComPort = _port;
            iface = obd;
        }
        ediabas.EdInterfaceClass = iface;
        ediabas.SetConfigProperty("EcuPath", _ecuPath);
        ApplyTrace(ediabas);
        ediabas.ProgressJobFunc = e => { if (e.InfoProgressText.Length > 0) Progress(e.InfoProgressText, e.InfoProgressPercent >= 0 ? e.InfoProgressPercent : null); };
        _ediabas = ediabas;
        return ediabas;
    }

    static List<Dictionary<string, object>> Execute(string sgbd, string job, string args = "", byte[] argBinary = null)
    {
        var ediabas = Ediabas();
        ediabas.ResolveSgbdFile(sgbd);
        // ArgString and ArgBinary are the SAME storage in EdiabasLib (_argInfo.BinData): setting one
        // replaces the other. So a job gets either text arguments or a binary buffer (e.g. C_C_LESEN's
        // BINAER_BUFFER), never both. Ordinary jobs read ArgBinary — ArgBinaryStd is only for EDIABAS
        // "standard" jobs. Exactly one setter runs on every call, so nothing carries over from the
        // previous job (an empty ArgString clears a leftover buffer).
        // (Setting ArgBinary = null after ArgString wiped every job's text arguments — fixed.)
        if (argBinary != null)
        {
            if (!string.IsNullOrEmpty(args))
                throw new ArgumentException("a job takes either text arguments or a binary buffer, not both");
            ediabas.ArgBinary = argBinary;
        }
        else
        {
            ediabas.ArgString = args;
        }
        ediabas.ResultsRequests = string.Empty;
        // Built-in jobs (_JOBS, _VERSIONINFO, …) only read the SGBD file; don't open the cable for them
        ediabas.NoInitForVJobs = true;
        ediabas.ExecuteJob(job);
        return ediabas.ResultSets.Select(set => set.ToDictionary(kv => kv.Key, kv => ToJsonValue(kv.Value.OpData))).ToList();
    }

    static object ToJsonValue(object v) => v switch
    {
        byte[] b => BitConverter.ToString(b).Replace("-", " "),
        double d => Math.Round(d, 4),
        _ => v,
    };

    // Pick the group SGBDs to IDENT: "ds2" = d_* (E-series K-line, e.g. E46), "dcan" = g_*
    // (D-CAN E8x/E9x and F/G-series, functional groups), "all" = both. Default follows the
    // interface: ENET implies the newer g_* set, the cable implies DS2.
    // E-series K-line modules that speak KWP2000 rather than DS2, so no d_* group file reaches
    // them: IDENT the SGBD directly. DSC_MK60 (ABS/DSC at KWP address 0x29, E46 incl. M3) was
    // invisible to the d_0056 group on a real car but answered IDENT directly.
    static readonly string[] DirectProbes = ["dsc_mk60"];

    static List<string> GroupsForScan(string set)
    {
        set = string.IsNullOrWhiteSpace(set) ? (_iface == "enet" ? "dcan" : "ds2") : set.ToLowerInvariant();
        bool Exists(string g) => File.Exists(Path.Combine(_ecuPath ?? "", g + ".grp"));
        bool PrgExists(string p) => File.Exists(Path.Combine(_ecuPath ?? "", p + ".prg"));
        var ds2 = Ds2Groups.Where(Exists).Concat(DirectProbes.Where(PrgExists));
        return set switch
        {
            "dcan" => DcanGroups(),
            "all" => ds2.Concat(DcanGroups()).Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            _ => ds2.ToList(),
        };
    }

    // D-CAN / F-series functional group SGBDs present in the ECU folder (g_*.grp), core ECUs first
    // so a cut-short scan still surfaces the gateway, immobiliser, cluster, engine and brakes.
    static List<string> DcanGroups()
    {
        if (string.IsNullOrEmpty(_ecuPath) || !Directory.Exists(_ecuPath)) return new List<string>();
        var all = Directory.EnumerateFiles(_ecuPath, "g_*.grp")
            .Select(Path.GetFileNameWithoutExtension).ToList();
        string[] priority = ["g_zgw", "g_bdc", "g_fem", "g_cas", "g_kombi", "g_motor", "g_motor2",
            "g_dde", "g_egs", "g_dsc", "g_frm", "g_cid", "g_hu_nbt", "g_hu_cic", "g_jbbf", "g_fzd", "g_ihka", "g_szl"];
        int Rank(string g) { int i = Array.IndexOf(priority, g.ToLowerInvariant()); return i < 0 ? priority.Length : i; }
        return all.OrderBy(Rank).ThenBy(g => g, StringComparer.OrdinalIgnoreCase).ToList();
    }

    // `only`: check just these group files (a quick rescan of the addresses that answered last time)
    static object Scan(string set, string[] only = null)
    {
        var found = new List<object>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var groups = only is { Length: > 0 }
            ? only.Concat(DirectProbes).Distinct(StringComparer.OrdinalIgnoreCase)   // probes too: lists saved before a probe was added lack it
                .Where(g => File.Exists(Path.Combine(_ecuPath ?? "", g + ".grp")) || File.Exists(Path.Combine(_ecuPath ?? "", g + ".prg"))).ToList()
            : GroupsForScan(set);
        for (int i = 0; i < groups.Count; i++)
        {
            string group = groups[i];
            if (_stop) { Progress("Scan stopped", 100); return found; }   // keep what answered so far
            Progress($"Checking {group}", 100 * i / groups.Count);
            try
            {
                // IDENT on a group file picks the matching variant SGBD for whatever answers at that address
                var ident = Execute(group, "IDENT");
                string sgbd = Path.GetFileNameWithoutExtension(Ediabas().SgbdFileName);
                if (!seen.Add(sgbd)) continue;
                found.Add(new { group, sgbd, name = ModuleComment(sgbd), ident = ident.Skip(1).FirstOrDefault() });
            }
            catch (Exception)
            {
                // no module at this address
            }
        }
        Progress("Scan complete", 100);
        return found;
    }

    static string ModuleComment(string sgbd)
    {
        try
        {
            var info = Execute(sgbd, "_VERSIONINFO");
            return info.SelectMany(s => s).Where(kv => kv.Key.StartsWith("ECUCOMMENT") || kv.Key == "ECU").Select(kv => kv.Value as string).FirstOrDefault(s => !string.IsNullOrWhiteSpace(s));
        }
        catch { return null; }
    }

    // Everything readable without changing the car: ident, fault and info memory, and (unless
    // `values` is false) every argument-less status job. Status jobs are most of the K-line round
    // trips (89 of ~92 on the S54 DME), so "Read all" skips them.
    static object ReadModule(string sgbd, bool values = true)
    {
        var result = new Dictionary<string, object>();
        var jobs = JobList(sgbd);
        string[] wanted = ["IDENT", "FS_LESEN", "FS_LESEN_DETAIL", "IS_LESEN", "AIF_LESEN", "ZFS_LESEN"];
        foreach (var job in wanted.Where(j => jobs.ContainsKey(j)))
        {
            CheckStop();
            Progress($"{sgbd}: {job}");
            result[job] = Safe(() => Execute(sgbd, job));
        }
        if (!values) return result;
        var statusJobs = jobs.Keys.Where(j => j.StartsWith("STATUS_") && !JobHasArgs(sgbd, j)).ToList();
        var status = new Dictionary<string, object>();
        for (int i = 0; i < statusJobs.Count; i++)
        {
            CheckStop();
            Progress($"{sgbd}: {statusJobs[i]}", 100 * i / Math.Max(1, statusJobs.Count));
            status[statusJobs[i]] = Safe(() => Execute(sgbd, statusJobs[i]));
        }
        result["STATUS"] = status;
        return result;
    }

    static object Safe(Func<object> f)
    {
        try { return f(); }
        catch (Exception ex) { return new { error = Describe(ex) }; }
    }

    static Dictionary<string, string> JobList(string sgbd)
    {
        var jobs = new Dictionary<string, string>();
        foreach (var set in Execute(sgbd, "_JOBS"))
            if (set.TryGetValue("JOBNAME", out var name) && name is string n)
                jobs[n] = null;
        foreach (var job in jobs.Keys.ToList())
        {
            try
            {
                var comments = Execute(sgbd, "_JOBCOMMENTS", job);
                jobs[job] = string.Join(" ", comments.SelectMany(s => s).Where(kv => kv.Key.StartsWith("JOBCOMMENT")).Select(kv => kv.Value as string).Where(s => !string.IsNullOrWhiteSpace(s)));
            }
            catch { }
        }
        return jobs;
    }

    static bool JobHasArgs(string sgbd, string job)
    {
        try { return Execute(sgbd, "_ARGUMENTS", job).Any(s => s.ContainsKey("ARG")); }
        catch { return true; }
    }

    static object Jobs(string sgbd) =>
        JobList(sgbd).Select(kv => new { job = kv.Key, comment = kv.Value, hasArgs = JobHasArgs(sgbd, kv.Key) }).ToList();

    // The only jobs that may receive a binary buffer (BINAER_BUFFER). Each was disassembled and sends
    // nothing but read telegrams — the buffer only sets address and length, never the command byte:
    //   zke5     C_C_LESEN  DS2 `00 05 08 <block>`            (08 = read coding block)
    //   kombi46r C_S_LESEN  DS2 `80 09 06 03 00 <addr> <n>`   (06 03 = read memory, as EEPROM_LESEN)
    // Any other job given a buffer is refused before it runs, whatever path sent it. Write jobs
    // (C_C_AUFTRAG, C_S_AUFTRAG…) will get their own reviewed command, not this list.
    static readonly HashSet<string> BinaryArgJobs = new(StringComparer.OrdinalIgnoreCase)
    {
        "zke5/C_C_LESEN",
        "kombi46r/C_S_LESEN",
    };

    // Specific DSC/steering self-calibration service routines. Each measures the module's own
    // sensors and stores its own offsets (no arbitrary data is written), the same category as the
    // brake-bleeding routines. Allowed through the gate so the app's own Calibration buttons can run
    // them; they are NOT on MCPTools.approvableJobs, so AI clients still can't trigger them. EWS/DME
    // *ABGLEICH* (immobilizer/engine alignment) stays blocked by the general rule below.
    static readonly HashSet<string> CalibrationJobs = new(StringComparer.OrdinalIgnoreCase)
    {
        "LENKWINKEL_DSC_ABGLEICHEN",        // steering-angle zero
        "QUERBESCHLEUNIGUNG_DSC_ABGLEICHEN", // lateral-acceleration sensor
        "DRUCKSENSOR_DSC_ABGLEICHEN",        // brake-pressure sensor
        "ABGLEICH_SCHREIBEN",                // lws5 steering-sensor zero
    };

    // Jobs the engine refuses outright, whichever part of the app asks: anything that writes coding,
    // the VIN, the vehicle order, checksums, the odometer or service dates, or that changes power mode.
    // Coding writes will get their own reviewed command. Reads (…_LESEN) stay allowed.
    static string DeniedReason(string job)
    {
        var j = (job ?? "").ToUpperInvariant();
        bool read = j.EndsWith("_LESEN");
        if (CalibrationJobs.Contains(j)) return null;   // specific DSC/steering self-calibrations
        if (j.Contains("SCHREIBEN") || j.Contains("AUFTRAG")) return "writes to the module";
        if (j.StartsWith("C_") && !read) return "coding job (checksum, vehicle order, coding reset…)";
        if (j.StartsWith("GWSZ_") && !read) return "changes the odometer";
        if (j.Contains("FLASH") || j.Contains("PROGRAMM") || j.Contains("SEED_KEY")) return "programming";
        if (j is "ZEITINSPEKTION_VORZIEHEN" or "ENERGIESPARMODE" or "SLEEP_MODE") return "changes service dates or the module's power mode";
        if (j is "SOFTWARE_RESET" or "SG_RESET") return "reboots the module";
        if (j == "STEUERN_DIGITAL") return "drives the module's outputs directly";
        if (j.Contains("ABGLEICH")) return "immobilizer/engine alignment";
        return null;
    }

    // ---- Coding writes: the ONLY path that writes coding -----------------------------------------
    // Body module (zke5) only, one 30-byte coding block per call: 29 data bytes + the 0xAA "korrekt
    // codiert" marker, written with C_C_AUFTRAG (which itself reads the block back and compares).
    // These checks are the engine's own, independent of the app's:
    //   - module zke5, block 0 or 1, exactly 30 bytes, byte 29 == 0xAA
    //   - the block on the car right now equals `expect` (what the app built the change from)
    //   - 1..4 bytes differ (one option, at most a multi-byte field — never a whole-block rewrite)
    //   - afterwards the block is read again and must equal `data` exactly
    // The generic "job" command keeps refusing C_C_AUFTRAG (DeniedReason), and C_C_AUFTRAG is not on
    // BinaryArgJobs, so nothing else can reach it.
    // Buffer layout (zke5.prg disassembly, verified on the car with C_C_LESEN): buf[0]=1, byte count
    // LE at 0x0D-0x0E, address buf[0x11]<<8|buf[0x12] = block number, data from 0x15.
    const int BodyBlockLength = 30;

    static byte[] BodyBuffer(int block, byte[] data)
    {
        var b = new byte[0x16 + BodyBlockLength];
        b[0] = 1;
        b[0x0D] = BodyBlockLength;
        b[0x12] = (byte)block;
        if (data != null) Array.Copy(data, 0, b, 0x15, BodyBlockLength);
        return b;
    }

    static string JobStatus(List<Dictionary<string, object>> sets) =>
        sets.Skip(1).Select(s => s.TryGetValue("JOB_STATUS", out var v) ? v as string : null).FirstOrDefault(s => s != null) ?? "";

    static byte[] ReadBodyBlock(int block)
    {
        var sets = Execute("zke5", "C_C_LESEN", "", BodyBuffer(block, null));
        if (JobStatus(sets) != "OKAY") throw new InvalidOperationException($"reading block {block} failed: {JobStatus(sets)}");
        var raw = HexBytes(sets.Skip(1).Select(s => s.TryGetValue("CODIER_DATEN", out var v) ? v as string : null).FirstOrDefault(s => s != null))
            ?? throw new InvalidOperationException($"reading block {block}: no data");
        if (raw.Length < 0x15 + BodyBlockLength) throw new InvalidOperationException($"reading block {block}: short reply");
        return raw.Skip(0x15).Take(BodyBlockLength).ToArray();
    }

    static string Hex(byte[] b) => string.Join(" ", b.Select(x => x.ToString("X2")));

    static object CodeWrite(string sgbd, int block, byte[] data, byte[] expect)
    {
        if (!string.Equals(sgbd, "zke5", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("codewrite: only the body module (zke5) can be coded");
        if (block is not (0 or 1)) throw new InvalidOperationException("codewrite: block must be 0 or 1");
        if (data == null || data.Length != BodyBlockLength || data[BodyBlockLength - 1] != 0xAA)
            throw new InvalidOperationException("codewrite: data must be 30 bytes ending in AA");
        if (expect == null || expect.Length != BodyBlockLength)
            throw new InvalidOperationException("codewrite: expect must be the 30 bytes the change was built from");
        var current = ReadBodyBlock(block);
        if (!current.SequenceEqual(expect))
            throw new InvalidOperationException($"codewrite: block {block} changed since it was read (now {Hex(current)}); nothing written");
        int differ = Enumerable.Range(0, BodyBlockLength).Count(i => data[i] != current[i]);
        if (differ == 0) throw new InvalidOperationException("codewrite: nothing to change");
        if (differ > 4) throw new InvalidOperationException($"codewrite: {differ} bytes differ; one option changes at most 4");
        var sets = Execute("zke5", "C_C_AUFTRAG", "", BodyBuffer(block, data));
        var status = JobStatus(sets);
        var after = ReadBodyBlock(block);
        if (status != "OKAY")
            throw new InvalidOperationException($"codewrite: C_C_AUFTRAG returned {status}; block {block} now reads {Hex(after)}");
        if (!after.SequenceEqual(data))
            throw new InvalidOperationException($"codewrite: verify failed; block {block} reads {Hex(after)}, expected {Hex(data)}");
        return new { block, before = Hex(current), after = Hex(after), status };
    }

    // ---- DSC coding write (dsc_mk60 only) --------------------------------------------------------
    // The DSC coding block is 15 bytes: byte 0 is the checksum (the module recomputes it), bytes
    // 1..14 are the data. COD_SCHREIBEN takes those 14 data bytes as a hex string ("die CS wird
    // automatisch berechnet", verified in the dsc_mk60.prg disassembly: it loops 0x0E=14 bytes and
    // XORs the checksum). COD_LESEN returns the raw telegram `_TEL_ANTWORT`
    // (B8 F1 29 12 62 30 00 <15 coding bytes> <telegram-cs>); the coding block is bytes 7..22.
    // Guards mirror CodeWrite: dsc_mk60 only, fresh read == expect, 1..4 data bytes differ, read
    // back and verify the 14 data bytes (byte 0 is the module's new checksum, so not compared).
    const int DscCodingLength = 15;   // 1 checksum + 14 data bytes

    static byte[] ReadDscCoding()
    {
        var sets = Execute("dsc_mk60", "COD_LESEN", "");
        if (JobStatus(sets) != "OKAY")
            throw new InvalidOperationException($"dsccodewrite: reading DSC coding failed: {JobStatus(sets)}");
        var telHex = sets.Select(s => s.TryGetValue("_TEL_ANTWORT", out var v) ? v as string : null).FirstOrDefault(s => s != null);
        var tel = HexBytes(telHex);
        if (tel == null || tel.Length < 7 + DscCodingLength || tel[0] != 0xB8)
            throw new InvalidOperationException($"dsccodewrite: unexpected DSC coding telegram {telHex}");
        return tel.Skip(7).Take(DscCodingLength).ToArray();
    }

    static object DscCodeWrite(string sgbd, byte[] cbytes, byte[] expect)
    {
        if (!string.Equals(sgbd, "dsc_mk60", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("dsccodewrite: only the ABS/DSC module (dsc_mk60) can be coded here");
        if (cbytes == null || cbytes.Length != DscCodingLength - 1)
            throw new InvalidOperationException($"dsccodewrite: data must be the {DscCodingLength - 1} coding bytes (byte 0 checksum excluded)");
        if (expect == null || expect.Length != DscCodingLength)
            throw new InvalidOperationException($"dsccodewrite: expect must be the {DscCodingLength} bytes the change was built from");
        var current = ReadDscCoding();
        if (!current.SequenceEqual(expect))
            throw new InvalidOperationException($"dsccodewrite: coding changed since it was read (now {Hex(current)}); nothing written");
        // Compare only the 14 data bytes (expect[1..] vs cbytes); the checksum byte 0 is module-managed.
        int differ = Enumerable.Range(0, DscCodingLength - 1).Count(i => cbytes[i] != expect[i + 1]);
        if (differ == 0) throw new InvalidOperationException("dsccodewrite: nothing to change");
        if (differ > 4) throw new InvalidOperationException($"dsccodewrite: {differ} bytes differ; one option changes at most 4");
        var arg = string.Join(",", cbytes.Select(b => b.ToString("X2")));
        var sets = Execute("dsc_mk60", "COD_SCHREIBEN", arg);
        var status = JobStatus(sets);
        var after = ReadDscCoding();
        if (status != "OKAY")
            throw new InvalidOperationException($"dsccodewrite: COD_SCHREIBEN returned {status}; coding now reads {Hex(after)}");
        if (!after.Skip(1).SequenceEqual(cbytes))
            throw new InvalidOperationException($"dsccodewrite: verify failed; data now reads {Hex(after.Skip(1).ToArray())}, expected {Hex(cbytes)}");
        return new { before = Hex(current), after = Hex(after), status };
    }

    // Cluster coding writes stay off: clustercode (general C_S_AUFTRAG coding) is an unimplemented stub.
    // There is deliberately NO odometer write path in this project, and GWSZ_* writes are refused by
    // DeniedReason. Odometer correction is a bench job on the M35080 EEPROM, not a cable feature.
    const bool ClusterWritesVerified = false;

    // ---- Cluster coding write (kombi46r only) — e.g. align the stored VIN after a cluster swap -----
    // Gated by ClusterWritesVerified. Mirrors CodeWrite's guards, adapted for the cluster:
    //   1. Refuse unless ClusterWritesVerified is true.
    //   2. Module must be kombi46r.
    //   3. data/expect are the full coding buffer; expect must equal a fresh read (no change since read).
    //   4. Recompute the two coding checksums (CHECKSUM@0x16E, CHECKSUM_2@0x3CD) over the new buffer
    //      with the verified C_CHECKSUM algorithm, then write via C_S_AUFTRAG and read back to verify.
    // RE (prior session, verified live on the M3): C_S_AUFTRAG and C_CHECKSUM are GENERIC — they read
    // the region bounds / store address from the input buffer (offsets 5/7 bounds, 0x11/0x12 store addr)
    // and C_S_AUFTRAG recomputes+stores the coding checksum itself. So `data` supplies the new coding
    // bytes plus those bounds; we do NOT precompute the checksum. The coding-checksum verify is recorded
    // COMPLETE (CHECKSUM@0x16E=EE, CHECKSUM_2@0x3CD=F4). Steps stay behind the gate pending reconciliation
    // of that prior finding + the VIN byte layout, then an on-car verify with backup/read-back.
    // Cluster odometer is NOT writable here — that is bench-only (M35080); see CLAUDE.md Rule 4.
    static object ClusterCode(string sgbd, byte[] data, byte[] expect)
    {
        if (!ClusterWritesVerified)
            throw new InvalidOperationException("cluster coding write is disabled until the cluster checksum algorithm is verified");

        if (!string.Equals(sgbd, "kombi46r", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("clustercode: only the cluster module (kombi46r) can be coded here");
        if (data == null || data.Length == 0)
            throw new InvalidOperationException("clustercode: data (the new coding buffer) is required");
        if (expect == null || expect.Length != data.Length)
            throw new InvalidOperationException("clustercode: expect must be the current coding buffer, same length as data");

        // Gated TODOs (to be verified on-car with the owner, with a backup and read-back ready):
        // - Read current coding (C_S_LESEN) and confirm it equals `expect` (no change since read).
        // - Bound the change (which coding/VIN bytes may move; refuse odometer/ring addresses).
        // - Recompute CHECKSUM@0x16E and CHECKSUM_2@0x3CD with the verified C_CHECKSUM algorithm.
        // - Write via C_S_AUFTRAG (buffer incl. checksums) and read back; verify it equals `data`.
        throw new NotImplementedException("TODO (on-car): verify C_CHECKSUM, then C_S_AUFTRAG cluster coding write with read-back");
    }

    // ---- Cluster VIN (FG_NR) write (kombi46r only) — align the stored chassis number after a swap ---
    // RE (kombi46r.b1v + owner EEPROM, verified on-car 2026-10-28): the FG_NR is read by C_FG_LESEN via
    // firmware svc 02 02 and sits at bank-03 EEPROM byte 0x07A (word 0x3D) as [2 ASCII letters][3 BCD
    // digit bytes] (a C_FG_LESEN reply 80 0A A0 02 <2 ASCII> <3 BCD> <cs> decodes to e.g. "AB"+123450 = AB12345; byte 0x07A matched).
    // It is NOT the vehicle order (C_FA_LESEN is a separate 06 08/FF-20 bank with no FG_NR), so the change
    // is a RAW 07 03 memory word write (see BuildMemTel) — NOT C_S_SCHREIBEN (coding-masked, see below)
    // and NOT C_FA_AUFTRAG.
    //
    // Reads are WORD-addressed (byte = word*2). The FG_NR spans bytes 0x7A-0x7E; byte 0x7F (the GWSZ
    // offset, a different value) shares word 0x3F and MUST be preserved — the caller passes whole words
    // and changes only the FG_NR bytes.
    //
    // SAFETY: access is gated in the app (Setup toggle, human-only, never MCP). The write self-checks the
    // raw channel read-only first and keeps a CHECKSUM at 0x16E consistent; it refuses the odometer ring
    // (word<0x10), requires `expect` == a fresh read, caps the change at the FG_NR size, and verifies by
    // read-back. Backup/restore is the app's responsibility.
    // Reads via EEPROM_LESEN ("EEPROM-Speicher auslesen") — unambiguously read-only and returns the raw
    // bytes directly (no header). NOTE: C_S_LESEN would also work (its disassembly sends only 06 03, i.e.
    // read), but its SGBD JOBCOMMENT is mislabeled "Codierdaten schreiben und verifizieren", so we avoid
    // it here and for backups to leave no doubt that reading is read-only.
    static byte[] ClusterReadWords(int wordAddr, int nWords)
    {
        var sets = Execute("kombi46r", "EEPROM_LESEN", $"0x{wordAddr:X4};{nWords}");
        if (JobStatus(sets) != "OKAY") throw new InvalidOperationException($"EEPROM_LESEN word 0x{wordAddr:X} x{nWords} failed: {JobStatus(sets)}");
        var raw = HexBytes(sets.Skip(1).Select(s => s.TryGetValue("DATEN", out var v) ? v as string : null).FirstOrDefault(s => s != null))
            ?? throw new InvalidOperationException("EEPROM_LESEN: no data");
        if (raw.Length < nWords * 2) throw new InvalidOperationException($"EEPROM_LESEN: short reply ({raw.Length} bytes)");
        return raw.Take(nWords * 2).ToArray();
    }

    // Raw DS2 memory telegram, framed exactly like the cluster's own GWSZ_OFFSET_SCHREIBEN (RE'd from
    // kombi46r.b1v). This is the ONLY clean way to write the FG_NR: C_S_SCHREIBEN is coding-specific (it
    // masks the write with a coding mask and does a two-telegram read-modify-write), so a bare FG_NR
    // change gets masked out — that is why the earlier C_S_SCHREIBEN-based write read back unchanged.
    //   read:  80 09 06 03 00 <addrHi> <addrLo> <count>                         (count in WORDS)
    //   write: 80 LEN 07 03 00 <addrHi> <addrLo> <count> <data…>   LEN = 9 + 2*count (incl checksum)
    // The telegram we build is the PAYLOAD ONLY — TransDs2 appends the DS2 XOR checksum itself at
    // sendData[sendData.Length] (ParChecksumByUser=false), and TransmitData passes sendDataLength =
    // sendData.Length. So the array must NOT include a checksum slot (an extra byte makes the on-wire
    // telegram one byte longer than its LEN field → the cluster ignores it → IFH_0009). The LEN byte,
    // though, counts the checksum the interface will add.
    static byte[] BuildMemTel(byte opcode, int wordAddr, int count, byte[] data)
    {
        int dataLen = data?.Length ?? 0;
        var tel = new byte[8 + dataLen];             // payload only (no checksum byte)
        tel[0] = 0x80;
        tel[1] = (byte)(9 + dataLen);                // DS2 length field = payload + the appended checksum
        tel[2] = opcode;                             // 0x06 = read memory, 0x07 = write memory
        tel[3] = 0x03;
        tel[4] = 0x00;
        tel[5] = (byte)((wordAddr >> 8) & 0xFF);
        tel[6] = (byte)(wordAddr & 0xFF);
        tel[7] = (byte)count;                        // word count
        if (dataLen > 0) Array.Copy(data, 0, tel, 8, dataLen);
        return tel;
    }

    // Send a raw telegram over the (already DS2-configured) K+DCAN interface and return the full response.
    // Only valid right after a cluster read (EEPROM_LESEN), which leaves the interface in DS2 mode.
    static byte[] ClusterRawXfer(byte[] tel)
    {
        if (_ediabas?.EdInterfaceClass is not EdInterfaceObd obd)
            throw new InvalidOperationException("raw cluster transfer needs the K+DCAN (OBD) interface");
        if (!obd.TransmitData(tel, out var recv) || recv == null)
        {
            string detail = _ediabas.ErrorCodeLast != EdiabasNet.ErrorCodes.EDIABAS_ERR_NONE
                ? $" ({EdiabasNet.GetErrorDescription(_ediabas.ErrorCodeLast)})" : "";
            throw new InvalidOperationException($"raw cluster transfer failed — no response to {Hex(tel)}{detail}");
        }
        return recv;
    }

    // Prove the raw channel read-only: the raw 06 03 read of `wordAddr` must contain, as a contiguous
    // run, the same bytes EEPROM_LESEN returns. Returns the offset of that run in the response, or -1.
    // This both validates the TransmitData framing/comm-params AND locates the data in the reply, with no
    // hard-coded response layout — so if the framing is wrong we find out here, before any write.
    static int ClusterRawReadEchoesEeprom(int wordAddr, int nWords, out byte[] rawResp, out byte[] eeprom)
    {
        eeprom = ClusterReadWords(wordAddr, nWords);            // leaves the interface in DS2 mode too
        rawResp = ClusterRawXfer(BuildMemTel(0x06, wordAddr, nWords, null));
        return IndexOfSeq(rawResp, eeprom);
    }

    static int IndexOfSeq(byte[] hay, byte[] needle)
    {
        if (hay == null || needle == null || needle.Length == 0 || hay.Length < needle.Length) return -1;
        for (int i = 0; i + needle.Length <= hay.Length; i++)
        {
            bool ok = true;
            for (int j = 0; j < needle.Length; j++) if (hay[i + j] != needle[j]) { ok = false; break; }
            if (ok) return i;
        }
        return -1;
    }

    // Raw 07 03 write of whole words. The DS2 positive status byte is 0xA0 (A0=OKAY in JOBRESULT); we
    // surface a rejection, but the caller's EEPROM_LESEN read-back is the real proof the bytes changed.
    static void ClusterRawWriteWords(int wordAddr, byte[] data)
    {
        var resp = ClusterRawXfer(BuildMemTel(0x07, wordAddr, data.Length / 2, data));
        if (resp.Length >= 3 && resp[2] != 0xA0)
            throw new InvalidOperationException($"raw write to word 0x{wordAddr:X} rejected (response {Hex(resp)})");
    }

    // Read-only: return `words` 2-byte words of cluster EEPROM from `wordAddr` as hex (for the app to
    // build the before/after of a VIN write, and for backups). Uses EEPROM_LESEN (read-only).
    static object ClusterRead(string sgbd, int wordAddr, int words)
    {
        if (!string.Equals(sgbd, "kombi46r", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("clusterread: only the cluster module (kombi46r)");
        if (wordAddr < 0 || wordAddr > 0x1FF) throw new InvalidOperationException("clusterread: word address out of range (0x000-0x1FF)");
        if (words < 1 || words > 16) throw new InvalidOperationException("clusterread: words must be 1-16");
        return new { wordAddr, words, data = Hex(ClusterReadWords(wordAddr, words)) };
    }

    // READ-ONLY. Proves the raw-telegram channel before anyone trusts a write: it reads `words` at
    // `wordAddr` two ways — the ordinary EEPROM_LESEN job, and a raw 06 03 telegram via TransmitData —
    // and reports whether the raw reply contains the EEPROM_LESEN bytes (and at what offset). A match
    // means the DS2 framing, comm-param persistence and XOR checksum are all correct, so the identical
    // framing with the 07 03 write opcode is sound. Never writes; the owner runs this on the M3 first.
    static object ClusterRawProbe(string sgbd, int wordAddr, int words)
    {
        if (!string.Equals(sgbd, "kombi46r", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("clusterrawprobe: only the cluster module (kombi46r)");
        if (wordAddr < 0 || wordAddr > 0x1FF) throw new InvalidOperationException("clusterrawprobe: word address out of range (0x000-0x1FF)");
        if (words < 1 || words > 16) throw new InvalidOperationException("clusterrawprobe: words must be 1-16");
        int echo = ClusterRawReadEchoesEeprom(wordAddr, words, out var rawResp, out var eeprom);
        return new
        {
            wordAddr,
            words,
            eepromLesen = Hex(eeprom),
            rawResponse = Hex(rawResp),
            match = echo >= 0,
            dataOffset = echo,
            note = echo >= 0
                ? "raw channel OK: the raw 06 03 reply contains the EEPROM_LESEN bytes — the 07 03 write framing is proven"
                : "NO MATCH: raw framing/comm-params not confirmed — do NOT enable the VIN write until this matches"
        };
    }

    // Access is gated in the app (Setup "Cluster VIN write" toggle, off by default; human-only, never
    // MCP). The engine always enforces the operational guards below (kombi46r-only, NEVER the odometer
    // ring, expect==fresh-read, <=5 bytes changed, read-back verify) so a stray call can't do damage.
    static object ClusterVinWrite(string sgbd, int wordAddr, byte[] data, byte[] expect)
    {
        if (!string.Equals(sgbd, "kombi46r", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("clustervin: only the cluster module (kombi46r) can be written here");
        if (data == null || data.Length == 0 || data.Length % 2 != 0)
            throw new InvalidOperationException("clustervin: data must be whole 2-byte words");
        if (expect == null || expect.Length != data.Length)
            throw new InvalidOperationException("clustervin: expect must be the current bytes, same length as data");
        if (wordAddr < 0 || wordAddr > 0x1FF)
            throw new InvalidOperationException("clustervin: word address out of range (0x000-0x1FF)");
        if (wordAddr < 0x10)
            throw new InvalidOperationException("clustervin: refusing the odometer ring region (word < 0x10) — odometer is never written here");

        // The incremental checksum maths below is only valid when every changed byte lies inside the
        // CHECKSUM region at byte 0x16E = XOR(bytes 0x5A..0xFF) (words 0x2D..0x7F, verified via the kombi
        // coding trafo and reproduced from the owner's dump). The FG_NR (bytes 0x7A..0x7E) is inside it;
        // refuse anything that isn't, so we never write with a checksum we can't correctly maintain.
        int firstByte = wordAddr * 2, lastByte = wordAddr * 2 + data.Length - 1;
        if (firstByte < 0x5A || lastByte > 0xFF)
            throw new InvalidOperationException($"clustervin: change (bytes 0x{firstByte:X}-0x{lastByte:X}) is outside the FG_NR checksum region (0x5A-0xFF); not supported");

        var current = ClusterReadWords(wordAddr, data.Length / 2);
        if (!current.SequenceEqual(expect))
            throw new InvalidOperationException($"clustervin: bytes changed since read (now {Hex(current)}); nothing written");
        int differ = Enumerable.Range(0, data.Length).Count(i => data[i] != current[i]);
        if (differ == 0) throw new InvalidOperationException("clustervin: nothing to change");
        if (differ > 5) throw new InvalidOperationException($"clustervin: {differ} bytes differ; a FG_NR change is at most 5");

        // Self-check the raw channel READ-ONLY before writing a single byte: a raw 06 03 read must echo
        // the EEPROM_LESEN bytes. If the TransmitData framing/comm-params are wrong, this fails here and
        // nothing is written.
        int echo = ClusterRawReadEchoesEeprom(wordAddr, data.Length / 2, out var rawResp, out _);
        if (echo < 0)
            throw new InvalidOperationException($"clustervin: raw-channel self-check failed — a raw read did not return the current bytes {Hex(current)} (got {Hex(rawResp)}); aborting before any write");

        // Maintain CHECKSUM @0x16E incrementally: new = old XOR old_bytes XOR new_bytes (XOR is linear, so
        // the delta is start-independent). Byte 0x16E is the high byte of word 0xB7; preserve 0x16F.
        var cks = ClusterReadWords(0xB7, 1);                     // [0x16E, 0x16F]
        byte delta = 0;
        for (int i = 0; i < data.Length; i++) delta ^= (byte)(current[i] ^ data[i]);
        byte newCksHi = (byte)(cks[0] ^ delta);

        // Write the FG_NR words, then the maintained checksum word. Read-back (EEPROM_LESEN) is the proof.
        ClusterRawWriteWords(wordAddr, data);
        ClusterRawWriteWords(0xB7, new[] { newCksHi, cks[1] });

        var after = ClusterReadWords(wordAddr, data.Length / 2);
        if (!after.SequenceEqual(data))
            throw new InvalidOperationException($"clustervin: verify failed; now reads {Hex(after)}, expected {Hex(data)} — if a checksum warning appears, restore the backup");
        var cksAfter = ClusterReadWords(0xB7, 1);
        if (cksAfter[0] != newCksHi)
            throw new InvalidOperationException($"clustervin: checksum verify failed; 0x16E reads {cksAfter[0]:X2}, expected {newCksHi:X2} — restore the backup");
        return new
        {
            wordAddr,
            before = Hex(current),
            after = Hex(after),
            checksum = new { addr = "0x16E", old = $"{cks[0]:X2}", @new = $"{newCksHi:X2}" }
        };
    }

    static void RefuseDenied(string sgbd, string job)
    {
        if (DeniedReason(job) is string why)
            throw new InvalidOperationException($"refused by the engine: {sgbd} {job} {why}");
    }

    static object RunJob(string sgbd, string job, string args, byte[] argBinary = null)
    {
        RefuseDenied(sgbd, job);
        if (argBinary != null && !BinaryArgJobs.Contains($"{sgbd}/{job}"))
            throw new InvalidOperationException($"binary argument refused: {sgbd} {job} is not on the engine's read-only buffer list");
        return Execute(sgbd, job, args, argBinary);
    }

    // Parse a hex string ("B8 29 F1", "b829f1") into bytes; null/empty → null (no binary arg).
    // Strict: anything but hex digits and space/:/- separators is an error, as is an odd digit
    // count, so a malformed string can never quietly become a different buffer.
    static byte[] HexBytes(string s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        if (!s.All(c => Uri.IsHexDigit(c) || c == ' ' || c == ':' || c == '-'))
            throw new ArgumentException("binary argument isn't hex");
        var hex = new string(s.Where(Uri.IsHexDigit).ToArray());
        if (hex.Length == 0 || hex.Length % 2 != 0) throw new ArgumentException("binary argument has an odd number of hex digits");
        var bytes = new byte[hex.Length / 2];
        for (int i = 0; i < bytes.Length; i++) bytes[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
        return bytes;
    }

    // One round trip for a whole dashboard refresh; a job that fails reports its error instead of failing the poll
    static object Poll(string sgbd, string[] jobs)
    {
        var result = new Dictionary<string, object>();
        foreach (var job in jobs)
            result[job] = Safe(() => { RefuseDenied(sgbd, job); return (object)Execute(sgbd, job).Skip(1).FirstOrDefault() ?? new Dictionary<string, object>(); });
        return result;
    }

    static string[] DetectGroups() =>
        "d_0000,d_0008,d_000d,d_0010,d_0011,d_0012,d_motor,d_0013,d_0014,d_0015,d_0016,d_0020,d_0021,d_0022,d_0024,d_0028,d_002c,d_002e,d_0030,d_0032,d_0035,d_0036,d_003b,d_0040,d_0044,d_0045,d_0050,d_0056,d_0057,d_0059,d_005a,d_005b,d_0060,d_0068,d_0069,d_006a,d_006c,d_0070,d_0071,d_0072,d_007f,d_0080,d_0086,d_0099,d_009a,d_009b,d_009c,d_009d,d_009e,d_00a0,d_00a4,d_00a6,d_00a7,d_00ac,d_00b0,d_00b9,d_00bb,d_00c0,d_00c8,d_00cd,d_00d0,d_00da,d_00e0,d_00e8,d_00ed,d_00f0,d_00f5,d_00ff"
            .Split(',');
}
