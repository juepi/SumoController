################################# SUMO Controller Failsafe script ##################################
### Author: jpichlbauer
####################################################################################################
# Use invariant Culture to avoid problems with comma seperator
[System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture;

# Load configuration
Import-Module $PSScriptRoot\configuration.ps1 -ErrorAction Stop -Force

# Local Script Variables
# Hour of Day when to turn SUMO On and Off
$TimeTable = [hashtable] @{}
$TimeTable.OnAtHour = @("9","15")
$TimeTable.OffAtHour = @("11","18")


########## Functions #############
# Load common Functions

Import-Module ($SumoController.BaseDir + "\Common-functions.ps1") -ErrorAction Stop -Force




########################## MAIN ##########################################
write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: Failsafe script started!") | Out-File -append -filepath $SumoController.PSLog
$SumoController.State = 'Failsafe'

while (($SumoController.Request -eq 'Run') -and (WaitUntilFull5Minutes))
{
    # get current SUMO State
    $SumoController.SumoState = Get-SumoState

    # If SUMO State is 2, exit (failsafe script probably running because SUMO not reachable)
    if ($SumoController.SumoState -eq 2)
    {
        write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: SumoState is 2, sumo-pj.mik unreachable, program will exit.") | Out-File -append -filepath $SumoController.PSLog
        #Send-Email -Type ERROR -Message ("Failsafe script will exit, sumo-pj.mik not reachable.") | Out-Null
        Write-Error "FAILSAFE-SUMO-Controller: SumoState is 2, sumo-pj.mik unreachable, program will exit." -ErrorAction Stop
    }

    if ($TimeTable.OnAtHour -eq (Get-Date).Hour)
    {
        if ($SumoController.SumoState -ne '1')
        {
            if ((Set-SumoState -State 1) -eq $true)
            {
                write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: SUMO started.") | Out-File -append -filepath $SumoController.PSLog
                Send-Email -Type INFO -Message ("Failsafe script started SUMO.") | Out-Null
                $SumoController.SumoState = 1
            }
            else
            {
                # Error, retry
                write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: Set-SumoState 1 failed, retrying..") | Out-File -append -filepath $SumoController.PSLog
                Start-Sleep -Seconds 5
                if ((Set-SumoState -State 1) -eq $true)
                {
                    write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: SUMO started on 2nd try.") | Out-File -append -filepath $SumoController.PSLog
                    Send-Email -Type INFO -Message ("Failsafe script started SUMO.") | Out-Null
                    $SumoController.SumoState = 1
                }
                else
                {
                    write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: Failed to start SUMO!") | Out-File -append -filepath $SumoController.PSLog
                    Send-Email -Type ERROR -Message ("Failsafe script FAILED to started SUMO.") -Priority high | Out-Null
                    $SumoController.SumoState = 2
                }
            }
        }
    }
    if ($TimeTable.OffAtHour -eq (Get-Date).Hour)
    {
        if ($SumoController.SumoState -ne '0')
        {
            if ((Set-SumoState -State 0) -eq $true)
            {
                write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: SUMO stopped.") | Out-File -append -filepath $SumoController.PSLog
                Send-Email -Type INFO -Message ("Failsafe script stopped SUMO.") | Out-Null
                $SumoController.SumoState = 0
            }
            else
            {
                # Error, retry
                write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: Set-SumoState 0 failed, retrying..") | Out-File -append -filepath $SumoController.PSLog
                Start-Sleep -Seconds 5
                if ((Set-SumoState -State 0) -eq $true)
                {
                    write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: SUMO stopped on 2nd try.") | Out-File -append -filepath $SumoController.PSLog
                    Send-Email -Type INFO -Message ("Failsafe script stopped SUMO.") | Out-Null
                    $SumoController.SumoState = 0
                }
                else
                {
                    write-output ((get-date).ToString() + ":: FAILSAFE-SUMO-Controller: Failed to stop SUMO!") | Out-File -append -filepath $SumoController.PSLog
                    Send-Email -Type ERROR -Message ("Failsafe script FAILED to stop SUMO.") | Out-Null
                    $SumoController.SumoState = 2
                }
            }
        }
    }
}