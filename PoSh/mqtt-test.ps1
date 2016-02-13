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


function Get-MqttTopic ([String]$Topic)
{
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $MQTT.MosqPub
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($MQTT.Topic_Test) -m ok -r")
    $pubproc = New-Object System.Diagnostics.Process
    $pubproc.StartInfo = $pinfo
    # Make sure broker is reachable by publishing to test topic
    $pubproc.Start() | Out-Null
    $pubproc.WaitForExit()
    if ( $pubproc.ExitCode -ne 0 )
    {
        # Broker not reachable
        return "ErrNoBroker"
    }
    # Subscribe to MQTT Topic and get most recent (retained) value
    $pinfo.FileName = $MQTT.MosqSub
    $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($Topic) -C 1")
    $subproc = New-Object System.Diagnostics.Process
    $subproc.StartInfo = $pinfo
    $subproc.Start() | Out-Null
    # wait 1 sec for a result
    if ( ! $subproc.WaitForExit(1000) ) 
    {
        # topic / value probably doesn't exit
        $subproc.kill()
        return "nan"
    }
    return $subproc.StandardOutput.ReadToEnd()
}


function Set-MqttTopic ([String]$Topic,[String]$Value,[switch]$Retain)
{
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $MQTT.MosqPub
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($MQTT.Topic_Test) -m ok -r")
    $pubproc = New-Object System.Diagnostics.Process
    $pubproc.StartInfo = $pinfo
    # Make sure broker is reachable by publishing to test topic
    $pubproc.Start() | Out-Null
    $pubproc.WaitForExit()
    if ( $pubproc.ExitCode -ne 0 )
    {
        # Broker not reachable
        return $false
    }

    # Publish to MQTT Topic
    if ($Retain)
    {
        $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($Topic) -m `"$($Value.ToString())`" -r")
    }
    else
    {
        $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($Topic) -m `"$($Value.ToString())`"")
    }
    $pubproc.StartInfo = $pinfo
    $pubproc.Start() | Out-Null
    $pubproc.WaitForExit()    
    if ( $pubproc.ExitCode -ne 0 )
    {
        # Broker not reachable
        return $false
    }
    return $true
}

