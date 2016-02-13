################################# SUMO Controller Failsafe script ##################################
### Author: jpichlbauer
####################################################################################################
# Use invariant Culture to avoid problems with comma seperator
[System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture;

#region Mail Alerting
# Mail alerting
$MailSource="editme"
$MailDest="editme"
$MailSubject="Failsafe-Sumo-Controller "
$MailText="SUMO Controller reports:`n`n"
$MailSrv="editme"
$MailPort="25"
$MailPass = ConvertTo-SecureString "yourSMTPpassword"-AsPlainText -Force
$MailCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "yourSMTPuser",$MailPass
#endregion

if ($SumoController -eq $null)
{
    $SumoController = [hashtable] @{}
    $SumoController.State = 'Failsafe'
    $SumoController.Request = 'Run'
    $SumoController.SumoState = [int]0
    $SumoController.BaseDir = $PSScriptRoot
    $SumoController.PSLog = "$($PSScriptRoot)\logs\SUMO-Controller.log"
    $SumoController.WZCsv = "$($SumoController.BaseDir)\data\TempWZ-Sumo.csv"
    $SumoController.WWWroot = "C:\inetpub\wwwroot"
    $SumoController.StatHTML = "$($SumoController.WWWroot)\index.html"
    $SumoController.SumoHost = "sumo-pj.mik"
    $SumoController.SumoURL = ("http://" + $SumoController.SumoHost)
    $SumoController.SumoON = ($SumoController.SumoURL + "/SUMO=ON")
    $SumoController.SumoOFF = ($SumoController.SumoURL + "/SUMO=OFF")
    $SumoController.SumoResponseOn = "SUMO state is now: On"
    $SumoController.SumoResponseOff = "SUMO state is now: Off"
    #Timout Value for Invoke-Webrequest
    $SumoController.WebReqTimeout = [int]'15'
}

# Local Script Variables
# Hour of Day when to turn SUMO On and Off
$TimeTable = [hashtable] @{}
$TimeTable.OnAtHour = @("5","15")
$TimeTable.OffAtHour = @("8","19")


########## Functions #############
# Load common Functions

try
{
    . $($SumoController.BaseDir + "\Common-functions.ps1")
}
catch
{
    Write-Error "Failed to load required functions from $($SumoController.BaseDir)\Common-functions.ps1 !" -ErrorAction Stop
}




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
    # Write index.html for IIS
    CreateStatusHTML -OutFile $SumoController.StatHTML | Out-Null
}