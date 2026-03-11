$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path ".\results\phase5" | Out-Null
$manualFile = ".\results\phase5\manual-tests.json"

$result = @{
    timestamp = (Get-Date).ToString("o")
    failure_tests = @()
    maintenance_tests = @()
}

function Ask-YesNo($prompt) {
    do {
        $ans = Read-Host "$prompt (y/n)"
    } while ($ans -notin @("y","n"))
    return ($ans -eq "y")
}

function Ask-Number($prompt) {
    do {
        $ans = Read-Host $prompt
    } while (-not ($ans -match '^\d+(\.\d+)?$'))
    return [double]$ans
}

Write-Host "============================================"
Write-Host " PHASE 5 MANUAL TESTS"
Write-Host "============================================"

# Failure Test 1 - Docker kill redis
Write-Host ""
Write-Host "FAILURE TEST 1 - Docker: stop redis"
docker compose -f .\docker-compose.benchmark.yml up -d | Out-Null
Start-Sleep -Seconds 20
docker compose -f .\docker-compose.benchmark.yml stop redis | Out-Null
Start-Sleep -Seconds 15

$dockerRedisFailed = Ask-YesNo "After stopping redis, did Docker app become unhealthy/fail?"
docker compose -f .\docker-compose.benchmark.yml start redis | Out-Null
Start-Sleep -Seconds 15
$dockerRedisRecovered = Ask-YesNo "After restarting redis, did Docker recover automatically?"

$result.failure_tests += @{
    scenario = "kill_redis"
    docker = @{
        app_failed = $dockerRedisFailed
        auto_recovered = $dockerRedisRecovered
        manual_steps = "docker compose stop redis ; docker compose start redis"
    }
}

# Failure Test 1 - Kubernetes kill redis pod
Write-Host ""
Write-Host "FAILURE TEST 1 - Kubernetes: delete redis pod"
kubectl apply -f .\k8s-healthcare.yaml | Out-Null
Start-Sleep -Seconds 25
kubectl delete pod -l app=redis -n healthcare | Out-Null
Start-Sleep -Seconds 20

$k8sRedisFailed = Ask-YesNo "After deleting redis pod, did Kubernetes app become unhealthy/fail?"
Start-Sleep -Seconds 20
$k8sRedisRecovered = Ask-YesNo "Did Kubernetes recreate redis and recover automatically?"

$result.failure_tests[-1]["kubernetes"] = @{
    app_failed = $k8sRedisFailed
    auto_recovered = $k8sRedisRecovered
    manual_steps = "kubectl delete pod -l app=redis -n healthcare"
}

# Failure Test 2 - Docker kill app
Write-Host ""
Write-Host "FAILURE TEST 2 - Docker: kill app"
docker compose -f .\docker-compose.benchmark.yml up -d | Out-Null
Start-Sleep -Seconds 15
docker compose -f .\docker-compose.benchmark.yml kill app | Out-Null
Start-Sleep -Seconds 10
$dockerAppRecovered = Ask-YesNo "Did Docker restart the app automatically?"

$result.failure_tests += @{
    scenario = "kill_app"
    docker = @{
        auto_recovered = $dockerAppRecovered
        manual_steps = "docker compose kill app"
    }
}

# Failure Test 2 - Kubernetes kill app pod
Write-Host ""
Write-Host "FAILURE TEST 2 - Kubernetes: delete app pod"
kubectl apply -f .\k8s-healthcare.yaml | Out-Null
Start-Sleep -Seconds 20
kubectl delete pod -l app=app -n healthcare | Out-Null
Start-Sleep -Seconds 20
$k8sAppRecovered = Ask-YesNo "Did Kubernetes recreate the app pod automatically?"

$result.failure_tests[-1]["kubernetes"] = @{
    auto_recovered = $k8sAppRecovered
    manual_steps = "kubectl delete pod -l app=app -n healthcare"
}

# Maintenance tests
Write-Host ""
Write-Host "MAINTENANCE TESTS"

Write-Host ""
Write-Host "Test: Docker scale app to 3"
$dockerScaleTime = Ask-Number "Enter stopwatch time in seconds for Docker scale-to-3"
$dockerScaleDowntime = Ask-YesNo "Did Docker scale-to-3 cause downtime?"

Write-Host ""
Write-Host "Test: Kubernetes scale app to 3"
$k8sScaleTime = Ask-Number "Enter stopwatch time in seconds for Kubernetes scale-to-3"
$k8sScaleDowntime = Ask-YesNo "Did Kubernetes scale-to-3 cause downtime?"

$result.maintenance_tests += @{
    scenario = "scale_to_3"
    docker = @{
        commands = 1
        time_sec = $dockerScaleTime
        downtime = $dockerScaleDowntime
    }
    kubernetes = @{
        commands = 1
        time_sec = $k8sScaleTime
        downtime = $k8sScaleDowntime
    }
}

Write-Host ""
Write-Host "Test: Docker full teardown + redeploy"
$dockerRedeployTime = Ask-Number "Enter stopwatch time in seconds for Docker full redeploy"
$dockerRedeployDowntime = Ask-YesNo "Did Docker full redeploy cause downtime?"

Write-Host ""
Write-Host "Test: Kubernetes full teardown + redeploy"
$k8sRedeployTime = Ask-Number "Enter stopwatch time in seconds for Kubernetes full redeploy"
$k8sRedeployDowntime = Ask-YesNo "Did Kubernetes full redeploy cause downtime?"

$result.maintenance_tests += @{
    scenario = "full_redeploy"
    docker = @{
        commands = 2
        time_sec = $dockerRedeployTime
        downtime = $dockerRedeployDowntime
    }
    kubernetes = @{
        commands = 2
        time_sec = $k8sRedeployTime
        downtime = $k8sRedeployDowntime
    }
}

$result | ConvertTo-Json -Depth 6 | Set-Content $manualFile

Write-Host ""
Write-Host "Manual test results saved to:"
Write-Host $manualFile