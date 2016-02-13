########################### Outdoor-Sensor Logger / Visualization script ###########################
### Author: jpichlbauer
####################################################################################################
# Use invariant Culture to avoid problems with comma seperator
[System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture;

# No console outputs in background mode
$BackgroundMode = $true

# This hashtable contains all common settings
$Outdoor = [hashtable] @{}
$Outdoor.State = 'Running'
$Outdoor.Request = 'Run'
$Outdoor.BaseDir = $PSScriptRoot
$Outdoor.PSLog = "$($PSScriptRoot)\logs\Outdoor-logger.log"


#region MQTT Settings
$MQTT = [hashtable] @{}
$MQTT.MosqSub = "$($env:MOSQUITTO_DIR)\mosquitto_sub.exe"
$MQTT.MosqPub = "$($env:MOSQUITTO_DIR)\mosquitto_pub.exe"
$MQTT.Broker = 'dvb-juepi.mik'
$MQTT.Port = [int]'1883'
$MQTT.ClientID = 'OutdoorSub'
$MQTT.Topic_Test = 'HB7/Outdoor/Test'
$MQTT.Topic_Out_Temp = 'HB7/Outdoor/Temp'
$MQTT.Topic_Out_RH = 'HB7/Outdoor/RH'
$MQTT.Topic_Out_Vbat = 'HB7/Outdoor/Vbat'
$MQTT.Topic_Out_AP = 'HB7/Outdoor/AirPress'
$MQTT.Topic_Out_Status = 'HB7/Outdoor/Status'


#region Files
$SensOutCsv = "$($Outdoor.BaseDir)\data\outdoor.csv"
$ChartFile = "C:\inetpub\wwwroot\OutdoorChart.png"
$ChartImgFmt = 'PNG'
#endregion


#region Valid Sensor Ranges
$SensorRange = New-Object PSObject
$SensorRange | Add-Member -MemberType NoteProperty -Name TempOutMin -Value '-30'
$SensorRange | Add-Member -MemberType NoteProperty -Name TempOutMax -Value '50'
$SensorRange | Add-Member -MemberType NoteProperty -Name RhOutMin -Value '0'
$SensorRange | Add-Member -MemberType NoteProperty -Name RhOutMax -Value '100'
$SensorRange | Add-Member -MemberType NoteProperty -Name VbatOutMin -Value ([Single]'2.5')
$SensorRange | Add-Member -MemberType NoteProperty -Name VbatOutMax -Value ([Single]'3.5')
$SensorRange | Add-Member -MemberType NoteProperty -Name ApOutMin -Value ([Single]'800')
$SensorRange | Add-Member -MemberType NoteProperty -Name ApOutMax -Value ([Single]'1200')
#endregion

#region Sensor Corrections
#Battery Voltage correction divider (/1000 -> sensor reports milliVolts) plus correction
[int]$VbatCorrDiv = 1051
#endregion

#region Mail Alerting
# Mail alerting
$MailSource="editme"
$MailDest="editme"
$MailSubject="Outdoor-Logger "
$MailText="Outdoor-Logger reports:`n`n"
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
$LastTempOutOK = Get-Date
$LastRhOutOK = Get-Date
$LastVbatOutOK = Get-Date
$LastApOutOK = Get-Date
[Single]$TempOutLastPlausible = "22.0"
[Single]$RhOutLastPlausible = "50.0"
[Single]$VbatOutLastPlausible = "3.0"
[Single]$ApOutLastPlausible = "1000"

$DataSet = New-Object PSObject
$DataSet | Add-Member -MemberType NoteProperty -Name Datum  -Value ''
$DataSet | Add-Member -MemberType NoteProperty -Name TempOut -Value ([single]'0.0')
$DataSet | Add-Member -MemberType NoteProperty -Name RhOut -Value ([int]'0')
$DataSet | Add-Member -MemberType NoteProperty -Name VbatOut -Value ([Single]'0')
$DataSet | Add-Member -MemberType NoteProperty -Name ApOut -Value ([Single]'0')
#endregion


#region######### Data Visualization stuff ###########

# Create Queues
$DatumQ = New-Object System.Collections.Queue
$TempOutQ = New-Object System.Collections.Queue
$RhOutQ = New-Object System.Collections.Queue
$ApOutQ = New-Object System.Collections.Queue
# Queue length (288 = 1 day)
[int]$QueueSize = (288 * 2)
# Y Axis Min/Max
$ChartTempMin = -15
$ChartTempMax = 35
$ChartRhMin = 0
$ChartRhMax = 100
$ChartAPMin = 930
$ChartAPMax = 1030
# Maximum Resolution for X Axis grid
$XAxisGridCount = 24

[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[Void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms.Datavisualization")


$chart = New-Object System.Windows.Forms.Datavisualization.charting.chart
$chart.width = 1920
$chart.Height = 1080

[Void]$chart.Titles.Add("Aussentemperatur")
$chart.Titles[0].Font = "Arial,14pt"
$chart.Titles[0].Alignment = "topCenter"
$chart.BackColor = [System.Drawing.Color]::White


$TempArea = New-Object System.windows.Forms.Datavisualization.charting.chartArea
$APArea = New-Object System.windows.Forms.Datavisualization.charting.chartArea


$TempArea.Name = "Temp"
#$TempArea.AxisX.Title = "Datum"
$TempArea.AxisY.Title = "Temperatur [°C]"
$TempArea.AxisX.TitleFont = "Arial,13pt"
$TempArea.AxisY.TitleFont = "Arial,13pt"
$TempArea.AxisY.TitleForeColor = [System.Drawing.Color]::Red
$TempArea.AxisY.LabelStyle.ForeColor = [System.Drawing.Color]::Red
$TempArea.AxisY.Minimum = $ChartTempMin
$TempArea.AxisY.Maximum = $ChartTempMax
$TempArea.AxisY.Interval = 5
$TempArea.AxisY2.Title = "rel. Luftfeuchtigkeit [%]"
$TempArea.AxisY2.TitleFont = "Arial,13pt"
$TempArea.AxisY2.TitleForeColor = [System.Drawing.Color]::Blue
$TempArea.AxisY2.Enabled = [System.Windows.Forms.DataVisualization.Charting.AxisEnabled]::True
$TempArea.AxisY2.LabelStyle.Enabled = $true
$TempArea.AxisY2.LabelStyle.ForeColor = [System.Drawing.Color]::Blue
$TempArea.AxisY2.MajorGrid.Enabled = $false
$TempArea.AxisY2.Minimum = $ChartRhMin
$TempArea.AxisY2.Maximum = $ChartRhMax
$TempArea.AxisY2.Interval = 10
$TempArea.AxisX.Interval = [Int]($QueueSize / $XAxisGridCount)
$chart.chartAreas.Add($TempArea)

$APArea.Name = "AP"
$APArea.AxisX.Title = "Datum"
$APArea.AxisY.Title = "Luftdruck [mBar]"
$APArea.AxisX.TitleFont = "Arial,13pt"
$APArea.AxisY.TitleFont = "Arial,13pt"
$APArea.AxisY.TitleForeColor = [System.Drawing.Color]::Green
$APArea.AxisY.LabelStyle.ForeColor = [System.Drawing.Color]::Green
$APArea.AxisY.Minimum = $ChartAPMin
$APArea.AxisY.Maximum = $ChartAPMax
$APArea.AxisY.Interval = 10
$APArea.AxisY2.Title = "Luftdruck [mBar]"
$APArea.AxisY2.TitleFont = "Arial,13pt"
$APArea.AxisY2.TitleForeColor = [System.Drawing.Color]::Green
$APArea.AxisY2.Enabled = [System.Windows.Forms.DataVisualization.Charting.AxisEnabled]::True
$APArea.AxisY2.LabelStyle.Enabled = $true
$APArea.AxisY2.LabelStyle.ForeColor = [System.Drawing.Color]::Green
$APArea.AxisY2.MajorGrid.Enabled = $false
$APArea.AxisY2.Minimum = $ChartAPMin
$APArea.AxisY2.Maximum = $ChartAPMax
$APArea.AxisY2.Interval = 10
$APArea.AxisX.Interval = [Int]($QueueSize / $XAxisGridCount)
$chart.chartAreas.Add($APArea)

#Legend
#$legend = New-Object system.Windows.Forms.DataVisualization.Charting.Legend
#$legend.name = "Legende"
#$chart.Legends.Add($legend)


# data series  
[void]$chart.Series.Add("Temperatur")  
$chart.Series["Temperatur"].ChartType = "Line"  
$chart.Series["Temperatur"].BorderWidth = 3
$chart.Series["Temperatur"].IsVisibleInLegend = $true  
$chart.Series["Temperatur"].chartarea = "Temp"  
#$chart.Series["Temperatur"].Legend = "Legende"  
$chart.Series["Temperatur"].color = [System.Drawing.Color]::Red

[void]$chart.Series.Add("Luftdruck")
$chart.Series["Luftdruck"].ChartType = "Line"  
$chart.Series["Luftdruck"].BorderWidth = 3
$chart.Series["Luftdruck"].IsVisibleInLegend = $true  
$chart.Series["Luftdruck"].chartarea = "AP"  
#$chart.Series["Luftdruck"].Legend = "Legende"  
$chart.Series["Luftdruck"].color = [System.Drawing.Color]::Green

[void]$chart.Series.Add("rel.Luftfeucht.")
$chart.Series["rel.Luftfeucht."].ChartType = "Line"  
$chart.Series["rel.Luftfeucht."].BorderWidth = 3
$chart.Series["rel.Luftfeucht."].IsVisibleInLegend = $true  
$chart.Series["rel.Luftfeucht."].chartarea = "Temp"  
#$chart.Series["rel.Luftfeucht."].Legend = "Legende"  
$chart.Series["rel.Luftfeucht."].color = [System.Drawing.Color]::Blue
$chart.Series["rel.Luftfeucht."].YAxisType = [System.Windows.Forms.DataVisualization.Charting.AxisType]::Secondary
#endregion


# Load common Functions

try
{
    . $($Outdoor.BaseDir + "\Common-functions.ps1")
}
catch
{
    Write-Error "Failed to load required functions!" -ErrorAction Stop
}


#region Local Functions
function write-log ([string]$message)
{
    write-output ((get-date).ToString() + ":: " + $message) | Out-File -append -filepath $Outdoor.PSLog
}
#endregion

################ Main ####################

$Outdoor.State = 'Running'

if ($BackgroundMode)
{
    write-log -message "Outdoor-Logger: Outdoor-Logger.ps1 script started in Background mode."
}
else
{
    write-log -message "Outdoor-Logger: Outdoor-Logger.ps1 script started in Foreground mode."
    Write-Host "Outdoor-Logger starting.." -ForegroundColor Green
}

# Get historic data from log (if available)
if (Test-Path $SensOutCsv)
{
    if (! $BackgroundMode) {Write-Host "Importing historic data.." -ForegroundColor Green}

    $HistoricData = Import-Csv -Delimiter ";" -Encoding UTF8 -Path $SensOutCsv

    # Fill the queues with historic data
    for ($i=$QueueSize; $i -gt 0; $i--)
    {
        $DatumQ.Enqueue($HistoricData.Datum[-$i])
        $TempOutQ.Enqueue([single]$HistoricData.TempOut[-$i])
        $RhOutQ.Enqueue([int]$HistoricData.RhOut[-$i])
        $ApOutQ.Enqueue([Int]$HistoricData.ApOut[-$i])
    }

    Clear-Variable HistoricData
}


# Start Processing

# Start loop on every 5th minutes and 0 seconds
while(WaitUntilFull5Minutes)
{
    # Verify if Sensor is online (Value published within last 30 minutes)
    # eventuell umbauen mit try/catch für Status Auslesen
    #try { [string]$TempOutStat = (Get-MqttTopic -Topic $MQTT.Topic_Out_Status) } catch { continue }
    if ((Get-MqttTopic -Topic $MQTT.Topic_Out_Status) -match 'online')
    {
        if (!$BackgroundMode) {Write-Host "Fetching Data from MQTT broker.." -ForegroundColor Green}
        $DataSet.Datum = Get-Date -UFormat $GTFormat
        try { [single]$TempOut = (Get-MqttTopic -Topic $MQTT.Topic_Out_Temp) } catch { [single]$TempOut = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_Out_Temp + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { [Single]$VbatOut = (Get-MqttTopic -Topic $MQTT.Topic_Out_Vbat) / $VbatCorrDiv } catch { [single]$VbatOut = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_Out_Vbat + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { [Single]$RhOut = (Get-MqttTopic -Topic $MQTT.Topic_Out_RH) } catch { [single]$RhOut = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_Out_RH + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        # AirPressure needs to be converted from Pa -> mBar (/100)
        try { [Single]$ApOut = ([single](Get-MqttTopic -Topic $MQTT.Topic_Out_AP) * 0.01) } catch { [single]$ApOut = 255; write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_Out_AP + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }

        # Verify Sensor Values
        if (VerifySensorVal -Val $TempOut -Min $SensorRange.TempOutMin -Max $SensorRange.TempOutMax)
        {
            $DataSet.TempOut = [Single]("{0:N2}" -f $TempOut)
            $TempOutLastPlausible = $DataSet.TempOut
            # Sensor Value OK, store TimeDate
            $LastTempOutOK = Get-Date
        }
        else
        {
            # Reported Value is implausible, use old value if not outdated
            if ($LastTempOutOK.AddMinutes($SensMaxAge) -gt (get-date))
            {
                # Sensor within grace period
                $DataSet.TempOut = $TempOutLastPlausible
            }
            else
            {
                # Sensor outdated
                #Send-Email -Type ERROR -Message ("Temp-Out nicht erreichbar, Temperatur Sensordaten ungültig!`nSumo wurde gestoppt, Get-SumoState meldet: " + (Get-SumoState) + "`nDie Programmausführung wurde beendet!") -AttachChart yes -Priority high | Out-Null
                write-log -message "Main: MQTT reports implausible Value for $($MQTT.Topic_Out_Temp) for $($SensMaxAge) minutes! Reported Value: $($TempOut)"
                Send-Email -Type ERROR -Message ("MQTT reports implausible Value for $($MQTT.Topic_Out_Temp) for $($SensMaxAge) minutes! Reported Value: $($TempOut)") -AttachChart no -Priority high | Out-Null
                $Outdoor.State = "Killed"
                Write-Error "Main: MQTT reports implausible Value for $($MQTT.Topic_Out_Temp) for $($SensMaxAge) minutes!" -ErrorAction Stop
            }
        }

        if (VerifySensorVal -Val $RhOut -Min $SensorRange.RhOutMin -Max $SensorRange.RhOutMax)
        {
            $DataSet.RhOut = [int]("{0:N0}" -f $RhOut)
            $RhOutLastPlausible = $DataSet.RhOut
            $LastRhOutOK = Get-Date
        }
        else
        {
            # Reported Value is implausible, use old value if not outdated
            if ($LastRhOutOK.AddMinutes($SensMaxAge) -gt (get-date))
            {
                # Sensor within grace period
                $DataSet.RhOut = $RhOutLastPlausible
            }
            else
            {
                # Sensor outdated
                write-log -message "Main: MQTT reports implausible Value for $($MQTT.Topic_Out_RH) for $($SensMaxAge) minutes! Reported Value: $($RhOut)"
                Send-Email -Type ERROR -Message ("MQTT reports implausible Value for $($MQTT.Topic_Out_RH) for $($SensMaxAge) minutes! Reported Value: $($RhOut)") -AttachChart no -Priority high | Out-Null
                $Outdoor.State = "Killed"
                Write-Error "Main: MQTT reports implausible Value for $($MQTT.Topic_Out_RH) for $($SensMaxAge) minutes!" -ErrorAction Stop
            }
        }        

        if (VerifySensorVal -Val $VbatOut -Min $SensorRange.VbatOutMin -Max $SensorRange.VbatOutMax)
        {
            $DataSet.VbatOut = [Single]("{0:N2}" -f $VbatOut)
            $VbatOutLastPlausible = $DataSet.VbatOut
            $LastVbatOutOK = Get-Date
        }
        else
        {
            # Reported Value is implausible, use old value if not outdated
            if ($LastVbatOutOK.AddMinutes($SensMaxAge) -gt (get-date))
            {
                # Sensor within grace period
                write-log -message "Main: MQTT reports implausible Value for $($MQTT.Topic_Out_Vbat)! Reported Value: $($VbatOut)"
                $DataSet.VbatOut = $VbatOutLastPlausible
            }
            else
            {
                # Sensor outdated
                write-log -message "Main: MQTT reports implausible Value for $($MQTT.Topic_Out_Vbat) for $($SensMaxAge) minutes! Reported Value: $($VbatOut)"
                Send-Email -Type ERROR -Message ("MQTT reports implausible Value for $($MQTT.Topic_Out_Vbat) for $($SensMaxAge) minutes! Reported Value: $($VbatOut)") -AttachChart no -Priority high | Out-Null
                $Outdoor.State = "Killed"
                Write-Error "Main: MQTT reports implausible Value for $($MQTT.Topic_Out_Vbat) for $($SensMaxAge) minutes!" -ErrorAction Stop
            }
        }

        if (VerifySensorVal -Val $ApOut -Min $SensorRange.ApOutMin -Max $SensorRange.ApOutMax)
        {
            $DataSet.ApOut = [Single]("{0:N2}" -f $ApOut)
            $ApOutLastPlausible = $DataSet.ApOut
            $LastApOutOK = Get-Date
        }
        else
        {
            # Reported Value is implausible, use old value if not outdated
            if ($LastApOutOK.AddMinutes($SensMaxAge) -gt (get-date))
            {
                # Sensor within grace period
                $DataSet.ApOut = $ApOutLastPlausible
            }
            else
            {
                # Sensor outdated
                write-log -message "Main: MQTT reports implausible Value for $($MQTT.Topic_Out_AP) for $($SensMaxAge) minutes! Reported Value: $($ApOut)"
                Send-Email -Type ERROR -Message ("MQTT reports implausible Value for $($MQTT.Topic_Out_AP) for $($SensMaxAge) minutes! Reported Value: $($ApOut)") -AttachChart no -Priority high | Out-Null
                $Outdoor.State = "Killed"
                Write-Error "Main: MQTT reports implausible Value for $($MQTT.Topic_Out_AP) for $($SensMaxAge) minutes!" -ErrorAction Stop
            }
        }

        ############################################################################
        # Sensors have been verified, send to ElasticSearch, enqueue and draw chart
        ############################################################################

        # .. send Data to ElasticSearch..
        SendTo-LogStash -JsonString "{`"HB7`":{`"Outdoor`":{`"RH`":$($DataSet.RhOut),`"Temp`":$($DataSet.TempOut),`"AirPress`":$($DataSet.ApOut)}}}" | Out-Null

        if (! $BackgroundMode) {$DataSet | ft -AutoSize}
        # Append to CSV file..
        $DataSet | Export-Csv -Delimiter ";" -Encoding UTF8 -Append -NoTypeInformation -Path $SensOutCsv
        # Enqueue Data for Chart to our Queues..
        if ($DatumQ.Count -ge $QueueSize) { $DatumQ.Dequeue() | Out-Null }
        $DatumQ.Enqueue($DataSet.Datum)
        if ($TempOutQ.Count -ge $QueueSize) { $TempOutQ.Dequeue() | Out-Null }
        $TempOutQ.Enqueue($DataSet.TempOut)
        if ($RhOutQ.Count -ge $QueueSize) { $RhOutQ.Dequeue() | Out-Null }
        $RhOutQ.Enqueue($DataSet.RhOut)
        if ($ApOutQ.Count -ge $QueueSize) { $ApOutQ.Dequeue() | Out-Null }
        $ApOutQ.Enqueue($DataSet.ApOut)
        # and Update our chart.
        $chart.Series["Temperatur"].Points.DataBindXY($DatumQ, $TempOutQ)
        $chart.Series["Luftdruck"].Points.DataBindXY($DatumQ, $ApOutQ)
        $chart.Series["rel.Luftfeucht."].Points.DataBindXY($DatumQ, $RhOutQ)
        $Chart.SaveImage($ChartFile, $ChartImgFmt)

    }
    else
    {
        # MQTT Sensor LWT triggered - sensor offline for at least 30min
        Send-Email -Type ERROR -Message ("temp-out.mik offline!`nDie Programmausführung wurde beendet!") -AttachChart no -Priority high | Out-Null
        write-log -message "Main: LWT triggered for $($MQTT.Topic_Out_Status)! Sensor Data outdated, Script stopped!"
        $Outdoor.State = "Killed"
        Write-Error "Main: LWT triggered for $($MQTT.Topic_Out_Status)! Sensor Data outdated, Script stopped!" -ErrorAction Stop
    }
}
