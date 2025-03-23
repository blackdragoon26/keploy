# Define the Dockerfile path
$DOCKERFILE_PATH = "./Dockerfile"

# Function to add the -race flag to the go build command in the Dockerfile
function Update-Dockerfile {
    Write-Output "Updating Dockerfile to include the -race flag in the go build command..."

    # Read Dockerfile content
    $dockerfileContent = Get-Content -Path $DOCKERFILE_PATH -Raw

    # Replace the go build command using regex
    $updatedContent = $dockerfileContent -replace 'RUN go build -tags=viper_bind_struct -ldflags="-X main.dsn=\$SENTRY_DSN_DOCKER -X main.version=\$VERSION" -o keploy .', 'RUN go build -race -tags=viper_bind_struct -ldflags="-X main.dsn=$SENTRY_DSN_DOCKER -X main.version=$VERSION" -o keploy .'

    # Write updated content back to Dockerfile
    $updatedContent | Set-Content -Path $DOCKERFILE_PATH

    Write-Output "Dockerfile updated successfully."
}

# Function to build the Docker image
function New-DockerImage {
    Write-Output "Building Docker image..."

    ## Set environment variable for PowerShell
$Env:GOMAXPROCS = "2"

# Build the Docker image with GOMAXPROCS passed as an argument
docker image build --build-arg GOMAXPROCS=$Env:GOMAXPROCS -t ghcr.io/keploy/keploy:v2-dev .
    # Check if the command was successful
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Docker image built successfully."
    } else {
        Write-Output "Failed to build Docker image."
        exit 1
    }
}

# Main function to update the Dockerfile and build the Docker image
function Main {
    Update-Dockerfile
    New-DockerImage  
}

# Run the main function
Main
