$ErrorActionPreference = "Stop"

$ResultsDir = "results/kubernetes"
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$ResultsFile = "$ResultsDir/run_$RunId.json"

Write-Host "============================================"
Write-Host "  KUBERNETES BENCHMARK - Run $RunId"
Write-Host "============================================"

Write-Host "[1/6] Cleaning previous state..."
kubectl delete namespace healthcare --ignore-not-found=true
Start-Sleep -Seconds 10

Write-Host "[2/6] Building images (no cache)..."
$BuildStart = Get-Date
docker build --no-cache -t healthcare-app:latest -f Dockerfile . | Tee-Object -FilePath "$ResultsDir/build_log_$RunId.txt"
docker build --no-cache -t healthcare-notification:latest -f Dockerfile.notification . | Tee-Object -Append -FilePath "$ResultsDir/build_log_$RunId.txt"
$BuildEnd = Get-Date
$BuildTimeMs = [math]::Round(($BuildEnd - $BuildStart).TotalMilliseconds)

Write-Host "[3/6] Applying manifest..."
$DeployStart = Get-Date
kubectl apply -f .\k8s-healthcare.yaml

Write-Host "[4/6] Waiting for pods..."
$TimeoutSec = 180
$Elapsed = 0
$Ready = $false

while ($Elapsed -lt $TimeoutSec) {
    $pods = kubectl -n healthcare get pods --no-headers 2>$null
    if ($pods -and (($pods | Select-String "Running").Count -ge 5)) {
        $Ready = $true
        break
    }
    Start-Sleep -Seconds 5
    $Elapsed += 5
    Write-Host "       ... waiting for pods ($Elapsed sec)"
}

Write-Host "[5/6] Waiting for /health endpoint..."
$HealthStart = Get-Date
$HealthTimeout = 180
$Elapsed = 0
$HealthReached = $false

while ($Elapsed -lt $HealthTimeout) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:30080/health" -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            $HealthReached = $true
            break
        }
    } catch {}
    Start-Sleep -Seconds 2
    $Elapsed += 2
    Write-Host "       ... waiting ($Elapsed sec)"
}

$HealthEnd = Get-Date
$HealthTimeMs = [math]::Round(($HealthEnd - $HealthStart).TotalMilliseconds)
$ApplyAndReadyTimeMs = [math]::Round(($HealthEnd - $DeployStart).TotalMilliseconds)
$GrandTotalMs = [math]::Round(($HealthEnd - $BuildStart).TotalMilliseconds)

$DeploySuccess = $false
$FailureReason = "none"

if ($HealthReached) {
    $DeploySuccess = $true
    Write-Host "       Health check PASSED"
} else {
    $FailureReason = "health_timeout_after_${HealthTimeout}s"
    Write-Host "       TIMEOUT - app never became healthy"
}

Write-Host "[6/6] Collecting metrics..."
Start-Sleep -Seconds 10

$ResourceSnapshot = @()
try {
    $tops = kubectl top pods -n healthcare --no-headers 2>$null
    if ($tops) {
        $ResourceSnapshot = $tops | ForEach-Object {
            $parts = ($_ -split "\s+")
            [PSCustomObject]@{
                pod = $parts[0]
                cpu = $parts[1]
                memory = $parts[2]
            }
        }
    }
} catch {}

$PodLines = kubectl -n healthcare get pods --no-headers 2>$null
$PodCount = if ($PodLines) { @($PodLines).Count } else { 0 }
$RunningPods = if ($PodLines) { (@($PodLines | Select-String "Running")).Count } else { 0 }

$ManifestLines = (Get-Content .\k8s-healthcare.yaml).Count
$DockerfileLines = (Get-Content Dockerfile).Count
$DockerfileNotifLines = if (Test-Path Dockerfile.notification) { (Get-Content Dockerfile.notification).Count } else { 0 }

$result = @{
    run_id = $RunId
    orchestrator = "kubernetes"
    timestamp = (Get-Date).ToString("o")
    deployment = @{
        success = $DeploySuccess
        failure_reason = $FailureReason
        total_time_ms = $GrandTotalMs
        build_time_ms = $BuildTimeMs
        apply_and_ready_time_ms = $ApplyAndReadyTimeMs
        health_ready_time_ms = $HealthTimeMs
    }
    pods = @{
        total = $PodCount
        running = $RunningPods
    }
    complexity = @{
        config_files_count = 2
        config_total_lines = $ManifestLines + $DockerfileLines + $DockerfileNotifLines
        manifest_lines = $ManifestLines
        dockerfile_lines = $DockerfileLines
        concepts_required = @("Namespace","Secret","Deployment","Service","NodePort","readinessProbe")
        cli_tools_required = @("docker","kubectl")
        cli_tools_count = 2
    }
    resources = $ResourceSnapshot
}

$result | ConvertTo-Json -Depth 6 | Set-Content $ResultsFile

Write-Host ""
Write-Host "RESULTS: $ResultsFile"
Write-Host "Success: $DeploySuccess"
Write-Host "Total time: $([math]::Round($GrandTotalMs / 1000, 2)) seconds"

Write-Host "Tearing down..."
kubectl delete namespace healthcare --ignore-not-found=true
Write-Host "Done."