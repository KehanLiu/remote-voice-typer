Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[voice-input] $Message"
}

function Load-DotEnv {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) {
        return
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (!$line -or $line.StartsWith("#")) {
            return
        }
        $parts = $line.Split("=", 2)
        if ($parts.Length -ne 2) {
            return
        }
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if (![string]::IsNullOrWhiteSpace($key) -and [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key))) {
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

function Stop-ManagedProcesses {
    param([System.Collections.ArrayList]$Processes)
    foreach ($proc in $Processes) {
        if ($null -ne $proc -and !$proc.HasExited) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            } catch {
            }
        }
    }
}

function Test-LocalPortListening {
    param([int]$Port)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok = $async.AsyncWaitHandle.WaitOne(250)
        if (!$ok) {
            $client.Close()
            return $false
        }
        $client.EndConnect($async)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

function Get-BackendHealth {
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 2
    } catch {
        return $null
    }
}

function Get-ListeningPid {
    param([int]$Port)
    try {
        $lines = netstat -ano -p tcp | Select-String -Pattern "LISTENING"
        foreach ($line in $lines) {
            $text = ($line.ToString() -replace "\s+", " ").Trim()
            $parts = $text.Split(" ")
            if ($parts.Length -lt 5) {
                continue
            }
            $localAddress = $parts[1]
            $pidText = $parts[4]
            if ($localAddress -like "*:$Port") {
                $listenPid = 0
                if ([int]::TryParse($pidText, [ref]$listenPid)) {
                    return $listenPid
                }
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Restart-BackendProcess {
    param(
        [string]$WorkingDirectory,
        [string]$StdOutLog,
        [string]$StdErrLog
    )
    $backendPid = Get-ListeningPid -Port 8000
    if ($null -ne $backendPid) {
        Write-Info "Stopping existing backend on port 8000 (PID $backendPid)..."
        try {
            Stop-Process -Id $backendPid -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 600
        } catch {
            throw "Could not stop existing backend PID $backendPid. Stop it manually and rerun."
        }
    }

    Write-Info "Starting backend server with current environment..."
    $backend = Start-Process -FilePath "uv" -ArgumentList @("run", "uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000") -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $StdOutLog -RedirectStandardError $StdErrLog -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 900
    if ($backend.HasExited) {
        throw "backend exited early after restart. Check logs\backend.err.log"
    }
    return $backend
}

Push-Location $PSScriptRoot
try {
    Load-DotEnv -Path (Join-Path $PSScriptRoot ".env")

    if ([string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
        throw "OPENAI_API_KEY is not set. Put it in .env or current environment."
    }

    if ([string]::IsNullOrWhiteSpace($env:WINDOWS_AGENT_URL)) {
        $env:WINDOWS_AGENT_URL = "http://127.0.0.1:8765/type"
    }
    if ([string]::IsNullOrWhiteSpace($env:TRANSCRIBE_MODEL)) {
        $env:TRANSCRIBE_MODEL = "gpt-4o-mini-transcribe"
    }

    $ngrokBasicAuth = $env:NGROK_BASIC_AUTH
    if ([string]::IsNullOrWhiteSpace($ngrokBasicAuth)) {
        $user = $env:NGROK_BASIC_AUTH_USER
        $pass = $env:NGROK_BASIC_AUTH_PASS
        if (![string]::IsNullOrWhiteSpace($user) -and ![string]::IsNullOrWhiteSpace($pass)) {
            $ngrokBasicAuth = "$user`:$pass"
        }
    }

    $null = Get-Command uv -ErrorAction Stop
    $null = Get-Command ngrok -ErrorAction Stop

    $logDir = Join-Path $PSScriptRoot "logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $procs = [System.Collections.ArrayList]::new()

    $agentOutLog = Join-Path $logDir "agent.out.log"
    $agentErrLog = Join-Path $logDir "agent.err.log"
    $backendOutLog = Join-Path $logDir "backend.out.log"
    $backendErrLog = Join-Path $logDir "backend.err.log"
    $ngrokOutLog = Join-Path $logDir "ngrok.out.log"
    $ngrokErrLog = Join-Path $logDir "ngrok.err.log"

    $agent = $null
    $backend = $null
    $ngrok = $null

    if (Test-LocalPortListening -Port 8765) {
        Write-Info "Agent already running on 127.0.0.1:8765. Reusing existing process."
    } else {
        Write-Info "Starting typing agent..."
        $agent = Start-Process -FilePath "uv" -ArgumentList @("run", "python", "agent.py") -WorkingDirectory $PSScriptRoot -RedirectStandardOutput $agentOutLog -RedirectStandardError $agentErrLog -WindowStyle Hidden -PassThru
        [void]$procs.Add($agent)

        Start-Sleep -Milliseconds 600
        if ($agent.HasExited) {
            throw "agent.py exited early. Check logs\agent.err.log"
        }
    }

    if (Test-LocalPortListening -Port 8000) {
        Write-Info "Backend already running on 0.0.0.0:8000 (or localhost:8000). Reusing existing process."
    } else {
        Write-Info "Starting backend server..."
        $backend = Start-Process -FilePath "uv" -ArgumentList @("run", "uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000") -WorkingDirectory $PSScriptRoot -RedirectStandardOutput $backendOutLog -RedirectStandardError $backendErrLog -WindowStyle Hidden -PassThru
        [void]$procs.Add($backend)

        Start-Sleep -Milliseconds 900
        if ($backend.HasExited) {
            throw "backend exited early. Check logs\backend.err.log"
        }
    }

    $health = Get-BackendHealth
    if ($null -eq $health) {
        throw "Backend health check failed on http://127.0.0.1:8000/health"
    }
    $expectedToken = ![string]::IsNullOrWhiteSpace($env:VOICE_INPUT_TOKEN)
    $actualToken = [bool]$health.token_required
    if ($expectedToken -and -not $actualToken) {
        Write-Info "Detected old backend without token enforcement. Auto-restarting backend..."
        $backend = Restart-BackendProcess -WorkingDirectory $PSScriptRoot -StdOutLog $backendOutLog -StdErrLog $backendErrLog
        [void]$procs.Add($backend)
        $health = Get-BackendHealth
        if ($null -eq $health -or -not [bool]$health.token_required) {
            throw "Backend restart completed, but token_required is still false. Check .env and logs\backend.err.log"
        }
        Write-Info "Backend now reports token_required=true."
    }

    $ngrokAlreadyRunning = Test-LocalPortListening -Port 4040
    if ($ngrokAlreadyRunning) {
        Write-Info "ngrok API already running on 127.0.0.1:4040. Reusing existing tunnel process."
    } else {
        Write-Info "Starting ngrok tunnel..."
    }
    $ngrokArgs = @("http", "8000", "--region=eu")
    if (![string]::IsNullOrWhiteSpace($ngrokBasicAuth)) {
        Write-Info "Using ngrok basic auth."
        $ngrokArgs += "--basic-auth=$ngrokBasicAuth"
    } else {
        Write-Info "ngrok basic auth is OFF. Set NGROK_BASIC_AUTH (or USER/PASS) to protect the public URL."
    }
    if (!$ngrokAlreadyRunning) {
        $ngrok = Start-Process -FilePath "ngrok" -ArgumentList $ngrokArgs -WorkingDirectory $PSScriptRoot -RedirectStandardOutput $ngrokOutLog -RedirectStandardError $ngrokErrLog -WindowStyle Hidden -PassThru
        [void]$procs.Add($ngrok)

        if ($ngrok.HasExited) {
            throw "ngrok exited early. Check logs\ngrok.err.log"
        }
    }

    Write-Info "Waiting for ngrok public URL..."
    $publicUrl = $null
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 750
        if ($null -ne $ngrok -and $ngrok.HasExited) {
            throw "ngrok stopped unexpectedly. Check logs\ngrok.err.log"
        }

        try {
            $res = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
            $httpsTunnel = $res.tunnels | Where-Object { $_.public_url -like "https://*" } | Select-Object -First 1
            if ($httpsTunnel) {
                $publicUrl = $httpsTunnel.public_url
                break
            }
        } catch {
        }
    }

    if ([string]::IsNullOrWhiteSpace($publicUrl)) {
        throw "Could not read ngrok URL from local API. Check logs\ngrok.err.log"
    }

    $urlFile = Join-Path $PSScriptRoot "ngrok_url.txt"
    Set-Content -LiteralPath $urlFile -Value $publicUrl -NoNewline

    try {
        Set-Clipboard -Value $publicUrl
        Write-Info "Public URL copied to clipboard."
    } catch {
    }

    Write-Host ""
    Write-Host "============================================"
    Write-Host "Voice Input is running."
    Write-Host "Open this URL on iPhone:"
    Write-Host $publicUrl
    Write-Host "Saved to: $urlFile"
    Write-Host "Logs: $logDir"
    Write-Host "Press Ctrl+C to stop services started by this launcher."
    Write-Host "============================================"
    Write-Host ""

    while ($true) {
        Start-Sleep -Seconds 1
        if ($null -ne $agent -and $agent.HasExited) { throw "agent.py exited. Check logs\agent.err.log" }
        if ($null -ne $backend -and $backend.HasExited) { throw "backend exited. Check logs\backend.err.log" }
        if ($null -ne $ngrok -and $ngrok.HasExited) { throw "ngrok exited. Check logs\ngrok.err.log" }
    }
} catch {
    Write-Error $_
} finally {
    if ($null -ne $procs) {
        Stop-ManagedProcesses -Processes $procs
    }
    Pop-Location
}
