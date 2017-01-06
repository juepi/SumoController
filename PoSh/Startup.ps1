# SUMO Controller Web Frontend
# Will also start Controller script to allow Configuration changes in the frontend

# Use invariant Culture to avoid problems with comma seperator
[System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture;

# Load configuration
Import-Module $PSScriptRoot\configuration.ps1 -ErrorAction Stop

# Check for Web Frontend
if (Test-Path $WebCfg.CfgINI)
{
    #INI file available, assume Webinterface is working
    $Script:WebCfgModified = (Get-Item $WebCfg.CfgINI).LastWriteTime
    # Helper Variable to load INI Settings at startup
    $Script:FirstRun = $true
}
else
{
    # Webinterface not available
    $WebCfg.Available = $false
}

#region ########### Local Functions ###############################################################
function VerifyTempVal([Single]$Val,[Single]$Min,[Single]$Max)
{
    # Verify if Sensor Value is between min and max
    if ( ($Val -ge $Min) -and ($Val -le $Max) )
    {
        return $true
    }
    else
    {
        return $false
    }
}

function write-log ([string]$message)
{
    write-output ((get-date).ToString() + ":: Startup.ps1:: " + $message) | Out-File -append -filepath $SumoController.PSLog
}
#endregion ========================================================================================


#region ############# Main ########################################################################

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

while ($Handle.IsCompleted -eq $false)
{
    Start-Sleep -Seconds 23
    if ($WebCfg.Available)
    {
        # Fetch new config if modified date of config.ini is newer
        if (((Get-Item $WebCfg.CfgINI).LastWriteTime -gt $WebCfgModified) -or $Script:FirstRun)
        {
            $Script:WebCfgModified = (Get-Item $WebCfg.CfgINI).LastWriteTime
            if ($Script:FirstRun)
            {
                $Script:FirstRun = $false
                write-log -message "Loading SUMO config data from WebUI due to script startup."
            }

            # Get recent configuration from NodeJS / INI file
            try
            {
                $WebReqData = Invoke-WebRequest -Uri $WebCfg.GetConfigURI -TimeoutSec $WebCfg.WebReqTimeout | ConvertFrom-Json
            }
            catch
            {
                write-log -message ("Invoke-Webrequest failed to fetch WebUI config. Exception:" + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," "))
                return
            }

            write-log -message "New config data from WebUI fetched."
            # Verify and import new config settings
            foreach ($HourVal in $WebCfg.HourValues)
            {
                try { $WebReqData.$HourVal = [int]$WebReqData.$HourVal }
                catch { write-log -message "Warn: $($HourVal) value not convertible to Int: $($WebReqData.$HourVal)" ; continue }
                if (($WebReqData.$HourVal -ge 0) -and ($WebReqData.$HourVal -le 23))
                {
                    #Data valid
                    if ($WebReqData.$HourVal -ne $SumoSettings.$HourVal)
                    {
                        $SumoSettings.$HourVal = $WebReqData.$HourVal
                        write-log -message "New value set for $($HourVal): $($WebReqData.$HourVal)"
                    }
                }
                else
                {
                    # Data invalid
                    write-log -message "Warn: New value for $($HourVal) not within plausible range: $($WebReqData.$HourVal). Value ignored."
                    continue
                }
            }

            $TempValsOK = $true
            $TempValsChanged = $false
            foreach ($TempVal in $WebCfg.TempValues)
            {
                try { $WebReqData.$TempVal = [Single]$WebReqData.$TempVal }
                catch { write-log -message "Error: $($TempVal) value not convertible to Single: $($WebReqData.$TempVal). Value ignored." ; $TempValsOK = $false ; continue }
                if (VerifyTempVal -Val $WebReqData.$TempVal -Min $WebCfg.MinTemp -Max $WebCfg.MaxTemp)
                {
                    #Data valid, check if changed
                    if ($WebReqData.$TempVal -ne $SumoSettings.$TempVal)
                    {
                        $TempValsChanged = $true
                    }
                    continue
                }
                else
                {
                    # Data invalid
                    write-log -message "New value for $($TempVal) not within plausible range: $($WebReqData.$TempVal). Value ignored."
                    $TempValsOK = $false
                    continue
                }
            }
            # make sure Min-temps are lower than Max-temps before using new values
            if ($TempValsOK -and $TempValsChanged)
            {
                if ($WebReqData.MinDayTemp -lt $WebReqData.MaxDayTemp)
                {
                    $SumoSettings.MinDayTemp = $WebReqData.MinDayTemp
                    $SumoSettings.MaxDayTemp = $WebReqData.MaxDayTemp
                    write-log -message "New Day Temperature values set: $($WebReqData.MinDayTemp) to $($WebReqData.MaxDayTemp)."
                }
                else
                {
                    write-log -message "Warn: New MinDayTemp ($($WebReqData.MinDayTemp)) not less than new MaxDayTemp ($($WebReqData.MaxDayTemp)). Ignoring Values."
                }

                if ($WebReqData.MinNightTemp -lt $WebReqData.MaxNightTemp)
                {
                    $SumoSettings.MinNightTemp = $WebReqData.MinNightTemp
                    $SumoSettings.MaxNightTemp = $WebReqData.MaxNightTemp
                    write-log -message "New Night Temperature values set: $($WebReqData.MinNightTemp) to $($WebReqData.MaxNightTemp)."
                }
                else
                {
                    write-log -message "Warn: New MinNightTemp ($($WebReqData.MinNightTemp)) not less than new MaxNightTemp ($($WebReqData.MaxNightTemp)). Ignoring Values."
                }
            }

            foreach ($BoolVal in $WebCfg.BoolValues)
            {
                # Check if value exists, if not set to false
                if ($WebReqData.$BoolVal -eq $null)
                {
                    $WebReqData | Add-Member -Name $BoolVal -MemberType NoteProperty -Value $false
                }
                else
                {
                    # convert string to bool
                    switch ($WebReqData.$BoolVal)
                    {
                        true { $WebReqData.$BoolVal = [bool]$true }
                        false { $WebReqData.$BoolVal = [bool]$false }
                        default { $WebReqData.$BoolVal = [bool]$false }
                    }
                }
                if ($SumoSettings.$BoolVal -ne $WebReqData.$BoolVal)
                {
                    $SumoSettings.$BoolVal = $WebReqData.$BoolVal
                    write-log -message "Flag $($BoolVal) set to $($WebReqData.$BoolVal)."
                }
            }

        }
    }

}

write-log -message "SumoControllerTask has ended. Program stopped."

#endregion ========================================================================================