# SumoController
Implements a room temperature based oven controller in PowerShell along with some visualization goodies.

I've created this project to control my RIKA SUMO wood pellet stove, however it probably can be used on any oven with a potential free trigger input.

The controller unit on the oven is an ESP8266 with a photoMOS relais attached to a GPIO output. I have used a Panasonic AQY212EH for this task.

The powershell code provides the following functionality:

* poll room Temperature and sensor state from MQTT broker (see project ESPEnvSens)
* control oven through configurable thresholds, considering day/night, Weekdays, Weekends and holidays
* save Sensor values / oven session and overall "on-hours" to local CSV file
* create PNG chart files visualizing the last 2 days (Room temperature and rel. humidity along with oven on/off state)
* sends data to LogStash (ElasticSearch) via TCP session for long-term data acquisition and visualization (Kibana)
* send emails on oven status change and errors

You might wander why the "startup.ps1" exists and synchronized collections are used. I've intentionally tried to add a webinterface to the controller script which could also update the parameters during runtime, but actually this is not required and might be removed in the future.

Have fun,
Juergen
