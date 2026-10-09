# ============================================================
# Post-Offboarding Verification
# Microsoft Entra ID / Microsoft Graph
# ============================================================
#
# Purpose:
# Independently verifies an employee's Microsoft Entra ID
# identity and access state after offboarding is complete.
#
# Verification:
# - Account status
# - Remaining group memberships
# - Remaining license assignments
# - Structured post-offboarding report
# ============================================================


# ============================================================
# Import Microsoft Graph Modules
# ============================================================

Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups


# ============================================================
# Connect to Microsoft Graph
# Read-Only Delegated Permissions
# ============================================================

Connect-MgGraph -Scopes `
    "User.Read.All", `
    "Group.Read.All", `
    "Directory.Read.All"


# ============================================================
# Import Termination Data
# ============================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$TerminationFile = Join-Path `
    $ProjectRoot `
    "Sample-Data\TerminatedEmployees.csv"

$TerminatedEmployees = Import-Csv $TerminationFile

# Collect verification results for all processed employees
$PostOffboardingReport = @()


# ============================================================
# Verify Post-Offboarding State
# ============================================================

foreach ($Employee in $TerminatedEmployees) {

    $UserPrincipalName = $Employee.UserPrincipalName

    Write-Host ""
    Write-Host "============================================"
    Write-Host "Post-Offboarding Verification"
    Write-Host "============================================"
    Write-Host "Verifying: $UserPrincipalName"

    try {

        # ----------------------------------------------------
        # Retrieve Current Entra ID User State
        # ----------------------------------------------------

        $EntraUser = Get-MgUser `
            -UserId $UserPrincipalName `
            -Property Id,DisplayName,UserPrincipalName,AccountEnabled,Department,JobTitle

        Write-Host ""
        Write-Host "Employee: $($EntraUser.DisplayName)"
        Write-Host "Account Enabled: $($EntraUser.AccountEnabled)"


        # ----------------------------------------------------
        # Verify Remaining Group Memberships
        # ----------------------------------------------------

        $Memberships = Get-MgUserMemberOf `
            -UserId $EntraUser.Id `
            -All

        $Groups = foreach ($Membership in $Memberships) {

            try {

                Get-MgGroup -GroupId $Membership.Id

            }
            catch {

                # Ignore directory objects that are not groups

            }
        }

        Write-Host ""
        Write-Host "Remaining Group Memberships:"

        if ($Groups) {

            $Groups |
                Select-Object DisplayName

        }
        else {

            Write-Host "None"

        }


        # ----------------------------------------------------
        # Verify Remaining License Assignments
        # ----------------------------------------------------

        $LicenseDetails = Get-MgUserLicenseDetail `
            -UserId $EntraUser.Id

        Write-Host ""
        Write-Host "Remaining Licenses:"

        if ($LicenseDetails) {

            $LicenseDetails |
                Select-Object SkuPartNumber

        }
        else {

            Write-Host "None"

        }


        # ----------------------------------------------------
        # Create Post-Offboarding Verification Record
        # ----------------------------------------------------

        if ($Groups) {

            $GroupNames = ($Groups.DisplayName -join "; ")

        }
        else {

            $GroupNames = "None"

        }

        if ($LicenseDetails) {

            $LicenseNames = ($LicenseDetails.SkuPartNumber -join "; ")

        }
        else {

            $LicenseNames = "None"

        }

        $VerificationRecord = [PSCustomObject]@{
            EmployeeName      = $EntraUser.DisplayName
            UserPrincipalName = $EntraUser.UserPrincipalName
            Department        = $EntraUser.Department
            AccountEnabled    = $EntraUser.AccountEnabled
            RemainingGroups   = $GroupNames
            RemainingLicenses = $LicenseNames
            TerminationDate   = $Employee.TerminationDate
            VerificationDate  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        $PostOffboardingReport += $VerificationRecord

    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Post-offboarding verification failed for $UserPrincipalName."
        Write-Host $_.Exception.Message

        continue

    }
}


# ============================================================
# Export Post-Offboarding Verification Report
# ============================================================

$ReportPath = Join-Path `
    $ProjectRoot `
    "Reports\Post-Offboarding-Verification.csv"

$PostOffboardingReport |
    Export-Csv `
        -Path $ReportPath `
        -NoTypeInformation

Write-Host ""
Write-Host "Post-offboarding verification report created successfully."
Write-Host "Report location: $ReportPath"