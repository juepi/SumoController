########## Common Functions for SUMO-Controller #############
##### requires global Variables from Controller script! #####
##### Dot-Sourcing is required! #########


function VerifySensorVal([Single]$Val,[Single]$Min,[Single]$Max)
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
        try { $subproc.kill() } catch {}
        return "nan"
    }
    return ($subproc.StandardOutput.ReadToEnd()).Trim()
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


function Get-SumoState ()
{
    # If Simulation Mode is active, return SUMO state from MQTT topic
    if ($SumoController.Simulate -eq $true)
    {
        try { [int]$State = (Get-MqttTopic -Topic $MQTT.Topic_WZ_Sumo) }
        catch { [int]$State = 0; write-log -message ("SIMULATION: Get-SumoState failed to fetch " + $MQTT.Topic_WZ_Sumo + "; Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) }
        write-log -message "SIMULATION: Get-SumoState reported value: $($State)" 
        return $State
    }

    #check if SUMO is reachable first.
    $PingSumo = Test-Connection -ComputerName $SumoController.SumoHost -Count 2 -ErrorAction SilentlyContinue
    if ($PingSumo.count -lt 2)
    {
        # wait some seconds and retry - just to be sure
        Start-Sleep -Seconds 3
        $PingSumo = Test-Connection -ComputerName $SumoController.SumoHost -Count 2 -ErrorAction SilentlyContinue
        if ($PingSumo.count -lt 2)
        {
            #SUMO is unreachable
            return 2
        }
    }
    try { $SumoResponse = Invoke-WebRequest -URI $SumoController.SumoURL -TimeoutSec $SumoController.WebReqTimeout }
    catch { return 2 }
    $CurrentState = ($SumoResponse.AllElements.innerText[1])
    if ($CurrentState -match $SumoController.SumoResponseOn) { return 1 }
    elseif ($CurrentState -match $SumoController.SumoResponseOff) { return 0 }
    return 2
}


function Set-SumoState([int]$State)
{
    #If Simulation Mode is active, return success
    if ($SumoController.Simulate -eq $true)
    {
        write-log -message "SIMULATION: Set-SumoState to value: $($State)"
        Set-MqttTopic -Topic $MQTT.Topic_WZ_Sumo -Value $State -Retain | Out-Null
        return $true
    }


    #check if SUMO is reachable first.
    $PingSumo = Test-Connection -ComputerName $SumoController.SumoHost -Count 2 -ErrorAction SilentlyContinue
    if ($PingSumo.count -lt 2)
    {
        # wait some seconds and retry - just to be sure
        Start-Sleep -Seconds 3
        $PingSumo = Test-Connection -ComputerName $SumoController.SumoHost -Count 2 -ErrorAction SilentlyContinue
        if ($PingSumo.count -lt 2)
        {
            #SUMO is unreachable
            return $false
        }
    }
    switch ($State)
        {
            1
            {
                try { Invoke-WebRequest -URI $SumoController.SumoON -TimeoutSec $SumoController.WebReqTimeout | Out-Null }
                catch
                {
                    # Log errors
                    write-output ((get-date).ToString() + ":: Set-SumoState: Invoke-WebRequest failed to Set SUMO State 1; Exception Message: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) | Out-File -append -filepath $SumoController.PSLog
                    #return $false
                }
                Start-Sleep -Milliseconds 500
                [int]$tempState = Get-SumoState
                if ($tempState -ne "1")
                {
                    # Log errors
                    write-output ((get-date).ToString() + ":: Set-SumoState: failed to set State to 1, Get-SumoState returned " + $tempState) | Out-File -append -filepath $SumoController.PSLog
                    return $false
                }
            }
            0
            {
                try { Invoke-WebRequest -URI $SumoController.SumoOFF -TimeoutSec $SumoController.WebReqTimeout | Out-Null }
                catch
                {
                    # Log errors
                    write-output ((get-date).ToString() + ":: Set-SumoState: Invoke-WebRequest failed to Set SUMO State 0; Exception Message: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) | Out-File -append -filepath $SumoController.PSLog
                    #return $false
                }
                Start-Sleep -Milliseconds 500
                [int]$tempState = Get-SumoState
                if ($tempState -ne "0")
                {
                    # Log errors
                    write-output ((get-date).ToString() + ":: Set-SumoState: failed to set State to 1, Get-SumoState returned " + $tempState) | Out-File -append -filepath $SumoController.PSLog
                    return $false
                }
            }
            default
            {
                return $false
            }
        }
    return $true
}


function Send-Email ([String]$Type,[String]$Message,[String]$Priority='normal')
{
    $MailSubject = ($Mail.Subject + $Type)
    $MailCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Mail.User,(ConvertTo-SecureString $Mail.Pass -AsPlainText -Force)
    try
    {
        Send-MailMessage -To $Mail.Dest -From $Mail.Source -Subject $MailSubject -Body ($Mail.Text + $Message) -Priority $Priority -SmtpServer $Mail.Srv -Port $Mail.Port -Encoding ([System.Text.Encoding]::UTF8) -Credential $MailCred
    }
    catch
    {
        write-output ((get-date).ToString() + ":: Send-EMail:: Failed to send mail message. Exception: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) | Out-File -append -filepath $SumoController.PSLog
        return $false
    }
    return $true
}


function WaitUntilFull5Minutes ()
{
    # Function will sleep until the next full 5 minutes (00:00,00:05,00:10,...)
    $gt = Get-Date -Second 0
    do {Start-Sleep -Seconds 1} until ((Get-Date) -ge ($gt.addminutes(5-($gt.minute % 5))))
    return $true
}


Function SendTo-LogStash ([string]$JsonString)
{ 
    if ($JsonString)
    {
        try
        {
            # Connect to local LogStash Service on TCP Port 5544 and send JSON string
            $Socket = New-Object System.Net.Sockets.TCPClient(127.0.0.1,5544)
            $Stream = $Socket.GetStream()
            $Writer = New-Object System.IO.StreamWriter($Stream)
            $Writer.WriteLine($JsonString)
            $Writer.Flush()
            $Stream.Close()
            $Socket.Close()
        }
        catch
        {
            return $false
        }
    }
    else
    {
        # No String parameter given
        return $false
    }
    return $true
}
