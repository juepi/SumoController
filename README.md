# SumoController
Implements a room temperature based oven controller in PowerShell along with some visualization goodies.

I've created this project to control my RIKA SUMO wood pellet stove, however it probably can be used on any oven with a potential free trigger input.

The controller unit on the oven is an ESP8266 with a photoMOS relais attached to a GPIO output. I have used a Panasonic AQY212EH for this task.

The powershell code provides the following functionality:

* poll room Temperature and sensor state from MQTT broker (see project ESPEnvSens)
* control oven through configurable thresholds, considering day/night, Weekdays, Weekends and holidays
* save Sensor values / oven session and overall "on-hours" to local CSV file
* create PNG chart files visualizing the last 2 days (Room temperature and rel. humidity along with oven on/off state)
* sends oven status to MQTT broker
* send emails on oven status change and errors

You might wander why the "startup.ps1" exists and synchronized collections are used. I've intentionally tried to add a webinterface to the controller script which could also update the parameters during runtime, but actually this is not required and might be removed in the future. A functions remains to generate a static HTML file with the current stats and write it somewhere along with the visualization PNG graph and display it through a ordinary webserver (IIS in my case).

The intended way to fire things up is by putting "startup.ps1" into a scheduled task. This will automatically start a "failsafe" mode in case the "high level" controller has failed (i.e. because the room temperature sensor died). Failsafe script operates the oven at a simple time-based mode, making sure that it will run a few hours a day to maintain a minimum room temperature.
SUMO-Controller-MQTT.ps1 can also be started directly, which will lead to a "foreground mode" where it will output some additional info to the console.

Note that some text (mail text, visualization stuff) is in german.

Software Requirements:
* Mosquitto MQTT Software (https://mosquitto.org/)
* Mosquitto installation path Environment variable set (MOSQUITTO_DIR)
* an MQTT broker (internet or local, authentication not implemented)
* ElasticSearch-Logger up and running (to verify indoor temperature-sensor functionality)


Have fun,
Juergen
