# ============================================================
# Secure Employee Offboarding Automation
# Microsoft Entra ID / Microsoft Graph
# ============================================================
#
# Purpose:
# Processes employee termination records and performs
# state-aware Microsoft Entra ID offboarding controls.
#
# Controls:
# - Disable the employee account
# - Revoke active sign-in sessions
# - Remove governed Finance access through Entitlement Management
# - Remove direct baseline group access
# - Generate a structured offboarding audit report
# ============================================================


# ============================================================
# Configuration
# ============================================================

$FinanceAccessPackageName = "Finance Operations Access Package"
$BaselineGroupName = "All Employees"


# ============================================================
# Import Microsoft Graph Modules
# ============================================================

Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Identity.Governance


# ============================================================
# Connect to Microsoft Graph
# Targeted Delegated Permissions
# ============================================================

Connect-MgGraph -Scopes `
    "User.Read.All", `
    "User.EnableDisableAccount.All", `
    "User.RevokeSessions.All", `
    "Group.Read.All", `
    "GroupMember.ReadWrite.All", `
    "EntitlementManagement.ReadWrite.All"


# ============================================================
# Import Termination Data
# ============================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$TerminationFile = Join-Path `
    $ProjectRoot `
    "Sample-Data\TerminatedEmployees.csv"

$TerminatedEmployees = Import-Csv $TerminationFile

# Collect audit results for all processed employees
$OffboardingReport = @()


# ============================================================
# Process Termination Records
# ============================================================

foreach ($Employee in $TerminatedEmployees) {

    $UserPrincipalName = $Employee.UserPrincipalName

    # Reset control statuses for each employee
    $AccountStatus = "Not Processed"
    $SessionStatus = "Not Processed"
    $FinanceAccessStatus = "Not Processed"
    $AllEmployeesStatus = "Not Processed"
    $OverallStatus = "In Progress"

    Write-Host ""
    Write-Host "============================================"
    Write-Host "Processing termination: $UserPrincipalName"
    Write-Host "============================================"

    try {

        # ----------------------------------------------------
        # Validate Entra ID User
        # ----------------------------------------------------

        $EntraUser = Get-MgUser `
            -UserId $UserPrincipalName `
            -Property Id,DisplayName,UserPrincipalName,AccountEnabled,Department,JobTitle

        Write-Host "User validated successfully."
        Write-Host "Employee: $($EntraUser.DisplayName)"
        Write-Host "Account Enabled: $($EntraUser.AccountEnabled)"


        # ----------------------------------------------------
        # Disable User Account
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "Checking account status..."

        if ($EntraUser.AccountEnabled -eq $true) {

            try {

                Update-MgUser `
                    -UserId $EntraUser.Id `
                    -AccountEnabled:$false

                Write-Host "Account disabled successfully."
                $AccountStatus = "Disabled"

            }
            catch {

                Write-Host "ERROR: Failed to disable account."
                Write-Host $_.Exception.Message
                $AccountStatus = "Failed"

            }
        }
        else {

            Write-Host "Account is already disabled. No action required."
            $AccountStatus = "Already Disabled"

        }


        # ----------------------------------------------------
        # Revoke Active Sign-In Sessions
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "Revoking active sign-in sessions..."

        try {

            $null = Revoke-MgUserSignInSession `
                -UserId $EntraUser.Id

            Write-Host "Sign-in sessions revoked successfully."
            $SessionStatus = "Revoked"

        }
        catch {

            Write-Host "ERROR: Failed to revoke sign-in sessions."
            Write-Host $_.Exception.Message
            $SessionStatus = "Failed"

        }


        # ----------------------------------------------------
        # Remove Governed Finance Access
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "Checking Finance Access Package assignment..."

        try {

            $AccessPackage = Get-MgEntitlementManagementAccessPackage `
                -Filter "displayName eq '$FinanceAccessPackageName'"

            if (-not $AccessPackage) {

                Write-Host "$FinanceAccessPackageName could not be found."
                $FinanceAccessStatus = "Access Package Not Found"

            }
            else {

                $AssignmentFilter = "accessPackage/id eq '$($AccessPackage.Id)' and state eq 'Delivered' and target/objectId eq '$($EntraUser.Id)'"

                $AccessPackageAssignment = Get-MgEntitlementManagementAssignment `
                    -Filter $AssignmentFilter `
                    -ExpandProperty Target `
                    -All

                if ($AccessPackageAssignment) {

                    Write-Host "Active Finance Access Package assignment found."
                    Write-Host "Submitting assignment removal..."

                    $RemovalParams = @{
                        requestType = "adminRemove"
                        assignment = @{
                            id = $AccessPackageAssignment.Id
                        }
                    }

                    $RemovalRequest = New-MgEntitlementManagementAssignmentRequest `
                        -BodyParameter $RemovalParams

                    Write-Host "Finance Access Package removal submitted."
                    Write-Host "Removal Status: $($RemovalRequest.Status)"

                    $FinanceAccessStatus = "Removal Submitted"

                }
                else {

                    Write-Host "No active Finance Access Package assignment found. No action required."
                    $FinanceAccessStatus = "Already Removed"

                }
            }
        }
        catch {

            Write-Host "ERROR: Failed while processing Finance Access Package."
            Write-Host $_.Exception.Message
            $FinanceAccessStatus = "Failed"

        }


        # ----------------------------------------------------
        # Remove Direct Baseline Group Membership
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "Checking $BaselineGroupName group membership..."

        try {

            $BaselineGroup = Get-MgGroup `
                -Filter "displayName eq '$BaselineGroupName'"

            if (-not $BaselineGroup) {

                Write-Host "$BaselineGroupName group could not be found."
                $AllEmployeesStatus = "Group Not Found"

            }
            else {

                $CurrentMemberships = Get-MgUserMemberOf `
                    -UserId $EntraUser.Id `
                    -All

                $BaselineMembership = $CurrentMemberships |
                    Where-Object {
                        $_.Id -eq $BaselineGroup.Id
                    }

                if ($BaselineMembership) {

                    Write-Host "$BaselineGroupName membership found."
                    Write-Host "Removing membership..."

                    Remove-MgGroupMemberByRef `
                        -GroupId $BaselineGroup.Id `
                        -DirectoryObjectId $EntraUser.Id

                    Write-Host "$BaselineGroupName membership removed successfully."
                    $AllEmployeesStatus = "Removed"

                }
                else {

                    Write-Host "User is not a member of $BaselineGroupName. No action required."
                    $AllEmployeesStatus = "Already Removed"

                }
            }
        }
        catch {

            Write-Host "ERROR: Failed while processing $BaselineGroupName membership."
            Write-Host $_.Exception.Message
            $AllEmployeesStatus = "Failed"

        }


        # ----------------------------------------------------
        # Determine Overall Offboarding Status
        # ----------------------------------------------------

        $SuccessfulAccountStatuses = @(
            "Disabled",
            "Already Disabled"
        )

        $SuccessfulSessionStatuses = @(
            "Revoked"
        )

        $SuccessfulFinanceStatuses = @(
            "Removal Submitted",
            "Already Removed"
        )

        $SuccessfulBaselineStatuses = @(
            "Removed",
            "Already Removed"
        )

        if (
            $AccountStatus -notin $SuccessfulAccountStatuses -or
            $SessionStatus -notin $SuccessfulSessionStatuses -or
            $FinanceAccessStatus -notin $SuccessfulFinanceStatuses -or
            $AllEmployeesStatus -notin $SuccessfulBaselineStatuses
        ) {

            $OverallStatus = "Completed with Errors"

        }
        else {

            $OverallStatus = "Completed"

        }


        # ----------------------------------------------------
        # Create Offboarding Audit Record
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "Creating offboarding audit record..."

        $OffboardingRecord = [PSCustomObject]@{
            EmployeeName        = $EntraUser.DisplayName
            UserPrincipalName   = $EntraUser.UserPrincipalName
            Department          = $EntraUser.Department
            TerminationDate     = $Employee.TerminationDate
            AccountStatus       = $AccountStatus
            SessionStatus       = $SessionStatus
            FinanceAccessStatus = $FinanceAccessStatus
            AllEmployeesStatus  = $AllEmployeesStatus
            OverallStatus       = $OverallStatus
            ProcessedDate       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        $OffboardingReport += $OffboardingRecord

    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Employee processing could not continue."
        Write-Host $_.Exception.Message

        continue

    }
}


# ============================================================
# Export Offboarding Audit Report
# ============================================================

$AuditReportPath = Join-Path `
    $ProjectRoot `
    "Reports\Offboarding-Audit-Report.csv"

$OffboardingReport |
    Export-Csv `
        -Path $AuditReportPath `
        -NoTypeInformation

Write-Host ""
Write-Host "Offboarding audit report created successfully."
Write-Host "Report location: $AuditReportPath"