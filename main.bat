@echo off
REM Optimizer v0.1 (Basic) - Read-only diagnostics and opt-in backups
title Optimizer v0.1 (Basic) - Diagnostics

echo ==================================================================
echo Optimizer v0.1 (Basic) - System Diagnostics (read-only by default)
echo ==================================================================

REM Check for administrative privileges
net session >nul 2>&1
if %errorlevel%==0 (
	set IS_ADMIN=1
) else (
	set IS_ADMIN=0
)
echo Administrative privileges: %IS_ADMIN%

echo.
echo Collecting core system information (this is read-only)...
echo.

echo --- System Summary ---
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" /C:"System Boot Time" /C:"System Manufacturer" /C:"System Model"

echo.
echo --- Memory Summary ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $os=Get-CimInstance Win32_OperatingSystem; $totalMB=[math]::Round($os.TotalVisibleMemorySize/1024,1); $freeMB=[math]::Round($os.FreePhysicalMemory/1024,1); $usedPct=[math]::Round((1-($os.FreePhysicalMemory/$os.TotalVisibleMemorySize))*100,1); Write-Host \"Total RAM (MB): $totalMB  Free (MB): $freeMB  Used%: $usedPct\" } catch { Write-Host 'Memory info unavailable' }"

echo.
echo --- Disk Summary (local fixed drives) ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID,@{N='FreeGB';E={[math]::Round($_.FreeSpace/1GB,1)}},@{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}},@{N='FreePct';E={[math]::Round(($_.FreeSpace/$_.Size)*100,1)}} | Format-Table -AutoSize"

echo.
echo --- Top Processes by Memory (top 10) ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process | Sort-Object -Descending WS | Select-Object -First 10 @{L='Name';E={$_.Name}},Id,@{L='MemoryMB';E={[math]::Round($_.WS/1MB,1)}},@{L='CPU(s)';E={if ($_.CPU) {[math]::Round($_.CPU,1)} else {''}}} | Format-Table -AutoSize"

echo.
echo --- Services (summary) ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Service | Select-Object Name,State,StartMode | Sort-Object StartMode,Name | Format-Table -AutoSize"

echo.
echo --- Startup Commands ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Get-CimInstance Win32_StartupCommand | Select-Object Name,Command,User | Format-Table -AutoSize } catch { Write-Host 'Startup info unavailable' }"

echo.
echo --- Network Interfaces ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter -Physical | Select-Object Name,Status,LinkSpeed | Format-Table -AutoSize"

echo.
echo --- Automated Analysis & Recommendations ---
echo (conservative, evidence-based suggestions; read-only by default)

powershell -NoProfile -ExecutionPolicy Bypass -Command "
	# Advanced heuristic engine: gathers multiple signals, assigns weighted scores, and emits prioritized recommendations.
	$score = 0; $details = @();

	# CPU usage
	try {
		$cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
		$cpu = [math]::Round($cpu,1)
		if ($cpu -ge 85) { $score += 25; $details += [pscustomobject]@{Category='CPU'; Value=$cpu; Msg='Sustained high CPU usage detected (>85%).'; Impact='High'; Recommendation='Investigate scheduled tasks, antivirus scans, or runaway processes. Consider tuning services.'} }
		elseif ($cpu -ge 60) { $score += 10; $details += [pscustomobject]@{Category='CPU'; Value=$cpu; Msg='Elevated CPU usage (>60%).'; Impact='Medium'; Recommendation='Monitor for processes with growing CPU over time.'} }
	} catch {}

	# Memory
	try {
		$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
		if ($os) {
			$usedPct = [math]::Round((1-($os.FreePhysicalMemory/$os.TotalVisibleMemorySize))*100,1)
			if ($usedPct -ge 85) { $score += 25; $details += [pscustomobject]@{Category='Memory'; Value=$usedPct; Msg='Very high memory usage (>85%).'; Impact='High'; Recommendation='Identify top memory processes and consider increasing physical memory.'} }
			elseif ($usedPct -ge 65) { $score += 10; $details += [pscustomobject]@{Category='Memory'; Value=$usedPct; Msg='Elevated memory usage (>65%).'; Impact='Medium'; Recommendation='Monitor for growth; check for memory leaks.'} }
		}
	} catch {}

	# Disk space & health
	try {
		$drives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue
		foreach ($d in $drives) {
			if ($d.Size -and ($d.FreeSpace/$d.Size)*100 -lt 15) { $score += 15; $details += [pscustomobject]@{Category='Disk'; Device=$d.DeviceID; Value=[math]::Round((($d.FreeSpace/$d.Size)*100),1); Msg='Low free space (<15%).'; Impact='Medium'; Recommendation='Clean up files, analyze large folders, consider expanding storage.'} }
		}
		$phys = Get-PhysicalDisk -ErrorAction SilentlyContinue
		if ($phys) { foreach ($p in $phys) { if ($p.HealthStatus -ne 'Healthy') { $score += 20; $details += [pscustomobject]@{Category='DiskHealth'; Device=$p.FriendlyName; Value=$p.HealthStatus; Msg='Physical disk reports degraded health'; Impact='High'; Recommendation='Investigate disk SMART details and prepare backup/replace drive.'} } } }
	} catch {}

	# Pagefile
	try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue; if ($cs -and $cs.AutomaticManagedPagefile -eq $false) { $score += 5; $details += [pscustomobject]@{Category='Pagefile'; Value='Manual'; Msg='Pagefile is not automatically managed.'; Impact='Low'; Recommendation='Consider enabling automatic pagefile management unless workload requires custom settings.'} } } catch {}

	# Services and scheduled tasks
	try {
		$interesting = @('SysMain','WSearch','DiagTrack')
		foreach ($name in $interesting) {
			$s = Get-Service -Name $name -ErrorAction SilentlyContinue
			if ($s -and $s.Status -eq 'Running') { $score += 5; $details += [pscustomobject]@{Category='Service'; Name=$name; Value=$s.Status; Msg="Service $name is running"; Impact='Low/Medium'; Recommendation='Review service purpose and adjust startup type if unnecessary.'} }
		}
		$stasks = Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' -or $_.State -eq 'Running' } -ErrorAction SilentlyContinue
		if ($stasks.Count -gt 20) { $score += 5; $details += [pscustomobject]@{Category='ScheduledTasks'; Value=$stasks.Count; Msg='Many scheduled tasks are active.'; Impact='Low'; Recommendation='Review scheduled tasks for unnecessary frequent jobs.'} }
	} catch {}

	# Recent critical errors (system & application)
	try {
		$now = Get-Date; $start = $now.AddDays(-7)
		$crit = Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=$start} -ErrorAction SilentlyContinue
		if ($crit.Count -gt 0) { $score += 20; $details += [pscustomobject]@{Category='Events'; Value=$crit.Count; Msg='Recent critical system errors found in last 7 days.'; Impact='High'; Recommendation='Inspect event log entries and address recurring errors.'} }
		$appcrit = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2; StartTime=$start} -ErrorAction SilentlyContinue
		if ($appcrit.Count -gt 0) { $score += 10; $details += [pscustomobject]@{Category='Events'; Value=$appcrit.Count; Msg='Recent critical application errors.'; Impact='Medium'; Recommendation='Review application errors and update or reconfigure offending apps.'} }
	} catch {}

	# Drivers with issues
	try { $pv = Get-PnpDevice -Status Error -ErrorAction SilentlyContinue; if ($pv.Count -gt 0) { $score += 15; $details += [pscustomobject]@{Category='Drivers'; Value=$pv.Count; Msg='Devices with driver issues detected.'; Impact='High'; Recommendation='Update or reinstall drivers for devices reporting errors.'} } } catch {}

	# Top resource consumers (summary)
	try { $topCPU = Get-Process | Sort-Object -Descending CPU | Select-Object -First 3 | Select-Object Name,Id,@{N='CPU';E={[math]::Round($_.CPU,1)}},@{N='MemoryMB';E={[math]::Round($_.WS/1MB,1)}} -ErrorAction SilentlyContinue; $topMem = Get-Process | Sort-Object -Descending WS | Select-Object -First 3 | Select-Object Name,Id,@{N='MemoryMB';E={[math]::Round($_.WS/1MB,1)}} -ErrorAction SilentlyContinue } catch {}

	# Normalize score and derive severity
	if ($score -gt 100) { $score = 100 }
	$severity = if ($score -ge 70) { 'High' } elseif ($score -ge 40) { 'Medium' } else { 'Low' }

	# Output summary with prioritized recommendations
	Write-Host '================== Optimization Summary =================='
	Write-Host "Optimization Score (0-100): $score  Severity: $severity"
	Write-Host '------------------------------------------------------------'
	foreach ($d in $details | Sort-Object @{Expression={$_.Impact};Descending=$true}) {
		Write-Host 'Title:' ($d.Category + (if ($d.Name) {"/$($d.Name)"} else {''}))
		if ($d.Value) { Write-Host 'Value: ' $d.Value }
		Write-Host 'Issue: ' $d.Msg
		Write-Host 'Impact: ' $d.Impact
		Write-Host 'Suggested action: ' $d.Recommendation
		Write-Host '---'
	}

	Write-Host 'Top CPU processes:'
	if ($topCPU) { $topCPU | Format-Table -AutoSize }
	Write-Host 'Top Memory processes:'
	if ($topMem) { $topMem | Format-Table -AutoSize }

	# Provide export option via batch caller
	exit 0
"

echo.
set /p SHOW_OPT=Would you like to export the optimization summary to a file? [y/N]: 
if /I "%SHOW_OPT%"=="y" (
	set TIMESTAMP=%DATE:~10,4%-%DATE:~4,2%-%DATE:~7,2%_%TIME:~0,2%-%TIME:~3,2%-%TIME:~6,2%
	set TIMESTAMP=%TIMESTAMP: =0%
	set OUTFILE=%~dp0backups\optimization_summary_%TIMESTAMP%.txt
	powershell -NoProfile -ExecutionPolicy Bypass -Command "
		$score = 0; $details = @();
		try { $cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue; $cpu = [math]::Round($cpu,1); if ($cpu -ge 85) { $score += 25; $details += 'High CPU usage: ' + $cpu } elseif ($cpu -ge 60) { $score += 10; $details += 'Elevated CPU: ' + $cpu } } catch {}
		try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue; if ($os) { $usedPct = [math]::Round((1-($os.FreePhysicalMemory/$os.TotalVisibleMemorySize))*100,1); if ($usedPct -ge 85) { $score += 25; $details += 'Very high memory usage: ' + $usedPct } elseif ($usedPct -ge 65) { $score += 10; $details += 'Elevated memory usage: ' + $usedPct } } } catch {}
		try { $drives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue; foreach ($d in $drives) { if ($d.Size -and ($d.FreeSpace/$d.Size)*100 -lt 15) { $score += 15; $details += 'Low disk space: ' + $d.DeviceID } } } catch {}
		try { $pv = Get-PnpDevice -Status Error -ErrorAction SilentlyContinue; if ($pv.Count -gt 0) { $score += 15; $details += ('Devices with driver errors: ' + $pv.Count) } } catch {}
		if ($score -gt 100) { $score = 100 }
		$severity = if ($score -ge 70) { 'High' } elseif ($score -ge 40) { 'Medium' } else { 'Low' }
		$out = @(); $out += 'Optimization Score: ' + $score; $out += 'Severity: ' + $severity; $out += 'Details:'; $out += $details; $out | Out-File -FilePath '%OUTFILE%' -Encoding utf8; Write-Host "Exported optimization summary to %OUTFILE%";" 
	echo Exported optimization summary to %OUTFILE%.
)

echo.
echo Completed. Exiting Optimizer v0.1 (Basic).
endlocal
exit /b 0
