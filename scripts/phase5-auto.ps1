$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path ".\results\phase5" | Out-Null

$result = @{
    timestamp = (Get-Date).ToString("o")
    failure_tests = @{}
    maintenance_tests = @{}
}

Write-Host "======================================"
Write-Host "PHASE 5 AUTOMATED FAILURE TESTS"
Write-Host "======================================"

# ---------- DOCKER REDIS FAILURE ----------
docker compose -f .\docker-compose.benchmark.yml up -d | Out-Null
Start-Sleep 20

docker compose -f .\docker-compose.benchmark.yml stop redis | Out-Null
Start-Sleep 15

$dockerHealthFail = $false
try {
    Invoke-WebRequest -Uri http://localhost:8000/health -UseBasicParsing -TimeoutSec 5 | Out-Null
} catch {
    $dockerHealthFail = $true
}

docker compose -f .\docker-compose.benchmark.yml start redis | Out-Null
Start-Sleep 15

$dockerHealthRecovered = $true
try {
    Invoke-WebRequest -Uri http://localhost:8000/health -UseBasicParsing -TimeoutSec 5 | Out-Null
} catch {
    $dockerHealthRecovered = $false
}

$result.failure_tests.docker_kill_redis = @{
    app_failed = $dockerHealthFail
    auto_recovered = $dockerHealthRecovered
}

# ---------- KUBERNETES REDIS FAILURE ----------
kubectl apply -f .\k8s-healthcare.yaml | Out-Null
Start-Sleep 25

kubectl delete pod -l app=redis -n healthcare | Out-Null
Start-Sleep 25

$k8sRedisRecovered = $false
$pods = kubectl get pods -n healthcare -l app=redis --no-headers

if ($pods) { $k8sRedisRecovered = $true }

$result.failure_tests.k8s_kill_redis = @{
    auto_recovered = $k8sRedisRecovered
}

# ---------- DOCKER APP FAILURE ----------
docker compose -f .\docker-compose.benchmark.yml kill app | Out-Null
Start-Sleep 10

$appRunning = docker compose -f .\docker-compose.benchmark.yml ps | Select-String "app"

$result.failure_tests.docker_kill_app = @{
    auto_restarted = ($appRunning -ne $null)
}

# ---------- KUBERNETES APP FAILURE ----------
kubectl delete pod -l app=app -n healthcare | Out-Null
Start-Sleep 20

$pods = kubectl get pods -n healthcare -l app=app --no-headers

$result.failure_tests.k8s_kill_app = @{
    auto_restarted = ($pods -ne $null)
}

Write-Host "Failure tests complete."

Write-Host ""
Write-Host "======================================"
Write-Host "MAINTENANCE TESTS"
Write-Host "======================================"

# ---------- DOCKER SCALE TEST ----------
docker compose -f .\docker-compose.benchmark.yml up -d | Out-Null
Start-Sleep 10

$start = Get-Date
docker compose -f .\docker-compose.benchmark.yml up -d --scale notification=3 | Out-Null
Start-Sleep 5
$end = Get-Date

$dockerScaleTime = ($end - $start).TotalSeconds

$result.maintenance_tests.docker_scale = @{
    service = "notification"
    replicas = 3
    time_sec = $dockerScaleTime
}

# ---------- K8S SCALE TEST ----------
kubectl scale deployment app --replicas=3 -n healthcare | Out-Null

$start = Get-Date
Start-Sleep 8
$end = Get-Date

$k8sScaleTime = ($end - $start).TotalSeconds

$result.maintenance_tests.k8s_scale = @{
    deployment = "app"
    replicas = 3
    time_sec = $k8sScaleTime
}

kubectl scale deployment app --replicas=1 -n healthcare | Out-Null

# ---------- DOCKER REDEPLOY ----------
$start = Get-Date
docker compose -f .\docker-compose.benchmark.yml down -v | Out-Null
docker compose -f .\docker-compose.benchmark.yml up -d | Out-Null
Start-Sleep 10
$end = Get-Date

$result.maintenance_tests.docker_redeploy = @{
    time_sec = ($end - $start).TotalSeconds
}

# ---------- K8S REDEPLOY ----------
$start = Get-Date
kubectl delete namespace healthcare --ignore-not-found=true | Out-Null
Start-Sleep 8
kubectl apply -f .\k8s-healthcare.yaml | Out-Null
Start-Sleep 15
$end = Get-Date

$result.maintenance_tests.k8s_redeploy = @{
    time_sec = ($end - $start).TotalSeconds
}

$result | ConvertTo-Json -Depth 6 | Set-Content ".\results\phase5\phase5-manual-results.json"

Write-Host ""
Write-Host "======================================"
Write-Host "PHASE 5 COMPLETE"
Write-Host "Results saved to:"
Write-Host "results\phase5\phase5-manual-results.json"