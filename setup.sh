#!/bin/bash

# Supabase on DigitalOcean Self-Hosting Setup Script
# Based on instructions from https://github.com/digitalocean/supabase-on-do

set -e # Exit immediately if a command exits with a non-zero status.

REPO_URL="https://github.com/digitalocean/supabase-on-do.git"
REPO_DIR="supabase-on-do"
PACKER_VARS_FILE="packer/supabase.auto.pkrvars.hcl"
TERRAFORM_VARS_FILE="terraform/terraform.tfvars"

echo "==================================================="
echo "Supabase on DigitalOcean Self-Hosting Setup Script"
echo "==================================================="
echo ""
echo "This script automates the setup process based on the"
echo "digitalocean/supabase-on-do GitHub repository."
echo ""
echo "!!! IMPORTANT !!!"
echo "Before running this script, ensure you have manually completed:"
echo "1. Creating DigitalOcean and SendGrid accounts."
echo "2. Generating DigitalOcean API Token (read/write)."
echo "3. Generating DO Spaces Access Key and Secret."
echo "4. Adding your Domain to DigitalOcean DNS and pointing nameservers."
echo "5. Generating SendGrid Admin API Token."
echo "6. (Optional) Generating Terraform Cloud User API Token if using TF Cloud."
echo ""
echo "This script will prompt you for these details."
echo "Sensitive information will be written to local files."
echo "Ensure you run this in a secure environment."
echo "==================================================="
echo ""

# --- Function to check for required commands ---
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: Required command '$1' not found."
        echo "Please install '$1' and run the script again."
        case "$1" in
            packer)
                echo "Instructions: https://developer.hashicorp.com/packer/tutorials/docker-get-started/get-started-install-cli"
                ;;
            terraform)
                echo "Instructions: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli"
                ;;
            git)
                echo "Instructions: https://git-scm.com/book/en/v2/Getting-Started-Installing-Git"
                ;;
        esac
        exit 1
    fi
}

# --- Check prerequisites ---
echo "Checking for required tools..."
check_command "git"
check_command "packer"
check_command "terraform"
echo "All required tools found."
echo ""

# --- Collect User Variables ---
echo "Collecting required parameters:"

read -s -p "Enter your DigitalOcean API Token (read/write): " DO_API_TOKEN
echo ""
read -s -p "Enter your DO Spaces Access Key: " DO_SPACES_ACCESS_KEY
echo ""
read -s -p "Enter your DO Spaces Secret Key: " DO_SPACES_SECRET_KEY
echo ""
read -r -p "Enter your Domain Name (e.g., example.com): " DOMAIN_NAME
read -s -p "Enter your SendGrid Admin API Token: " SENDGRID_API_KEY
echo ""
read -r -p "Are you using Terraform Cloud for state management? (yes/no): " USE_TF_CLOUD
if [[ "$USE_TF_CLOUD" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
    read -s -p "Enter your Terraform Cloud User API Token: " TF_CLOUD_TOKEN
    echo ""
else
    TF_CLOUD_TOKEN=""
fi

echo ""
echo "--- Packer Specific Variables ---"
read -r -p "Enter the DigitalOcean Region slug (e.g., nyc3): " DO_REGION
read -r -p "Enter the DigitalOcean Image slug (e.g., ubuntu-22-04-x64): " DO_IMAGE_SLUG
read -r -p "Enter the DigitalOcean Droplet Size slug (e.g., s-2vcpu-4gb): " DO_SIZE_SLUG
read -r -p "Enter the SSH Username for the Droplet (e.g., root or your user): " SSH_USERNAME
echo ""

# --- Clone the repository ---
if [ -d "$REPO_DIR" ]; then
    echo "Repository directory '$REPO_DIR' already exists. Skipping clone."
    echo "Please ensure it's the correct repository."
else
    echo "Cloning repository '$REPO_URL'..."
    git clone "$REPO_URL"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone repository."
        exit 1
    fi
    echo "Repository cloned successfully."
fi
echo ""

# --- Navigate into the repository ---
cd "$REPO_DIR" || { echo "Error: Failed to change directory to '$REPO_DIR'."; exit 1; }
echo "Changed directory to '$REPO_DIR'."
echo ""

# --- Configure and Run Packer ---
echo "--- Running Packer ---"
cd packer || { echo "Error: Failed to change directory to 'packer'."; exit 1; }

echo "Creating Packer variables file: $PACKER_VARS_FILE"
cat <<EOF > "$PACKER_VARS_FILE"
do_api_token = "$DO_API_TOKEN"
do_region    = "$DO_REGION"
do_image     = "$DO_IMAGE_SLUG"
do_size      = "$DO_SIZE_SLUG"
ssh_username = "$SSH_USERNAME"
EOF
echo "Packer variables file created."
echo ""

echo "Initializing Packer..."
packer init .
if [ $? -ne 0 ]; then
    echo "Error: Packer initialization failed."
    exit 1
fi
echo "Packer initialized."
echo ""

echo "Building Packer snapshot (this will take some time)..."
packer build .
if [ $? -ne 0 ]; then
    echo "Error: Packer build failed."
    exit 1
fi
echo "Packer snapshot built successfully."
echo ""

# --- Configure and Run Terraform ---
echo "--- Running Terraform ---"
cd ../terraform || { echo "Error: Failed to change directory to '../terraform'."; exit 1; }

echo "Creating Terraform variables file: $TERRAFORM_VARS_FILE"
cat <<EOF > "$TERRAFORM_VARS_FILE"
do_api_token         = "$DO_API_TOKEN"
do_spaces_access_key = "$DO_SPACES_ACCESS_KEY"
do_spaces_secret_key = "$DO_SPACES_SECRET_KEY"
do_region            = "$DO_REGION"
domain_name          = "$DOMAIN_NAME"
sendgrid_api_key     = "$SENDGRID_API_KEY"
EOF

if [ -n "$TF_CLOUD_TOKEN" ]; then
    echo "tf_cloud_token       = \"$TF_CLOUD_TOKEN\"" >> "$TERRAFORM_VARS_FILE"
fi
echo "Terraform variables file created."
echo ""

echo "Initializing Terraform..."
terraform init
if [ $? -ne 0 ]; then
    echo "Error: Terraform initialization failed."
    exit 1
fi
echo "Terraform initialized."
echo ""

echo "Applying Terraform plan (first pass)..."
echo "You will be prompted to confirm by typing 'yes'."
terraform apply
if [ $? -ne 0 ]; then
    echo "Error: Terraform apply (first pass) failed."
    exit 1
fi
echo "Terraform apply (first pass) completed."
echo ""

echo "Applying Terraform plan again to verify SendGrid components..."
echo "You will be prompted to confirm by typing 'yes'."
terraform apply
if [ $? -ne 0 ]; then
    echo "Error: Terraform apply (second pass) failed."
    exit 1
fi
echo "Terraform apply (second pass) completed."
echo ""

# --- Show Outputs ---
echo "--- Generated Passwords and Tokens ---"
echo "Showing generated passwords and tokens. Keep these secure!"
terraform output htpasswd
terraform output psql_pass
terraform output jwt
terraform output jwt_anon
terraform output jwt_service_role
echo "--------------------------------------"
echo ""

# --- Final Instructions ---
echo "Setup complete!"
echo "Please wait 5-10 minutes for everything to start up."
echo "Then, point your browser to: supabase.${DOMAIN_NAME}"
echo "When prompted for authentication, use the username 'supabase' and the 'htpasswd' shown above."
echo ""
echo "Remember to secure the variable files created:"
echo "- $REPO_DIR/$PACKER_VARS_FILE"
echo "- $REPO_DIR/$TERRAFORM_VARS_FILE"
echo ""
echo "To destroy the created resources later, navigate to the '$REPO_DIR/terraform' directory"
echo "and run 'terraform destroy'."
echo ""

exit 0
