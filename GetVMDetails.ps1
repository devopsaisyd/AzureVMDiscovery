# Define the VM name
$vmName = "YourVMName"  # Replace with your VM name

# Get the VM object and Resource Group dynamically
$vm = Get-AzVM -Name $vmName -ErrorAction SilentlyContinue

if (-not $vm) {
    Write-Output "VM with the name '$vmName' not found in the current subscription."
    return
}

$resourceGroupName = $vm.ResourceGroupName

# Display Resource Group name for verification
Write-Output "Resource Group for VM '$vmName' identified as: $resourceGroupName"

# Format server name for account searches
$serverPattern = $vmName -replace '[^a-zA-Z0-9]', '' # Remove any special characters in the VM name
$accountPatterns = @("adm_$serverPattern", "bat_$serverPattern", "svc_$serverPattern", "rdp_$serverPattern")

# Function to check if accounts exist in AD or AAD
function Get-AssociatedAccounts {
    param (
        [string]$pattern
    )

    # Search in Azure AD
    try {
        $aadAccount = Get-AzureADUser -Filter "startswith(displayName,'$pattern')" -ErrorAction SilentlyContinue
        if ($aadAccount) {
            return "AAD Account: $($aadAccount.DisplayName)"
        }
    } catch {
        Write-Output "AzureAD module not found or unable to connect. Skipping Azure AD search."
    }

    # Search in on-premises Active Directory
    try {
        $adAccount = Get-ADUser -Filter { SamAccountName -like $pattern } -ErrorAction SilentlyContinue
        if ($adAccount) {
            return "AD Account: $($adAccount.SamAccountName)"
        }
    } catch {
        Write-Output "Active Directory module not found or unable to connect. Skipping AD search."
    }

    return "Not available / Check manually"
}

# Table to hold account results
$accountTable = @()

# Loop through account patterns and check their existence
foreach ($pattern in $accountPatterns) {
    $accountStatus = Get-AssociatedAccounts -pattern $pattern
    $accountTable += [PSCustomObject]@{
        AccountPattern = $pattern
        Status         = $accountStatus
    }
}

# Display results for AD and AAD accounts
Write-Output "Group Policies and Account Status for VM: $vmName"
$accountTable | Format-Table -AutoSize

# Checking Azure Monitor alert rules for the VM
Write-Output "`nChecking Azure Monitor Alert Rules..."

$alertRules = Get-AzAlertRuleV2 | Where-Object { $_.TargetResourceId -eq $vm.Id }
if ($alertRules) {
    $alertTable = $alertRules | Select-Object -Property Name, Description, Severity, Enabled, {$_.Criteria.Operator}, {$_.Criteria.Threshold} | Format-Table -AutoSize
    Write-Output "Alert Rules for VM: $vmName"
    $alertTable
} else {
    Write-Output "No Alert Rules found for the VM."
}

# Checking Metric Alerts associated with the VM
Write-Output "`nChecking Metric Alerts..."

$metricAlerts = Get-AzMetricAlertRule | Where-Object { $_.TargetResourceId -eq $vm.Id }
if ($metricAlerts) {
    $metricsTable = $metricAlerts | Select-Object -Property Name, Description, Severity, {$_.Criteria.MetricName}, {$_.Criteria.Operator}, {$_.Criteria.Threshold} | Format-Table -AutoSize
    Write-Output "Metric Alerts for VM: $vmName"
    $metricsTable
} else {
    Write-Output "No Metric Alerts found for the VM."
}

# Checking Log Analytics Workspaces associated with the VM
Write-Output "`nChecking Log Analytics Workspaces..."

$workspaces = Get-AzOperationalInsightsWorkspace | Where-Object { $_.ResourceGroupName -eq $resourceGroupName }
$logAnalyticsTable = foreach ($workspace in $workspaces) {
    $workspace | Select-Object -Property Name, ResourceGroupName, Location, Sku
} | Format-Table -AutoSize

if ($logAnalyticsTable) {
    Write-Output "Log Analytics Workspaces in Resource Group: $resourceGroupName"
    $logAnalyticsTable
} else {
    Write-Output "No Log Analytics Workspaces found in Resource Group for the VM."
}

# Checking Azure Policies assigned to the VM
Write-Output "`nChecking Azure Group Policies (Azure Policy)..."

$policyAssignments = Get-AzPolicyAssignment -ResourceGroupName $resourceGroupName | Where-Object { $_.Scope -like "*$vmName*" }

if ($policyAssignments) {
    $policyTable = $policyAssignments | Select-Object -Property Name, DisplayName, PolicyDefinitionId, Scope | Format-Table -AutoSize
    Write-Output "Azure Policies for VM: $vmName"
    $policyTable
} else {
    Write-Output "No Azure Policies associated with the VM or check manually."
}
