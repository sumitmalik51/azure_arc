param (
    [string]$adminUsername,
    [string]$adminPassword,
    [string]$spnClientId,
    [string]$spnClientSecret,
    [string]$spnTenantId,
    [string]$subscriptionId,
    [string]$resourceGroup,
    [string]$azureLocation,
    [string]$stagingStorageAccountName,
    [string]$workspaceName,
    [string]$templateBaseUrl,
    [string]$registerCluster,
    [string]$deployAKSHCI,
    [string]$deployResourceBridge,
    [string]$natDNS
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnClientID', $spnClientId,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnClientSecret', $spnClientSecret,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnTenantId', $spnTenantId,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('SPN_CLIENT_ID', $spnClientId,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('SPN_CLIENT_SECRET', $spnClientSecret,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('SPN_TENANT_ID', $spnTenantId,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('subscriptionId', $subscriptionId,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('stagingStorageAccountName', $stagingStorageAccountName,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('workspaceName', $workspaceName,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', $templateBaseUrl,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('deployAKSHCI', $deployAKSHCI,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('deployResourceBridge', $deployResourceBridge,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('registerCluster', $registerCluster,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('natDNS', $natDNS,[System.EnvironmentVariableTarget]::Machine)

# Creating HCIBox path
Write-Output "Creating HCIBox paths"
$Env:HCIBoxDir = "C:\HCIBox"
$Env:HCIBoxLogsDir = "C:\HCIBox\Logs"
$Env:HCIBoxVMDir = "C:\HCIBox\Virtual Machines"
$Env:HCIBoxIconDir = "C:\HCIBox\Icons"
$Env:HCIBoxVHDDir = "C:\HCIBox\VHD"
$Env:HCIBoxSDNDir = "C:\HCIBox\SDN"
$Env:HCIBoxKVDir = "C:\HCIBox\KeyVault"
$Env:HCIBoxWACDir = "C:\HCIBox\Windows Admin Center"
$Env:agentScript = "C:\HCIBox\agentScript"
$Env:ToolsDir = "C:\Tools"
$Env:tempDir = "C:\Temp"
$Env:VMPath = "C:\VMs"

New-Item -Path $Env:HCIBoxDir -ItemType directory -Force
New-Item -Path $Env:HCIBoxVHDDir -ItemType directory -Force
New-Item -Path $Env:HCIBoxSDNDir -ItemType directory -Force
New-Item -Path $Env:HCIBoxLogsDir -ItemType directory -Force
New-Item -Path $Env:HCIBoxVMDir -ItemType directory -Force
New-Item -Path $Env:HCIBoxIconDir -ItemType directory -Force
New-Item -Path $Env:HCIBoxWACDir -ItemType directory -Force
New-Item -Path $Env:HCIBoxKVDir -ItemType directory -Force
New-Item -Path $Env:ToolsDir -ItemType Directory -Force
New-Item -Path $Env:tempDir -ItemType directory -Force
New-Item -Path $Env:agentScript -ItemType directory -Force

Start-Transcript -Path $Env:HCIBoxLogsDir\Bootstrap.log

$ErrorActionPreference = 'SilentlyContinue'

# Copy PowerShell Profile and Reload
Invoke-WebRequest ($templateBaseUrl + "artifacts/PSProfile.ps1") -OutFile $PsHome\Profile.ps1
.$PsHome\Profile.ps1

# Extending C:\ partition to the maximum size
Write-Host "Extending C:\ partition to the maximum size"
Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax

Write-Header "Downloading Azure Stack HCI configuration scripts"
Invoke-WebRequest "https://raw.githubusercontent.com/microsoft/azure_arc/main/img/hcibox_wallpaper.png" -OutFile $Env:HCIBoxDir\wallpaper.png
Invoke-WebRequest https://aka.ms/wacdownload -OutFile $Env:HCIBoxWACDir\WindowsAdminCenter.msi
Invoke-WebRequest ($templateBaseUrl + "artifacts/HCIBoxLogonScript.ps1") -OutFile $Env:HCIBoxDir\HCIBoxLogonScript.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/New-HCIBoxCluster.ps1") -OutFile $Env:HCIBoxDir\New-HCIBoxCluster.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/Register-AzSHCI.ps1") -OutFile $Env:HCIBoxDir\Register-AzSHCI.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/HCIBox-Config.psd1") -OutFile $Env:HCIBoxDir\HCIBox-Config.psd1
Invoke-WebRequest ($templateBaseUrl + "artifacts/Deploy-AKS.ps1") -OutFile $Env:HCIBoxDir\Deploy-AKS.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/Uninstall-AKS.ps1") -OutFile $Env:HCIBoxDir\Uninstall-AKS.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/Deploy-ArcResourceBridge.ps1") -OutFile $Env:HCIBoxDir\Deploy-ArcResourceBridge.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/Deploy-GitOps.ps1") -OutFile $Env:HCIBoxDir\Deploy-GitOps.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/SDN/CertHelpers.ps1") -OutFile $Env:HCIBoxSDNDir\CertHelpers.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/SDN/NetworkControllerRESTWrappers.ps1") -OutFile $Env:HCIBoxSDNDir\NetworkControllerRESTWrappers.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/SDN/NetworkControllerWorkloadHelpers.psm1") -OutFile $Env:HCIBoxSDNDir\NetworkControllerWorkloadHelpers.psm1
Invoke-WebRequest ($templateBaseUrl + "artifacts/SDN/SDNExplorer.ps1") -OutFile $Env:HCIBoxSDNDir\SDNExplorer.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/SDN/SDNExpress.ps1") -OutFile $Env:HCIBoxSDNDir\SDNExpress.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/SDN/SDNExpressModule.psm1") -OutFile $Env:HCIBoxSDNDir\SDNExpressModule.psm1
Invoke-WebRequest ($templateBaseUrl + "artifacts/SDN/SDNExpressUI.psm1") -OutFile $Env:HCIBoxSDNDir\SDNExpressUI.psm1
Invoke-WebRequest ($templateBaseUrl + "artifacts/SDN/Single-NC.psd1") -OutFile $Env:HCIBoxSDNDir\Single-NC.psd1
Invoke-WebRequest ($templateBaseUrl + "artifacts/LogInstructions.txt") -OutFile $Env:HCIBoxSDNDir\LogInstructions.txt

# Replace password and DNS placeholder
(Get-Content -Path $Env:HCIBoxDir\HCIBox-Config.psd1) -replace '%staging-password%',$adminPassword | Set-Content -Path $Env:HCIBoxDir\HCIBox-Config.psd1
(Get-Content -Path $Env:HCIBoxDir\HCIBox-Config.psd1) -replace '%staging-natDNS%',$natDNS | Set-Content -Path $Env:HCIBoxDir\HCIBox-Config.psd1

# Disabling Windows Server Manager Scheduled Task
Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

# Creating scheduled task for HCIBoxLogonScript.ps1
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Env:HCIBoxDir\HCIBoxLogonScript.ps1
Register-ScheduledTask -TaskName "HCIBoxLogonScript" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force

# Clean up Bootstrap.log
Write-Header "Clean up Bootstrap.log"
Stop-Transcript
$logSuppress = Get-Content $Env:HCIBoxLogsDir\Bootstrap.log | Where-Object { $_ -notmatch "Host Application: powershell.exe" } 
$logSuppress | Set-Content $Env:HCIBoxLogsDir\Bootstrap.log -Force

Restart-Computer
