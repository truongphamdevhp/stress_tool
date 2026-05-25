param(
    [ValidateRange(0, 256)]
    [int]$CpuThreads = 0,

    [ValidateRange(0, 1048576)]
    [int]$RamMB = 0,

    [ValidateRange(0, 8192)]
    [int]$DiskMBps = 0,

    [ValidateRange(1, 86400)]
    [int]$Seconds = 60,

    [ValidateSet("BelowNormal", "Normal", "AboveNormal")]
    [string]$Priority = "BelowNormal"
)

$ErrorActionPreference = "Stop"

function Get-LogicalCoreCount {
    try {
        $count = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        if ($count -gt 0) { return [int]$count }
    }
    catch {
    }

    return [Environment]::ProcessorCount
}

function Format-Bytes([double]$bytes) {
    if ($bytes -ge 1GB) { return "{0:n1} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:n0} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:n0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

$logicalCores = Get-LogicalCoreCount
if ($CpuThreads -eq 0) {
    $CpuThreads = $logicalCores
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$runId = [Guid]::NewGuid().ToString("n")
$workDir = Join-Path $root "stress-temp-$runId"
$stopFile = Join-Path $workDir "stop.signal"
$diskFile = Join-Path $workDir "disk-stress.bin"
$jobs = New-Object System.Collections.Generic.List[object]
$memoryBlocks = New-Object System.Collections.Generic.List[byte[]]
$allocatedRamBytes = 0
$started = Get-Date
$endsAt = $started.AddSeconds($Seconds)

New-Item -ItemType Directory -Force -Path $workDir | Out-Null

try {
    [Diagnostics.Process]::GetCurrentProcess().PriorityClass = $Priority

    Write-Host "Stress started"
    Write-Host "  CPU threads : $CpuThreads / $logicalCores logical cores"
    Write-Host "  RAM target  : $RamMB MB"
    Write-Host "  Disk target : $DiskMBps MB/s"
    Write-Host "  Duration    : $Seconds seconds"
    Write-Host "  Temp dir    : $workDir"
    Write-Host "Press Ctrl+C or close this terminal to stop early."
    Write-Host ""

    $cpuWorker = {
        param([string]$StopFilePath, [datetime]$EndTime)

        $x = 0.000001
        while ((Get-Date) -lt $EndTime -and -not (Test-Path -LiteralPath $StopFilePath)) {
            for ($i = 0; $i -lt 250000; $i++) {
                $x = [Math]::Sin($x + 1.000001) * [Math]::Cos($x + 0.999999)
                if ($x -eq 0) { $x = 0.000001 }
            }
        }
    }

    for ($i = 0; $i -lt $CpuThreads; $i++) {
        $jobs.Add((Start-Job -ScriptBlock $cpuWorker -ArgumentList $stopFile, $endsAt)) | Out-Null
    }

    if ($DiskMBps -gt 0) {
        $diskWorker = {
            param([string]$StopFilePath, [datetime]$EndTime, [string]$Path, [int]$TargetMBps)

            $chunkSize = 1MB
            $buffer = New-Object byte[] $chunkSize
            $random = [Random]::new()
            $random.NextBytes($buffer)

            $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
            try {
                while ((Get-Date) -lt $EndTime -and -not (Test-Path -LiteralPath $StopFilePath)) {
                    $windowStart = Get-Date
                    $written = 0

                    while ($written -lt $TargetMBps -and (Get-Date) -lt $EndTime -and -not (Test-Path -LiteralPath $StopFilePath)) {
                        $stream.Write($buffer, 0, $buffer.Length)
                        $written++

                        if ($stream.Position -ge 1024MB) {
                            $stream.Position = 0
                        }
                    }

                    $stream.Flush()
                    $elapsed = ((Get-Date) - $windowStart).TotalMilliseconds
                    if ($elapsed -lt 1000) {
                        Start-Sleep -Milliseconds ([int](1000 - $elapsed))
                    }
                }
            }
            finally {
                $stream.Dispose()
            }
        }

        $jobs.Add((Start-Job -ScriptBlock $diskWorker -ArgumentList $stopFile, $endsAt, $diskFile, $DiskMBps)) | Out-Null
    }

    if ($RamMB -gt 0) {
        $remaining = $RamMB
        while ($remaining -gt 0) {
            $blockMB = [Math]::Min(64, $remaining)
            $block = New-Object byte[] ($blockMB * 1MB)

            for ($offset = 0; $offset -lt $block.Length; $offset += 4096) {
                $block[$offset] = 1
            }

            $memoryBlocks.Add($block)
            $allocatedRamBytes += $block.Length
            $remaining -= $blockMB
        }
    }

    while ((Get-Date) -lt $endsAt) {
        Start-Sleep -Seconds 1

        $now = Get-Date
        $elapsedSeconds = [Math]::Floor(($now - $started).TotalSeconds)
        $remainingSeconds = [Math]::Max(0, [Math]::Ceiling(($endsAt - $now).TotalSeconds))
        $diskSize = if (Test-Path -LiteralPath $diskFile) { (Get-Item -LiteralPath $diskFile).Length } else { 0 }

        Write-Host ("[{0,4}s elapsed, {1,4}s left] RAM held: {2}; disk file: {3}; jobs: {4}" -f `
            $elapsedSeconds, `
            $remainingSeconds, `
            (Format-Bytes $allocatedRamBytes), `
            (Format-Bytes $diskSize), `
            ($jobs | Where-Object { $_.State -eq "Running" }).Count)
    }
}
finally {
    New-Item -ItemType File -Force -Path $stopFile | Out-Null

    foreach ($job in $jobs) {
        if ($job.State -eq "Running") {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
        }
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    $memoryBlocks.Clear()
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "Stress stopped and temp files cleaned."
}
