################################# SUMO Controller script ###########################################
### Author: jpichlbauer
####################################################################################################
# Use invariant Culture to avoid problems with comma seperator
[System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture;

#region Desired Temperature Ranges for SUMO
#If Shared Object from Startup.ps1 is not available, define settings
$BackgroundMode = $true
if ($SumoSettings -eq $null)
{
    $SumoSettings = New-Object PSObject
    $SumoSettings | Add-Member -MemberType NoteProperty -Name DayStartHour -Value '14'
    $SumoSettings | Add-Member -MemberType NoteProperty -Name DayEndHour -Value '21'
    $SumoSettings | Add-Member -MemberType NoteProperty -Name WeekendDayStartHour -Value '7'
    $SumoSettings | Add-Member -MemberType NoteProperty -Name WeekendDayEndHour -Value '22'
    $SumoSettings | Add-Member -MemberType NoteProperty -Name MinNightTemp -Value ([Single]'19')
    $SumoSettings | Add-Member -MemberType NoteProperty -Name MaxNightTemp -Value ([Single]'21')
    $SumoSettings | Add-Member -MemberType NoteProperty -Name MinDayTemp -Value ([Single]'21')
    $SumoSettings | Add-Member -MemberType NoteProperty -Name MaxDayTemp -Value ([Single]'23')
    $BackgroundMode = $false
}
# This hashtable contains all common settings for the Backend
if ($SumoController -eq $null)
{
    $SumoController = [hashtable] @{}
    $SumoController.State = 'Running'
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
    # Timeout Value for Invoke-Webrequest (seconds)
    $SumoController.WebReqTimeout = [int]'15'
    # Minimum Runtime for SUMO in Hours
    $SumoController.MinRuntime = [single]'1.5'
}
#endregion


#region MQTT Settings
$MQTT = [hashtable] @{}
$MQTT.MosqSub = "$($env:MOSQUITTO_DIR)\mosquitto_sub.exe"
$MQTT.MosqPub = "$($env:MOSQUITTO_DIR)\mosquitto_pub.exe"
$MQTT.Broker = 'dvb-juepi.mik'
$MQTT.Port = [int]'1883'
$MQTT.ClientID = 'SumoController'
$MQTT.Topic_Test = 'HB7/SumoController/Test'
$MQTT.Topic_WZ_Temp = 'HB7/Indoor/WZ/Temp'
$MQTT.Topic_WZ_RH = 'HB7/Indoor/WZ/RH'
$MQTT.Topic_WZ_Vbat = 'HB7/Indoor/WZ/Vbat'
$MQTT.Topic_WZ_Status = 'HB7/Indoor/WZ/Status'


#region Files
$TempWZCsv = "$($SumoController.BaseDir)\data\TempWZ-Sumo.csv"
$HolidaysICS = "$($SumoController.BaseDir)\data\Feiertage-AT.ics"
$ChartFile = "$($SumoController.WWWroot)\IndoorWZChart.png"
$ChartImgFmt = 'PNG'
#endregion


#region Valid Sensor Ranges
$SensorRange = New-Object PSObject
$SensorRange | Add-Member -MemberType NoteProperty -Name WZTempMin -Value '10'
$SensorRange | Add-Member -MemberType NoteProperty -Name WZTempMax -Value '40'
$SensorRange | Add-Member -MemberType NoteProperty -Name WZRelHumMin -Value '0'
$SensorRange | Add-Member -MemberType NoteProperty -Name WZRelHumMax -Value '100'
$SensorRange | Add-Member -MemberType NoteProperty -Name WZSensVbatMin -Value ([Single]'2.5')
$SensorRange | Add-Member -MemberType NoteProperty -Name WZSensVbatMax -Value ([Single]'3.5')
#endregion

#region Sensor Corrections
#Battery Voltage correction divider (/1000 -> sensor reports milliVolts) plus correction
[int]$VbatCorrDiv = 1051
#endregion

#region Mail Alerting
# Mail alerting
$MailSource="editme"
$MailDest="editme"
$MailSubject="Sumo-Controller "
$MailText="SUMO Controller reports:`n`n"
$MailSrv="smtp-server"
$MailPort="25"
$MailPass = ConvertTo-SecureString "yourSMTPpassword"-AsPlainText -Force
$MailCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "yourSMTPusername",$MailPass
#endregion


#region Script Variables
#Maximum Age for Sensor Values in Minutes
$SensMaxAge = 30
# Display Format for Datetime: 31.12.2015 23:13
$GTFormat = "%d.%m.%Y %H:%M"

# Helpers
$LastWZTempValOK = Get-Date
$LastWZRelHumValOK = Get-Date
$LastWZSensVbatOK = Get-Date
[Single]$WZTempLastPlausible = "22.0"
[Single]$WZRelHumLastPlausible = "50.0"
[Single]$WZSensVbatLastPlausible = "3.0"
$SumoSessionStart = Get-Date
# Ignore Change Requests for SUMO for 2 times to avoid SUMO turning on or off with wrong temp reading or room venting
# Use script scope as variable will be modified in a function
Set-Variable -Name SumoStateChangeRequested -Scope Script
[int]$script:SumoStateChangeRequested = 0
[int]$IgnoreSumoStateChangeRequests = 2
# Load Holidays from ICS Calendar
$Holidays = gc $HolidaysICS | ? { $_ -match "DTSTART"}
$HolidayDateUFormat = "%Y%m%d"


$DataSet = New-Object PSObject
$DataSet | Add-Member -MemberType NoteProperty -Name Datum  -Value ''
$DataSet | Add-Member -MemberType NoteProperty -Name TempWZ -Value ([single]'0.0')
$DataSet | Add-Member -MemberType NoteProperty -Name RelHumWZ -Value ([int]'0')
$DataSet | Add-Member -MemberType NoteProperty -Name WZSensVbat -Value ([Single]'0')
$DataSet | Add-Member -MemberType NoteProperty -Name SumoState -Value ([int]'0')
$DataSet | Add-Member -MemberType NoteProperty -Name SumoSessionHours -Value ([Single]'0')
$DataSet | Add-Member -MemberType NoteProperty -Name SumoOverallHours -Value ([Single]'0')
#endregion

# Load common Functions and Data Visualization

try
{
    . $($SumoController.BaseDir + "\Common-functions.ps1")
    . $($SumoController.BaseDir + "\Data-Visualization.ps1")
}
catch
{
    Write-Error "Failed to load required functions!" -ErrorAction Stop
}


########## Local Functions #############
#region Function-Definitions

function Control-Sumo([Single]$Temp)
{
    # Check if Weekend or Holiday
    if (((get-date).DayOfWeek -eq "Saturday") -or ((get-date).DayOfWeek -eq "Sunday") -or ($Holidays -match "$(Get-Date -UFormat $($HolidayDateUFormat))"))
    {
        #Weekend or Holiday
        [int]$DayStartHour = $SumoSettings.WeekendDayStartHour
        [int]$DayEndHour = $SumoSettings.WeekendDayEndHour
    }
    else
    {
        #not Weekend
        [int]$DayStartHour = $SumoSettings.DayStartHour
        [int]$DayEndHour = $SumoSettings.DayEndHour
        
    }
    if (((Get-Date).Hour -ge $DayStartHour) -and ((Get-Date).Hour -le $DayEndHour))
    {
        #Write-Host "Day"
        if ( ($Temp -lt $SumoSettings.MinDayTemp) -and ($SumoController.SumoState -eq "0"))
        {
            # SUMO must be turned ON
            if ( $script:SumoStateChangeRequested -ne $IgnoreSumoStateChangeRequests )
            {
                # Ignore State Change request and return current state
                $script:SumoStateChangeRequested ++
                return 0
            }
            else
            {
                if ((Set-SumoState -State 1) -eq $true)
                {
                    $script:SumoStateChangeRequested = 0
                    return 1
                }
                else
                {
                    # Error, retry
                    write-output ((get-date).ToString() + ":: Control-Sumo: Set-SumoState 1 failed, retrying..") | Out-File -append -filepath $SumoController.PSLog
                    Start-Sleep -Seconds 5
                    if ((Set-SumoState -State 1) -eq $true)
                    {
                        $script:SumoStateChangeRequested = 0
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
            # SUMO must be turned OFF
            if ( $script:SumoStateChangeRequested -ne $IgnoreSumoStateChangeRequests )
            {
                # Ignore State Change request and return current state
                $script:SumoStateChangeRequested ++
                return 1
            }
            else
            {
                # Verify that SUMO has run longer than minimum runtime
                if ($DataSet.SumoSessionHours -lt $SumoController.MinRuntime)
                {
                    # Session shorter than MinRuntime, do not turn off yet
                    return 1
                }
                if ((Set-SumoState -State 0) -eq $true)
                {
                    $script:SumoStateChangeRequested = 0
                    return 0
                }
                else
                {
                    # Error, retry
                    write-output ((get-date).ToString() + ":: Control-Sumo: Set-SumoState 0 failed, retrying..") | Out-File -append -filepath $SumoController.PSLog
                    Start-Sleep -Seconds 5
                    if ((Set-SumoState -State 0) -eq $true)
                    {
                        $script:SumoStateChangeRequested = 0
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
            return Get-SumoState
        }
    }
    else
    {
        #Write-Host "Night"
        if ( ($Temp -lt $SumoSettings.MinNightTemp) -and ($SumoController.SumoState -eq "0"))
        {
            # SUMO must be turned ON
            if ( $script:SumoStateChangeRequested -ne $IgnoreSumoStateChangeRequests )
            {
                # Ignore State Change request and return current state
                $script:SumoStateChangeRequested ++
                return 0
            }
            else
            {
                if ((Set-SumoState -State 1) -eq $true)
                {
                    $script:SumoStateChangeRequested = 0
                    return 1
                }
                else
                {
                    # Error, retry
                    write-output ((get-date).ToString() + ":: Control-Sumo: Set-SumoState 1 failed, retrying..") | Out-File -append -filepath $SumoController.PSLog
                    Start-Sleep -Seconds 5
                    if ((Set-SumoState -State 1) -eq $true)
                    {
                        $script:SumoStateChangeRequested = 0
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
            if ( $script:SumoStateChangeRequested -ne $IgnoreSumoStateChangeRequests )
            {
                # Ignore State Change request and return current state
                $script:SumoStateChangeRequested ++
                return 1
            }
            else
            {
                if ((Set-SumoState -State 0) -eq $true)
                {
                    $script:SumoStateChangeRequested = 0
                    return 0
                }
                else
                {
                    # Error, retry
                    write-output ((get-date).ToString() + ":: Control-Sumo: Set-SumoState 0 failed, retrying..") | Out-File -append -filepath $SumoController.PSLog
                    Start-Sleep -Seconds 5
                    if ((Set-SumoState -State 0) -eq $true)
                    {
                        $script:SumoStateChangeRequested = 0
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
            return Get-SumoState
        }
    }
}

function write-log ([string]$message)
{
    write-output ((get-date).ToString() + ":: " + $message) | Out-File -append -filepath $SumoController.PSLog
}
#endregion

################ Main ####################

$SumoController.State = 'Running'

if ($BackgroundMode)
{
    write-log -message "SUMO-Controller: SUMO-Controller-MQTT.ps1 script started in Frontend / Backend mode."
}
else
{
    write-log -message "SUMO-Controller: script started without Frontend."
}

# Get historic data from log (if available)
if (Test-Path $SumoController.WZCsv)
{
    if (! $BackgroundMode) {Write-Host "Importing historic data.." -ForegroundColor Green}

    $HistoricData = Import-Csv -Delimiter ";" -Encoding UTF8 -Path $TempWZCsv

    # Fill the queues with historic data
    for ($i=$QueueSize; $i -gt 0; $i--)
    {
        $DatumQ.Enqueue($HistoricData.Datum[-$i])
        $TempWZQ.Enqueue([single]$HistoricData.TempWZ[-$i])
        $RhWZQ.Enqueue([int]$HistoricData.RelHumWZ[-$i])
        $SumoStateQ.Enqueue([Int]$HistoricData.SumoState[-$i]*5+$ChartTempMin)
    }

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
while(($SumoController.Request -eq 'Run') -and (WaitUntilFull5Minutes))
{
    # Verify if Sensor is online (Value published within last 30 minutes)
    if ((Get-MqttTopic -Topic $MQTT.Topic_WZ_Status) -match 'online')
    {
        $DataSet.Datum = Get-Date -UFormat $GTFormat
        try { [single]$WZTempC = (Get-MqttTopic -Topic $MQTT.Topic_WZ_Temp) } catch { [single]$WZTempC = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_WZ_Temp + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { [Single]$WZSensVbat = (Get-MqttTopic -Topic $MQTT.Topic_WZ_Vbat) / $VbatCorrDiv } catch { [single]$WZSensVbat = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_WZ_Vbat + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { [Single]$WZRelHum = (Get-MqttTopic -Topic $MQTT.Topic_WZ_RH) } catch { [single]$WZRelHum = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_WZ_RH + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }

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
            if ($LastWZTempValOK.AddMinutes($SensMaxAge) -gt (get-date))
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
                Send-Email -Type ERROR -Message ("Temp-WZ nicht erreichbar, Temperatur Sensordaten ung�ltig!`nSumo wurde gestoppt, Get-SumoState meldet: " + (Get-SumoState) + "`nDie Programmausf�hrung wurde beendet!") -AttachChart yes -Priority high | Out-Null
                write-log -message "Main: VerifySensorValues: Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_Temp)) within $($SensMaxAge) minutes! Sensor Data outdated, SUMO stopped! Get-SumoState=$(Get-SumoState)"
                $SumoController.State = "Killed"
                Write-Error "Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_Temp)) within $($SensMaxAge) minutes! Sensor Data outdated, SUMO stopped!" -ErrorAction Stop
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
            if ($LastWZRelHumValOK.AddMinutes($SensMaxAge) -gt (get-date))
            {
                # Sensor within grace period
                write-log -message "Main: Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_RH)). Reported Value was: $($WZRelHum)"
                $DataSet.RelHumWZ = $WZRelHumLastPlausible
            }
            else
            {
                # Sensor outdated
                # Just log the error, we actually don't care about humidity
                write-log -message "Main: VerifySensorValues: Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_RH)) within $($SensMaxAge) minutes. This is non fatal."
            }
        }        

        if (VerifySensorVal -Val $WZSensVbat -Min $SensorRange.WZSensVbatMin -Max $SensorRange.WZSensVbatMax)
        {
            $DataSet.WZSensVbat = [Single]("{0:N2}" -f $WZSensVbat)
            $WZSensVbatLastPlausible = $DataSet.WZSensVbat
            $LastWZSensVbatOK = Get-Date
        }
        else
        {
            # Reported Value is implausible, use old value if not outdated
            if ($LastWZSensVbatOK.AddMinutes($SensMaxAge) -gt (get-date))
            {
                # Sensor within grace period
                write-log -message "Main: Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_Vbat)). Reported Value was: $($WZSensVbat)"
                $DataSet.WZSensVbat = $WZSensVbatLastPlausible
            }
            else
            {
                # Report Sensor value per mail
                Send-Email -Type WARNING -Message ("Temp-WZ Batteriespannung seit $($SensMaxAge) ausserhalb der Grenzwerte: " + $WZSensVbat + " Volt`n") -Priority high | Out-Null
                write-log -message "Main: VerifySensorValues: Could not fetch valid Sensor data from MQTT Broker (Topic $($MQTT.Topic_WZ_Vbat)) within $($SensMaxAge) minutes. This is non fatal."
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
            Send-Email -Type INFO -Message ("Sumo gestartet.") -AttachChart yes | Out-Null
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
            Send-Email -Type INFO -Message ("Sumo gestoppt.") -AttachChart yes | Out-Null
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
                    Send-Email -Type ERROR -Message ("Control-Sumo setzt Sumo Status 2, sumo-pj.mik nicht erreichbar, Programmausf�hrung wird beendet!") -Priority high | Out-Null
                    write-log -message "Main: Control-Sumo reports status 2, sumo-pj.mik not reachable! Programm will exit!"
                    $SumoController.State = "Killed"
                    # Update HTML before killing program
                    CreateStatusHtml -OutFile $SumoController.StatHTML | Out-Null
                    write-error "Main: Control-Sumo reports status 2, sumo-pj.mik not reachable! Programm will exit!" -ErrorAction Stop
                }

            }
        }

        # DataSet successfully updated, save to CSV..
        if (! $BackgroundMode) {$DataSet | ft -AutoSize}
        # Append to CSV file..
        $DataSet | Export-Csv -Delimiter ";" -Encoding UTF8 -Append -NoTypeInformation -Path $SumoController.WZCsv

        # .. send Data to ElasticSearch..
        SendTo-LogStash -JsonString "{`"HB7`":{`"Indoor`":{`"WZ`":{`"RH`":$($DataSet.RelHumWZ),`"Temp`":$($DataSet.TempWZ),`"Sumo`":$($DataSet.SumoState)}}}}" | Out-Null

        #.. update Status HTML for IIS..
        CreateStatusHtml -OutFile $SumoController.StatHTML | Out-Null

        # .. and enqueue Data for Charts..
        if ($DatumQ.Count -ge $QueueSize) { $DatumQ.Dequeue() | Out-Null }
        $DatumQ.Enqueue($DataSet.Datum)
        if ($TempWZQ.Count -ge $QueueSize) { $TempWZQ.Dequeue() | Out-Null }
        $TempWZQ.Enqueue($DataSet.TempWZ)
        if ($RhWZQ.Count -ge $QueueSize) { $RhWZQ.Dequeue() | Out-Null }
        $RhWZQ.Enqueue($DataSet.RelHumWZ)
        if ($SumoStateQ.Count -ge $QueueSize) { $SumoStateQ.Dequeue() | Out-Null }
        $SumoStateQ.Enqueue($DataSet.SumoState*5 + $ChartTempMin)

        # .. and Update our chart.
        $chart.Series["Temperatur"].Points.DataBindXY($DatumQ, $TempWZQ)
        $chart.Series["SUMO Status"].Points.DataBindXY($DatumQ, $SumoStateQ)
        $chart.Series["RH"].Points.DataBindXY($DatumQ, $RhWZQ)
        $Chart.SaveImage($ChartFile, $ChartImgFmt)
    }
    else
    {
        # Sensor outdated, stop SUMO and quit
        if ((Set-SumoState -State 0) -eq $false)
        {
            # Error, retry
            write-output ((get-date).ToString() + ":: Main: Sensor Data outdated! Set-SumoState 0 failed, retrying..") | Out-File -append -filepath $SumoController.PSLog
            Start-Sleep -Seconds 5
            Set-SumoState -State 0 | Out-Null
        }
        Send-Email -Type ERROR -Message ("Temp-WZ nicht erreichbar, Sensordaten ung�ltig!`nSumo wurde gestoppt, Get-SumoState meldet: " + (Get-SumoState) + "`nDie Programmausf�hrung wurde beendet!") -AttachChart yes -Priority high | Out-Null
        write-log -message "Main: LWT on MQTT broker triggered for $($MQTT.Topic_WZ_Status)! Sensor Data outdated, SUMO stopped! Get-SumoState=$(Get-SumoState)"
        $SumoController.State = "Killed"
        # Update HTML before killing program
        CreateStatusHtml -OutFile $SumoController.StatHTML | Out-Null
        Write-Error "Main: LWT on MQTT broker triggered for $($MQTT.Topic_WZ_Status)! Sensor Data outdated, SUMO stopped!" -ErrorAction Stop
    }
}