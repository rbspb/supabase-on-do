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
echo "2. Generating DigitalOcean API Token (read/write). (docs: https://docs.digitalocean.com/reference/api/create-personal-access-token/)"
echo "3. Generating DO Spaces Access Key and Secret. (docs: https://docs.digitalocean.com/products/spaces/how-to/manage-access/#access-keys)"
echo "4. Adding your Domain to DigitalOcean DNS and pointing nameservers. (docs: https://docs.digitalocean.com/products/networking/dns/how-to/add-domains/)"
echo "5. Generating SendGrid Admin API Token. (docs: https://docs.sendgrid.com/for-developers/sending-email/brite-verify#creating-a-new-api-key)"
echo "6. (Optional) Generating Terraform Cloud User API Token if using TF Cloud. (docs: https://app.terraform.io/app/settings/tokens)"
echo ""
echo "This script will prompt you for these details."
echo "Sensitive information will be written to local files."
echo "Ensure you run this in a secure environment."
echo ""
echo "Note for Windows Users: This is a bash script. You will need to run it"
echo "using Windows Subsystem for Linux (WSL) or Git Bash. The installation"
echo "instructions provided for Windows are for native PowerShell."
echo "==================================================="
echo ""

# --- Function to check for required commands and provide install instructions ---
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found."
        echo "Please install '$cmd' and run the script again."

        local os_type=$(uname -s)

        case "$os_type" in
            Darwin)
                echo "Detected macOS. Install using Homebrew:"
                if [ "$cmd" == "doctl" ]; then
                    echo "  brew install doctl"
                else
                    echo "  brew tap hashicorp/tap"
                    echo "  brew install hashicorp/tap/$cmd" # This works for both packer and terraform
                fi
                ;;
            Linux)
                echo "Detected Linux."
                if [ "$cmd" == "doctl" ]; then
                    echo "Install doctl:"
                    # Check for snap
                    if command -v snap &> /dev/null; then
                        echo "  Option 1: Using Snap (recommended for many distributions):"
                        echo "    sudo snap install doctl"
                        echo "    sudo snap connect doctl:dot-docker" # Optional: if you need docker integration
                    fi

                    # Provide package manager instructions as Option 2 or primary if snap not found
                    echo "  Option 2: Using package manager (adds DigitalOcean repository):"
                    if [ -f /etc/os-release ]; then
                        . /etc/os-release
                        local id_like="$ID_LIKE"
                        local id="$ID"
                        local version_id="$VERSION_ID"

                        if [[ "$id" == "ubuntu" || "$id_like" == *"debian"* ]]; then
                            echo "    Detected Ubuntu/Debian. Install using apt:"
                            echo "      sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl"
                            echo "      curl -sL https://repos.insights.digitalocean.com/apt/do-agent.gpg | sudo apt-key add -" # Using do-agent key for doctl repo
                            echo "      echo \"deb https://repos.insights.digitalocean.com/apt/do-agent/ \$(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/digitalocean-agent.list" # Using do-agent repo for doctl
                            echo "      sudo apt-get update"
                            echo "      sudo apt-get install -y doctl"
                        elif [[ "$id" == "centos" || "$id" == "rhel" || "$id_like" == *"rhel"* ]]; then
                             echo "    Detected CentOS/RHEL. Install using yum:"
                             echo "      sudo yum install -y yum-utils"
                             echo "      sudo yum-config-manager --add-repo https://repos.insights.digitalocean.com/yum/do-agent.repo" # Using do-agent repo for doctl
                             echo "      sudo yum -y install doctl"
                        elif [[ "$id" == "fedora" ]]; then
                             echo "    Detected Fedora. Install using dnf:"
                             echo "      sudo dnf install -y dnf-plugins-core"
                             echo "      sudo dnf config-manager --add-repo https://repos.insights.digitalocean.com/yum/do-agent.repo" # Using do-agent repo for doctl
                             echo "      sudo dnf -y install doctl"
                        elif [[ "$id" == "amzn" ]]; then
                             echo "    Detected Amazon Linux. Install using yum:"
                             echo "      sudo yum install -y yum-utils"
                             echo "      sudo yum-config-manager --add-repo https://repos.insights.digitalocean.com/yum/do-agent.repo" # Using do-agent repo for doctl
                             echo "      sudo yum -y install doctl"
                        else
                            echo "    Could not detect specific Linux distribution package manager."
                            echo "    Please refer to the official documentation for installation:"
                            echo "      https://docs.digitalocean.com/reference/doctl/how-to/install/"
                        fi
                    else
                        echo "    Could not detect specific Linux distribution package manager."
                        echo "    Please refer to the official documentation for installation:"
                        echo "      https://docs.digitalocean.com/reference/doctl/how-to/install/"
                    fi

                    # Provide generic manual install as Option 3 or alternative
                    echo "  Option 3: Manual installation (example using v1.124.0 - check releases for latest):"
                    echo "    cd ~"
                    echo "    wget https://github.com/digitalocean/doctl/releases/download/v1.124.0/doctl-1.124.0-linux-amd64.tar.gz"
                    echo "    tar xf ~/doctl-1.124.0-linux-amd64.tar.gz"
                    echo "    sudo mv ~/doctl /usr/local/bin"

                else # Handle packer and terraform for Linux
                    echo "Install $cmd:"
                    if [ -f /etc/os-release ]; then
                        . /etc/os-release
                        local id_like="$ID_LIKE"
                        local id="$ID"
                        local version_id="$VERSION_ID"

                        if [[ "$id" == "ubuntu" || "$id_like" == *"debian"* ]]; then
                            echo "    Detected Ubuntu/Debian. Install using apt:"
                            echo "      sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl"
                            # Using the recommended gpg --dearmor method
                            echo "      curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null"
                            # Using the more robust method to get the codename
                            echo "      echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs 2>/dev/null) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list"
                            echo "      sudo apt-get update"
                            echo "      sudo apt-get install $cmd"
                        elif [[ "$id" == "centos" || "$id" == "rhel" || "$id_like" == *"rhel"* ]]; then
                             echo "    Detected CentOS/RHEL. Install using yum:"
                             echo "      sudo yum install -y yum-utils"
                             echo "      sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo"
                             echo "      sudo yum -y install $cmd"
                        elif [[ "$id" == "fedora" ]]; then
                             echo "    Detected Fedora."
                             if [[ "$version_id" == "40" ]]; then
                                 echo "    Install using yum (Fedora 40):"
                                 echo "      sudo yum install -y yum-utils"
                                 echo "      sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo" # Instructions use RHEL repo for Fedora 40 yum
                                 echo "      sudo yum -y install $cmd"
                             elif [[ "$version_id" == "41" ]]; then
                                 echo "    Install using dnf (Fedora 41):"
                                 echo "      sudo dnf install -y dnf-plugins-core"
                                 echo "      sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo"
                                 echo "      sudo dnf -y install $cmd"
                             else
                                 echo "    Install using dnf (generic Fedora):"
                                 echo "      sudo dnf install -y dnf-plugins-core"
                                 echo "      sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo"
                                 echo "      sudo dnf -y install $cmd"
                             fi
                        elif [[ "$id" == "amzn" ]]; then
                             echo "    Detected Amazon Linux. Install using yum:"
                             echo "      sudo yum install -y yum-utils"
                             echo "      sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo"
                             echo "      sudo yum -y install $cmd"
                        else
                            echo "    Detected an unknown Linux distribution. Please refer to the official documentation for installation:"
                            case "$cmd" in
                                packer) echo "      https://developer.hashicorp.com/packer/downloads";;
                                terraform) echo "      https://developer.hashicorp.com/terraform/downloads";;
                            esac
                        fi
                    else
                        echo "    Could not detect specific Linux distribution. Please refer to the official documentation for installation:"
                        case "$cmd" in
                            packer) echo "      https://developer.hashicorp.com/packer/downloads";;
                            terraform) echo "      https://developer.hashicorp.com/terraform/downloads";;
                        esac
                    fi
                fi
                ;;
            CYGWIN*|MINGW*|MSYS*)
                echo "Detected Windows (running in Cygwin, MinGW, or MSYS)."
                echo "For native Windows/PowerShell, you can use these instructions (run in PowerShell as Administrator):"
                echo "  Visit the doctl Releases page (https://github.com/digitalocean/doctl/releases) and find the appropriate archive for your OS/architecture."
                echo "  Example using v1.124.0 (check releases for latest):"
                echo "    Invoke-WebRequest https://github.com/digitalocean/doctl/releases/download/v1.124.0/doctl-1.124.0-windows-amd64.zip -OutFile ~\doctl-1.124.0-windows-amd64.zip"
                echo "    Expand-Archive -Path ~\doctl-1.124.0-windows-amd64.zip"
                echo "    New-Item -ItemType Directory \$env:ProgramFiles\\doctl\\"
                echo "    Move-Item -Path ~\doctl-1.124.0-windows-amd64\\doctl.exe -Destination \$env:ProgramFiles\\doctl\\"
                echo "    [Environment]::SetEnvironmentVariable("
                echo "        \"Path\","
                echo "        [Environment]::GetEnvironmentVariable(\"Path\","
                echo "        [EnvironmentVariableTarget]::Machine) + \";\$env:ProgramFiles\\doctl\\\","
                echo "        [EnvironmentVariableTarget]::Machine)"
                echo "    \$env:Path = [System.Environment]::GetEnvironmentVariable(\"Path\",\"Machine\")"
                echo ""
                echo "Alternatively, if using WSL, follow the Linux instructions above."
                ;;
            *)
                echo "Detected unknown OS type: $os_type."
                echo "Please refer to the official documentation for installation:"
                case "$cmd" in
                    packer) echo "  https://developer.hashicorp.com/packer/downloads";;
                    terraform) echo "  https://developer.hashicorp.com/terraform/downloads";;
                    doctl) echo "  https://docs.digitalocean.com/reference/doctl/how-to/install/";;
                esac
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
check_command "doctl"
echo "All required tools found."
echo ""

# --- Collect User Variables ---
echo "Collecting required parameters:"

read -s -p "Enter your DigitalOcean API Token (read/write): " DO_API_TOKEN
echo ""
# Configure doctl with the API token temporarily to list sizes
echo "Configuring doctl with API token..."
echo "$DO_API_TOKEN" | doctl auth init --access-token -
if [ $? -ne 0 ]; then
    echo "Error: Failed to configure doctl with the provided API token."
    echo "Please ensure the token is valid and has read/write permissions."
    exit 1
fi
echo "doctl configured successfully."
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

# --- Select DigitalOcean Region ---
echo "Select your DigitalOcean Region:"
declare -A regions=(
    [1]="nyc1: New York City, United States"
    [2]="nyc2: New York City, United States"
    [3]="nyc3: New York City, United States"
    [4]="ams3: Amsterdam, the Netherlands"
    [5]="sfo2: San Francisco, United States"
    [6]="sfo3: San Francisco, United States"
    [7]="sgp1: Singapore"
    [8]="lon1: London, United Kingdom"
    [9]="fra1: Frankfurt, Germany"
    [10]="tor1: Toronto, Canada"
    [11]="blr1: Bangalore, India"
    [12]="syd1: Sydney, Australia"
    [13]="atl1: Atlanta, United States"
)

# Print the list
for i in "${!regions[@]}"; do
    echo "$i) ${regions[$i]}"
done

# Prompt for selection and validate
while true; do
    read -r -p "Enter the number of your desired region: " region_choice
    if [[ "$region_choice" =~ ^[0-9]+$ ]] && [ "$region_choice" -ge 1 ] && [ "$region_choice" -le ${#regions[@]} ]; then
        # Extract the slug from the selected region string (e.g., "nyc3: ...")
        DO_REGION=$(echo "${regions[$region_choice]}" | cut -d':' -f1)
        echo "Selected region: $DO_REGION"
        break
    else
        echo "Invalid selection. Please enter a number between 1 and ${#regions[@]}."
    fi
done
echo ""

read -r -p "Enter the DigitalOcean Image slug (e.g., ubuntu-22-04-x64): " DO_IMAGE_SLUG
echo ""

# --- Select DigitalOcean Droplet Size using doctl ---
echo "Fetching available Droplet sizes for region '$DO_REGION'..."
# Use doctl to list sizes, format output, and store in an array
# Format: Slug,Memory,VCPUs,Disk,PriceMonthly,PriceHourly
mapfile -t droplet_sizes < <(doctl compute size list --format Slug,Memory,VCPUs,Disk,PriceMonthly,PriceHourly --no-header --region "$DO_REGION" 2>/dev/null)

if [ ${#droplet_sizes[@]} -eq 0 ]; then
    echo "Error: Could not retrieve droplet sizes for region '$DO_REGION'."
    echo "Please check the region slug and your DigitalOcean API token permissions."
    exit 1
fi

echo "Available Droplet Sizes:"
declare -A size_map # Map selection number to slug
size_count=0
for size_info in "${droplet_sizes[@]}"; do
    size_count=$((size_count + 1))
    # Split the line by comma
    IFS=',' read -r slug memory vcpus disk price_monthly price_hourly <<< "$size_info"
    # Store the slug in the map
    size_map[$size_count]="$slug"
    # Print the formatted option
    printf "%d) %s: Memory %sMB, VCPUs %s, Disk %sGB, Price \$%.2f/mo (\$%.4f/hr)\n" \
           "$size_count" "$slug" "$memory" "$vcpus" "$disk" "$price_monthly" "$price_hourly"
done

# Prompt for selection and validate
while true; do
    read -r -p "Enter the number of your desired Droplet size: " size_choice
    if [[ "$size_choice" =~ ^[0-9]+$ ]] && [ "$size_choice" -ge 1 ] && [ "$size_choice" -le "$size_count" ]; then
        DO_SIZE_SLUG="${size_map[$size_choice]}"
        echo "Selected size: $DO_SIZE_SLUG"
        break
    else
        echo "Invalid selection. Please enter a number between 1 and $size_count."
    fi
done
echo ""

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
