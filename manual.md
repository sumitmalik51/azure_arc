# Azure Arc JumpStart LocalBox: Manual Setup Guide

This document provides detailed manual instructions for setting up Azure Arc LocalBox environment without using the automated scripts. This guide will explain each command and configuration step needed to deploy and configure a complete Azure Local (formerly Azure Stack HCI) environment locally using nested virtualization.

This manual is derived from the automated deployment scripts and ARM templates in the Azure Arc JumpStart repository, providing step-by-step instructions to manually perform all the tasks that would normally be automated.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Azure VM Deployment](#initial-azure-vm-deployment)
3. [Configuring the Host VM](#configuring-the-host-vm)
4. [Installing Required Software](#installing-required-software)
5. [Setting Up Hyper-V](#setting-up-hyper-v)
6. [Downloading Required VHDXs](#downloading-required-vhdxs)
7. [Creating Virtual Networks](#creating-virtual-networks)
8. [Creating and Configuring Nested VMs](#creating-and-configuring-nested-vms)
9. [Configuring the Domain Controller](#configuring-the-domain-controller)
10. [Configuring the Router VM](#configuring-the-router-vm)
11. [Setting Up Azure Local Cluster](#setting-up-azure-local-cluster)
12. [Deploying Azure Resources](#deploying-azure-resources)
13. [Registering Azure Local Cluster](#registering-azure-local-cluster)
14. [Post-Deployment Configuration](#post-deployment-configuration)
15. [Troubleshooting](#troubleshooting)

## Prerequisites

Before starting the manual deployment, ensure you have the following:

### Azure Requirements
- An Azure subscription with Owner permissions
- Azure AD tenant with permission to create service principals
- Access to register Azure resource providers

### System Requirements
- At least 32GB of RAM for the host VM (recommended: Standard_E32s_v5 or Standard_E32s_v6 VM size)
- Minimum 32 CPU cores for the host VM
- At least 1TB of total disk space (OS disk + data disk)
- Windows Server 2022 Datacenter or Windows Server 2025 Datacenter

### Tools and Knowledge
- Knowledge of Hyper-V and networking concepts
- Understanding of Active Directory Domain Services
- Familiarity with Azure Resource Manager templates
- Basic PowerShell scripting knowledge

## Initial Azure VM Deployment

### Overview
This step creates the host Azure VM that will run all nested virtual machines for the Azure Arc LocalBox environment. The VM serves as the hypervisor host and requires sufficient resources to support multiple nested VMs running Azure Local nodes, domain controller, and management services.

### Why This Step is Needed
- **Nested Virtualization Support**: The host VM must support Hyper-V to create nested VMs for Azure Local cluster nodes
- **Resource Requirements**: Azure Local requires significant compute and memory resources, necessitating a large VM size
- **Network Isolation**: Provides isolated environment for testing Azure Local without affecting production systems
- **Cost Management**: Single large VM is more cost-effective than multiple smaller VMs for this scenario

1. **Deploy a VM in Azure with these specifications**:

   **Using Azure Portal (GUI Method)**:
   - Navigate to Azure portal (portal.azure.com)
   - Click "Create a resource" → "Virtual machine"
   - **Basics tab**:
     - Subscription: Select your subscription
     - Resource group: Create new (e.g., "localbox-rg")
     - Virtual machine name: Enter descriptive name (e.g., "localbox-host")
     - Region: Choose your preferred region (e.g., East US)
     - Availability options: No infrastructure redundancy required
     - Security type: Standard
     - Image: Windows Server 2022 Datacenter - x64 Gen2
     - Size: Click "See all sizes" → Search for "Standard_E32s_v5" or "Standard_E32s_v6"
   - **Disks tab**:
     - OS disk type: Premium SSD (256GB minimum)
     - Click "Create and attach a new disk"
     - Disk name: "localbox-data"
     - Size: 1024 GB (1TB)
     - Disk type: Premium SSD
   - **Networking tab**:
     - Virtual network: Create new with default settings
     - Subnet: Default (10.0.0.0/24)
     - Public IP: Create new
     - NIC network security group: Basic
     - Public inbound ports: Allow selected ports → RDP (3389)
   - **Management tab**: Leave defaults
   - **Advanced tab**: Leave defaults
   - Click "Review + create" → "Create"

   **Using Azure CLI (Command Method)**:
   ```bash
   # Create resource group
   az group create --name localbox-rg --location eastus
   
   # Create the VM with data disk
   az vm create \
     --resource-group localbox-rg \
     --name localbox-host \
     --image Win2022Datacenter \
     --size Standard_E32s_v5 \
     --admin-username azureuser \
     --admin-password 'YourSecurePassword123!' \
     --data-disk-sizes-gb 1024 \
     --os-disk-size-gb 256 \
     --storage-sku Premium_LRS \
     --public-ip-sku Standard \
     --nsg-rule RDP
   ```

2. **Connect to the VM** using Remote Desktop Protocol (RDP):

   **Using Azure Portal (GUI Method)**:
   - Navigate to your VM in Azure portal
   - Click "Connect" → "RDP"
   - Click "Download RDP File"
   - Open the downloaded .rdp file
   - Enter the administrator credentials you created during VM deployment
   - Accept any certificate warnings

   **Using Command Line**:
   ```powershell
   # Get the public IP address
   $publicIP = (Get-AzPublicIpAddress -ResourceGroupName "localbox-rg").IpAddress
   
   # Connect using mstsc
   mstsc /v:$publicIP
   ```

3. **Initialize and format the data disk**:

   **Why This Step is Needed**: The data disk provides high-performance storage for virtual machine files, VHDXs, and cluster storage. Proper initialization ensures optimal performance and reliability.

   **Using Server Manager (GUI Method)**:
   - Open Server Manager (automatically opens on first login)
   - Click "File and Storage Services" in the left navigation
   - Click "Disks" under "Volumes"
   - Right-click the "Offline" disk (Disk 1, 1TB)
   - Select "Bring Online" → Click "Yes" to confirm
   - Right-click the disk again → Select "Initialize"
   - Choose "GPT (GUID Partition Table)" → Click "OK"
   - Right-click the unallocated space → Select "New Volume"
   - **New Volume Wizard**:
     - Click "Next" on Before You Begin
     - Select the disk → Click "Next"
     - Volume size: Use maximum size → Click "Next"  
     - Drive letter: Select "V" → Click "Next"
     - File system: NTFS
     - Allocation unit size: 64K (65536 bytes)
     - Volume label: "AzLocalData"
     - Perform quick format: Checked → Click "Next"
     - Click "Create"

   **Using PowerShell (Command Method)**:
     ```powershell
     # Initialize the disk
     Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Initialize-Disk -PartitionStyle GPT -PassThru
     
     # Create partition and format
     New-Partition -DiskNumber 1 -DriveLetter V -UseMaximumSize | 
     Format-Volume -FileSystem NTFS -NewFileSystemLabel "AzLocalData" -AllocationUnitSize 65536 -Confirm:$false
     ```

## Configuring the Host VM

### Overview
This section prepares the host VM for running nested virtualization by configuring the operating system, creating directory structure, and setting up essential services. These configurations ensure optimal performance and proper resource allocation for the nested Azure Local environment.

### Why This Step is Needed
- **Storage Optimization**: Extends the OS disk and creates organized directory structure for VM files
- **Environment Setup**: Establishes consistent paths and variables used throughout the deployment
- **Security Configuration**: Disables unnecessary prompts and configures authentication for nested VM management
- **Performance Tuning**: Optimizes system settings for virtualization workloads

1. **Extend the C:\ drive to maximum size**:

   **Why This Step is Needed**: The OS disk may not utilize all available space by default. Extending ensures maximum storage availability for system files, logs, and temporary data.

   **Using Disk Management (GUI Method)**:
   - Right-click "Start" button → Select "Disk Management"
   - Right-click the C: drive → Select "Extend Volume"
   - **Extend Volume Wizard**:
     - Click "Next" on Welcome screen
     - Available space should show all unallocated space → Click "Next"
     - Click "Finish"

   **Using PowerShell (Command Method)**:
   ```powershell
   # Extend C: drive to use all available space
   Resize-Partition -DriveLetter C -Size (Get-PartitionSupportedSize -DriveLetter C).SizeMax
   ```

2. **Create the directory structure**:

   **Why This Step is Needed**: Establishes standardized folder structure for organizing VM files, logs, configuration files, and tools. This organization is essential for automation scripts and maintenance tasks.

   **Using File Explorer (GUI Method)**:
   - Open File Explorer (Windows key + E)
   - Navigate to C:\ drive
   - Create the following folders by right-clicking → "New" → "Folder":
     - C:\LocalBox (main folder)
     - Inside C:\LocalBox, create:
       - DSC (for PowerShell DSC configurations)
       - Tests (for validation scripts)
       - Virtual Machines (for nested VM configurations)
       - Logs (for deployment and operation logs)
       - Icons (for desktop shortcuts and branding)
       - VHD (for VHDX file storage)
       - SDN (for Software Defined Networking configs)
       - KeyVault (for certificate and secret storage)
       - Windows Admin Center (for WAC installer)
       - agentScript (for Azure Arc agent scripts)
     - C:\Tools (for management utilities)
     - C:\Temp (for temporary files)
     - V:\VMs (on the data disk for VM storage)

   **Using PowerShell (Command Method)**:
   ```powershell
   # Create main LocalBox directory
   $LocalBoxPath = "C:\LocalBox"
   New-Item -Path $LocalBoxPath -ItemType Directory -Force

   # Create required subdirectories
   $Directories = @(
       "C:\LocalBox\DSC",
       "C:\LocalBox\Tests", 
       "C:\LocalBox\Virtual Machines",
       "C:\LocalBox\Logs",
       "C:\LocalBox\Icons",
       "C:\LocalBox\VHD",
       "C:\LocalBox\SDN",
       "C:\LocalBox\KeyVault",
       "C:\LocalBox\Windows Admin Center",
       "C:\LocalBox\agentScript",
       "C:\Tools",
       "C:\Temp",
       "V:\VMs"
   )
   
   foreach ($Directory in $Directories) {
       New-Item -Path $Directory -ItemType Directory -Force
       Write-Output "Created directory: $Directory"
   }
   ```

3. **Set environment variables**:

   **Why This Step is Needed**: Environment variables provide consistent paths that automation scripts and applications can reference. This ensures all tools know where to find configuration files, logs, and resources.

   **Using System Properties (GUI Method)**:
   - Right-click "This PC" → Properties → "Advanced system settings"
   - Click "Environment Variables"
   - Under "System variables" section, click "New"
   - Add each of these variables:
     - Variable name: `LocalBoxDir`, Variable value: `C:\LocalBox`
     - Variable name: `LocalBoxLogsDir`, Variable value: `C:\LocalBox\Logs` 
     - Variable name: `LocalBoxTestsDir`, Variable value: `C:\LocalBox\Tests`
     - Variable name: `LocalBoxConfigFile`, Variable value: `C:\LocalBox\LocalBox-Config.psd1`
   - Click "OK" to close all windows

   **Using PowerShell (Command Method)**:
   ```powershell
   # Set system environment variables
   [System.Environment]::SetEnvironmentVariable('LocalBoxDir', 'C:\LocalBox', [System.EnvironmentVariableTarget]::Machine)
   [System.Environment]::SetEnvironmentVariable('LocalBoxLogsDir', 'C:\LocalBox\Logs', [System.EnvironmentVariableTarget]::Machine)
   [System.Environment]::SetEnvironmentVariable('LocalBoxTestsDir', 'C:\LocalBox\Tests', [System.EnvironmentVariableTarget]::Machine)
   [System.Environment]::SetEnvironmentVariable('LocalBoxConfigFile', 'C:\LocalBox\LocalBox-Config.psd1', [System.EnvironmentVariableTarget]::Machine)
   ```

4. **Disable unnecessary features**:

   **Why This Step is Needed**: Removes distractions and prompts that interfere with automated deployments and improves the user experience during manual operations.

   **Using GUI Methods**:
   - **Disable Server Manager startup**:
     - Open Server Manager → Click "Manage" menu → "Server Manager Properties"
     - Check "Do not start Server Manager automatically at logon"
   - **Disable WAC prompt**:
     - Open Registry Editor (regedit.exe)
     - Navigate to `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager`
     - Right-click → New → DWORD (32-bit) Value
     - Name: `DoNotPopWACConsoleAtSMLaunch`
     - Value: `1`
   - **Disable Network Profile prompt**:
     - In Registry Editor, navigate to `HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Network`
     - Right-click "Network" → New → Key
     - Name the key: `NewNetworkWindowOff`

   **Using PowerShell (Command Method)**:
   ```powershell
   # Disable Windows Server Manager scheduled task
   Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask
   
   # Disable Server Manager WAC prompt
   $RegistryPath = "HKLM:\SOFTWARE\Microsoft\ServerManager"
   New-Item -Path $RegistryPath -Force | Out-Null
   New-ItemProperty -Path $RegistryPath -Name "DoNotPopWACConsoleAtSMLaunch" -Value "1" -PropertyType DWORD -Force
   
   # Disable Network Profile prompt
   New-Item -Path "HKLM:\System\CurrentControlSet\Control\Network\NewNetworkWindowOff" -Force | Out-Null
   ```

5. **Configure CredSSP and WinRM for nested virtualization**:

   **Why This Step is Needed**: CredSSP (Credential Security Support Provider) and WinRM (Windows Remote Management) enable PowerShell remote management of nested VMs. This is essential for automating configuration of VMs running inside the host VM.

   **Using PowerShell (Command Method)**:
   ```powershell
   # Enable PowerShell Remoting
   Enable-PSRemoting -Force
   
   # Configure WinRM trusted hosts
   Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
   
   # Enable CredSSP (required for nested VM management)
   Enable-WSManCredSSP -Role Server -Force
   Enable-WSManCredSSP -Role Client -DelegateComputer $Env:COMPUTERNAME -Force
   ```

   **Note**: CredSSP is required but has security implications. In production environments, configure specific computer names instead of using wildcards.

## Installing Required Software

### Overview
This section installs all necessary software, tools, and PowerShell modules required for Azure Local deployment and management. The software stack includes PowerShell 7, Azure CLI, management tools, and specialized modules for Azure Arc and HCI management.

### Why This Step is Needed
- **Modern PowerShell**: PowerShell 7 provides enhanced Azure integration and cross-platform compatibility
- **Azure Integration**: Azure CLI and Az PowerShell modules enable Azure resource management
- **Automation Tools**: WinGet and package managers streamline software installation and updates
- **Management Utilities**: Tools like Windows Admin Center provide GUI-based cluster management
- **Performance**: Proper software configuration optimizes deployment speed and reliability

1. **Install PowerShell 7**:

   **Why This Step is Needed**: PowerShell 7 offers better performance, enhanced Azure integration, and modern features required by the latest Azure modules and automation scripts.

   **Using GUI Method**:
   - Open web browser and navigate to: https://github.com/PowerShell/PowerShell/releases/latest
   - Download the latest "PowerShell-[version]-win-x64.msi" file
   - Double-click the downloaded MSI file
   - **PowerShell 7 Setup Wizard**:
     - Click "Next" on Welcome screen
     - Accept license agreement → Click "Next"
     - Installation folder: Keep default → Click "Next"
     - Features: Check all options including:
       - "Add PowerShell to Path Environment Variable"
       - "Add 'Open here' context menus to Explorer"
       - "Enable PowerShell remoting"
     - Click "Install"
     - Click "Finish" when installation completes

   **Using PowerShell (Command Method)**:
   ```powershell
   # Download and install PowerShell 7 (latest version)
   $url = "https://github.com/PowerShell/PowerShell/releases/latest"
   $latestVersion = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content | Select-String -Pattern "v[0-9]+\.[0-9]+\.[0-9]+" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value
   $downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/$latestVersion/PowerShell-$($latestVersion.Substring(1,5))-win-x64.msi"
   Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile .\PowerShell7.msi
   Start-Process msiexec.exe -Wait -ArgumentList '/I PowerShell7.msi /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1'
   Remove-Item .\PowerShell7.msi
   ```

2. **Install PowerShell modules**:

   **Why This Step is Needed**: These modules provide essential cmdlets for Azure management, Azure Arc operations, HCI cluster management, and testing. Each module serves specific functions in the deployment and ongoing management.

   **Module Descriptions**:
   - **Az**: Core Azure PowerShell module for resource management
   - **Az.ConnectedMachine**: Manages Azure Arc-enabled servers
   - **Azure.Arc.Jumpstart.Common**: Common functions for JumpStart scenarios
   - **Azure.Arc.Jumpstart.LocalBox**: Specific LocalBox automation functions
   - **Microsoft.PowerShell.SecretManagement**: Secure credential storage
   - **Pester**: PowerShell testing framework for validation scripts
   - **Microsoft.WinGet.Client**: Programmatic access to Windows Package Manager
   - **Microsoft.WinGet.DSC**: Desired State Configuration integration

   **Using PowerShell (Command Method)**:
   ```powershell
   # Install required package providers
   Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
   Install-Module -Name Microsoft.PowerShell.PSResourceGet -Force
   
   # Install required PowerShell modules
   $modules = @(
       "Az",
       "Az.ConnectedMachine", 
       "Azure.Arc.Jumpstart.Common",
       "Azure.Arc.Jumpstart.LocalBox",
       "Microsoft.PowerShell.SecretManagement",
       "Pester",
       "Microsoft.WinGet.Client",
       "Microsoft.WinGet.DSC"
   )
   
   foreach ($module in $modules) {
       Write-Output "Installing module: $module"
       Install-PSResource -Name $module -Scope AllUsers -Quiet -AcceptLicense -TrustRepository
   }
   ```

   **Alternative GUI Method** (for individual modules):
   - Open PowerShell ISE or PowerShell 7 as Administrator
   - Use PowerShell Gallery website (https://www.powershellgallery.com/) to find specific modules
   - For each module, run: `Install-Module -Name [ModuleName] -Scope AllUsers -Force`

3. **Install essential tools using WinGet**:

   **Why This Step is Needed**: These tools provide comprehensive management, development, and troubleshooting capabilities for the Azure Local environment. WinGet ensures consistent, automated installation with proper versioning.

   **Tool Descriptions**:
   - **Git**: Version control for configuration management
   - **Visual Studio Code**: Advanced text editor for scripts and configs
   - **Azure CLI**: Command-line interface for Azure operations
   - **kubectl**: Kubernetes command-line tool for container management
   - **AzCopy**: High-performance file transfer for Azure Storage
   - **Helm**: Kubernetes package manager
   - **BGInfo**: System information display utility
   - **SQL Server Management Studio**: Database management tools
   - **Azure Data Studio**: Modern database tool for SQL Server

   **Using PowerShell (Command Method)**:
   ```powershell
   # Install WinGet packages for development and management tools
   $packages = @(
       "Git.Git",
       "Microsoft.VisualStudioCode",
       "Microsoft.AzureCLI",
       "Microsoft.PowerShell",
       "Kubernetes.kubectl",
       "Microsoft.Azure.AZCopy.10",
       "Helm.Helm",
       "Microsoft.Sysinternals.BGInfo",
       "Microsoft.SQLServerManagementStudio",
       "Microsoft.AzureDataStudio"
   )
   
   # Update WinGet to latest version
   Repair-WinGetPackageManager -AllUsers -Force -Latest
   
   foreach ($package in $packages) {
       Write-Output "Installing package: $package"
       winget install --id $package --silent --accept-package-agreements --accept-source-agreements
   }
   ```

4. **Download Windows Admin Center**:
   ```powershell
   # Download Windows Admin Center installer
   Invoke-WebRequest https://aka.ms/wacdownload -OutFile "C:\LocalBox\Windows Admin Center\WindowsAdminCenter.msi"
   ```

5. **Download configuration files and scripts**:
   ```powershell
   $templateBaseUrl = "https://raw.githubusercontent.com/microsoft/azure_arc/main/azure_jumpstart_localbox/"
   $configFiles = @{
       "artifacts/PowerShell/LocalBox-Config.psd1" = "C:\LocalBox\LocalBox-Config.psd1"
       "artifacts/azlocal.json" = "C:\LocalBox\azlocal.json"
       "artifacts/azlocal.parameters.json" = "C:\LocalBox\azlocal.parameters.json"
       "artifacts/PowerShell/dsc/packages.dsc.yml" = "C:\LocalBox\DSC\packages.dsc.yml"
       "artifacts/PowerShell/dsc/hyper-v.dsc.yml" = "C:\LocalBox\DSC\hyper-v.dsc.yml"
   }
   
   foreach ($file in $configFiles.GetEnumerator()) {
       Write-Output "Downloading: $($file.Key)"
       Invoke-WebRequest ($templateBaseUrl + $file.Key) -OutFile $file.Value
   }
   ```

6. **Configure Windows Defender exclusions for Hyper-V**:
   ```powershell
   # Add Hyper-V exclusions to Windows Defender
   $exclusionPaths = @(
       "C:\ClusterStorage",
       "C:\LocalBox\VHD",
       "V:\VMs",
       "C:\ProgramData\Microsoft\Windows\Hyper-V",
       "C:\Users\Public\Documents\Hyper-V\Virtual hard disks",
       "C:\ProgramData\Microsoft\Windows\Snapshots"
   )
   
   $exclusionExtensions = @(
       ".vhd", ".vhdx", ".avhd", ".avhdx", ".vsv", ".iso", ".rct", ".vmcx", ".vmrs"
   )
   
   $exclusionProcesses = @(
       "vmms.exe", "vmwp.exe", "vmcompute.exe"
   )
   
   foreach ($path in $exclusionPaths) {
       Add-MpPreference -ExclusionPath $path -Force
   }
   
   foreach ($extension in $exclusionExtensions) {
       Add-MpPreference -ExclusionExtension $extension -Force
   }
   
   foreach ($process in $exclusionProcesses) {
       Add-MpPreference -ExclusionProcess $process -Force
   }
   ```

## Setting Up Hyper-V

### Overview
Hyper-V is the virtualization platform that enables running nested virtual machines on the host system. This section installs Hyper-V role, configures optimal settings for nested virtualization, and prepares the hypervisor for hosting Azure Local cluster nodes and management VMs.

### Why This Step is Needed
- **Nested Virtualization**: Enables running VMs inside the Azure VM host, essential for Azure Local node simulation
- **Hardware Acceleration**: Provides hardware-assisted virtualization for better performance
- **Network Virtualization**: Enables creation of virtual switches and network isolation
- **Storage Virtualization**: Supports virtual hard disks and advanced storage features
- **Management Integration**: Integrates with Windows management tools and PowerShell

1. **Install Hyper-V and required Windows features**:

   **Why This Step is Needed**: Hyper-V role provides the virtualization engine, while additional features like Containers and VirtualMachinePlatform enable advanced scenarios and better compatibility.

   **Using Server Manager (GUI Method)**:
   - Open Server Manager
   - Click "Add roles and features"
   - **Add Roles and Features Wizard**:
     - Installation Type: Select "Role-based or feature-based installation" → Click "Next"
     - Server Selection: Select local server → Click "Next"
     - Server Roles: Check "Hyper-V" → Click "Add Features" when prompted → Click "Next"
     - Features: Check the following:
       - "Containers" 
       - "Virtual Machine Platform"
     - Click "Next" through remaining screens
     - Hyper-V page: Accept defaults → Click "Next"
     - Virtual Switches: Leave empty for now → Click "Next"
     - Migration: Accept defaults → Click "Next"  
     - Default Stores: Change to "V:\VMs" for both VM and VHD storage → Click "Next"
     - Confirmation: Check "Restart the destination server automatically if required"
     - Click "Install"
   - Server will restart automatically to complete installation

   **Using PowerShell (Command Method)**:
   ```powershell
   # Install Hyper-V role and management tools
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -All -NoRestart
   
   # Install additional required features
   Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
   Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All
   
   # Alternative method using DISM
   DISM /Online /Enable-Feature /All /FeatureName:Microsoft-Hyper-V /NoRestart
   DISM /Online /Enable-Feature /All /FeatureName:Containers /NoRestart
   
   # Restart the computer to complete installation
   Restart-Computer
   ```

2. **Configure Hyper-V settings after restart**:

   **Why This Step is Needed**: Configures default storage locations on the high-performance data disk and enables enhanced session mode for better VM interaction. Proper MAC address range prevents conflicts in nested environments.

   **Using Hyper-V Manager (GUI Method)**:
   - Open Hyper-V Manager (Start → Windows Administrative Tools → Hyper-V Manager)
   - Right-click the server name in left panel → Select "Hyper-V Settings"
   - **Hyper-V Settings Dialog**:
     - Virtual Hard Disks: Change location to "V:\VMs" → Click "Apply"
     - Virtual Machines: Change location to "V:\VMs" → Click "Apply" 
     - Enhanced Session Mode Policy: Check "Allow enhanced session mode" → Click "Apply"
     - User: Check "Use enhanced session mode" → Click "Apply"
     - MAC Address Range:
       - Minimum: 00-15-5D-01-0A-00
       - Maximum: 00-15-5D-01-0A-FF
     - Click "OK"

   **Using PowerShell (Command Method)**:
   ```powershell
   # Set default locations for VMs and VHDs
   Set-VMHost -VirtualHardDiskPath "V:\VMs" -VirtualMachinePath "V:\VMs"
   
   # Enable Enhanced Session Mode for better VM interaction
   Set-VMHost -EnableEnhancedSessionMode $true
   
   # Configure Hyper-V settings
   Get-VMHost | Set-VMHost -MacAddressMinimum "00-15-5D-01-0A-00" -MacAddressMaximum "00-15-5D-01-0A-FF"
   ```

3. **Verify Hyper-V installation**:

   **Why This Step is Needed**: Validation ensures all components are properly installed and services are running before proceeding with VM creation. This prevents issues during later deployment steps.

   **Using GUI Methods**:
   - **Check Windows Features**: 
     - Open "Turn Windows features on or off" (Control Panel → Programs → Turn Windows features on or off)
     - Verify "Hyper-V" is checked and expanded showing all sub-components
   - **Check Services**:
     - Open Services (services.msc)
     - Verify these services are running:
       - "Hyper-V Virtual Machine Management" (vmms)
       - "Hyper-V Host Compute Service" (vmcompute)
   - **Check Hyper-V Manager**:
     - Open Hyper-V Manager
     - Should show the local server with no errors

   **Using PowerShell (Command Method)**:
   ```powershell
   # Check if Hyper-V is properly installed
   Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
   
   # Check Hyper-V services are running
   Get-Service vmms, vmcompute
   
   # Verify Hyper-V PowerShell module is available
   Get-Module Hyper-V -ListAvailable
   ```

## Downloading Required VHDXs

### Overview
This section downloads the pre-configured VHDX (Virtual Hard Disk) files that serve as the foundation for the nested virtual machines. These files contain optimized Windows Server images specifically prepared for Azure Local deployments and management scenarios.

### Why This Step is Needed
- **Pre-configured Images**: VHDX files contain Windows Server installations optimized for Azure Local and management tasks
- **Time Savings**: Eliminates the need to install and configure Windows Server from scratch on multiple VMs
- **Consistency**: Ensures all VMs start from the same baseline configuration
- **Performance**: Images are optimized with proper drivers and settings for nested virtualization
- **Security**: Images include latest security updates and configurations
- **Compatibility**: Specifically tested and validated for Azure Local scenarios

1. **Install AzCopy (if not already installed via WinGet)**:

   **Why This Step is Needed**: AzCopy is a command-line utility optimized for high-speed Azure Storage transfers. It provides better performance, reliability, and progress reporting compared to standard download methods for large files like VHDXs.

   **Using Web Download (GUI Method)**:
   - Open web browser and navigate to: https://aka.ms/downloadazcopy-v10-windows
   - Download will start automatically (AzCopy.zip file)
   - Extract the zip file to a temporary folder
   - Copy azcopy.exe to C:\Windows\System32\ (requires administrator privileges)
   - Open Command Prompt and verify: `azcopy --version`

   **Using PowerShell (Command Method):**
   ```powershell
   # Download and install AzCopy manually if needed
   $uri = "https://aka.ms/downloadazcopy-v10-windows"
   $zipPath = "$env:TEMP\azcopy.zip"
   Invoke-WebRequest -Uri $uri -OutFile $zipPath
   Expand-Archive -Path $zipPath -DestinationPath "$env:TEMP\azcopy" -Force
   $azcopyPath = Get-ChildItem "$env:TEMP\azcopy" -Recurse -Name "azcopy.exe" | Select-Object -First 1
   Copy-Item "$env:TEMP\azcopy\$azcopyPath" -Destination "$env:SystemRoot\System32\azcopy.exe"
   ```

2. **Configure AzCopy for optimal performance**:

   **Why This Step is Needed**: These environment variables tune AzCopy for better performance when downloading large VHDX files by increasing buffer size and concurrent operations.

   **Using PowerShell (Command Method)**:
   ```powershell
   # Set environment variables for better AzCopy performance
   [System.Environment]::SetEnvironmentVariable('AZCOPY_BUFFER_GB', '4', [System.EnvironmentVariableTarget]::Process)
   [System.Environment]::SetEnvironmentVariable('AZCOPY_CONCURRENT_FILES', '10', [System.EnvironmentVariableTarget]::Process)
   ```

3. **Download Azure Local node VHDX**:

   **Why This Step is Needed**: This VHDX contains a specialized Azure Local (Azure Stack HCI) installation that includes all necessary drivers, services, and configurations for cluster nodes. The checksum verification ensures file integrity after download.

   **VHDX Details**:
   - **File**: AzLocal2507.vhdx (approximately 10GB)
   - **Purpose**: Azure Local cluster node base image
   - **Contents**: Windows Server with Azure Local services pre-installed
   - **Optimization**: Configured for nested virtualization and cluster operations

   **Using PowerShell (Command Method)**:
   ```powershell
   # Download the Azure Local node VHDX (approximately 10GB)
   Write-Output "Downloading Azure Local node VHDX files..."
   azcopy cp 'https://jumpstartprodsg.blob.core.windows.net/jslocal/localbox/prod/AzLocal2507.vhdx' "C:\LocalBox\VHD\AzL-node.vhdx" --check-length=false --log-level=ERROR
   
   # Download checksum file
   azcopy cp 'https://jumpstartprodsg.blob.core.windows.net/jslocal/localbox/prod/AzLocal2507.sha256' "C:\LocalBox\VHD\AzL-node.sha256" --check-length=false --log-level=ERROR
   
   # Verify file integrity
   $checksum = Get-FileHash -Path "C:\LocalBox\VHD\AzL-node.vhdx" -Algorithm SHA256
   $expectedHash = Get-Content -Path "C:\LocalBox\VHD\AzL-node.sha256"
   
   if ($checksum.Hash -eq $expectedHash) {
       Write-Output "Azure Local node VHDX checksum verified successfully"
   } else {
       Write-Error "Azure Local node VHDX checksum verification failed"
       throw "File integrity check failed"
   }
   ```

4. **Download Windows Server GUI VHDX**:

   **Why This Step is Needed**: This VHDX provides a full Windows Server installation with desktop experience for management VMs, domain controllers, and router VMs. It includes GUI tools essential for administration and troubleshooting.

   **VHDX Details**:
   - **File**: WinServerApril2024.vhdx (approximately 12GB)
   - **Purpose**: Management VM, domain controller, and router base image
   - **Contents**: Windows Server 2022 with desktop experience
   - **Features**: Full GUI, management tools, and administrative utilities

   **Using PowerShell (Command Method)**:
   ```powershell
   # Download Windows Server VHDX for management VMs
   Write-Output "Downloading Windows Server GUI VHDX files..."
   azcopy cp 'https://jumpstartprodsg.blob.core.windows.net/hcibox23h2/WinServerApril2024.vhdx' "C:\LocalBox\VHD\GUI.vhdx" --check-length=false --log-level=ERROR
   
   # Download checksum file
   azcopy cp 'https://jumpstartprodsg.blob.core.windows.net/hcibox23h2/WinServerApril2024.sha256' "C:\LocalBox\VHD\GUI.sha256" --check-length=false --log-level=ERROR
   
   # Verify file integrity
   $checksum = Get-FileHash -Path "C:\LocalBox\VHD\GUI.vhdx" -Algorithm SHA256
   $expectedHash = Get-Content -Path "C:\LocalBox\VHD\GUI.sha256"
   
   if ($checksum.Hash -eq $expectedHash) {
       Write-Output "Windows Server GUI VHDX checksum verified successfully"
   } else {
       Write-Error "Windows Server GUI VHDX checksum verification failed"
       throw "File integrity check failed"
   }
   ```

   **Manual Download Alternative**:
   - Open web browser and navigate to the download URL (not recommended due to file size)
   - Use download manager software for better reliability
   - Verify checksum manually using certutil: `certutil -hashfile GUI.vhdx SHA256`

5. **Copy VHDX files to VM storage location**:

   **Why This Step is Needed**: Moves the verified VHDX files to the high-performance data disk location where VMs will be created. This separation keeps working VM files on the optimized storage while preserving originals for future use.

   **Using File Explorer (GUI Method)**:
   - Open File Explorer and navigate to C:\LocalBox\VHD
   - Select GUI.vhdx and copy (Ctrl+C)
   - Navigate to V:\VMs and paste (Ctrl+V)
   - Repeat for AzL-node.vhdx
   - This may take several minutes due to file sizes

   **Using PowerShell (Command Method)**:
   ```powershell
   # Copy the verified VHDX files to the VM storage directory
   Copy-Item -Path "C:\LocalBox\VHD\GUI.vhdx" -Destination "V:\VMs\GUI.vhdx" -Force
   Copy-Item -Path "C:\LocalBox\VHD\AzL-node.vhdx" -Destination "V:\VMs\AzL-node.vhdx" -Force
   
   Write-Output "VHDX files copied to V:\VMs directory"
   ```

## Creating Virtual Networks

### Overview
This section creates the virtual network infrastructure required for the nested VM environment. The network design includes internal switches for VM management, NAT configuration for internet access, and proper IP addressing schemes that enable communication between all components while maintaining isolation from the host network.

### Why This Step is Needed
- **Network Isolation**: Creates separate network segments for different types of traffic (management, storage, internet)
- **Internet Connectivity**: NAT configuration enables nested VMs to access external resources for updates and Azure connectivity
- **IP Management**: Establishes consistent IP addressing scheme for predictable network configuration
- **Security**: Isolates nested VM traffic from the host network while allowing controlled access
- **Performance**: Dedicated network paths optimize traffic flow between cluster components

1. **Create the Internal Switch for VM management network**:

   **Why This Step is Needed**: The internal switch provides the primary management network for all nested VMs. This network carries domain authentication traffic, management commands, and cluster communication.

   **Network Design**:
   - **Switch Name**: InternalSwitch
   - **Network Range**: 192.168.1.0/24
   - **Host IP**: 192.168.1.20
   - **DNS Server**: 192.168.1.254 (Domain Controller)
   - **Purpose**: VM management and domain traffic

   **Using Hyper-V Manager (GUI Method)**:
   - Open Hyper-V Manager
   - Right-click the server name → Select "Virtual Switch Manager"
   - **Virtual Switch Manager**:
     - Select "Internal" in the left panel
     - Click "Create Virtual Switch"
     - Name: "InternalSwitch"
     - Connection type: Internal network
     - Click "OK"
   - **Configure IP Address**:
     - Open Network and Sharing Center
     - Click "Change adapter settings"
     - Right-click "vEthernet (InternalSwitch)" → Properties
     - Select "Internet Protocol Version 4 (TCP/IPv4)" → Properties
     - Select "Use the following IP address":
       - IP address: 192.168.1.20
       - Subnet mask: 255.255.255.0
       - Default gateway: (leave blank)
     - Select "Use the following DNS server addresses":
       - Preferred DNS server: 192.168.1.254
     - Click "OK" twice

   **Using PowerShell (Command Method)**:
   ```powershell
   # Create internal virtual switch for VM management traffic
   New-VMSwitch -Name "InternalSwitch" -SwitchType Internal
   
   # Get the network adapter for the internal switch
   $adapter = Get-NetAdapter | Where-Object Name -like "*InternalSwitch*"
   
   # Configure static IP address on the host for the internal network
   New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress 192.168.1.20 -PrefixLength 24
   
   # Set DNS server (will point to domain controller later)
   Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses 192.168.1.254
   ```

2. **Create the NAT Switch for internet access**:

   **Why This Step is Needed**: The NAT switch provides internet connectivity for nested VMs while maintaining network isolation. This is essential for downloading updates, accessing Azure services, and performing Arc registration.

   **Network Design**:
   - **Switch Name**: InternalNAT  
   - **Network Range**: 192.168.46.0/24
   - **Host IP**: 192.168.46.1
   - **Purpose**: Internet access via NAT

   **Using Hyper-V Manager and Network Settings (GUI Method)**:
   - **Create Switch**:
     - Open Hyper-V Manager → Virtual Switch Manager
     - Select "Internal" → Click "Create Virtual Switch"
     - Name: "InternalNAT"
     - Connection type: Internal network → Click "OK"
   - **Configure IP Address**:
     - Open Network and Sharing Center → Change adapter settings
     - Right-click "vEthernet (InternalNAT)" → Properties
     - Select "Internet Protocol Version 4 (TCP/IPv4)" → Properties
     - Select "Use the following IP address":
       - IP address: 192.168.46.1
       - Subnet mask: 255.255.255.0
     - Click "OK" twice
   - **Create NAT Network**:
     - Open PowerShell as Administrator
     - Run: `New-NetNat -Name "LocalBoxNAT" -InternalIPInterfaceAddressPrefix 192.168.46.0/24`

   **Using PowerShell (Command Method)**:
   ```powershell
   # Create another internal switch for NAT network
   New-VMSwitch -Name "InternalNAT" -SwitchType Internal
   
   # Get the NAT adapter
   $natAdapter = Get-NetAdapter | Where-Object Name -like "*InternalNAT*"
   
   # Configure IP address for NAT network
   New-NetIPAddress -InterfaceIndex $natAdapter.InterfaceIndex -IPAddress 192.168.46.1 -PrefixLength 24
   
   # Create NAT network for internet access from nested VMs
   New-NetNat -Name "LocalBoxNAT" -InternalIPInterfaceAddressPrefix 192.168.46.0/24
   ```

3. **Verify network configuration**:

   **Why This Step is Needed**: Validation ensures all network components are properly configured before creating VMs. This prevents connectivity issues that would be difficult to troubleshoot later.

   **Using Network and Sharing Center (GUI Method)**:
   - Open Network and Sharing Center
   - Click "Change adapter settings"
   - Verify you see:
     - "vEthernet (InternalSwitch)" with status "Connected" and IP 192.168.1.20
     - "vEthernet (InternalNAT)" with status "Connected" and IP 192.168.46.1
   - **Test NAT Configuration**:
     - Open Command Prompt as Administrator
     - Run: `route print` to verify routes exist
     - Run: `netsh interface ipv4 show addresses` to verify IP assignments

   **Using Hyper-V Manager (GUI Method)**:
   - Open Hyper-V Manager
   - Expand server name and click "Virtual Switch Manager"
   - Verify two internal switches exist:
     - InternalSwitch (Internal network)
     - InternalNAT (Internal network)

   **Using PowerShell (Command Method)**:
   ```powershell
   # Check virtual switches
   Get-VMSwitch
   
   # Check IP configuration
   Get-NetIPAddress | Where-Object InterfaceAlias -like "*vEthernet*"
   
   # Check NAT configuration
   Get-NetNat
   ```

4. **Configure network adapter settings**:

   **Why This Step is Needed**: Proper adapter naming and performance settings optimize network traffic flow and make troubleshooting easier. Jumbo frames can improve performance for storage and cluster traffic.

   **Using Network Adapter Properties (GUI Method)**:
   - Open Network and Sharing Center → Change adapter settings
   - **Rename Adapters** (for clarity):
     - Right-click "vEthernet (InternalSwitch)" → Rename → "vEthernet (InternalSwitch)"
     - Right-click "vEthernet (InternalNAT)" → Rename → "vEthernet (InternalNAT)"
   - **Configure Jumbo Frames** (optional, for performance):
     - Right-click "vEthernet (InternalSwitch)" → Properties
     - Click "Configure" → "Advanced" tab
     - Find "Jumbo Packet" or "Jumbo Frame" → Set to "9014 Bytes"
     - Click "OK"

   **Using PowerShell (Command Method)**:
   ```powershell
   # Rename network adapters for clarity
   $internalAdapter = Get-NetAdapter | Where-Object Name -like "*InternalSwitch*"
   $natAdapter = Get-NetAdapter | Where-Object Name -like "*InternalNAT*"
   
   Rename-NetAdapter -Name $internalAdapter.Name -NewName "vEthernet (InternalSwitch)"
   Rename-NetAdapter -Name $natAdapter.Name -NewName "vEthernet (InternalNAT)"
   
   # Enable jumbo frames for better performance (optional)
   Set-NetAdapterAdvancedProperty -Name "vEthernet (InternalSwitch)" -DisplayName "Jumbo Packet" -DisplayValue "9014 Bytes"
   ```

## Creating and Configuring Nested VMs

### Overview
This section creates the virtual machines that will host the Azure Local cluster nodes and management services. The VM configuration includes proper resource allocation, network connectivity, and security settings required for nested virtualization and Azure Local deployment.

### Why This Step is Needed
- **Azure Local Cluster Nodes**: Creates the VMs that will form the Azure Local cluster for hybrid cloud scenarios
- **Management Infrastructure**: Provides centralized management, domain services, and administrative access
- **Resource Optimization**: Ensures VMs have sufficient resources for Azure Local operations while maximizing host utilization
- **Security Configuration**: Implements TPM, Secure Boot, and other security features required for modern workloads
- **Network Integration**: Connects VMs to the management network for proper communication

### VM Architecture Overview
- **AzLMGMT**: Management VM hosting domain controller, router, and administrative tools
- **AzLHOST1**: First Azure Local cluster node with maximum resources
- **AzLHOST2**: Second Azure Local cluster node with same configuration as AzLHOST1

1. **Set up credentials for VM management**:

   **Why This Step is Needed**: Establishes secure credential objects for automated VM configuration and management. Domain credentials will be used after VMs join the domain, while local credentials are needed during initial setup.

   **Security Considerations**:
   - Use complex passwords with at least 12 characters
   - Include uppercase, lowercase, numbers, and special characters
   - Consider using Azure Key Vault for production environments
   - Rotate passwords regularly in production scenarios

   **Using PowerShell (Command Method)**:
   ```powershell
   # Define the password for all VMs (use a strong password)
   $adminPassword = "YourSecurePassword123!"
   $securePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
   
   # Create local credential object (will be used before domain join)
   $localCred = New-Object System.Management.Automation.PSCredential("Administrator", $securePassword)
   
   # Create domain credential object (will be used after domain join)
   $domainCred = New-Object System.Management.Automation.PSCredential("jumpstart\Administrator", $securePassword)
   ```

2. **Create Management VM (AzLMGMT)**:

   **Why This Step is Needed**: The management VM serves as the central administration point for the environment, hosting the domain controller, router VM, and management tools. It requires substantial resources to run nested VMs and provide management services.

   **VM Specifications**:
   - **Purpose**: Central management, domain controller host, administrative access point
   - **Memory**: 28GB (dynamic allocation 8GB-32GB) to support nested VMs
   - **Processors**: 20 cores for hosting multiple nested VMs
   - **Storage**: Uses Windows Server GUI VHDX for full management capabilities
   - **Network**: Connected to InternalSwitch for management traffic
   - **Special Features**: Nested virtualization enabled, TPM and Secure Boot configured

   **Using Hyper-V Manager (GUI Method)**:
   - Open Hyper-V Manager
   - Right-click server name → "New" → "Virtual Machine"
   - **New Virtual Machine Wizard**:
     - **Before You Begin**: Click "Next"
     - **Specify Name and Location**: 
       - Name: "AzLMGMT"
       - Location: Browse to "V:\VMs\AzLMGMT" (create folder if needed)
       - Click "Next"
     - **Specify Generation**: Select "Generation 2" → Click "Next"
     - **Assign Memory**: 
       - Startup memory: 28672 MB (28GB)
       - Check "Use Dynamic Memory for this virtual machine"
       - Click "Next"
     - **Configure Networking**: Select "InternalSwitch" → Click "Next"
     - **Connect Virtual Hard Disk**:
       - Select "Use an existing virtual hard disk"
       - Browse to "V:\VMs\GUI.vhdx" and copy it to "V:\VMs\AzLMGMT\AzLMGMT.vhdx"
       - Click "Next"
     - **Summary**: Click "Finish"
   - **Configure VM Settings**:
     - Right-click "AzLMGMT" → "Settings"
     - **Processor**: Set number of virtual processors to 20
     - **Memory**: 
       - Minimum RAM: 8192 MB
       - Maximum RAM: 32768 MB
       - Check "Enable Dynamic Memory"
     - **Network Adapter**: 
       - Advanced Features → MAC Address → Static: 00-15-5D-01-0A-11
     - **Security**: 
       - Check "Enable Trusted Platform Module"
       - Template: Microsoft Windows (for Secure Boot)
     - **Processor → Compatibility**: 
       - Check "Expose virtualization extensions to this virtual machine"
     - **Management**: 
       - Check "Disable checkpoints"
     - Click "OK"

   **Using PowerShell (Command Method)**:
   ```powershell
   # Create the management VM
   $vmName = "AzLMGMT"
   $vmPath = "V:\VMs\$vmName"
   $vhdPath = "$vmPath\$vmName.vhdx"
   
   # Create VM directory
   New-Item -Path $vmPath -ItemType Directory -Force
   
   # Copy GUI VHDX for management VM
   Copy-Item -Path "V:\VMs\GUI.vhdx" -Destination $vhdPath
   
   # Create the VM
   New-VM -Name $vmName -MemoryStartupBytes 28GB -Path $vmPath -VHDPath $vhdPath -Generation 2 -Switch "InternalSwitch"
   
   # Configure VM settings
   Set-VM -Name $vmName -ProcessorCount 20 -DynamicMemory -MemoryMinimumBytes 8GB -MemoryMaximumBytes 32GB
   Set-VM -Name $vmName -CheckpointType Disabled
   
   # Set static MAC address
   Set-VMNetworkAdapter -VMName $vmName -StaticMacAddress "00155D010A11"
   
   # Enable nested virtualization (required for this VM to run Hyper-V)
   Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true
   
   # Configure secure boot and TPM
   Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
   Enable-VMTPM -VMName $vmName
   
   # Start the VM
   Start-VM -Name $vmName
   ```

3. **Create first Azure Local node VM (AzLHOST1)**:

   **Why This Step is Needed**: AzLHOST1 is the first node in the Azure Local cluster. It requires maximum available resources to simulate a physical Azure Local node and support cluster operations, storage spaces direct, and workload VMs.

   **VM Specifications**:
   - **Purpose**: Primary Azure Local cluster node
   - **Memory**: Up to 96GB or 40% of host memory (whichever is less) - static allocation for cluster stability
   - **Processors**: Maximum available minus 4 cores (reserved for host and management VM)
   - **Storage**: Uses Azure Local node VHDX with pre-configured HCI services
   - **Network**: Connected to InternalSwitch for cluster and management traffic
   - **Requirements**: Nested virtualization, TPM, Secure Boot for Azure Local compliance

   **Resource Allocation Logic**:
   - Memory: Uses up to 40% of host memory to leave resources for host OS and management VM
   - CPU: Uses most available cores but reserves some for host stability
   - Static memory allocation ensures consistent performance for cluster operations

   **Using Hyper-V Manager (GUI Method)**:
   - Follow similar steps as AzLMGMT creation but with these differences:
   - **Specify Name and Location**: Name: "AzLHOST1", Location: "V:\VMs\AzLHOST1"
   - **Assign Memory**: Calculate 40% of total system memory or 96GB maximum
   - **Connect Virtual Hard Disk**: Use copy of "AzL-node.vhdx"
   - **Processor**: Set to maximum available minus 4
   - **Memory**: Use static memory allocation (uncheck Dynamic Memory)
   - **Network Adapter**: MAC Address: 00-15-5D-01-0A-12
   - Enable nested virtualization, TPM, and Secure Boot as with AzLMGMT

   **Using PowerShell (Command Method)**:
   ```powershell
   # Create first Azure Local cluster node
   $vmName = "AzLHOST1"
   $vmPath = "V:\VMs\$vmName"
   $vhdPath = "$vmPath\$vmName.vhdx"
   
   # Create VM directory
   New-Item -Path $vmPath -ItemType Directory -Force
   
   # Copy Azure Local node VHDX
   Copy-Item -Path "V:\VMs\AzL-node.vhdx" -Destination $vhdPath
   
   # Create the VM with maximum available resources
   $availableMemory = (Get-WmiObject -Class Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
   $vmMemory = [Math]::Min(96GB, ($availableMemory * 0.4))  # Use up to 40% of available memory, max 96GB
   
   New-VM -Name $vmName -MemoryStartupBytes $vmMemory -Path $vmPath -VHDPath $vhdPath -Generation 2 -Switch "InternalSwitch"
   
   # Configure VM with maximum processor count
   $processorCount = [Math]::Min(32, (Get-WmiObject Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum - 4)
   Set-VM -Name $vmName -ProcessorCount $processorCount -StaticMemory
   Set-VM -Name $vmName -CheckpointType Disabled
   
   # Set static MAC address
   Set-VMNetworkAdapter -VMName $vmName -StaticMacAddress "00155D010A12"
   
   # Enable nested virtualization (critical for Azure Local nodes)
   Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true
   
   # Configure secure boot and TPM
   Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
   Enable-VMTPM -VMName $vmName
   
   # Start the VM
   Start-VM -Name $vmName
   ```

4. **Create second Azure Local node VM (AzLHOST2)**:
   ```powershell
   # Create second Azure Local cluster node
   $vmName = "AzLHOST2"
   $vmPath = "V:\VMs\$vmName"
   $vhdPath = "$vmPath\$vmName.vhdx"
   
   # Create VM directory
   New-Item -Path $vmPath -ItemType Directory -Force
   
   # Copy Azure Local node VHDX
   Copy-Item -Path "V:\VMs\AzL-node.vhdx" -Destination $vhdPath
   
   # Create the VM with same settings as AzLHOST1
   New-VM -Name $vmName -MemoryStartupBytes $vmMemory -Path $vmPath -VHDPath $vhdPath -Generation 2 -Switch "InternalSwitch"
   
   Set-VM -Name $vmName -ProcessorCount $processorCount -StaticMemory
   Set-VM -Name $vmName -CheckpointType Disabled
   
   # Set different static MAC address
   Set-VMNetworkAdapter -VMName $vmName -StaticMacAddress "00155D010A13"
   
   # Enable nested virtualization
   Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true
   
   # Configure secure boot and TPM
   Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
   Enable-VMTPM -VMName $vmName
   
   # Start the VM
   Start-VM -Name $vmName
   ```

5. **Configure VM Network Settings**:
   ```powershell
   # Wait for VMs to boot (allow 5-10 minutes)
   Write-Output "Waiting for VMs to boot up completely..."
   Start-Sleep -Seconds 300
   
   # Configure networking on AzLMGMT
   Invoke-Command -VMName "AzLMGMT" -Credential $localCred -ScriptBlock {
       # Rename network adapter
       Get-NetAdapter | Rename-NetAdapter -NewName "MGMT"
       
       # Configure static IP
       New-NetIPAddress -InterfaceAlias "MGMT" -IPAddress 192.168.1.11 -PrefixLength 24 -DefaultGateway 192.168.1.1
       Set-DnsClientServerAddress -InterfaceAlias "MGMT" -ServerAddresses 192.168.1.254
   }
   
   # Configure networking on AzLHOST1
   Invoke-Command -VMName "AzLHOST1" -Credential $localCred -ScriptBlock {
       # Rename network adapter
       Get-NetAdapter | Rename-NetAdapter -NewName "MGMT"
       
       # Configure static IP
       New-NetIPAddress -InterfaceAlias "MGMT" -IPAddress 192.168.1.12 -PrefixLength 24 -DefaultGateway 192.168.1.1
       Set-DnsClientServerAddress -InterfaceAlias "MGMT" -ServerAddresses 192.168.1.254
   }
   
   # Configure networking on AzLHOST2
   Invoke-Command -VMName "AzLHOST2" -Credential $localCred -ScriptBlock {
       # Rename network adapter
       Get-NetAdapter | Rename-NetAdapter -NewName "MGMT"
       
       # Configure static IP
       New-NetIPAddress -InterfaceAlias "MGMT" -IPAddress 192.168.1.13 -PrefixLength 24 -DefaultGateway 192.168.1.1
       Set-DnsClientServerAddress -InterfaceAlias "MGMT" -ServerAddresses 192.168.1.254
   }
   ```

6. **Verify VM creation and network connectivity**:
   ```powershell
   # Check VM status
   Get-VM | Select-Object Name, State, CPUUsage, MemoryMB
   
   # Test network connectivity between VMs (after network configuration)
   Test-NetConnection -ComputerName 192.168.1.11 -Port 5985  # AzLMGMT
   Test-NetConnection -ComputerName 192.168.1.12 -Port 5985  # AzLHOST1
   Test-NetConnection -ComputerName 192.168.1.13 -Port 5985  # AzLHOST2
   ```

## Configuring the Domain Controller

1. **Create Domain Controller VM on AzLMGMT**:
   ```powershell
   # Connect to the management VM and create the domain controller VM inside it
   Invoke-Command -VMName "AzLMGMT" -Credential $localCred -ScriptBlock {
       # Create the domain controller VM inside AzLMGMT
       $dcVmName = "jumpstartdc"
       $dcVmPath = "C:\VMs\$dcVmName"
       $dcVhdPath = "$dcVmPath\$dcVmName.vhdx"
       
       # Create VM directory
       New-Item -Path $dcVmPath -ItemType Directory -Force
       
       # Copy GUI VHDX for domain controller
       Copy-Item -Path "C:\VMs\GUI.vhdx" -Destination $dcVhdPath
       
       # Create the domain controller VM
       New-VM -Name $dcVmName -MemoryStartupBytes 2GB -Path $dcVmPath -VHDPath $dcVhdPath -Generation 2 -Switch "InternalSwitch"
       
       # Configure VM settings
       Set-VM -Name $dcVmName -ProcessorCount 2 -StaticMemory
       Set-VM -Name $dcVmName -CheckpointType Disabled
       
       # Set static MAC address
       Set-VMNetworkAdapter -VMName $dcVmName -StaticMacAddress "00155D010DCE"
       
       # Configure secure boot and TPM
       Set-VMFirmware -VMName $dcVmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
       Enable-VMTPM -VMName $dcVmName
       
       # Start the VM
       Start-VM -Name $dcVmName
   }
   ```

2. **Configure Domain Controller networking**:
   ```powershell
   # Wait for DC VM to boot
   Start-Sleep -Seconds 180
   
   # Configure DC networking
   Invoke-Command -VMName "AzLMGMT" -Credential $localCred -ScriptBlock {
       Invoke-Command -VMName "jumpstartdc" -Credential $using:localCred -ScriptBlock {
           # Configure static IP for domain controller
           Get-NetAdapter | Rename-NetAdapter -NewName "DC"
           New-NetIPAddress -InterfaceAlias "DC" -IPAddress 192.168.1.254 -PrefixLength 24 -DefaultGateway 192.168.1.1
           Set-DnsClientServerAddress -InterfaceAlias "DC" -ServerAddresses 192.168.1.254
       }
   }
   ```

3. **Install Active Directory Domain Services**:
   ```powershell
   # Install AD DS role on the domain controller
   Invoke-Command -VMName "AzLMGMT" -Credential $localCred -ScriptBlock {
       Invoke-Command -VMName "jumpstartdc" -Credential $using:localCred -ScriptBlock {
           # Install AD DS role and management tools
           Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
           
           # Install DNS Server role
           Install-WindowsFeature -Name DNS -IncludeManagementTools
           
           # Import ADDSDeployment module
           Import-Module ADDSDeployment
       }
   }
   ```

4. **Promote server to Domain Controller**:
   ```powershell
   # Promote the server to domain controller
   Invoke-Command -VMName "AzLMGMT" -Credential $localCred -ScriptBlock {
       Invoke-Command -VMName "jumpstartdc" -Credential $using:localCred -ScriptBlock {
           $domainName = "jumpstart.local"
           $netbiosName = "JUMPSTART"
           $dsrmPassword = ConvertTo-SecureString "YourDSRMPassword123!" -AsPlainText -Force
           
           # Create new forest and domain
           Install-ADDSForest `
               -DomainName $domainName `
               -DomainNetbiosName $netbiosName `
               -SafeModeAdministratorPassword $dsrmPassword `
               -InstallDNS `
               -Force `
               -NoRebootOnCompletion:$false
       }
   }
   ```

5. **Wait for domain controller restart and verify installation**:
   ```powershell
   # Wait for DC to restart after promotion (this can take 10-15 minutes)
   Write-Output "Waiting for Domain Controller to restart and complete AD DS installation..."
   Start-Sleep -Seconds 900
   
   # Verify domain controller is operational
   Invoke-Command -VMName "AzLMGMT" -Credential $localCred -ScriptBlock {
       # Test domain connectivity
       do {
           Start-Sleep -Seconds 30
           $dcStatus = Test-NetConnection -ComputerName "jumpstartdc" -Port 389
           Write-Output "Waiting for DC to be ready... Status: $($dcStatus.TcpTestSucceeded)"
       } while (-not $dcStatus.TcpTestSucceeded)
       
       # Verify AD services are running
       Invoke-Command -VMName "jumpstartdc" -Credential $using:domainCred -ScriptBlock {
           Get-Service | Where-Object {$_.Name -in @("ADWS", "DNS", "KDC", "Netlogon")} | Select-Object Name, Status
           
           # Create an OU for cluster computers
           try {
               New-ADOrganizationalUnit -Name "AzureLocal" -Path "DC=jumpstart,DC=local"
               Write-Output "Created AzureLocal OU successfully"
           }
           catch {
               Write-Output "OU creation failed or already exists: $($_.Exception.Message)"
           }
       }
   }
   ```

6. **Configure DNS forwarders**:
   ```powershell
   # Configure DNS forwarders for internet name resolution
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       Invoke-Command -VMName "jumpstartdc" -Credential $using:domainCred -ScriptBlock {
           # Add DNS forwarders
           Add-DnsServerForwarder -IPAddress 8.8.8.8, 8.8.4.4
           
           # Verify DNS configuration
           Get-DnsServerForwarder
           Get-DnsServerZone
       }
   }
   ```

## Configuring the Router VM

1. **Create Router VM on AzLMGMT**:
   ```powershell
   # Create the router VM inside AzLMGMT
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       $routerVmName = "vm-router"
       $routerVmPath = "C:\VMs\$routerVmName"
       $routerVhdPath = "$routerVmPath\$routerVmName.vhdx"
       
       # Create VM directory
       New-Item -Path $routerVmPath -ItemType Directory -Force
       
       # Copy GUI VHDX for router
       Copy-Item -Path "C:\VMs\GUI.vhdx" -Destination $routerVhdPath
       
       # Create the router VM
       New-VM -Name $routerVmName -MemoryStartupBytes 2GB -Path $routerVmPath -VHDPath $routerVhdPath -Generation 2 -Switch "InternalSwitch"
       
       # Configure VM settings
       Set-VM -Name $routerVmName -ProcessorCount 2 -StaticMemory
       Set-VM -Name $routerVmName -CheckpointType Disabled
       
       # Set static MAC address
       Set-VMNetworkAdapter -VMName $routerVmName -StaticMacAddress "00155D010B01"
       
       # Configure secure boot and TPM
       Set-VMFirmware -VMName $routerVmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
       Enable-VMTPM -VMName $routerVmName
       
       # Start the VM
       Start-VM -Name $routerVmName
   }
   ```

2. **Configure Router VM networking**:
   ```powershell
   # Wait for router VM to boot
   Start-Sleep -Seconds 180
   
   # Configure router networking
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       Invoke-Command -VMName "vm-router" -Credential $using:localCred -ScriptBlock {
           # Configure static IP for router
           Get-NetAdapter | Rename-NetAdapter -NewName "MGMT"
           New-NetIPAddress -InterfaceAlias "MGMT" -IPAddress 192.168.1.1 -PrefixLength 24
           Set-DnsClientServerAddress -InterfaceAlias "MGMT" -ServerAddresses 192.168.1.254
           
           # Enable IP forwarding
           Set-NetIPInterface -InterfaceAlias "MGMT" -Forwarding Enabled
       }
   }
   ```

3. **Install and configure Routing and Remote Access**:
   ```powershell
   # Install RRAS role on router
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       Invoke-Command -VMName "vm-router" -Credential $using:localCred -ScriptBlock {
           # Install Remote Access role with Routing
           Install-WindowsFeature -Name RemoteAccess -IncludeManagementTools
           Install-WindowsFeature -Name Routing -IncludeManagementTools
           
           # Import RemoteAccess module
           Import-Module RemoteAccess
       }
   }
   ```

4. **Configure RRAS for NAT and routing**:
   ```powershell
   # Configure RRAS
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       Invoke-Command -VMName "vm-router" -Credential $using:localCred -ScriptBlock {
           # Install and configure RRAS
           Install-RemoteAccess -VpnType Vpn
           
           # Configure NAT
           $externalInterface = Get-NetAdapter -Name "MGMT"
           
           # Configure routing protocols
           netsh routing ip nat install
           netsh routing ip nat add interface name="MGMT" mode=full
           
           # Enable RRAS service
           Set-Service -Name RemoteAccess -StartupType Automatic
           Start-Service RemoteAccess
           
           # Configure static routes if needed
           New-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceAlias "MGMT" -NextHop 192.168.1.20
       }
   }
   ```

5. **Verify router configuration**:
   ```powershell
   # Test router functionality
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       # Test connectivity from management VM through router
       Test-NetConnection -ComputerName 8.8.8.8 -Port 53
       
       # Verify routing table
       Get-NetRoute | Where-Object DestinationPrefix -eq "0.0.0.0/0"
       
       # Check RRAS status
       Invoke-Command -VMName "vm-router" -Credential $using:localCred -ScriptBlock {
           Get-Service RemoteAccess
           Get-RemoteAccessConnectionStatistics
       }
   }
   ```

## Setting Up Azure Local Cluster

1. **Join all VMs to the domain**:
   ```powershell
   # Join AzLMGMT to domain
   Invoke-Command -VMName "AzLMGMT" -Credential $localCred -ScriptBlock {
       # Set DNS to point to domain controller
       Set-DnsClientServerAddress -InterfaceAlias "MGMT" -ServerAddresses 192.168.1.254
       
       # Join domain
       Add-Computer -DomainName "jumpstart.local" -Credential $using:domainCred -Restart -Force
   }
   
   # Wait for AzLMGMT to restart
   Start-Sleep -Seconds 120
   
   # Join AzLHOST1 to domain
   Invoke-Command -VMName "AzLHOST1" -Credential $localCred -ScriptBlock {
       Set-DnsClientServerAddress -InterfaceAlias "MGMT" -ServerAddresses 192.168.1.254
       Add-Computer -DomainName "jumpstart.local" -Credential $using:domainCred -Restart -Force
   }
   
   # Join AzLHOST2 to domain
   Invoke-Command -VMName "AzLHOST2" -Credential $localCred -ScriptBlock {
       Set-DnsClientServerAddress -InterfaceAlias "MGMT" -ServerAddresses 192.168.1.254
       Add-Computer -DomainName "jumpstart.local" -Credential $using:domainCred -Restart -Force
   }
   
   # Wait for all VMs to restart and join domain
   Write-Output "Waiting for VMs to restart and complete domain join..."
   Start-Sleep -Seconds 300
   ```

2. **Install required roles and features on Azure Local nodes**:
   ```powershell
   # Install Hyper-V and Failover Clustering on both nodes
   $nodeNames = @("AzLHOST1", "AzLHOST2")
   
   foreach ($nodeName in $nodeNames) {
       Invoke-Command -VMName $nodeName -Credential $domainCred -ScriptBlock {
           # Install required Windows features
           $features = @(
               "Hyper-V",
               "Hyper-V-PowerShell", 
               "Failover-Clustering",
               "RSAT-Clustering-PowerShell",
               "RSAT-Clustering-CmdInterface",
               "BitLocker"
           )
           
           foreach ($feature in $features) {
               Install-WindowsFeature -Name $feature -IncludeManagementTools
           }
           
           # Restart to complete feature installation
           Restart-Computer -Force
       }
   }
   
   # Wait for nodes to restart
   Start-Sleep -Seconds 180
   ```

3. **Configure storage and networking on Azure Local nodes**:
   ```powershell
   # Configure storage disks on both nodes
   foreach ($nodeName in $nodeNames) {
       Invoke-Command -VMName $nodeName -Credential $domainCred -ScriptBlock {
           # Create storage pool from available disks
           $disks = Get-PhysicalDisk -CanPool $true
           if ($disks.Count -gt 0) {
               New-StoragePool -FriendlyName "S2DPool" -StorageSubSystemFriendlyName "*Spaces*" -PhysicalDisks $disks
               
               # Create virtual disks for storage
               New-VirtualDisk -StoragePoolFriendlyName "S2DPool" -FriendlyName "S2DDisk1" -Size 100GB -ResiliencySettingName Simple
               New-VirtualDisk -StoragePoolFriendlyName "S2DPool" -FriendlyName "S2DDisk2" -Size 100GB -ResiliencySettingName Simple
               New-VirtualDisk -StoragePoolFriendlyName "S2DPool" -FriendlyName "S2DDisk3" -Size 100GB -ResiliencySettingName Simple
               New-VirtualDisk -StoragePoolFriendlyName "S2DPool" -FriendlyName "S2DDisk4" -Size 100GB -ResiliencySettingName Simple
           }
           
           # Configure Hyper-V virtual switch
           New-VMSwitch -Name "hciSwitch" -NetAdapterName "MGMT" -AllowManagementOS $true
           
           # Add virtual network adapters for storage
           Add-VMNetworkAdapter -ManagementOS -Name "StorageA" -SwitchName "hciSwitch"
           Add-VMNetworkAdapter -ManagementOS -Name "StorageB" -SwitchName "hciSwitch"
       }
   }
   ```

4. **Configure storage network IP addresses**:
   ```powershell
   # Configure storage network on AzLHOST1
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       # Configure StorageA adapter
       New-NetIPAddress -InterfaceAlias "vEthernet (StorageA)" -IPAddress 10.71.1.10 -PrefixLength 24
       
       # Configure StorageB adapter
       New-NetIPAddress -InterfaceAlias "vEthernet (StorageB)" -IPAddress 10.71.2.10 -PrefixLength 24
       
       # Set VLAN IDs
       Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "StorageA" -Access -VlanId 711
       Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "StorageB" -Access -VlanId 712
   }
   
   # Configure storage network on AzLHOST2
   Invoke-Command -VMName "AzLHOST2" -Credential $domainCred -ScriptBlock {
       # Configure StorageA adapter
       New-NetIPAddress -InterfaceAlias "vEthernet (StorageA)" -IPAddress 10.71.1.11 -PrefixLength 24
       
       # Configure StorageB adapter
       New-NetIPAddress -InterfaceAlias "vEthernet (StorageB)" -IPAddress 10.71.2.11 -PrefixLength 24
       
       # Set VLAN IDs
       Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "StorageA" -Access -VlanId 711
       Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "StorageB" -Access -VlanId 712
   }
   ```

5. **Create and validate the failover cluster**:
   ```powershell
   # Run cluster validation
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       # Test cluster configuration
       Test-Cluster -Node "AzLHOST1", "AzLHOST2" -Include "Storage Spaces Direct", "Inventory", "Network", "System Configuration"
   }
   
   # Create the failover cluster
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       # Create the cluster
       New-Cluster -Name "localboxcluster" -Node "AzLHOST1", "AzLHOST2" -StaticAddress 192.168.1.100 -NoStorage
       
       # Enable Storage Spaces Direct
       Enable-ClusterStorageSpacesDirect -Confirm:$false
       
       # Create cluster shared volume
       New-Volume -StoragePoolFriendlyName "S2D*" -FriendlyName "ClusterVolume" -FileSystem CSVFS_ReFS -Size 200GB
   }
   ```

6. **Verify cluster status**:
   ```powershell
   # Check cluster status
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       Get-Cluster
       Get-ClusterNode
       Get-ClusterResource
       Get-StoragePool
       Get-VirtualDisk
       Get-ClusterSharedVolume
   }
   ```

## Deploying Azure Resources

1. **Create Azure service principal and required Azure resources**:
   ```powershell
   # Login to Azure on the host machine (not in VMs)
   Connect-AzAccount
   
   # Set your subscription context
   $subscriptionId = "your-subscription-id"
   Set-AzContext -SubscriptionId $subscriptionId
   
   # Register required resource providers
   $providers = @(
       "Microsoft.HybridCompute",
       "Microsoft.GuestConfiguration", 
       "Microsoft.Kubernetes",
       "Microsoft.KubernetesConfiguration",
       "Microsoft.ExtendedLocation",
       "Microsoft.AzureArcData",
       "Microsoft.OperationsManagement",
       "Microsoft.AzureStackHCI",
       "Microsoft.ResourceConnector",
       "Microsoft.OperationalInsights"
   )
   
   foreach ($provider in $providers) {
       Write-Output "Registering provider: $provider"
       Register-AzResourceProvider -ProviderNamespace $provider
   }
   ```

2. **Create resource group and required Azure resources**:
   ```powershell
   # Create resource group
   $resourceGroupName = "localbox-rg"
   $location = "East US"
   New-AzResourceGroup -Name $resourceGroupName -Location $location
   
   # Create Log Analytics workspace
   $workspaceName = "localbox-workspace"
   New-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $workspaceName -Location $location
   
   # Create Key Vault for storing secrets
   $keyVaultName = "localbox-kv-$(Get-Random -Minimum 1000 -Maximum 9999)"
   New-AzKeyVault -ResourceGroupName $resourceGroupName -VaultName $keyVaultName -Location $location
   
   # Create storage accounts
   $diagStorageName = "localboxdiag$(Get-Random -Minimum 1000 -Maximum 9999)"
   $witnessStorageName = "localboxwitness$(Get-Random -Minimum 1000 -Maximum 9999)"
   
   New-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $diagStorageName -Location $location -SkuName "Standard_LRS"
   New-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $witnessStorageName -Location $location -SkuName "Standard_LRS"
   ```

3. **Create service principal for Azure Local cluster registration**:
   ```powershell
   # Create service principal with Owner permissions
   $spName = "localbox-sp-$(Get-Random -Minimum 1000 -Maximum 9999)"
   $sp = New-AzADServicePrincipal -DisplayName $spName -Role "Owner" -Scope "/subscriptions/$subscriptionId"
   
   # Store service principal information
   $spClientId = $sp.AppId
   $spClientSecret = $sp.PasswordCredentials.SecretText
   $tenantId = (Get-AzContext).Tenant.Id
   
   # Get Microsoft.AzureStackHCI resource provider object ID
   $hciProviderId = (Get-AzADServicePrincipal -DisplayName "Microsoft.AzureStackHCI").Id
   
   Write-Output "Service Principal ID: $spClientId"
   Write-Output "Tenant ID: $tenantId" 
   Write-Output "HCI Provider ID: $hciProviderId"
   ```

4. **Update ARM template parameters**:
   ```powershell
   # Read the parameters file
   $parametersFile = "C:\LocalBox\azlocal.parameters.json"
   $parameters = Get-Content -Path $parametersFile | ConvertFrom-Json
   
   # Update parameter values
   $parameters.parameters.keyVaultName.value = $keyVaultName
   $parameters.parameters.diagnosticStorageAccountName.value = $diagStorageName
   $parameters.parameters.clusterName.value = "localboxcluster"
   $parameters.parameters.location.value = $location
   $parameters.parameters.tenantId.value = $tenantId
   $parameters.parameters.clusterWitnessStorageAccountName.value = $witnessStorageName
   $parameters.parameters.localAdminUserName.value = "Administrator"
   $parameters.parameters.localAdminPassword.value = $adminPassword
   $parameters.parameters.AzureStackLCMAdminUsername.value = "Administrator"
   $parameters.parameters.AzureStackLCMAdminPasssword.value = $adminPassword
   $parameters.parameters.hciResourceProviderObjectID.value = $hciProviderId
   $parameters.parameters.domainFqdn.value = "jumpstart.local"
   $parameters.parameters.namingPrefix.value = "localbox"
   $parameters.parameters.adouPath.value = "OU=AzureLocal,DC=jumpstart,DC=local"
   
   # Update network configuration
   $parameters.parameters.subnetMask.value = "255.255.255.0"
   $parameters.parameters.defaultGateway.value = "192.168.1.1"
   $parameters.parameters.startingIPAddress.value = "192.168.1.100"
   $parameters.parameters.endingIPAddress.value = "192.168.1.199"
   $parameters.parameters.dnsServers.value = @("192.168.1.254")
   
   # Update physical nodes configuration
   $parameters.parameters.physicalNodesSettings.value = @(
       @{
           name = "AzLHOST1"
           ipv4Address = "192.168.1.12"
       },
       @{
           name = "AzLHOST2" 
           ipv4Address = "192.168.1.13"
       }
   )
   
   # Save updated parameters file
   $parameters | ConvertTo-Json -Depth 10 | Set-Content -Path $parametersFile
   ```

## Registering Azure Local Cluster

1. **Install Azure Arc agents on the cluster nodes**:
   ```powershell
   # Download and install Connected Machine agent on both nodes
   $nodeNames = @("AzLHOST1", "AzLHOST2")
   
   foreach ($nodeName in $nodeNames) {
       Invoke-Command -VMName $nodeName -Credential $domainCred -ScriptBlock {
           # Download Connected Machine agent
           $agentUrl = "https://aka.ms/azcmagent-windows"
           $agentPath = "$env:TEMP\AzureConnectedMachineAgent.msi"
           Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath
           
           # Install the agent
           Start-Process msiexec.exe -ArgumentList "/i $agentPath /quiet" -Wait
           
           # Connect to Azure Arc
           & "$env:ProgramFiles\AzureConnectedMachineAgent\azcmagent.exe" connect `
               --service-principal-id $using:spClientId `
               --service-principal-secret $using:spClientSecret `
               --tenant-id $using:tenantId `
               --subscription-id $using:subscriptionId `
               --resource-group $using:resourceGroupName `
               --location $using:location `
               --tags "Project=AzureLocal"
           
           Write-Output "Azure Arc agent installed and connected on $env:COMPUTERNAME"
       }
   }
   ```

2. **Get Arc-enabled server resource IDs**:
   ```powershell
   # Get the resource IDs of the Arc-enabled servers
   $arcNode1 = Get-AzConnectedMachine -ResourceGroupName $resourceGroupName -Name "AzLHOST1"
   $arcNode2 = Get-AzConnectedMachine -ResourceGroupName $resourceGroupName -Name "AzLHOST2"
   
   $arcNodeResourceIds = @($arcNode1.Id, $arcNode2.Id)
   
   # Update parameters file with Arc resource IDs
   $parameters = Get-Content -Path $parametersFile | ConvertFrom-Json
   $parameters.parameters.arcNodeResourceIds.value = $arcNodeResourceIds
   $parameters | ConvertTo-Json -Depth 10 | Set-Content -Path $parametersFile
   ```

3. **Validate the ARM template deployment**:
   ```powershell
   # Validate the ARM template before deployment
   $templateFile = "C:\LocalBox\azlocal.json"
   $parametersFile = "C:\LocalBox\azlocal.parameters.json"
   
   # Set deployment mode to Validate in parameters
   $parameters = Get-Content -Path $parametersFile | ConvertFrom-Json
   $parameters.parameters.deploymentMode.value = "Validate"
   $parameters | ConvertTo-Json -Depth 10 | Set-Content -Path $parametersFile
   
   # Run validation deployment
   $validationResult = New-AzResourceGroupDeployment `
       -ResourceGroupName $resourceGroupName `
       -Name "localcluster-validate" `
       -TemplateFile $templateFile `
       -TemplateParameterFile $parametersFile `
       -Verbose
   
   if ($validationResult.ProvisioningState -eq "Succeeded") {
       Write-Output "Validation succeeded. Proceeding with deployment..."
   } else {
       Write-Error "Validation failed: $($validationResult.ProvisioningState)"
       exit 1
   }
   ```

4. **Deploy the Azure Local cluster**:
   ```powershell
   # Set deployment mode to Deploy
   $parameters = Get-Content -Path $parametersFile | ConvertFrom-Json
   $parameters.parameters.deploymentMode.value = "Deploy"
   $parameters | ConvertTo-Json -Depth 10 | Set-Content -Path $parametersFile
   
   # Run the deployment
   $deploymentResult = New-AzResourceGroupDeployment `
       -ResourceGroupName $resourceGroupName `
       -Name "localcluster-deploy" `
       -TemplateFile $templateFile `
       -TemplateParameterFile $parametersFile `
       -Verbose
   
   if ($deploymentResult.ProvisioningState -eq "Succeeded") {
       Write-Output "Azure Local cluster deployed successfully!"
   } else {
       Write-Error "Deployment failed: $($deploymentResult.ProvisioningState)"
   }
   ```

5. **Verify cluster registration in Azure**:
   ```powershell
   # Check the Azure Local cluster resource in Azure
   $clusterResource = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.AzureStackHCI/clusters"
   
   if ($clusterResource) {
       Write-Output "Azure Local cluster registered successfully:"
       Write-Output "Cluster Name: $($clusterResource.Name)"
       Write-Output "Status: $($clusterResource.Properties.status)"
       Write-Output "Connection Status: $($clusterResource.Properties.connectivityStatus)"
   } else {
       Write-Error "Azure Local cluster resource not found in Azure"
   }
   
   # Verify cluster nodes are connected
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       # Check cluster status from inside the cluster
       Get-Cluster
       Get-ClusterNode
       
       # Check Azure Arc connectivity
       & "$env:ProgramFiles\AzureConnectedMachineAgent\azcmagent.exe" show
   }
   ```

6. **Configure cluster cloud witness (optional)**:
   ```powershell
   # Configure cloud witness for cluster quorum
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       # Get storage account key
       $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $using:resourceGroupName -Name $using:witnessStorageName)[0].Value
       
       # Set cloud witness
       Set-ClusterQuorum -CloudWitness -AccountName $using:witnessStorageName -AccessKey $storageKey
       
       # Verify quorum configuration
       Get-ClusterQuorum
   }
   ```

## Post-Deployment Configuration

1. **Verify the cluster deployment status**:
   ```powershell
   # Check cluster health from Azure
   $cluster = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.AzureStackHCI/clusters"
   $cluster.Properties
   
   # Check cluster status from nodes
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       Get-Cluster | Select-Object Name, Domain, QuorumModel, QuorumType
       Get-ClusterNode | Select-Object Name, State, StatusInformation
       Get-ClusterSharedVolume | Select-Object Name, State, OwnerNode
       Get-StoragePool | Where-Object FriendlyName -like "*S2D*"
   }
   ```

2. **Install and configure Windows Admin Center**:
   ```powershell
   # Install Windows Admin Center on the management VM
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       # Install Windows Admin Center
       $wacPath = "C:\LocalBox\Windows Admin Center\WindowsAdminCenter.msi"
       
       if (Test-Path $wacPath) {
           $args = @(
               "/i", $wacPath,
               "/quiet",
               "/log", "C:\LocalBox\Logs\WAC-Install.log",
               "SME_PORT=443",
               "SSL_CERTIFICATE_OPTION=generate"
           )
           
           Start-Process msiexec.exe -ArgumentList $args -Wait
           
           Write-Output "Windows Admin Center installed successfully"
           Write-Output "Access URL: https://192.168.1.11"
       } else {
           Write-Error "Windows Admin Center installer not found at $wacPath"
       }
   }
   
   # Configure firewall rule for Windows Admin Center
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       New-NetFirewallRule -DisplayName "Windows Admin Center" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
   }
   ```

3. **Configure cluster monitoring and management**:
   ```powershell
   # Enable cluster performance monitoring
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       # Enable Storage Spaces Direct health monitoring
       Enable-StorageMaintenanceMode -StorageSubSystemName "*cluster*" -Disable
       
       # Configure cluster logging
       $clusterLog = Get-ClusterLog -UseLocalTime -TimeSpan 24
       Write-Output "Cluster log location: $($clusterLog.Name)"
       
       # Check cluster validation report
       Test-Cluster -Node (Get-ClusterNode).Name -ReportName "C:\LocalBox\Logs\ClusterValidation.html"
   }
   ```

4. **Set up desktop shortcuts and management tools**:
   ```powershell
   # Create desktop shortcuts on management VM
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       $desktopPath = [Environment]::GetFolderPath("Desktop")
       
       # Create Hyper-V Manager shortcut
       $wshShell = New-Object -ComObject WScript.Shell
       $shortcut = $wshShell.CreateShortcut("$desktopPath\Hyper-V Manager.lnk")
       $shortcut.TargetPath = "C:\Windows\System32\virtmgmt.msc"
       $shortcut.Save()
       
       # Create Failover Cluster Manager shortcut  
       $shortcut = $wshShell.CreateShortcut("$desktopPath\Failover Cluster Manager.lnk")
       $shortcut.TargetPath = "C:\Windows\System32\CluAdmin.msc"
       $shortcut.Save()
       
       # Create Windows Admin Center shortcut
       $shortcut = $wshShell.CreateShortcut("$desktopPath\Windows Admin Center.lnk")
       $shortcut.TargetPath = "https://192.168.1.11"
       $shortcut.Save()
       
       # Create PowerShell ISE shortcut
       $shortcut = $wshShell.CreateShortcut("$desktopPath\PowerShell ISE.lnk")
       $shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\PowerShell_ISE.exe"
       $shortcut.Save()
   }
   ```

5. **Configure automatic updates (optional)**:
   ```powershell
   # Configure Windows Update settings on all VMs
   $allVMs = @("AzLMGMT", "AzLHOST1", "AzLHOST2")
   
   foreach ($vmName in $allVMs) {
       Invoke-Command -VMName $vmName -Credential $domainCred -ScriptBlock {
           # Configure Windows Update to download but not install automatically
           $au = New-Object -ComObject Microsoft.Update.AutoUpdate
           $auSettings = $au.Settings
           $auSettings.NotificationLevel = 2  # Download updates but let me choose whether to install them
           $auSettings.ScheduledInstallationDay = 0  # Every day
           $auSettings.ScheduledInstallationTime = 3  # 3 AM
           $auSettings.Save()
           
           Write-Output "Windows Update configured on $env:COMPUTERNAME"
       }
   }
   ```

6. **Create cluster management script**:
   ```powershell
   # Create a management script for common cluster operations
   $managementScript = @'
   # Azure Local Cluster Management Script
   # Run this on AzLHOST1 or AzLHOST2
   
   function Get-ClusterHealth {
       Write-Output "=== Cluster Status ==="
       Get-Cluster | Select-Object Name, Domain, QuorumModel
       
       Write-Output "`n=== Cluster Nodes ==="
       Get-ClusterNode | Select-Object Name, State, StatusInformation
       
       Write-Output "`n=== Storage Spaces Direct ==="
       Get-StoragePool | Where-Object FriendlyName -like "*S2D*" | Select-Object FriendlyName, OperationalStatus, HealthStatus
       
       Write-Output "`n=== Virtual Disks ==="
       Get-VirtualDisk | Select-Object FriendlyName, OperationalStatus, HealthStatus, Size
       
       Write-Output "`n=== Cluster Shared Volumes ==="
       Get-ClusterSharedVolume | Select-Object Name, State, OwnerNode
   }
   
   function Test-ClusterConnectivity {
       Write-Output "=== Testing Cluster Connectivity ==="
       $nodes = Get-ClusterNode
       foreach ($node in $nodes) {
           $result = Test-NetConnection -ComputerName $node.Name -Port 5985
           Write-Output "$($node.Name): $($result.TcpTestSucceeded)"
       }
   }
   
   # Export functions
   Export-ModuleMember -Function Get-ClusterHealth, Test-ClusterConnectivity
'@
   
   # Save the script to the management VM
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       $using:managementScript | Out-File -FilePath "C:\LocalBox\ClusterManagement.psm1" -Encoding UTF8
       Write-Output "Cluster management module saved to C:\LocalBox\ClusterManagement.psm1"
   }
   ```

## Troubleshooting

### Common Issues and Solutions

1. **VM Creation and Configuration Issues**:
   ```powershell
   # Check Hyper-V host requirements
   Get-WindowsOptionalFeature -Online | Where-Object FeatureName -like "*Hyper-V*"
   
   # Verify nested virtualization is enabled
   Get-VM | Get-VMProcessor | Select-Object VMName, ExposeVirtualizationExtensions
   
   # Check VM memory and CPU allocation
   Get-VM | Select-Object Name, State, MemoryMB, ProcessorCount
   
   # Fix VM network connectivity
   Get-VMNetworkAdapter -All | Select-Object VMName, SwitchName, Connected
   ```

2. **Network Connectivity Issues**:
   ```powershell
   # Test network connectivity between VMs
   Test-NetConnection -ComputerName 192.168.1.11 -Port 5985  # AzLMGMT
   Test-NetConnection -ComputerName 192.168.1.12 -Port 5985  # AzLHOST1
   Test-NetConnection -ComputerName 192.168.1.13 -Port 5985  # AzLHOST2
   
   # Verify DNS resolution
   nslookup jumpstart.local 192.168.1.254
   nslookup AzLHOST1.jumpstart.local
   
   # Check virtual switch configuration
   Get-VMSwitch | Select-Object Name, SwitchType, NetAdapterInterfaceDescription
   Get-NetAdapter | Where-Object Name -like "*vEthernet*"
   
   # Verify NAT configuration for internet access
   Get-NetNat
   Get-NetIPAddress | Where-Object InterfaceAlias -like "*vEthernet*"
   ```

3. **Domain Controller Issues**:
   ```powershell
   # Check AD services on domain controller
   Invoke-Command -VMName "AzLMGMT" -Credential $domainCred -ScriptBlock {
       Invoke-Command -VMName "jumpstartdc" -Credential $using:domainCred -ScriptBlock {
           Get-Service | Where-Object {$_.Name -in @("ADWS", "DNS", "KDC", "Netlogon")} | Select-Object Name, Status
           
           # Run DCDiag
           dcdiag /v
           
           # Check event logs
           Get-EventLog -LogName "Directory Service" -EntryType Error -Newest 10
       }
   }
   
   # Test domain authentication from nodes
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       nltest /dsgetdc:jumpstart.local
       Test-ComputerSecureChannel -Verbose
   }
   ```

4. **Cluster Validation and Creation Issues**:
   ```powershell
   # Run cluster validation with detailed output
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       Test-Cluster -Node "AzLHOST1", "AzLHOST2" -Include "Storage Spaces Direct", "Inventory", "Network", "System Configuration" -Verbose
   }
   
   # Check cluster network configuration
   Get-ClusterNetwork
   Get-ClusterNetworkInterface
   
   # Verify storage configuration
   Get-PhysicalDisk | Where-Object CanPool -eq $true
   Get-StoragePool
   Get-VirtualDisk
   
   # Check cluster logs
   Get-ClusterLog -UseLocalTime -TimeSpan 1
   ```

5. **Azure Arc Registration Issues**:
   ```powershell
   # Check Azure Arc agent status
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       & "$env:ProgramFiles\AzureConnectedMachineAgent\azcmagent.exe" show
       & "$env:ProgramFiles\AzureConnectedMachineAgent\azcmagent.exe" check
   }
   
   # Test Azure connectivity
   Test-NetConnection -ComputerName "management.azure.com" -Port 443
   Test-NetConnection -ComputerName "login.windows.net" -Port 443
   
   # Check service principal permissions
   Get-AzRoleAssignment -ServicePrincipalName $spClientId
   
   # Review Arc agent logs
   Get-ChildItem "$env:ProgramData\AzureConnectedMachineAgent\Log" | Sort-Object LastWriteTime -Descending
   ```

6. **ARM Template Deployment Issues**:
   ```powershell
   # Validate ARM template before deployment
   Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -TemplateParameterFile $parametersFile
   
   # Get detailed deployment error information
   $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name "localcluster-deploy"
   $deployment.Properties.Error
   
   # Check deployment operation details
   Get-AzResourceGroupDeploymentOperation -ResourceGroupName $resourceGroupName -DeploymentName "localcluster-deploy"
   ```

7. **Storage Spaces Direct Issues**:
   ```powershell
   # Check Storage Spaces Direct health
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       Get-StoragePool | Where-Object FriendlyName -like "*S2D*"
       Get-PhysicalDisk | Select-Object FriendlyName, OperationalStatus, HealthStatus
       Get-VirtualDisk | Select-Object FriendlyName, OperationalStatus, HealthStatus
       
       # Get Storage Spaces Direct events
       Get-WinEvent -FilterHashtable @{LogName="Microsoft-Windows-StorageSpaces-Driver/Operational"; Level=2} -MaxEvents 10
   }
   ```

### Performance Optimization

1. **VM Performance Tuning**:
   ```powershell
   # Configure VM for optimal performance
   $vmNames = @("AzLHOST1", "AzLHOST2")
   foreach ($vmName in $vmNames) {
       Set-VM -Name $vmName -AutomaticStopAction ShutDown
       Set-VM -Name $vmName -AutomaticStartAction StartIfRunning
       
       # Configure VM processor settings
       Set-VMProcessor -VMName $vmName -Count (Get-VM -Name $vmName).ProcessorCount -Reserve 10 -Maximum 100 -RelativeWeight 100
   }
   ```

2. **Network Performance Optimization**:
   ```powershell
   # Enable SR-IOV if supported by hardware
   $vmNames = @("AzLHOST1", "AzLHOST2")
   foreach ($vmName in $vmNames) {
       Set-VMNetworkAdapter -VMName $vmName -IovWeight 100
   }
   
   # Configure jumbo frames
   Get-NetAdapter | Where-Object Name -like "*vEthernet*" | Set-NetAdapterAdvancedProperty -DisplayName "Jumbo Packet" -DisplayValue "9014 Bytes"
   ```

### Emergency Recovery Procedures

1. **Reset cluster configuration**:
   ```powershell
   # If cluster becomes unresponsive, force cleanup
   Invoke-Command -VMName "AzLHOST1" -Credential $domainCred -ScriptBlock {
       Stop-ClusterService -Force
       Clear-ClusterNode -Force
   }
   ```

2. **Restore VM from checkpoint**:
   ```powershell
   # Create VM checkpoints before major changes
   Checkpoint-VM -Name "AzLHOST1" -SnapshotName "BeforeClusterSetup"
   
   # Restore from checkpoint if needed
   Restore-VMCheckpoint -VMName "AzLHOST1" -Name "BeforeClusterSetup" -Confirm:$false
   ```

For additional assistance and the latest troubleshooting guides, refer to:
- [Azure Arc JumpStart documentation](https://azurearcjumpstart.io/)
- [Azure Local documentation](https://docs.microsoft.com/en-us/azure-stack/hci/)
- [Azure Arc documentation](https://docs.microsoft.com/en-us/azure/azure-arc/)

### Support and Community Resources

- GitHub Issues: [Azure Arc JumpStart GitHub](https://github.com/microsoft/azure_arc/issues)
- Microsoft Tech Community: Azure Arc Forums
- Microsoft Documentation: Azure Arc and Azure Local official docs
- Azure Support: For production environments, consider opening Azure support tickets
