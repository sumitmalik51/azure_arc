# Azure Arc JumpStart LocalBox: Manual Setup Guide

This document provides detailed manual instructions for setting up Azure Arc LocalBox environment without using the automated scripts. This guide will explain the conceptual steps needed to deploy and configure a complete Azure Arc environment locally.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Azure VM Deployment](#initial-azure-vm-deployment)
3. [Configuring the Host VM](#configuring-the-host-vm)
4. [Setting Up Hyper-V](#setting-up-hyper-v)
5. [Downloading Required VHDXs](#downloading-required-vhdxs)
6. [Creating Virtual Networks](#creating-virtual-networks)
7. [Creating and Configuring Nested VMs](#creating-and-configuring-nested-vms)
8. [Configuring the Domain Controller](#configuring-the-domain-controller)
9. [Configuring the Router VM](#configuring-the-router-vm)
10. [Setting Up Azure Local Cluster](#setting-up-azure-local-cluster)
11. [Deploying Azure Resources](#deploying-azure-resources)
12. [Registering Azure Local Cluster](#registering-azure-local-cluster)
13. [Post-Deployment Configuration](#post-deployment-configuration)
14. [Troubleshooting](#troubleshooting)

## Prerequisites

Before starting the manual deployment, ensure you have the following:

- An Azure subscription with required permissions
- Azure CLI installed
- PowerShell 7 or later
- Knowledge of Hyper-V and networking concepts
- At least 32GB of RAM for the host VM
- Minimum 4 CPU cores for the host VM
- At least 256GB of free disk space

## Initial Azure VM Deployment

1. **Deploy a VM in Azure with these minimum specifications**:
   - Size: Standard_D8s_v3 or larger (8 vCPUs, 32GB RAM)
   - OS: Windows Server 2022 Datacenter
   - Disk: At least 256GB OS disk and an additional data disk of 1TB

2. **Connect to the VM** using Remote Desktop Protocol (RDP).

3. **Format and configure the data disk**:
   - Open Server Manager, navigate to File and Storage Services, then Disks
   - Locate the additional data disk, which will be in an offline state
   - Right-click the disk and select "Initialize"
   - Choose GPT as the partition style
   - Create a new volume with drive letter V
   - Format as NTFS with a label of "AzLocalData"
   - Use 64KB as the allocation unit size for better performance with virtualization workloads

## Configuring the Host VM

1. **Create the directory structure**:
   - Create a main directory at C:\LocalBox to house all configuration files
   - Create subdirectories for different components:
     - C:\LocalBox\DSC for Desired State Configuration files
     - C:\LocalBox\Tests for test scripts
     - C:\LocalBox\Virtual Machines for VM configurations
     - C:\LocalBox\Logs for log files
     - C:\LocalBox\Icons for icon files
     - C:\LocalBox\VHD for virtual hard disk files
     - C:\LocalBox\SDN for Software Defined Networking files
     - C:\LocalBox\KeyVault for Azure Key Vault related files
     - C:\LocalBox\Windows Admin Center for WAC installation files
     - C:\LocalBox\agentScript for agent scripts
     - C:\Tools for tools and utilities
     - C:\Temp for temporary files
     - V:\VMs for the actual VM files on the data disk

2. **Set environment variables**:
   - Open System Properties (right-click on This PC, select Properties)
   - Click on Advanced system settings, then Environment Variables
   - Add the following system variables:
     - LocalBoxDir = C:\LocalBox
     - LocalBoxLogsDir = C:\LocalBox\Logs
     - LocalBoxTestsDir = C:\LocalBox\Tests

3. **Install required PowerShell modules**:
   - Open PowerShell as Administrator
   - Install the NuGet package provider
   - Install the Microsoft.PowerShell.PSResourceGet module
   - Install the following PowerShell modules:
     - Az (Azure PowerShell modules)
     - Az.ConnectedMachine (for Azure Arc)
     - Microsoft.PowerShell.SecretManagement (for credential management)
     - Pester (for testing)

4. **Install PowerShell 7**:
   - Download the latest PowerShell 7 MSI installer from GitHub
   - Install PowerShell 7 with all features including:
     - Add "Open PowerShell here" context menu items
     - Enable PowerShell remoting
     - Add PowerShell to PATH
   - Verify installation by opening PowerShell 7

5. **Configure CredSSP and WinRM**:
   - Enable CredSSP authentication on the server role
   - Enable CredSSP authentication on the client role
   - Add all computers to the trusted hosts list for WinRM
   - This allows for secure credential delegation needed for nested virtualization

6. **Configure Windows Defender exclusions for Hyper-V**:
   - Open Windows Security
   - Navigate to Virus & threat protection
   - Under Virus & threat protection settings, click "Manage settings"
   - Scroll down to Exclusions and click "Add or remove exclusions"
   - Add file extension exclusions for virtualization files (.vhd, .vhdx, etc.)
   - Add folder exclusions for Hyper-V directories
   - Add process exclusions for Hyper-V processes
   - These exclusions improve performance by preventing security scanning of virtualization files

## Setting Up Hyper-V

1. **Install Hyper-V and required features**:
   - Open Server Manager and click "Add Roles and Features"
   - Follow the wizard until you reach the "Server Roles" section
   - Check the "Hyper-V" role
   - In the "Features" section, ensure "Containers" and "Virtual Machine Platform" are selected
   - Complete the wizard and allow the server to restart when prompted
   - Alternatively, you can use PowerShell as an administrator to install these features
   - After restart, verify Hyper-V is installed by opening Hyper-V Manager from the Start menu

2. **Configure Hyper-V settings**:
   - Open Hyper-V Manager
   - In the right panel, click on "Hyper-V Settings" under your server name
   - Set the default location for virtual hard disks to "V:\VMs"
   - Set the default location for virtual machines to "V:\VMs"
   - Enable enhanced session mode for better VM interaction
   - Click Apply and OK to save these settings

## Downloading Required VHDXs

1. **Download AzCopy for file transfers**:
   - Open a browser and download AzCopy from "https://aka.ms/downloadazcopy-v10-windows"
   - Extract the ZIP file to a temporary location
   - Copy the azcopy.exe file to C:\Windows\System32\ for easy access
   - Verify installation by opening a command prompt and typing "azcopy --version"

2. **Download the required VHDX files**:
   - Set environment variable for AzCopy buffer size to improve download performance
   - Using AzCopy, download the Azure Local node VHDX from the JumpStart storage account
   - The file is approximately 10GB, so this may take some time depending on your connection
   - Download the corresponding SHA256 checksum file
   - Verify the downloaded file integrity by comparing its hash with the SHA256 file
   - Similarly, download the Windows Server VHDX for GUI VMs and its checksum
   - Verify the file integrity
   - Copy both VHDX files to the V:\VMs directory for use in VM creation

## Creating Virtual Networks

1. **Create the Internal Switch**:
   - Open Hyper-V Manager
   - In the right panel, click on "Virtual Switch Manager"
   - Select "Create Virtual Switch" and choose "Internal"
   - Name the switch "InternalSwitch"
   - Click OK to create the switch
   - Open Network Connections in Control Panel
   - Locate the new virtual switch network adapter (named like "vEthernet (InternalSwitch)")
   - Right-click and select Properties
   - Select IPv4 and click Properties
   - Set a static IP address of 192.168.1.20 with subnet mask 255.255.255.0

2. **Create the NAT Switch**:
   - Return to Hyper-V Manager and open Virtual Switch Manager
   - Create another internal switch named "InternalNAT"
   - After creating the switch, open Network Connections
   - Configure the new vEthernet adapter with IP 192.168.46.1/24
   - Open PowerShell as administrator
   - Create a new NAT network using the New-NetNat cmdlet
   - The NAT network should use the prefix 192.168.46.0/24
   - This network will allow VMs to access the internet through the host

## Creating and Configuring Nested VMs

1. **Set up credentials**:
   - Decide on a secure administrator password for all VMs
   - Document this password securely as you'll need it repeatedly
   - You'll need this password for local admin access to all VMs
   - Later you'll also need domain admin credentials

2. **Create Management VM (AzLMGMT)**:
   - Open Hyper-V Manager
   - Click New > Virtual Machine
   - Name the VM "AzLMGMT"
   - Choose Generation 2
   - Assign 28GB of memory
   - Configure networking to use the "InternalSwitch"
   - Create a new virtual hard disk by copying the GUI.vhdx
   - In VM settings, add virtual processors (20 cores recommended)
   - Set the MAC address to a static value (00:15:5D:01:0A:11)
   - Configure the boot order to boot from the hard drive
   - Enable Secure Boot with Microsoft template
   - Enable TPM for enhanced security
   - Start the VM

3. **Create first Azure Local node VM (AzLHOST1)**:
   - Create another new Generation 2 VM named "AzLHOST1"
   - Assign 96GB of memory (or maximum available)
   - Connect to the "InternalSwitch"
   - Create a virtual hard disk by copying the AzL-node.vhdx
   - Add as many virtual processors as possible
   - Set the MAC address to a static value (00:15:5D:01:0A:12)
   - Configure boot order to start from hard disk
   - Enable TPM
   - Most importantly, enable nested virtualization
   - This setting allows Hyper-V to run inside this VM
   - Start the VM

4. **Create second Azure Local node VM (AzLHOST2)**:
   - Repeat the process for a VM named "AzLHOST2"
   - Use the same settings as AzLHOST1
   - Set the MAC address to a different value (00:15:5D:01:0A:13)
   - Enable nested virtualization
   - Start the VM

5. **Configure VM Network Settings**:
   - Connect to the AzLMGMT VM via Hyper-V console
   - Log in with the local administrator account
   - Open Network Connections and rename the adapter to "MGMT"
   - Configure it with IP 192.168.1.11/24, gateway 192.168.1.1
   - Set DNS server to 192.168.1.254 (this will be the DC)
   - Repeat for AzLHOST1 with IP 192.168.1.12/24
   - Repeat for AzLHOST2 with IP 192.168.1.13/24

## Configuring the Domain Controller

1. **Create Domain Controller VM on AzLMGMT**:
   - Connect to the AzLMGMT VM via Hyper-V console
   - Open Hyper-V Manager within this VM
   - Create a new Generation 2 VM named "jumpstartdc"
   - Allocate 2GB RAM and 2 vCPUs
   - Create a 127GB virtual hard disk
   - Connect it to the InternalSwitch
   - Copy the contents of GUI.vhdx to the new VM's virtual hard disk
   - Configure the boot order to start from the hard disk
   - Set a static MAC address (00:15:5D:01:0D:CE)
   - Start the VM

2. **Configure Domain Controller**:
   - Connect to the DC VM and log in with the local administrator account
   - Configure networking with static IP 192.168.1.254/24 and gateway 192.168.1.1
   - Open Server Manager and add the Active Directory Domain Services role
   - After installation completes, promote the server to a domain controller
   - Create a new forest with the domain name "jumpstart.local"
   - Set the domain NetBIOS name to "JUMPSTART"
   - Enter a Directory Services Restore Mode password
   - Complete the promotion wizard
   - The server will restart automatically

3. **Verify domain controller is operational**:
   - After restart, log in with the domain administrator account (jumpstart.local\Administrator)
   - Open Server Manager and verify AD DS is running
   - Check that all related services are running:
     - Active Directory Web Services
     - DNS Server
     - Kerberos Key Distribution Center
     - Netlogon
   - Create an Organizational Unit (OU) for the cluster computers

## Configuring the Router VM

1. **Create Router VM on AzLMGMT**:
   - In the AzLMGMT VM, open Hyper-V Manager
   - Create a new Generation 2 VM named "vm-router"
   - Allocate 2GB RAM and 2 vCPUs
   - Create a 127GB virtual hard disk
   - Connect it to the InternalSwitch
   - Copy the contents of GUI.vhdx to the new VM's virtual hard disk
   - Configure the boot order to start from the hard disk
   - Set a static MAC address (00:15:5D:01:0B:01)
   - Start the VM

2. **Configure Router VM**:
   - Connect to the Router VM and log in with the local administrator account
   - Configure networking with static IP 192.168.1.1/24
   - Open Server Manager and add the Remote Access role
   - During installation, select the "Routing" role service
   - After installation, configure Routing and Remote Access
   - Choose the "Custom Configuration" option
   - Enable the "NAT" and "LAN Routing" features
   - Configure the NAT interface to use the Internet connection
   - Add static mappings for any ports you want to forward
   - Enable IP forwarding on all network interfaces
   - This router VM will provide connectivity between the nested VMs and the outside network

## Setting Up Azure Local Cluster

1. **Join the Azure Local nodes to the domain**:
   - On each VM (AzLMGMT, AzLHOST1, AzLHOST2), set the DNS server to point to the domain controller (192.168.1.254)
   - On AzLMGMT:
     - Open System Properties (right-click on This PC, select Properties)
     - Click Change Settings > Change
     - Select "Domain" and enter "jumpstart.local"
     - Enter domain admin credentials when prompted
     - The system will restart after joining the domain
   - Repeat the same process for AzLHOST1 and AzLHOST2
   - Wait for all systems to restart

2. **Prepare Azure Local node VMs for clustering**:
   - Connect to AzLHOST1 using domain credentials
   - Open Server Manager and add the following roles and features:
     - Hyper-V
     - Failover Clustering
     - RSAT Clustering PowerShell tools
   - Create a Hyper-V virtual switch named "hciSwitch" connected to the MGMT adapter
   - Add a virtual network adapter to the management OS for storage traffic
   - Configure the storage adapter with IP 10.71.1.10/24
   
   - Repeat the same process on AzLHOST2, but use IP 10.71.1.11/24 for the storage adapter

3. **Create Azure Local cluster**:
   - Connect to AzLHOST1 using domain credentials
   - Open Failover Cluster Manager
   - Run the "Validate Configuration" wizard to check the nodes
   - Include both AzLHOST1 and AzLHOST2 in the validation
   - Review the validation report for any warnings or errors
   - Run the "Create Cluster" wizard
   - Name the cluster "localboxcluster"
   - Add both nodes (AzLHOST1 and AzLHOST2)
   - Specify 192.168.1.100 as the cluster IP address
   - Do not add any storage at this time
   - Complete the wizard to create the cluster

## Deploying Azure Resources

1. **Create Azure Key Vault and storage account**:
   - Open a browser and log in to the Azure portal
   - Create a new resource group named "localbox-rg"
   - Create a new Key Vault with the following settings:
     - Name: A unique name (e.g., "localbox-kv-[random]")
     - Region: East US (or your preferred region)
     - Pricing tier: Standard
     - Enable all access policies for deployment, disk encryption, and template deployment
   
   - Create a new storage account for diagnostics:
     - Name: A unique name (e.g., "localboxsa[random]")
     - Performance: Standard
     - Redundancy: Locally-redundant storage (LRS)
   
   - Create another storage account for cluster witness:
     - Name: A unique name (e.g., "localboxwitness[random]")
     - Use the same settings as the diagnostics storage account

2. **Download ARM template for Azure Local cluster deployment**:
   - Download the ARM template files from the Azure Arc JumpStart GitHub repository
   - Save azlocal.json and azlocal.parameters.json to the C:\LocalBox directory
   - These templates will be used to deploy the Azure Local cluster

3. **Update template parameters file**:
   - Open the azlocal.parameters.json file in a text editor
   - Update the following parameters:
     - keyVaultName: The name of your Key Vault
     - diagnosticStorageAccountName: The name of your diagnostics storage account
     - clusterName: "localboxcluster"
     - clusterWitnessStorageAccountName: The name of your witness storage account
     - localAdminUserName: "Administrator"
     - localAdminPassword: Your secure password
     - AzureStackLCMAdminUsername: "Administrator"
     - AzureStackLCMAdminPasssword: Your secure password
     - arcNodeResourceIds: The resource IDs of your Azure Arc-enabled servers
     - physicalNodesSettings: Update with the correct node names and IP addresses

## Registering Azure Local Cluster

1. **Install Azure Local Arc agents on the nodes**:
   - Connect to each Azure Local node (AzLHOST1 and AzLHOST2)
   - Download the Azure Connected Machine agent
     - Open a web browser and navigate to https://aka.ms/azcmagent-windows
     - Save the MSI installer to the desktop
   
   - Install the agent on each node:
     - Double-click the downloaded MSI file
     - Follow the installation wizard
     - Accept the default installation options
     - Wait for the installation to complete
   
   - Connect to Azure:
     - Open PowerShell as Administrator
     - Run the azcmagent connect command
     - Specify your resource group name
     - Provide your tenant ID, subscription ID, and location
     - Add appropriate tags (e.g., "Project=AzureLocal")
     - The nodes will be registered as Arc-enabled servers in Azure

2. **Validate and deploy Azure Local cluster**:
   - Open PowerShell as Administrator
   - Connect to your Azure subscription
   - Navigate to the directory containing the ARM templates
   - Run a validation deployment to check for any issues:
     - Use the New-AzResourceGroupDeployment cmdlet with the template and parameter files
     - Set the deployment mode to "Validate"
     - Review any validation errors and fix them
   
   - Deploy the cluster:
     - Run the deployment again with the mode set to "Deploy"
     - This deployment will take some time to complete
     - Monitor the deployment progress in the Azure portal
     - When successful, your Azure Local cluster will be registered and managed through Azure Arc

## Post-Deployment Configuration

1. **Verify the cluster deployment**:
   - Log in to the Azure portal
   - Navigate to your resource group
   - Locate the Azure Stack HCI cluster resource
   - Check the status and properties
   - Verify that the cluster is healthy and connected
   - Explore the monitoring and management options available

2. **Set up Windows Admin Center**:
   - Download Windows Admin Center from https://aka.ms/wacdownload
   - Save the MSI installer to the C:\LocalBox\Windows Admin Center directory
   - Install Windows Admin Center with the following options:
     - Use port 443 for the gateway
     - Generate a self-signed certificate
     - Allow all authenticated users to connect
   - After installation, open Windows Admin Center in a browser
   - Add your Azure Local cluster as a connection
   - Use Windows Admin Center to manage your cluster

## Troubleshooting

If you encounter issues during the manual deployment, check the following:

1. **Networking Issues**:
   - Verify that all VMs can communicate with each other on the internal network
   - Use the ping command to test connectivity between VMs
   - Check that network adapters are properly configured with correct IP addresses
   - Ensure DNS is properly configured and pointing to the domain controller (192.168.1.254)
   - Verify the domain controller is serving DNS requests
   - Check that the default gateway is set to the router VM (192.168.1.1)
   - Test internet connectivity through the NAT router

2. **Domain Issues**:
   - Verify the domain controller is operational by checking the services
   - Use the dcdiag command on the domain controller to check for issues
   - Check that all VMs are properly joined to the domain using System Properties
   - Ensure DNS resolution is working correctly by testing nslookup
   - Check for any authentication issues in the event logs

3. **Cluster Issues**:
   - Run the Cluster Validation Wizard in Failover Cluster Manager
   - Review the validation report for any errors or warnings
   - Check event logs for any cluster-related errors
   - Verify storage connectivity between nodes using the ping command
   - Ensure all required roles and features are installed on both nodes

4. **Azure Arc Registration Issues**:
   - Check that the Arc agents are installed and running on both nodes
   - Review the agent logs in %ProgramData%\AzureConnectedMachineAgent\Log
   - Verify connectivity to Azure by testing network connectivity to global Azure endpoints
   - Check that the service principal has appropriate permissions
   - Try running the azcmagent check command to diagnose issues

5. **ARM Template Deployment Issues**:
   - Validate the template before deployment using the Test-AzResourceGroupDeployment command
   - Check for any validation errors in the parameters
   - Ensure all referenced resources exist and are accessible
   - Review deployment logs in the Azure portal
   - Try incremental deployments if full deployments are failing

For additional assistance, refer to the Azure Arc JumpStart documentation at https://azurearcjumpstart.io/azure_arc_jumpstart/azure_arc_servers/azure_stack_hci/local_box/.
