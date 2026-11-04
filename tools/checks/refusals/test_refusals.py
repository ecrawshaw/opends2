#!/usr/bin/env python3
import json
import os
import subprocess
import sys

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
    engine_bin = os.path.join(repo_root, "Engine/bin/Debug/net10.0/opends2-engine")
    if not os.path.isfile(engine_bin):
        sys.stderr.write(f"Engine binary not found at {engine_bin}. Run dotnet build first.\n")
        sys.exit(1)

    proc = subprocess.Popen(
        [engine_bin],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    failed = 0
    passed = 0

    def send_cmd(cmd_dict):
        line = json.dumps(cmd_dict) + "\n"
        proc.stdin.write(line)
        proc.stdin.flush()
        resp_line = proc.stdout.readline()
        if not resp_line:
            raise RuntimeError("Engine closed stdout unexpectedly")
        return json.loads(resp_line)

    # 1. generic job GWSZ_OFFSET_SCHREIBEN must be refused by the engine
    r1 = send_cmd({"id": 1, "cmd": "job", "sgbd": "kombi46r", "job": "GWSZ_OFFSET_SCHREIBEN", "args": ""})
    if not r1.get("ok") and "refused by the engine" in r1.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: generic job GWSZ_OFFSET_SCHREIBEN was not refused: {r1}")
        failed += 1

    # 2. regression: GWSZ_RESET
    r2 = send_cmd({"id": 2, "cmd": "job", "sgbd": "kombi46r", "job": "GWSZ_RESET", "args": ""})
    if not r2.get("ok") and "refused by the engine" in r2.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: generic job GWSZ_RESET was not refused: {r2}")
        failed += 1

    # 3. regression: C_FA_LOESCHEN
    r3 = send_cmd({"id": 3, "cmd": "job", "sgbd": "kombi46r", "job": "C_FA_LOESCHEN", "args": ""})
    if not r3.get("ok") and "refused by the engine" in r3.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: generic job C_FA_LOESCHEN was not refused: {r3}")
        failed += 1

    # 4. regression: C_CHECKSUM
    r4 = send_cmd({"id": 4, "cmd": "job", "sgbd": "kombi46r", "job": "C_CHECKSUM", "args": ""})
    if not r4.get("ok") and "refused by the engine" in r4.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: generic job C_CHECKSUM was not refused: {r4}")
        failed += 1

    # 5. regression: C_C_AUFTRAG
    r5 = send_cmd({"id": 5, "cmd": "job", "sgbd": "zke5", "job": "C_C_AUFTRAG", "args": ""})
    if not r5.get("ok") and "refused by the engine" in r5.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: generic job C_C_AUFTRAG was not refused: {r5}")
        failed += 1

    # 6. there is no odometer write command: gwsoffset must be an unknown command
    r6 = send_cmd({"id": 6, "cmd": "gwsoffset", "sgbd": "kombi46r", "targetKm": 150000})
    if not r6.get("ok") and "unknown command" in r6.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: gwsoffset is not an unknown command: {r6}")
        failed += 1

    # 6b. dedicated clustercode command must refuse with the disabled message (gated off)
    r6b = send_cmd({"id": 61, "cmd": "clustercode", "sgbd": "kombi46r",
                    "data": "01 02 03", "expect": "01 02 03"})
    if not r6b.get("ok") and "cluster coding write is disabled until the cluster checksum algorithm is verified" in r6b.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: clustercode did not refuse with disabled message: {r6b}")
        failed += 1

    # 6b2. clustervin ALWAYS refuses the odometer ring region (critical safety guard, even when enabled)
    r6b2 = send_cmd({"id": 63, "cmd": "clustervin", "sgbd": "kombi46r", "wordAddr": 0x05,
                     "data": "00 00", "expect": "00 00"})
    if not r6b2.get("ok") and "odometer ring" in r6b2.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: clustervin did not refuse the odometer ring: {r6b2}")
        failed += 1

    # 6b3. clustervin refuses a non-cluster module
    r6b3 = send_cmd({"id": 64, "cmd": "clustervin", "sgbd": "zke5", "wordAddr": 0x3D,
                     "data": "00 00", "expect": "00 00"})
    if not r6b3.get("ok") and "only the cluster module" in r6b3.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: clustervin did not refuse a non-cluster sgbd: {r6b3}")
        failed += 1

    # 6b4. clustervin refuses a change outside the FG_NR checksum region (bytes 0x5A-0xFF = words 0x2D-0x7F)
    r6b4 = send_cmd({"id": 65, "cmd": "clustervin", "sgbd": "kombi46r", "wordAddr": 0x100,
                     "data": "00 00", "expect": "00 00"})
    if not r6b4.get("ok") and "outside the FG_NR checksum region" in r6b4.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: clustervin did not refuse a change outside the checksum region: {r6b4}")
        failed += 1

    # 6b5. clusterrawprobe (read-only) refuses a non-cluster module
    r6b5 = send_cmd({"id": 66, "cmd": "clusterrawprobe", "sgbd": "zke5", "wordAddr": 0x3D, "words": 1})
    if not r6b5.get("ok") and "only the cluster module" in r6b5.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: clusterrawprobe did not refuse a non-cluster sgbd: {r6b5}")
        failed += 1

    # 6c. cluster coding writes via the generic job stay refused (C_S_AUFTRAG, C_S_SCHREIBEN, C_FA_AUFTRAG)
    for job in ["C_S_AUFTRAG", "C_S_SCHREIBEN", "C_FA_AUFTRAG"]:
        r = send_cmd({"id": 62, "cmd": "job", "sgbd": "kombi46r", "job": job, "args": ""})
        if not r.get("ok") and "refused by the engine" in r.get("error", ""):
            passed += 1
        else:
            print(f"FAIL: generic job {job} was not refused: {r}")
            failed += 1

    # 7. read job GWSZ_OFFSET_LESEN must pass the refusal gate (not refused by the engine)
    r7 = send_cmd({"id": 7, "cmd": "job", "sgbd": "kombi46r", "job": "GWSZ_OFFSET_LESEN", "args": ""})
    if "refused by the engine" not in r7.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: read job GWSZ_OFFSET_LESEN was unexpectedly refused: {r7}")
        failed += 1

    # 8. poll refusal test
    r8 = send_cmd({"id": 8, "cmd": "poll", "sgbd": "kombi46r", "jobs": ["GWSZ_OFFSET_SCHREIBEN", "GWSZ_RESET"]})
    poll_data = r8.get("data", {})
    s1 = str(poll_data.get("GWSZ_OFFSET_SCHREIBEN", ""))
    s2 = str(poll_data.get("GWSZ_RESET", ""))
    if "refused by the engine" in s1 and "refused by the engine" in s2:
        passed += 1
    else:
        print(f"FAIL: poll did not refuse jobs: {r8}")
        failed += 1

    # 9. DSC/steering calibration routines must PASS the engine gate (not refused)
    for job in ["LENKWINKEL_DSC_ABGLEICHEN", "QUERBESCHLEUNIGUNG_DSC_ABGLEICHEN",
                "DRUCKSENSOR_DSC_ABGLEICHEN", "ABGLEICH_SCHREIBEN"]:
        r = send_cmd({"id": 90, "cmd": "job", "sgbd": "dsc_mk60", "job": job, "args": ""})
        if "refused by the engine" not in r.get("error", ""):
            passed += 1
        else:
            print(f"FAIL: calibration job {job} was refused by the engine: {r}")
            failed += 1

    # 10. a non-calibration ABGLEICH job (EWS/engine alignment) stays refused
    r = send_cmd({"id": 91, "cmd": "job", "sgbd": "dsc_mk60", "job": "SYNC_ABGLEICH", "args": ""})
    if not r.get("ok") and "refused by the engine" in r.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: SYNC_ABGLEICH was not refused: {r}")
        failed += 1

    # 11. DSC coding write via the generic job stays refused
    r = send_cmd({"id": 92, "cmd": "job", "sgbd": "dsc_mk60", "job": "COD_SCHREIBEN", "args": "00"})
    if not r.get("ok") and "refused by the engine" in r.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: COD_SCHREIBEN via generic job was not refused: {r}")
        failed += 1

    # 12. dsccodewrite only accepts the DSC module
    r = send_cmd({"id": 93, "cmd": "dsccodewrite", "sgbd": "kombi46r",
                  "data": "00 00 00 00 00 00 00 00 00 00 00 00 00 00",
                  "expect": "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"})
    if not r.get("ok") and "only the ABS/DSC module" in r.get("error", ""):
        passed += 1
    else:
        print(f"FAIL: dsccodewrite accepted a non-DSC sgbd: {r}")
        failed += 1

    send_cmd({"cmd": "quit"})
    proc.wait(timeout=3)

    # 9. MCPTools Swift gating verification
    mcptools_path = os.path.join(repo_root, "App/Sources/OpenDS2/MCPTools.swift")
    with open(mcptools_path, "r", encoding="utf-8") as f:
        mcptools_content = f.read()

    # Verify GWSZ_OFFSET_SCHREIBEN is not in approvableJobs
    if '"GWSZ_OFFSET_SCHREIBEN"' in mcptools_content:
        print("FAIL: GWSZ_OFFSET_SCHREIBEN still present in MCPTools.swift")
        failed += 1
    else:
        passed += 1

    # MCP policy: coding never runs directly from run_job; it goes through the user-approved request.
    import re as _re
    run_job = mcptools_content[mcptools_content.index("private static func runJob("):mcptools_content.index("private static func requestCodingChange(")]
    for desc, ok in [
        ("runJob checks codingJobReason before running anything", "codingJobReason(job)" in run_job),
        ("codingJobReason blocks C_* / AUFTRAG / COD*SCHREIBEN", all(t in mcptools_content for t in ['j.hasPrefix("C_")', 'j.contains("AUFTRAG")', 'j.contains("COD") && j.contains("SCHREIBEN")'])),
        ("request_coding_change waits for the user's decision", "withCheckedContinuation" in mcptools_content and "confirmIsDefault: staged.confirmIsDefault" in mcptools_content),
        ("MCP never calls a write command itself", not _re.search(r'engineSend\("(codewrite|dsccodewrite|clustervin|clustercode)"', mcptools_content)),
    ]:
        if ok:
            passed += 1
        else:
            print(f"FAIL: MCP policy: {desc}")
            failed += 1

    print(f"refusal tests: {passed} checks passed | failed: {failed}")
    if failed > 0:
        sys.exit(1)

if __name__ == "__main__":
    main()
