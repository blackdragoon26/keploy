# Load test-iid script (if necessary)
# Note: PowerShell does not have 'source', use dot-sourcing if needed
. ..\..\github\workflows\test_workflow_scripts\test-iid.ps1

# Create Docker network
Write-Output "Creating Docker network..."
docker network create keploy-network

# Start MongoDB container
Write-Output "Starting MongoDB container..."
docker run --name mongoDb --rm --net keploy-network -p 27017:27017 -d mongo

# Remove any preexisting keploy tests
Write-Output "Removing previous keploy tests..."
Remove-Item -Recurse -Force keploy

# Build the Docker image for the application
Write-Output "Building Node.js application image..."
docker build -t node-app:1.0 .

function container_kill {
    $processId = Get-Process | Where-Object { $_.ProcessName -eq "keployv2" } | Select-Object -ExpandProperty Id
    if ($processId) {
        Write-Output "Keploy PID: $processId"
        Write-Output "Killing keploy..."
        Stop-Process -Id $processId -Force
    }
}

function send_request {
    Start-Sleep -Seconds 10

    # Wait for application to start
    $app_started = $false
    while (-not $app_started) {
        try {
            Invoke-WebRequest -Uri "http://localhost:8000/students" -UseBasicParsing
            $app_started = $true
        } catch {
            Start-Sleep -Seconds 3
        }
    }

    # Making HTTP requests to record test cases and mocks
    Write-Output "Sending requests..."
    Invoke-RestMethod -Uri "http://localhost:8000/students" -Method Post -Headers @{"Content-Type"="application/json"} -Body '{"name":"John Doe","email":"john@xyz.com","phone":"0123456799"}'
    Invoke-RestMethod -Uri "http://localhost:8000/students" -Method Post -Headers @{"Content-Type"="application/json"} -Body '{"name":"Alice Green","email":"green@alice.com","phone":"3939201584"}'
    Invoke-WebRequest -Uri "http://localhost:8000/students" -UseBasicParsing

    # Wait for keploy to record test cases
    Start-Sleep -Seconds 5
    container_kill
    Wait-Process -Name "keployv2"
}

for ($i = 1; $i -le 2; $i++) {
    Write-Output "Running Keploy in record mode for iteration $i..."
    $container_name = "nodeApp_$i"

    Start-Job -ScriptBlock { send_request }

    Start-Process -NoNewWindow -Wait -FilePath "..\..\keployv2.exe" -ArgumentList "record -c `"docker run -p 8000:8000 --name $container_name --network keploy-network node-app:1.0`" --container-name $container_name" -RedirectStandardOutput "$container_name.txt"

    if (Select-String -Path "$container_name.txt" -Pattern "ERROR") {
        Write-Output "Error found in pipeline..."
        Get-Content "$container_name.txt"
        exit 1
    }

    if (Select-String -Path "$container_name.txt" -Pattern "WARNING: DATA RACE") {
        Write-Output "Race condition detected in recording, stopping pipeline..."
        Get-Content "$container_name.txt"
        exit 1
    }

    Start-Sleep -Seconds 5
    Write-Output "Recorded test case and mocks for iteration $i"
}

# Run Keploy in test mode
Write-Output "Running Keploy in test mode..."
$test_container = "nodeApp_test"
Start-Process -NoNewWindow -Wait -FilePath "..\..\keployv2.exe" -ArgumentList "test -c `"docker run -p8000:8000 --rm --name $test_container --network keploy-network node-app:1.0`" --containerName $test_container --apiTimeout 30 --delay 30 --generate-github-actions=false" -RedirectStandardOutput "$test_container.txt"

if (Select-String -Path "$test_container.txt" -Pattern "ERROR") {
    Write-Output "Error found in pipeline..."
    Get-Content "$test_container.txt"
    exit 1
}

if (Select-String -Path "$test_container.txt" -Pattern "WARNING: DATA RACE") {
    Write-Output "Race condition detected in test, stopping pipeline..."
    Get-Content "$test_container.txt"
    exit 1
}

$all_passed = $true

for ($i = 0; $i -le 1; $i++) {
    $report_file = ".\keploy\reports\test-run-0\test-set-$i-report.yaml"

    if (Test-Path $report_file) {
        $test_status = (Select-String -Path $report_file -Pattern 'status:' | Select-Object -First 1).ToString().Split(" ")[1]

        Write-Output "Test status for test-set-${i}: ${test_status}"

        if ($test_status -ne "PASSED") {
            $all_passed = $false
            Write-Output "Test-set-$i did not pass."
            break
        }
    } else {
        Write-Output "Report file not found: $report_file"
        $all_passed = $false
        break
    }
}

if ($all_passed) {
    Write-Output "All tests passed"
    exit 0
} else {
    Get-Content "$test_container.txt"
    exit 1
}
