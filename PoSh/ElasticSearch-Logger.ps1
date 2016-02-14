########################### ElasticSearch-Logger #########################################
### Author: jpichlbauer
### Logs all environmental data from Sensors (MQTT Broker) to ElasticSearch via LogStash
##########################################################################################
# Use invariant Culture to avoid problems with comma seperator
[System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture;

# No console outputs in background mode
$BackgroundMode = $true

# common settings
$BaseDir = $PSScriptRoot
$LogFile = "$($BaseDir)\logs\ElasticSearch-Logger.log"


#region MQTT Settings
$MQTT = [hashtable] @{}
$MQTT.MosqSub = "$($env:MOSQUITTO_DIR)\mosquitto_sub.exe"
$MQTT.MosqPub = "$($env:MOSQUITTO_DIR)\mosquitto_pub.exe"
$MQTT.Broker = 'dvb-juepi.mik'
$MQTT.Port = [int]'1883'
$MQTT.ClientID = 'ES-Logger'
$MQTT.Topic_Test = 'HB7/Outdoor/Test'
$MQTT.Topic_Out_Temp = 'HB7/Outdoor/Temp'
$MQTT.Topic_Out_RH = 'HB7/Outdoor/RH'
$MQTT.Topic_Out_Vbat = 'HB7/Outdoor/Vbat'
$MQTT.Topic_Out_AP = 'HB7/Outdoor/AirPress'
$MQTT.Topic_Out_Status = 'HB7/Outdoor/Status'
$MQTT.Topic_In_WZ_Temp = 'HB7/Indoor/WZ/Temp'
$MQTT.Topic_In_WZ_RH = 'HB7/Indoor/WZ/RH'
$MQTT.Topic_In_WZ_Vbat = 'HB7/Indoor/WZ/Vbat'
$MQTT.Topic_In_WZ_Status = 'HB7/Indoor/WZ/Status'

# Hashtable for Logstash JSON output
$LS = [hashtable] @{}
$LS.HB7 = [hashtable] @{}
$LS.HB7.Outdoor = [hashtable] @{}
$LS.HB7.Indoor = [hashtable] @{}
$LS.HB7.Indoor.WZ = [hashtable] @{}


#region Sensor Corrections
#Battery Voltage correction divider (/1000 -> sensor reports milliVolts) plus correction
[int]$VbatCorrDiv = 1051
#endregion

#region Mail Alerting
# Mail alerting
$MailSource="editme"
$MailDest="editme"
$MailSubject="ElasticSearch-Logger "
$MailText="ElasticSearch-Logger reports:`n`n"
$MailSrv="smtp-server"
$MailPort="25"
$MailPass = ConvertTo-SecureString "your-smtp-pass"-AsPlainText -Force
$MailCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "your-smtp-user",$MailPass
#endregion


# Load common Functions

try
{
    . $($BaseDir + "\Common-functions.ps1")
}
catch
{
    Write-Error "Failed to load required functions!" -ErrorAction Stop
}


#region Local Functions
function write-log ([string]$message)
{
    write-output ((get-date).ToString() + ":: " + $message) | Out-File -append -filepath $LogFile
}
#endregion


################ Main ####################

if ($BackgroundMode)
{
    write-log -message "ElasticSearch-Logger: started in Background mode."
}
else
{
    write-log -message "ElasticSearch-Logger: ElasticSearch-Logger.ps1 script started in Foreground mode."
    Write-Host "ElasticSearch-Logger starting.." -ForegroundColor Green
}


# Start loop on every 5th minutes and 0 seconds
while(WaitUntilFull5Minutes)
{
    # Verify if Sensor is online (Value published within last 30 minutes)
    try { [string]$SensOutStat = (Get-MqttTopic -Topic $MQTT.Topic_Out_Status) } catch { write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_Out_Status + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) ; continue }
    try { [string]$SensWZStat = (Get-MqttTopic -Topic $MQTT.Topic_In_WZ_Status) } catch { write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_In_WZ_Status + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) ; continue }
    if (($SensOutStat -match 'online') -and ($SensWZStat -match 'online'))
    {
        if (!$BackgroundMode) {Write-Host "Fetching Data from MQTT broker.." -ForegroundColor Green}
        # OUTDOOR Sensor
        try { [single]$LS.HB7.Outdoor.Temp = (Get-MqttTopic -Topic $MQTT.Topic_Out_Temp) } catch { write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_Out_Temp + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { [Single]$LS.HB7.Outdoor.Vbat = [math]::round(((Get-MqttTopic -Topic $MQTT.Topic_Out_Vbat) / $VbatCorrDiv),2) } catch { write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_Out_Vbat + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { [Single]$LS.HB7.Outdoor.RH = (Get-MqttTopic -Topic $MQTT.Topic_Out_RH) } catch { write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_Out_RH + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        # AirPressure needs to be converted from Pa -> mBar (/100)
        try { [Single]$LS.HB7.Outdoor.AirPress = ([single](Get-MqttTopic -Topic $MQTT.Topic_Out_AP) * 0.01) } catch { write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_Out_AP + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }

        # INDOOR-WZ Sensor
        try { [single]$LS.HB7.Indoor.WZ.Temp = (Get-MqttTopic -Topic $MQTT.Topic_In_WZ_Temp) } catch { write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_In_WZ_Temp + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { [Single]$LS.HB7.Indoor.WZ.Vbat = [math]::round(((Get-MqttTopic -Topic $MQTT.Topic_In_WZ_Vbat) / $VbatCorrDiv),2) } catch { write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_In_WZ_Vbat + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        try { [Single]$LS.HB7.Indoor.WZ.RH = (Get-MqttTopic -Topic $MQTT.Topic_In_WZ_RH) } catch { write-log -message ("Get-MqttTopic failed to fetch " + $MQTT.Topic_In_WZ_RH + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }

        # Send Data to ElasticSearch..
        SendTo-LogStash -JsonString "$($LS | ConvertTo-Json -Compress -Depth 3)" | Out-Null
        if (! $BackgroundMode) { Write-Host "$($LS | ConvertTo-Json -Compress -Depth 3)" }
    }
    else
    {
        # MQTT Sensor LWT triggered - sensor offline for at least 30min
        ifSend-Email -Type ERROR -Message ("ElasticSearch-Logger reports sensor offline:`nStatus Indoor-WZ: $($SensWZStat)`nStatus Outdoor: $($SensOutStat)`nProgramm will exit.") -AttachChart no -Priority high | Out-Null
        write-log -message "Main: LWT triggered for a sensor! Sensor Data outdated (Status Indoor-WZ: $($SensWZStat) ; Status Outdoor: $($SensOutStat)), Script stopped!"
        Write-Error "Main: LWT triggered! Sensor Data outdated, Script stopped!" -ErrorAction Stop
    }
}
