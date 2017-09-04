################################# SUMO Controller Startup script ##################################
### Author: jpichlbauer
###################################################################################################
# handles startup of backend and synchronized collections for runtime config changes
# fetches and updates runtime config changes from various sources (jnode web frontend and MQTT)

# Use invariant Culture to avoid problems with comma seperator
[System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture;

# Load configuration
Import-Module $PSScriptRoot\configuration.ps1 -ErrorAction Stop

#region ############################## Load functions #############################################

Import-Module $($SumoController.BaseDir + "\Common-functions.ps1") -ErrorAction Stop

#endregion ========================================================================================

#region ########### Local Settings and Variables ##################################################
# Helpers to detect SUMO state changes
$Script:PrevCtrlSumoState = $SumoController.SumoState
$Script:PrevMqttSumoState = [int]"0"
#endregion ========================================================================================

#region ########### Local Functions ###############################################################
function write-log ([string]$message)
{
    write-output ((get-date).ToString() + ":: Startup.ps1:: " + $message) | Out-File -append -filepath $SumoController.PSLog
}
#endregion ========================================================================================


#region ############# Start SUMO Controller Task ##################################################

# Setup SUMO Controller Task
$Runspace = [Runspacefactory]::CreateRunspace()
$Runspace.Open()
$Runspace.SessionStateProxy.SetVariable('SumoSettings',$SumoSettings)
$Runspace.SessionStateProxy.SetVariable('SumoController',$SumoController)
$Runspace.SessionStateProxy.SetVariable('Mail',$Mail)
$Runspace.SessionStateProxy.SetVariable('MQTT',$MQTT)
$Runspace.SessionStateProxy.SetVariable('SensorRange',$SensorRange)

$SumoControllerTask = [PowerShell]::Create()
$SumoControllerTask.Runspace = $Runspace

$SumoControllerTask.AddScript(
{
    # Hardcoded Path needed here - for whatever reason
    & C:\scripts\SUMO-Controller\BackendWrapper.ps1
}) | Out-Null

$Handle = $SumoControllerTask.BeginInvoke()
write-log -message "SumoControllerTask has been started."
#endregion ========================================================================================



#region ################# Handle periodic Config Sync with MQTT / FHEM Frontend ###################

while ($Handle.IsCompleted -eq $false)
{
    Start-Sleep -Seconds 23
    # Sync active config from FHEM / MQTT Settings
    # Verify and import new config settings

    foreach ($HourVal in $Startup.HourValues)
    {
        # build MQTT hashtable entry
        [string]$CurrentTopic = 'T_FHEM_' + $HourVal
        try { [single]$CurrentValue = (Get-MqttTopic -Topic $MQTT.$CurrentTopic) }
        catch { [single]$CurrentValue = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.$CurrentTopic + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { $CurrentValue = [int]$CurrentValue }
        catch { write-log -message "Warn: $($HourVal) value not convertible to Int: $($CurrentValue)" ; continue }
        if (($CurrentValue -ge 0) -and ($CurrentValue -le 23))
        {
            #Data valid
            if ($CurrentValue -ne $SumoSettings.$HourVal)
            {
                $SumoSettings.$HourVal = $CurrentValue
                write-log -message "New value set for $($HourVal): $($CurrentValue)"
            }
        }
        else
        {
            # Data invalid
            write-log -message "Warning: New value for $($HourVal) not within plausible range: $($CurrentValue). Value ignored."
        }
    }

    foreach ($TempVal in $Startup.TempValues)
    {
        # build MQTT hashtable entry
        [string]$CurrentTopic = 'T_FHEM_' + $TempVal
        try { [single]$CurrentValue = (Get-MqttTopic -Topic $MQTT.$CurrentTopic) }
        catch { [single]$CurrentValue = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.$CurrentTopic + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }

        # Verify Data
        if (VerifySensorVal -Val $CurrentValue -Min $Startup.MinTemp -Max $Startup.MaxTemp)
        {
            #Data valid
            if ($CurrentValue -ne $SumoSettings.$TempVal)
            {
                $SumoSettings.$TempVal = $CurrentValue
                write-log -message "New value set for $($TempVal): $($CurrentValue)"
            }
        }
        else
        {
            # Data invalid
            write-log -message "Warning: New value for $($TempVal) not within plausible range: $($CurrentValue). Value ignored."
        }
    }

    foreach ($BoolVal in $Startup.BoolValues)
    {
    # build MQTT hashtable entry
    [string]$CurrentTopic = 'T_FHEM_' + $BoolVal
    try { [string]$CurrentValue = (Get-MqttTopic -Topic $MQTT.$CurrentTopic) }
    catch { [string]$CurrentValue = 'invalid'; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.$CurrentTopic + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        # Check if value is valid
        if ($CurrentValue -match "on|off")
        {
            # convert string to bool
            switch ($CurrentValue)
            {
                on { $CurrentValue = [bool]$true }
                off { $CurrentValue = [bool]$false }
            }
            # set new value
            if ($SumoSettings.$BoolVal -ne $CurrentValue)
            {
                $SumoSettings.$BoolVal = $CurrentValue
                write-log -message "Flag $($BoolVal) set to $($CurrentValue)."
            }
        }
        else
        {
            # Data invalid
            write-log -message "Warning: New value for $($BoolVal) not valid: $($CurrentValue). Value ignored."
        }
    }


    # Check if a SUMO state change is requested by FHEM / MQTT

    try { [string]$MqttSumoState = (Get-MqttTopic -Topic $MQTT.T_FHEM_SumoState) }
    catch { [string]$MqttSumoState = 'invalid'; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.T_FHEM_SumoState + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }

    # Check if value is valid and handle state changes
    if ($MqttSumoState -match "on|off")
    {
        # convert string to corresponding SUMO state
        switch ($MqttSumoState)
        {
            on { $MqttSumoState = [int]"1" }
            off { $MqttSumoState = [int]"0" }
        }
        # SUMO State changed by Controller since last loop?
        if ($SumoController.SumoState -ne $Script:PrevCtrlSumoState)
        {
            # yes, Update MQTT FHEM Topic if SUMO is in a valid state
            if ($SumoController.SumoState -lt 2)
            {
                Set-MqttTopic -Topic $MQTT.T_FHEM_SumoState -Value $MQTT.FhemIntToOnOff[$SumoController.SumoState] -Retain | Out-Null
                write-log -message "Topic $($MQTT.T_FHEM_SumoState) updated due to controller state change, new state: $($MQTT.FhemIntToOnOff[$SumoController.SumoState])"
            }
        }
        # SUMO state change requested by FHEM since last loop?
        if (($MqttSumoState -ne $Script:PrevMqttSumoState) -and ($MqttSumoState -ne $SumoController.SumoState))
        {
            # yes, set SUMO state; controller script will update SumoSettings on next loop
            if ((Set-SumoState -State $MqttSumoState) -eq $true)
            {
                write-log -message "New SUMO state set due to FHEM request. New state: $($MqttSumoState)"
            }
            else
            {
                # Error, retry
                write-log -message "Set-SumoState $($MqttSumoState) failed, retrying.."
                Start-Sleep -Seconds 5
                if ((Set-SumoState -State $MqttSumoState) -eq $true)
                {
                    write-log -message "New SUMO state set due to FHEM request. New state: $($MqttSumoState)"
                }
                else
                {
                    write-log -message "FAILED to set new SUMO state ($($MqttSumoState)) due to FHEM request."
                }
            }            
        }
        # Update SUMO State helpers for next loop
        $Script:PrevCtrlSumoState = $SumoController.SumoState
        $Script:PrevMqttSumoState = $MqttSumoState
    }
    else
    {
        # Data invalid
        write-log -message "Warning: Value for $($MQTT.T_FHEM_SumoState) not valid: $($MqttSumoState). Value ignored."
    }
}

write-log -message "SumoControllerTask has ended. Startup.ps1 stopped."

#endregion ========================================================================================