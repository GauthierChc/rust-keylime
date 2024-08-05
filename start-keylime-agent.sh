#!/bin/bash

CV_CA_GITHUB_TOKEN=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
CV_CA_REPO_URL=github.com/Teprikey/shared-keylime-git.git
CV_CA_REPO_NAME=shared-keylime-git
RUST_KEY_REPO_URL=github.com/GauthierChc/rust-keylime.git
RUST_KEY_REPO_NAME=rust-keylime
CURRENT_DIR=$(pwd)

# Clone the cv_ca repository
echo "Cloning cv_ca repository from $CV_CA_REPO_URL into /var/lib/keylime"
git clone "https://$CV_CA_GITHUB_TOKEN@$CV_CA_REPO_URL" /var/lib/keylime

# Check if git clone was successful
if [ $? -ne 0 ]; then
    echo "Failed to clone cv_ca repository. Check repository URL and token."
    exit 1
fi

# Clone the rust-keylime repository
echo "Cloning rust-keylime repository from $RUST_KEY_REPO_URL into /var/lib/keylime"
git clone https://github.com/GauthierChc/rust-keylime.git

# Check if git clone was successful
if [ $? -ne 0 ]; then
    echo "Failed to clone rust-keylime repository. Check repository URL."
    exit 1
fi

# Check if the directory exists
cd "$RUST_KEY_REPO_NAME" || { echo "Directory $RUST_KEY_REPO_NAME does not exist. Exiting."; exit 1; }

# Run docker-compose
echo "Running docker-compose-agent"
docker-compose -f docker-compose-agent.yml up --build

# Check if docker-compose was successful
if [ $? -ne 0 ]; then
    echo "docker-compose-agent failed. Check docker-compose.yml configuration."
    exit 1
fi

echo "Process completed successfully."
exit 0