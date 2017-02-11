/**************************************************************************
 * Copyright 2017 Sensel, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **************************************************************************/

/**
 * Read Contacts
 * by Aaron Zarraga - Sensel, Inc
 * 
 * This opens a Sensel sensor, reads contact data, and prints the data to the console.
 */

boolean sensel_sensor_opened = false;
SenselDevice sensel;

void setup() 
{
  DisposeHandler dh = new DisposeHandler(this);
  sensel = new SenselDevice(this);
  
  sensel_sensor_opened = sensel.openConnection();
  
  if(!sensel_sensor_opened)
  {
    println("Unable to open Sensel sensor!");
    exit();
    return; 
  }
  
  //Enable contact sending
  sensel.setFrameContentControl(SenselDevice.SENSEL_FRAME_CONTACTS_FLAG);
  
  //Enable scanning
  sensel.startScanning();
}

void draw() 
{
  if(!sensel_sensor_opened)
    return;
 
  SenselContact[] c = sensel.readContacts();
  
  if(c == null)
  {
    println("NULL CONTACTS");
    return;
  }
   
  for(int i = 0; i < c.length; i++)
  {
    float force = c[i].total_force;
    float area = c[i].area_mm_sq;
    float sensor_x_mm = c[i].x_pos_mm;
    float sensor_y_mm = c[i].y_pos_mm;
    
    float orientation = c[i].orientation_degrees;
    float major = c[i].major_axis_mm;
    float minor = c[i].minor_axis_mm;    
    
    int id = c[i].id;
    int event_type = c[i].type;
    
    String event;
    switch (event_type)
    {
      case SenselDevice.SENSEL_EVENT_CONTACT_INVALID:
        event = "invalid"; 
        break;
      case SenselDevice.SENSEL_EVENT_CONTACT_START:
        sensel.setLEDBrightness(id, (byte)100); //turn on LED
        event = "start";   
        break;
      case SenselDevice.SENSEL_EVENT_CONTACT_MOVE:
        event = "move";
        break;
      case SenselDevice.SENSEL_EVENT_CONTACT_END:
        sensel.setLEDBrightness(id, (byte)0);
        event = "end";
        break;
      default:
        event = "error";
    }
    
    println("Contact ID " + id + ", event=" + event + ", mm coord: (" + sensor_x_mm + ", " + sensor_y_mm + "), shape: (" + orientation + ", " + major + ", " + minor + "), area=" + area + ", force=" + force); 
  }
  
  if(false) // Set to true to see accelerometer data
  {
    float[] acc_data = sensel.readAccelerometerData();
    println("Acc Data: (" + acc_data[0] + ", " + acc_data[1] + ", " + acc_data[2] + ")");
  }
  
  if(c.length > 0)
    println("****");
}

public class DisposeHandler 
{   
  DisposeHandler(PApplet pa)
  {
    pa.registerMethod("dispose", this);
  }  
  public void dispose()
  {      
    println("Closing sketch");
    if(sensel_sensor_opened)
    {
      sensel.stopScanning();
      sensel.closeConnection();
    }
  }
}