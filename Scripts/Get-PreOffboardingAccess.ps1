# ============================================================
# Pre-Offboarding Access Discovery
# Microsoft Entra ID / Microsoft Graph
# ============================================================
#
# Purpose:
# Captures an employee's identity and access state before
# offboarding begins. Results are exported for audit and
# before/after access reconciliation.
# ============================================================

# Import required Microsoft Graph modules
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups

# Connect using read-only delegated permissions
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

# Collect all successful discovery records before exporting
$PreOffboardingReport = @()


# ============================================================
# Process Termination Records
# ============================================================

foreach ($Employee in $TerminatedEmployees) {

    $UserPrincipalName = $Employee.UserPrincipalName

    Write-Host ""
    Write-Host "============================================"
    Write-Host "Pre-Offboarding Access Discovery"
    Write-Host "============================================"
    Write-Host "Searching Entra ID for: $UserPrincipalName"

    try {

        # ----------------------------------------------------
        # Validate Entra ID User
        # ----------------------------------------------------

        $EntraUser = Get-MgUser `
            -UserId $UserPrincipalName `
            -Property Id,DisplayName,UserPrincipalName,AccountEnabled,Department,JobTitle

        Write-Host "User found successfully."

        $EntraUser | Select-Object `
            DisplayName,
            UserPrincipalName,
            AccountEnabled,
            Department,
            JobTitle


        # ----------------------------------------------------
        # Discover Group Memberships
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "Current Group Memberships:"

        $GroupMemberships = Get-MgUserMemberOf `
            -UserId $EntraUser.Id `
            -All

        $Groups = foreach ($Membership in $GroupMemberships) {

            try {

                Get-MgGroup -GroupId $Membership.Id

            }
            catch {

                # Ignore directory objects that are not groups

            }
        }

        if ($Groups) {

            $Groups |
                Select-Object DisplayName, Id

        }
        else {

            Write-Host "None"

        }


        # ----------------------------------------------------
        # Discover Assigned Licenses
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "Current Assigned Licenses:"

        $LicenseDetails = Get-MgUserLicenseDetail `
            -UserId $EntraUser.Id

        if ($LicenseDetails) {

            $LicenseDetails |
                Select-Object SkuPartNumber, SkuId

        }
        else {

            Write-Host "No licenses assigned."

        }


        # ----------------------------------------------------
        # Create Pre-Offboarding Record
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "Creating pre-offboarding access record..."

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

        $PreOffboardingRecord = [PSCustomObject]@{

            EmployeeName      = $EntraUser.DisplayName
            UserPrincipalName = $EntraUser.UserPrincipalName
            Department        = $EntraUser.Department
            JobTitle          = $EntraUser.JobTitle
            AccountEnabled    = $EntraUser.AccountEnabled
            Groups            = $GroupNames
            Licenses          = $LicenseNames
            TerminationDate   = $Employee.TerminationDate
            DiscoveryDate     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        }

        $PreOffboardingReport += $PreOffboardingRecord

    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Pre-offboarding discovery failed for $UserPrincipalName."
        Write-Host $_.Exception.Message

        continue

    }
}


# ============================================================
# Export Pre-Offboarding Access Report
# ============================================================

$ReportPath = Join-Path `
    $ProjectRoot `
    "Reports\Pre-Offboarding-Access.csv"

$PreOffboardingReport |
    Export-Csv `
        -Path $ReportPath `
        -NoTypeInformation

Write-Host ""
Write-Host "Pre-offboarding report created successfully."
Write-Host "Report location: $ReportPath"