################################# SUMO Controller script ##########################################
### Author: jpichlbauer
### Attention: Script must be executed by Startup.ps1
###################################################################################################
# Use invariant Culture to avoid problems with comma seperator
[System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture;

#region ############################## Load functions #############################################

Import-Module $($SumoController.BaseDir + "\Common-functions.ps1") -ErrorAction Stop

#endregion ========================================================================================


#region ########### Local Settings and Variables ##################################################

#region Script Variables
# Display Format for Datetime: 31.12.2015 23:13
$GTFormat = "%d.%m.%Y %H:%M"
# Date Format for matching holidays from ICS
$HolidayDateUFormat = "%Y%m%d"


# Helper variables
$LastWZTempValOK = Get-Date
$LastWZRelHumValOK = Get-Date
[Single]$WZTempLastPlausible = "22.0"
[Single]$WZRelHumLastPlausible = "50.0"
$SumoSessionStart = Get-Date


# Create PSObject for CSV output
$DataSet = New-Object PSObject
$DataSet | Add-Member -MemberType NoteProperty -Name Datum  -Value ''
$DataSet | Add-Member -MemberType NoteProperty -Name TempWZ -Value ([single]'0.0')
$DataSet | Add-Member -MemberType NoteProperty -Name RelHumWZ -Value ([int]'0')
$DataSet | Add-Member -MemberType NoteProperty -Name SumoState -Value ([int]'0')
$DataSet | Add-Member -MemberType NoteProperty -Name SumoSessionHours -Value ([Single]'0')
$DataSet | Add-Member -MemberType NoteProperty -Name SumoOverallHours -Value ([Single]'0')
#endregion
#endregion ========================================================================================



#region ########## Local Functions ################################################################

function Control-Sumo([Single]$Temp)
{
    # Check if Weekend or Holiday
    $IsWeekendday=[bool]((get-date).DayOfWeek -match 'Friday|Saturday|Sunday')
    $IsHoliday=[bool]($Holidays -match "$(Get-Date -UFormat $($HolidayDateUFormat))")
    if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Day/Night criterias: IsWeekendday=$($IsWeekendday) | IsHoliday=$($IsHoliday) | ForceWeekend=$($SumoSettings.ForceWeekend) | NOT ForceWorkday=$(-not $SumoSettings.ForceWorkday)" -Logfile $SumoController.DebugLog }

    if (($IsWeekendday -or $IsHoliday -or $SumoSettings.ForceWeekend) -and (-not $SumoSettings.ForceWorkday))
    {
        if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Weekend or holiday" -Logfile $SumoController.DebugLog }
        [int]$DayStartHour = $SumoSettings.WeekendDayStartHour
        [int]$DayEndHour = $SumoSettings.WeekendDayEndHour
    }
    else
    {
        if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Workday" -Logfile $SumoController.DebugLog }
        [int]$DayStartHour = $SumoSettings.DayStartHour
        [int]$DayEndHour = $SumoSettings.DayEndHour
        
    }
    if (((Get-Date).Hour -ge $DayStartHour) -and ((Get-Date).Hour -le $DayEndHour))
    {
        # Day
        if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Day time" -Logfile $SumoController.DebugLog }
        if ( ($Temp -lt $SumoSettings.MinDayTemp) -and ($SumoController.SumoState -eq "0"))
        {
            if ($SumoSettings.ManualMode)
            {
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: ManualMode enabled, not starting SUMO." -Logfile $SumoController.DebugLog }
                return 0
            }

            if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: SUMO must be turned on" -Logfile $SumoController.DebugLog }
            if ( $SumoController.StateChangeRequested -ne $SumoController.IgnoreStateChangeReq )
            {
                # Ignore State Change request and return current state
                $SumoController.StateChangeRequested ++
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: StateChangeRequested increased to $($SumoController.StateChangeRequested)" -Logfile $SumoController.DebugLog }
                return Get-SumoState
            }
            else
            {
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Turning on SUMO" -Logfile $SumoController.DebugLog }
                if ((Set-SumoState -State 1) -eq $true)
                {
                    $SumoController.StateChangeRequested = 0
                    return 1
                }
                else
                {
                    # Error, retry
                    write-log -message "Control-Sumo: Set-SumoState 1 failed, retrying.."
                    Start-Sleep -Seconds 5
                    if ((Set-SumoState -State 1) -eq $true)
                    {
                        $SumoController.StateChangeRequested = 0
                        return 1
                    }
                    else
                    {
                        return 2
                    }
                }
            }
        }
        elseif ( ($Temp -ge $SumoSettings.MaxDayTemp) -and ($SumoController.SumoState -eq "1"))
        {
            if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: SUMO must be turned off." -Logfile $SumoController.DebugLog }
            if ( $SumoController.StateChangeRequested -ne $SumoController.IgnoreStateChangeReq )
            {
                # Ignore State Change request and return current state
                $SumoController.StateChangeRequested ++
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: StateChangeRequested increased to $($SumoController.StateChangeRequested)" -Logfile $SumoController.DebugLog }
                return Get-SumoState
            }
            else
            {
                # Verify that SUMO has run longer than minimum runtime
                if ($DataSet.SumoSessionHours -lt $SumoController.MinRuntime)
                {
                    if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Session shorter than MinRuntime, do not turn off yet." -Logfile $SumoController.DebugLog }
                    return 1
                }
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Turning off SUMO" -Logfile $SumoController.DebugLog }
                if ((Set-SumoState -State 0) -eq $true)
                {
                    $SumoController.StateChangeRequested = 0
                    return 0
                }
                else
                {
                    # Error, retry
                    write-log -message "Control-Sumo: Set-SumoState 0 failed, retrying.."
                    Start-Sleep -Seconds 5
                    if ((Set-SumoState -State 0) -eq $true)
                    {
                        $SumoController.StateChangeRequested = 0
                        return 0
                    }
                    else
                    {
                        return 2
                    }
                }
            }
        }
        else
        {
            # Temperature within range, no change needed, return current SUMO Status
            if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Temperature within range, no change needed." -Logfile $SumoController.DebugLog }
            return Get-SumoState
        }
    }
    else
    {
        # Night
        if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Night time" -Logfile $SumoController.DebugLog }
        if ( ($Temp -lt $SumoSettings.MinNightTemp) -and ($SumoController.SumoState -eq "0"))
        {
            if ($SumoSettings.ManualMode)
            {
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: ManualMode enabled, not starting SUMO." -Logfile $SumoController.DebugLog }
                return 0
            }

            if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: SUMO needs to be turned on" -Logfile $SumoController.DebugLog }
            if ( $SumoController.StateChangeRequested -ne $SumoController.IgnoreStateChangeReq )
            {
                # Ignore State Change request and return current state
                $SumoController.StateChangeRequested ++
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: StateChangeRequested increased to $($SumoController.StateChangeRequested)" -Logfile $SumoController.DebugLog }
                return Get-SumoState
            }
            else
            {
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Turning on SUMO" -Logfile $SumoController.DebugLog }
                if ((Set-SumoState -State 1) -eq $true)
                {
                    $SumoController.StateChangeRequested = 0
                    return 1
                }
                else
                {
                    # Error, retry
                    write-log -message "Control-Sumo: Set-SumoState 1 failed, retrying.."
                    Start-Sleep -Seconds 5
                    if ((Set-SumoState -State 1) -eq $true)
                    {
                        $SumoController.StateChangeRequested = 0
                        return 1
                    }
                    else
                    {
                        return 2
                    }
                }
            }
        }
        elseif ( ($Temp -ge $SumoSettings.MaxNightTemp) -and ($SumoController.SumoState -eq "1"))
        {
            # SUMO must be turned OFF
            if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: SUMO must be turned off" -Logfile $SumoController.DebugLog }
            if ( $SumoController.StateChangeRequested -ne $SumoController.IgnoreStateChangeReq )
            {
                # Ignore State Change request and return current state
                $SumoController.StateChangeRequested ++
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: StateChangeRequested increased to $($SumoController.StateChangeRequested)" -Logfile $SumoController.DebugLog }
                return Get-SumoState
            }
            else
            {
                # Verify that SUMO has run longer than minimum runtime
                if ($DataSet.SumoSessionHours -lt $SumoController.MinRuntime)
                {
                    # Session shorter than MinRuntime, do not turn off yet
                    if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Session shorter than MinRuntime, do not turn off yet" -Logfile $SumoController.DebugLog }
                    return 1
                }
                if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Turning off SUMO" -Logfile $SumoController.DebugLog }
                if ((Set-SumoState -State 0) -eq $true)
                {
                    $SumoController.StateChangeRequested = 0
                    return 0
                }
                else
                {
                    # Error, retry
                    write-log -message "Control-Sumo: Set-SumoState 0 failed, retrying.."
                    Start-Sleep -Seconds 5
                    if ((Set-SumoState -State 0) -eq $true)
                    {
                        $SumoController.StateChangeRequested = 0
                        return 0
                    }
                    else
                    {
                        return 2
                    }
                }
            }
        }
        else
        {
            # Temperature within valid range, no change needed, return current SUMO Status
            if ($SumoSettings.Debug) { write-log -message "Control-Sumo:: Temperature within valid range, no change needed" -Logfile $SumoController.DebugLog }
            return Get-SumoState
        }
    }
}

function write-log ([string]$message,[string]$Logfile)
{
    if (!$Logfile)
    {
        $Logfile = $SumoController.PSLog
    }
    write-output ((get-date).ToString() + ":: " + $message) | Out-File -append -filepath $Logfile
}

#endregion ========================================================================================



#region ################ Main #####################################################################

$SumoController.State = 'Running'
write-log -message "SUMO-Controller-MQTT: script started."

# Load Holidays from ICS Calendar
if (Test-Path $SumoController.HolidaysICS)
{
    $Holidays = gc $SumoController.HolidaysICS | ? { $_ -match "DTSTART"}
}
else
{
    $Holidays = "none"
    write-log -message "Main: Holiday file not found, no holidays loaded!"
}

# Get historic data from log (if available)
if (Test-Path $SumoController.WZCsv)
{
    $HistoricData = Import-Csv -Delimiter ";" -Encoding UTF8 -Path $SumoController.WZCsv

    #import most recent SumoSessionHours
    $DataSet.SumoSessionHours = [Single]($HistoricData[-1].SumoSessionHours)
    if ($DataSet.SumoSessionHours -ne '0')
    {
        # Restore previous SUMO Session
        $SumoSessionStart = (Get-Date).AddHours(-$DataSet.SumoSessionHours)
    }
    #import SumoOverallHours
    $DataSet.SumoOverallHours = [Single]($HistoricData[-1].SumoOverallHours)

    Clear-Variable HistoricData
    write-log -message "Main: Finished importing historic data."
}

#Update variable to match current SUMO state
$SumoController.SumoState = Get-SumoState


# Start Processing
while (($SumoController.Request -eq 'Run') -and (WaitUntilFull5Minutes))
{
    # Verify if Sensor is online (Value published within last 30 minutes)
    # CAUTION: this requires ElasticSearch-Logger script to be running or to update Sensor Status topic if a fault occurs!
    if ((Get-MqttTopic -Topic $MQTT.Topic_WZ_Status) -notmatch $MQTT.VAL_StatusSensorDead)
    {
        # Sensor online
        $DataSet.Datum = Get-Date -UFormat $GTFormat
        try { [single]$WZTempC = (Get-MqttTopic -Topic $MQTT.Topic_WZ_Temp) }
        catch { [single]$WZTempC = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_WZ_Temp + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { [Single]$WZRelHum = (Get-MqttTopic -Topic $MQTT.Topic_WZ_RH) }
        catch { [single]$WZRelHum = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_WZ_RH + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }

        # Verify Sensor Values
        if (VerifySensorVal -Val $WZTempC -Min $SensorRange.WZTempMin -Max $SensorRange.WZTempMax)
        {
            $DataSet.TempWZ = [Single]("{0:N2}" -f $WZTempC)
            $WZTempLastPlausible = $DataSet.TempWZ
            # Sensor Value OK, store TimeDate
            $LastWZTempValOK = Get-Date
        }
        else
        {
            # Reported Value is implausible, use old value if not outdated
            if ($LastWZTempValOK.AddMinutes($SumoController.SensMaxAge) -gt (get-date))
            {
                # Sensor within grace period
                write-log -message "Main: Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_Temp)). Reported Value was: $($WZTempC)"
                $DataSet.TempWZ = $WZTempLastPlausible
            }
            else
            {
                # Sensor outdated, stop SUMO and quit
                if ((Set-SumoState -State 0) -eq $false)
                {
                    # Error, retry
                    write-log -message "Main: Sensor Data outdated! Set-SumoState 0 failed, retrying.."
                    Start-Sleep -Seconds 5
                    Set-SumoState -State 0 | Out-Null
                }
                Send-Email -Type ERROR -Message ("Temp-WZ nicht erreichbar, Temperatur Sensordaten ungültig!`nSumo wurde gestoppt, Get-SumoState meldet: " + (Get-SumoState) + "`nDie Programmausführung wurde beendet!") -Priority high | Out-Null
                write-log -message "Main: VerifySensorValues: Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_Temp)) within $($SumoController.SensMaxAge) minutes! Sensor Data outdated, SUMO stopped! Get-SumoState=$(Get-SumoState)"
                $SumoController.State = "Killed"
                Write-Error "Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_Temp)) within $($SumoController.SensMaxAge) minutes! Sensor Data outdated, SUMO stopped!" -ErrorAction Stop
            }
        }

        if (VerifySensorVal -Val $WZRelHum -Min $SensorRange.WZRelHumMin -Max $SensorRange.WZRelHumMax)
        {
            $DataSet.RelHumWZ = [int]("{0:N0}" -f $WZRelHum)
            $WZRelHumLastPlausible = $DataSet.RelHumWZ
            $LastWZRelHumValOK = Get-Date
        }
        else
        {
            # Reported Value is implausible, use old value if not outdated
            if ($LastWZRelHumValOK.AddMinutes($SumoController.SensMaxAge) -gt (get-date))
            {
                # Sensor within grace period
                write-log -message "Main: Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_RH)). Reported Value was: $($WZRelHum)"
                $DataSet.RelHumWZ = $WZRelHumLastPlausible
            }
            else
            {
                # Sensor outdated
                # Just log the error, we actually don't care about humidity
                write-log -message "Main: VerifySensorValues: Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_RH)) within $($SumoController.SensMaxAge) minutes. This is non fatal."
            }
        }        


        #################################################
        # Sensors have been verified, set SUMO actions
        #################################################
        $SumoOldState = $SumoController.SumoState
        $SumoController.SumoState = [Int](Control-Sumo -Temp $DataSet.TempWZ)
        $DataSet.SumoState = $SumoController.SumoState

        # Update Sumo Runtime
        if ( ($SumoOldState -eq "0") -and ($SumoController.SumoState -eq "1") )
        {
            # Sumo was turned on, start new session
            $SumoSessionStart = Get-Date
            $DataSet.SumoSessionHours = 0
            if ($SumoController.SendInfoMail) { Send-Email -Type INFO -Message ("Sumo gestartet.") | Out-Null }
        }
        elseif ( ($SumoOldState -eq $SumoController.SumoState) -and ($SumoController.SumoState -eq "1") )
        {
            # Sumo is still running, update session hours
            $DataSet.SumoSessionHours = [Single]("{0:N2}" -f((get-date) - $SumoSessionStart).TotalHours)
        }
        elseif ( ($SumoOldState -ne "0") -and ($SumoController.SumoState -eq "0") )
        {
            # Sumo has been turned off, finish session and update OverallHours
            # also catches case if previous Sumo state was 2 (controller unreachable / rebooted)
            $DataSet.SumoSessionHours = [Single]("{0:N2}" -f((get-date) - $SumoSessionStart).TotalHours)
            $DataSet.SumoOverallHours = [Single]("{0:N2}" -f($DataSet.SumoOverallHours + $DataSet.SumoSessionHours))
            $DataSet.SumoSessionHours = 0
            if ($SumoController.SendInfoMail) { Send-Email -Type INFO -Message ("Sumo gestartet.") | Out-Null }
        }
        elseif ( ($SumoOldState -eq "0") -and ($SumoController.SumoState -eq "0") -and ($DataSet.SumoSessionHours -ne 0) )
        {
            # SUMO-Controller.ps1 has ended due to an error while SUMO was ON.
            # SUMO is now off (turned off by error handling), previously imported SessionHours need to be added to the OverallHours
            # do not send email in this case
            $DataSet.SumoSessionHours = [Single]("{0:N2}" -f((get-date) - $SumoSessionStart).TotalHours)
            $DataSet.SumoOverallHours = [Single]("{0:N2}" -f($DataSet.SumoOverallHours + $DataSet.SumoSessionHours))
            $DataSet.SumoSessionHours = 0
        }
        else
        {
            # probably an error
            if ($SumoController.SumoState -eq "2")
            {
                # sleep some seconds and try one last time to get current SUMO state
                Start-Sleep -Seconds 15
                if ( (Get-SumoState) -eq 2)
                {
                    Send-Email -Type ERROR -Message ("Control-Sumo setzt Sumo Status 2, sumo-pj.mik nicht erreichbar, Programmausführung wird beendet!") -Priority high | Out-Null
                    write-log -message "Main: Control-Sumo reports status 2, sumo-pj.mik not reachable! Program will exit!"
                    $SumoController.State = "Killed"
                    write-error "Main: Control-Sumo reports status 2, sumo-pj.mik not reachable! Program will exit!" -ErrorAction Stop
                }

            }
        }

        # DataSet successfully updated, save to CSV..
        $DataSet | Export-Csv -Delimiter ";" -Encoding UTF8 -Append -NoTypeInformation -Path $SumoController.WZCsv

        # .. set SUMO status in MQTT topic..
        Set-MqttTopic -Topic $MQTT.Topic_WZ_Sumo -Value $DataSet.SumoState -Retain | Out-Null

        # write debug log if requested
        if ($SumoSettings.Debug -eq $true)
        {
            if ((Write-DebugLog -Logfile $SumoController.DebugLog) -ne $true)
            {
                write-log -message "Main: Failed to write debug output to $SumoController.DebugLog !"
            }
        }
                
    }
    else
    {
        # Sensor dead, stop SUMO and quit
        if ((Set-SumoState -State 0) -eq $false)
        {
            # Error, retry
            write-log -message "Main: Sensor status dead! Set-SumoState 0 failed, retrying.."
            Start-Sleep -Seconds 5
            Set-SumoState -State 0 | Out-Null
        }
        Send-Email -Type ERROR -Message ("Temp-WZ Sensor nicht erreichbar, Sensordaten ungültig!`nSumo wurde gestoppt, Get-SumoState meldet: " + (Get-SumoState) + "`nDie Programmausführung wurde beendet!") -Priority high | Out-Null
        write-log -message "Main: Temp-WZ Sensor Status dead, SUMO stopped! Get-SumoState=$(Get-SumoState)"
        $SumoController.State = "Killed"
        Write-Error "Main: Temp-WZ Sensor Status dead, SUMO stopped!" -ErrorAction Stop
    }
}
#endregion ========================================================================================