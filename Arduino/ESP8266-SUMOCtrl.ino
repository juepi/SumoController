#include <ESP8266WiFi.h>

// define Serial Output for debugging
//#define SerialEnabled

// SUMO is connected to GPIO4 on the ESP8266
#define SUMO 4

// Status LED on GPIO2 (LED inverted!)
#define LED 2
#define LEDON LOW
#define LEDOFF HIGH

//WLAN Configuration
const char* ssid = "";
const char* password = "";

// Vars
int SumoState = LOW;
int ClientCounter = 4000;

// Watchdog for SUMO - maximum ON time 6 hours
unsigned long maxOnTimeMillis = (6 * 3600 * 1000);
unsigned long CurrentMillis = 0;
unsigned long StartSumoMillis = 0;
unsigned long CurrentOnTime = 0;
// Watchdog runs every second
long WatchdogCounter = 120000;

WiFiServer server(80);

void setup() {
  #ifdef SerialEnabled
  Serial.begin(115200);
  #endif 
 
  pinMode(SUMO, OUTPUT);
  digitalWrite(SUMO, LOW);
  pinMode(LED, OUTPUT);
  digitalWrite(LED, LEDOFF);
   
  // Connect to WiFi network
  #ifdef SerialEnabled
  Serial.println();
  Serial.println();
  Serial.print("Connecting to ");
  Serial.println(ssid);
  #endif
   
  WiFi.begin(ssid, password);
   
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    #ifdef SerialEnabled
    Serial.print(".");
    #endif
  }
  #ifdef SerialEnabled
  Serial.println("");
  Serial.println("WiFi connected");
  #endif
     
  // Start the server
  server.begin();
 
  // Print the IP address
  #ifdef SerialEnabled
  Serial.print("Use this URL to connect: ");
  Serial.print("http://");
  Serial.print(WiFi.localIP());
  Serial.println("/");
  #endif    
  digitalWrite(LED, LEDON);
  delay(250);
  digitalWrite(LED, LEDOFF);
  delay(250);
  digitalWrite(LED, LEDON);
  delay(250);
  digitalWrite(LED, LEDOFF);
  delay(250);
  digitalWrite(LED, LEDON);
  delay(250);
  digitalWrite(LED, LEDOFF);
}
 
void loop() {
  // Check if a client has connected
  WiFiClient client = server.available();
  if (!client) {
    
    while(WatchdogCounter != 0)
    {
      WatchdogCounter--;
      return;
    }
    WatchdogCounter = 120000;
    // SUMO Watchdog
    if (SumoState == HIGH) {
      #ifdef SerialEnabled
      Serial.println("SUMO Watchdog");
      #endif
      CurrentMillis = millis();
      CurrentOnTime = CurrentMillis - StartSumoMillis;
      #ifdef SerialEnabled
      Serial.print("CurrentOnTimeMillis=");
      Serial.println(CurrentOnTime);
      #endif
      if ( CurrentOnTime >= maxOnTimeMillis ) {
        // SUMO is running for longer than maxOnTime, turn it off!
        digitalWrite(SUMO, LOW);
        digitalWrite(LED, LEDOFF);
        SumoState = LOW;
        StartSumoMillis=0; 
      }
    }
    return;
  }
   
  // Wait until the client sends some data
  #ifdef SerialEnabled
  Serial.println("New client connected, waiting for data..");
  #endif
  while(!client.available()){
    ClientCounter--;
    if (ClientCounter == 0){
      #ifdef SerialEnabled
      Serial.println("Disconnecting inactive Client.");
      #endif
      client.stop();
      delay(150);  
      return;
    }
    delay(1);
  }
  ClientCounter=4000;
  // Read the first line of the request
  String request = client.readStringUntil('\r');
  client.flush();
   
  // Match the request
 
  if (request.indexOf("/SUMO=ON") != -1) {
    digitalWrite(SUMO, HIGH);
    digitalWrite(LED, LEDON);
    SumoState = HIGH;
    StartSumoMillis = millis();
  } 
  if (request.indexOf("/SUMO=OFF") != -1){
    digitalWrite(SUMO, LOW);
    digitalWrite(LED, LEDOFF);
    SumoState = LOW;
    StartSumoMillis=0;
  }
 
  // Return the response
  client.println("HTTP/1.1 200 OK");
  client.println("Content-Type: text/html");
  client.println(""); //  do not forget this one
  client.println("<!DOCTYPE HTML>");
  client.println("<html>");
   
  client.print("SUMO state is now: ");
   
  if(SumoState == HIGH) {
    client.print("On");
    client.println("<br>");
    CurrentMillis = millis();
    CurrentOnTime = CurrentMillis - StartSumoMillis;
    int OnTimeMin = CurrentOnTime / 60000;
    client.print ("SumoOnTimeMinutes=");
    client.println(OnTimeMin);
  } else {
    client.print("Off");
  }
  client.println("<br><br>");
  client.println("Click <a href=\"/SUMO=ON\">here</a> turn the SUMO on<br>");
  client.println("Click <a href=\"/SUMO=OFF\">here</a> turn the SUMO off<br>");
  client.println("</html>");
 
  delay(150);
  client.stop();
  delay(150);  
  #ifdef SerialEnabled
  Serial.println("Client disonnected");
  Serial.println("");
  #endif
}
 
