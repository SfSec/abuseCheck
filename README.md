# abuseCheck
abuseCheck queries the AbuseIPDB API for each supplied IP address and returns
its abuse confidence score, report count, country, and ISP. It accepts single
IPs, comma-separated lists, or pipeline input, and can output results to the
console or export them to CSV for reporting and triage.

**Set the variable (choose one):**

User-level, persistent (recommended — survives reboots):

powershell

```powershell
[System.Environment]::SetEnvironmentVariable("ABUSEIPDB_KEY", "your_key_here", "User")
```

Or via setx (also persistent):

cmd

```cmd
setx ABUSEIPDB_KEY "your_key_here"
```

**Then open a new terminal and run the script and it should work.**
