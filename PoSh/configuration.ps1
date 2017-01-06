################################# SUMO Controller Configuration ###################################
### Author: jpichlbauer
### Info: Configuration will be loaded either by "Startup.ps1" when run in background mode
###       or by "SUMO-Controller-MQTT.ps1" for foreground mode
###       Synchronized Collections are used to be able to adopt SumoSettings at runtime (Startup.ps1)
###################################################################################################

#SUMO Controller User Settings
$SumoSettings = [HashTable]::Synchronized(@{})
# Force Weekend or Workday (forced Workday overrules forced weekend)
$SumoSettings.ForceWeekend = [bool]$false
$SumoSettings.ForceWorkday = [bool]$false

# Temperature Thresholds
<# Winter
$SumoSettings.DayStartHour = [Int]'14'
$SumoSettings.DayEndHour = [Int]'21'
$SumoSettings.WeekendDayStartHour = [Int]'7'
$SumoSettings.WeekendDayEndHour = [Int]'22'
$SumoSettings.MinNightTemp = [Single]'18.5'
$SumoSettings.MaxNightTemp = [Single]'21'
$SumoSettings.MinDayTemp = [Single]'20.8'
$SumoSettings.MaxDayTemp = [Single]'22.8'
#>

# Transition Period
$SumoSettings.DayStartHour = [Int]'15'
$SumoSettings.DayEndHour = [Int]'21'
$SumoSettings.WeekendDayStartHour = [Int]'7'
$SumoSettings.WeekendDayEndHour = [Int]'21'
$SumoSettings.MinNightTemp = [Single]'18'
$SumoSettings.MaxNightTemp = [Single]'21'
$SumoSettings.MinDayTemp = [Single]'20.8'
$SumoSettings.MaxDayTemp = [Single]'22.5'



# SumoController System settings
$SumoController = [HashTable]::Synchronized(@{})
$SumoController.State = 'Stopped'
$SumoController.Request = 'Run'
$SumoController.SumoState = [int]'0'
$SumoController.BaseDir = $PSScriptRoot
$SumoController.PSLog = "$($SumoController.BaseDir)\logs\SUMO-Controller.log"
$SumoController.WZCsv = "$($SumoController.BaseDir)\data\TempWZ-Sumo.csv"
$SumoController.HolidaysICS = "$($SumoController.BaseDir)\data\Feiertage-AT.ics"
$SumoController.WWWroot = "C:\wwwroot\nodejs\SumoCtrl\static"
$SumoController.StatHTML = "$($SumoController.WWWroot)\index.html"
$SumoController.ChartFile = "$($SumoController.WWWroot)\IndoorWZChart.png"
$SumoController.ChartFormat = 'PNG'
$SumoController.SumoHost = "sumo-pj.mik"
$SumoController.SumoURL = ("http://" + $SumoController.SumoHost)
$SumoController.SumoON = ($SumoController.SumoURL + "/SUMO=ON")
$SumoController.SumoOFF = ($SumoController.SumoURL + "/SUMO=OFF")
$SumoController.SumoResponseOn = "SUMO state is now: On"
$SumoController.SumoResponseOff = "SUMO state is now: Off"
# Timeout Value for Invoke-Webrequest calls (seconds)
$SumoController.WebReqTimeout = [int]'15'
# Minimum Runtime for SUMO in Hours
$SumoController.MinRuntime = [single]'1.5'
#Maximum Age for Sensor Values in Minutes
$SumoController.SensMaxAge = [int]'30'
#Ignore SUMO state change requests for X times (i.e. while venting room)
# Note: Main lop runs every 5 minutes, so state change will be ignored fox X * 5min
$SumoController.IgnoreStateChangeReq = [int]'2'
#Send Info Mails on oven status change
$SumoController.SendInfoMail = $false
# Attach temperature chart to info mails
$SumoController.AttachChart = "no"

#region Mail Settings
# Mail alerting
$Mail = [HashTable]::Synchronized(@{})
$Mail.Source="juepi@liwest.at"
$Mail.Dest="juergen.pichlbauer@gmail.com"
$Mail.Subject="Sumo-Controller "
$Mail.Text="SUMO Controller meldet:`n`n"
$Mail.Srv="smtp.provider.com"
$Mail.Port="25"
$Mail.User="xxx"
$Mail.Pass = "xxx"
#endregion

#region MQTT Settings
$MQTT = [HashTable]::Synchronized(@{})
$MQTT.MosqSub = "$($env:MOSQUITTO_DIR)\mosquitto_sub.exe"
$MQTT.MosqPub = "$($env:MOSQUITTO_DIR)\mosquitto_pub.exe"
$MQTT.Broker = 'dvb-juepi.mik'
$MQTT.Port = [int]'1883'
$MQTT.ClientID = 'SumoController'
$MQTT.Topic_Test = 'HB7/SumoController/Test'
$MQTT.Topic_WZ_Temp = 'HB7/Indoor/WZ/Temp'
$MQTT.Topic_WZ_RH = 'HB7/Indoor/WZ/RH'
$MQTT.Topic_WZ_Sumo = 'HB7/Indoor/WZ/Sumo'
$MQTT.Topic_WZ_Status = 'HB7/Indoor/WZ/Status'
$MQTT.StatusSensorDead = 'SensorDead'
#endregion

#region Plausible Sensor Ranges
$SensorRange = [HashTable]::Synchronized(@{})
$SensorRange.WZTempMin = [int]'10'
$SensorRange.WZTempMax = [int]'40'
$SensorRange.WZRelHumMin = [int]'0'
$SensorRange.WZRelHumMax = [int]'100'
#endregion

#region Settings for Syncing Web Frontend changes to backend
# no sync'ed collection required here, will only be used in startup.ps1
$WebCfg = [HashTable] @{}
$WebCfg.GetConfigURI = "http://localhost:8080/getconfig"
# INI file will only be checked by ModifyDate, if modified, ew config will be fetched by Invoke-WebRequest (JSON)
$WebCfg.CfgINI = "C:\wwwroot\nodejs\SumoCtrl\config.ini"
$WebCfg.WebReqTimeout = [int]'2'
$WebCfg.Available = $true
# min/max Temperatures for plausibility checks
$WebCfg.MinTemp = [single]'15'
$WebCfg.MaxTemp = [single]'26'
$WebCfg.HourValues = @('DayStartHour','DayEndHour','WeekendDayStartHour','WeekendDayEndHour')
$WebCfg.TempValues = @('MinNightTemp','MaxNightTemp','MinDayTemp','MaxDayTemp')
$WebCfg.BoolValues = @('ForceWorkday','ForceWeekend')
