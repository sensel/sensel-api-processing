/**************************************************************************
 * Copyright 2015 Sensel, Inc.
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

/* 
  Sensel API for Processing.

  -> Outside of all functions:
  -> SenselDevice sensel;

  -> Inside setup():
  -> sensel = new SenselDevice(this);
  -> sensel.openConnection(); //returns true if successful, false if error
  -> sensel.setFrameContentControl(SenselDevice.SENSEL_FRAME_CONTACTS_FLAG); //enables contact sending
  -> sensel.startScanning(); //Start scanning
  
  -> Inside draw():
  -> SenselContact[] contacts = sensel.readContacts();

  -> Inside DisposeHandler:
  -> sensel.stopScanning();
  -> sensel.closeConnection();
*/

import processing.serial.*;

public class SenselContact
{
  int total_force;
  int uid;
  float area_mm_sq; // area in square mm
  float x_pos_mm; // x position in mm                                                                                                                                         
  float y_pos_mm; // y position in mm                                                                                                                                           
  float dx_mm; // change in x from last frame                                                                                                                                                                     
  float dy_mm; // change in y from last frame                                                                                                                                                                     
  float orientation_degrees; // angle from -90 to 90 degrees                                                                                                                          
  float major_axis_mm; // length of the major axis                                                                                                                                             
  float minor_axis_mm; // length of the minor axis                                                                                                                                             
  int id;
  int type;
}

public class SenselDevice
{
  final static byte SENSEL_REG_MAGIC                = (byte)0x00;
  final static byte SENSEL_REG_MAGIC_LENGTH         = (byte)0x06;
  final static byte SENSEL_REG_SCAN_CONTENT_CONTROL = (byte)0x24;
  final static byte SENSEL_REG_SCAN_ENABLED         = (byte)0x25;
  final static byte SENSEL_REG_SCAN_READ_FRAME      = (byte)0x26;
  final static byte SENSEL_REG_CONTACTS_MAX_COUNT   = (byte)0x40;
  final static byte SENSEL_REG_ACCEL_X              = (byte)0x60;
  final static byte SENSEL_REG_ACCEL_Y              = (byte)0x62;
  final static byte SENSEL_REG_ACCEL_Z              = (byte)0x64;
  final static byte SENSEL_REG_LED_BRIGHTNESS       = (byte)0x80;

  final static byte SENSEL_FRAME_CONTACTS_FLAG      = (byte)0x04;

  final static byte SENSEL_PT_FRAME     = 1;
  final static byte SENSEL_PT_READ_ACK  = 6;
  final static byte SENSEL_PT_WRITE_ACK = 10;

  final static int SENSEL_EVENT_CONTACT_INVALID = 0;
  final static int SENSEL_EVENT_CONTACT_START   = 1;
  final static int SENSEL_EVENT_CONTACT_MOVE    = 2;
  final static int SENSEL_EVENT_CONTACT_END     = 3;

  final static byte SENSEL_BOARD_ADDR   = (byte)0x01;
  final static byte SENSEL_READ_HEADER  = (byte)(SENSEL_BOARD_ADDR | (1 << 7));
  final static byte SENSEL_WRITE_HEADER = SENSEL_BOARD_ADDR;

  private Serial serial_port;
  private int sensor_max_x;
  private int sensor_max_y;
  private float sensor_width_mm;
  private float sensor_height_mm;
  private int sensor_max_contacts;
  private float sensor_x_to_mm_factor;
  private float sensor_y_to_mm_factor;
  private float sensor_orientation_to_degrees_factor = 1.0f/256.0f;
  private float sensor_area_to_mm_sq_factor = 1.0f/4096.0f;
  private PApplet parent;

  public SenselDevice(PApplet p)
  {
    parent = p; 
  }

  private boolean _checkForMagic(Serial port)
  {
    port.write(SENSEL_READ_HEADER);
    port.write(SENSEL_REG_MAGIC);
    port.write(SENSEL_REG_MAGIC_LENGTH);
    
    delay(500);
    
    //1-byte packet type, 2-byte size of payload, Payload, 1-byte checksum
    int magic_response_size = 4 + SENSEL_REG_MAGIC_LENGTH;
    
    if(port.available() < magic_response_size)
    {
      println("Magic not found!");
    }
    else
    {
      //println("Bytes available: " + port.available());

      //Check ACK
      if(port.readChar() != SENSEL_PT_READ_ACK) //Packet ACK
      {
        println("READ ACK NOT FOUND IN MAGIC PACKET!");
        return false;
      }

      //Check 2-byte packet size
      int packet_size = _convertBytesTo16((byte)port.readChar(), (byte)port.readChar());
      if(packet_size != SENSEL_REG_MAGIC_LENGTH)
      {
        println("LENGTH MISMATCH IN MAGIC PACKET! (Expected " + SENSEL_REG_MAGIC_LENGTH + ", received " + packet_size + ")");
        return false;
      }
      
      String magic = "";
      int checksum_calculated = 0;
      for(int i = 0; i < SENSEL_REG_MAGIC_LENGTH; i++)
      {
        char c = port.readChar();
        magic += c;
        checksum_calculated += c; 
      }
      checksum_calculated &= (0xFF);
      
      //Verify checksum
      int checksum_received = (int)port.readChar();
      if(checksum_received != checksum_calculated)
      {
        println("CHECKSUM MISMATCH IN MAGIC PACKET! (calculated " + (int)checksum_calculated + ", received " + (int)checksum_received + ")");
        return false;
      }
      
      if(magic.equals("S3NS31"))
      {
        println("MAGIC FOUND!");
        return true;
      }
      else
      {
        println("Invalid magic: " + magic);
      }
    }  
    return false;
  }

  public boolean openConnection()
  {
    String[] serial_list = Serial.list();
    serial_port = null;
    
    for(int i = 0; i < serial_list.length; i++)
    {
      println("Opening " + serial_list[i]);
      Serial curr_port;
      
      try{
        curr_port = new Serial(parent, serial_list[i], 115200);
      }
      catch(Exception e)
      {
        continue;
      }
      
      //Flush port
      curr_port.clear();
      
      if(_checkForMagic(curr_port))
      {
        serial_port = curr_port;
        sensor_max_x =  (256 * (_readReg(0x10, 1)[0] - 1));
        sensor_max_y =  (256 * (_readReg(0x11, 1)[0] - 1));
        
        println("Sensor Max X = " + sensor_max_x);
        println("Sensor Max Y = " + sensor_max_y);
        
        int [] sensor_width_arr  = _readReg(0x14, 4);
        int [] sensor_height_arr = _readReg(0x18, 4);
        
        //Convert from um to mm
        sensor_width_mm  = ((float)_convertBytesTo32((byte)sensor_width_arr[0],  (byte)sensor_width_arr[1],  (byte)sensor_width_arr[2],  (byte)sensor_width_arr[3]))  / 1000.0;
        sensor_height_mm = ((float)_convertBytesTo32((byte)sensor_height_arr[0], (byte)sensor_height_arr[1], (byte)sensor_height_arr[2], (byte)sensor_height_arr[3])) / 1000.0;
        
        println("Sensor Width = "  + sensor_width_mm  + " mm");
        println("Sensor Height = " + sensor_height_mm + " mm");
        
        sensor_max_contacts = _readReg(SENSEL_REG_CONTACTS_MAX_COUNT, 1)[0];
        println("Sensor Max Contacts = " + sensor_max_contacts);
        
        sensor_x_to_mm_factor = sensor_width_mm  / sensor_max_x;
        sensor_y_to_mm_factor = sensor_height_mm / sensor_max_y;
        
        break;
      }
      else
      {
        curr_port.stop(); 
      }
    }
    return (serial_port != null);
  }
  
  public void closeConnection()
  {
    setLEDBrightnessAll((byte)0);
    serial_port.stop();
  }
  
  public void setFrameContentControl(byte content)
  {
    senselWriteReg(SENSEL_REG_SCAN_CONTENT_CONTROL, 1, content);
  }
  
  public void setLEDBrightness(int idx, byte brightness)
  {
    if(idx < 16)
      senselWriteReg(SENSEL_REG_LED_BRIGHTNESS + idx, 1, brightness); 
  }
  
  public void setLEDBrightnessAll(byte brightness)
  {
    for(int i = 0; i < 16; i++)
      senselWriteReg(SENSEL_REG_LED_BRIGHTNESS + i, 1, brightness); 
  }
  
  public float getSensorWidthMM()
  {
    return sensor_width_mm;
  }
  
  public float getSensorHeightMM()
  {
    return sensor_height_mm; 
  }
  
  public int getMaxNumContacts()
  {
    return sensor_max_contacts;
  }
  
  public void startScanning()
  {
    senselWriteReg(SENSEL_REG_SCAN_ENABLED, 1, 1);
  }
  
  public void stopScanning()
  {
    senselWriteReg(SENSEL_REG_SCAN_ENABLED, 1, 0);
  }
  
  private int[] _readReg(int addr, int size)
  {
    serial_port.write(SENSEL_READ_HEADER);
    serial_port.write((byte)addr);
    serial_port.write((byte)size);
    
    int[] rx_buf = new int[size]; // TODO (Ilya): I think the rx_buf should be a byte array, and this funciton should return bytes.
    
    int ack;
    while((ack = serial_port.read()) == -1);
    
    if(ack != SENSEL_PT_READ_ACK)
      println("FAILED TO RECEIVE ACK ON READ (regaddr=" + addr + ", ack=" + ack + ")");
    
    int size0;
    while((size0 = serial_port.read()) == -1);
  
    int size1;
    while((size1 = serial_port.read()) == -1);
    
    int resp_size = _convertBytesTo16((byte)size0, (byte)size1);
  
    //if(size != resp_size)
    //  println("RESP_SIZE != SIZE (" + resp_size + "!=" + size + ") ON READ");
    //else
    //  println("RESP_SIZE == SIZE (" + resp_size + "==" + size + ") ON READ");
    
    int checksum = 0;
    
    for(int i = 0; i < size; i++)
    {
       while((rx_buf[i] = serial_port.read()) == -1);
       checksum += rx_buf[i];
    }
    
    checksum = (checksum & 0xFF);
    
    int resp_checksum;
    while((resp_checksum = serial_port.read()) == -1);
    
    if(checksum != resp_checksum)
      println("CHECKSUM FAILED: " + checksum + "!=" + resp_checksum + " ON READ");
    
    return rx_buf;
  }
  
  private int _readContactFrameSize()
  {
    serial_port.write(SENSEL_READ_HEADER);
    serial_port.write((byte)SENSEL_REG_SCAN_READ_FRAME);
    serial_port.write((byte)0x00);
    
    int ack;
    while((ack = serial_port.read()) == -1);
    
    if(ack != SENSEL_PT_FRAME)
      println("FAILED TO RECEIVE FRAME PACKET TYPE ON FRAME READ");
    
    int size0;
    while((size0 = serial_port.read()) == -1);
  
    int size1;
    while((size1 = serial_port.read()) == -1);
    
    int content_bitmask;
    while((content_bitmask = serial_port.read()) == -1);
    //println("CBM: " + content_bitmask);
    
    int frame_counter;
    while((frame_counter = serial_port.read()) == -1);
    //println("FC: " + frame_counter);
    
    //println("Finished reading contact frame size: " + (size0 | (size1 <<8)));  
    
    return _convertBytesTo16((byte)size0, (byte)size1) - 2; //Packet size includes content bitmask and lost frame count which we've already read out
  }
  
  //We only support single-byte writes at this time TODO: Implement multi-byte write
  private void senselWriteReg(int addr, int size, int data)
  {
    if(size != 1)
      println("writeReg only supports writes of size 1");
      
    serial_port.write(SENSEL_WRITE_HEADER);
    serial_port.write((byte)addr);
    serial_port.write((byte)size);
    serial_port.write((byte)data);
    serial_port.write((byte)data); //Checksum
    
    int ack;
    while((ack = serial_port.read()) == -1);
    
    if(ack != SENSEL_PT_WRITE_ACK)
      println("FAILED TO RECEIVE ACK ON WRITE (regaddr=" + addr + ", ack=" + ack + ")");
  }
  
  private int _convertBytesTo32(byte b0, byte b1, byte b2, byte b3)
  {
    return ((((int)b3) & 0xff) << 24) | ((((int)b2) & 0xff) << 16) | ((((int)b1) & 0xff) << 8) | (((int)b0) & 0xff); 
  }
  
  private int _convertBytesTo16(byte b0, byte b1)
  {
    return ((((int)b1) & 0xff) << 8) | (((int)b0) & 0xff); 
  }
  
  // Convert two bytes (which represent a two's complement signed 16 bit integer) into a signed int
  private int _convertBytesToS16(byte b0, byte b1)
  {
    return (((int)b1) << 8) | (((int)b0) & 0xff);
  }
  
  public SenselContact[] readContacts()
  {
    SenselContact[] retval = null;
    int contact_frame_size = _readContactFrameSize() + 1; //For checksum!
  
    //println("CFS: " + contact_frame_size);
  
    if(true)//contact_frame_size > 0)
    {  
      //println("Force frame: " + contact_frame_size);
      byte[] contact_frame = new byte[contact_frame_size];
      
      int aval;
      do
      {
        aval = serial_port.available();
        //println("Aval: " + aval);
        delay(1);
      }
      while(aval < contact_frame_size);
      
      int read_count = serial_port.readBytes(contact_frame);
      
      if(read_count < contact_frame_size)
      {
        println("SOMETHING BAD HAPPENED! (" + read_count + " < " + contact_frame_size + ")");
        exit(); 
      }
      
      int num_contacts = ((int)contact_frame[0]) & 0xff;  
    
      //print("Num Contacts: " + num_contacts + "....");
      
      int idx = 0;
      
      SenselContact[] c = new SenselContact[num_contacts];
      
      for(int i = 0; i < num_contacts; i++)
      {
        c[i] = new SenselContact();
        c[i].total_force = _convertBytesTo32(contact_frame[++idx], contact_frame[++idx], contact_frame[++idx], contact_frame[++idx]);
        c[i].uid = _convertBytesTo32(contact_frame[++idx], contact_frame[++idx], contact_frame[++idx], contact_frame[++idx]);
        //Convert area to square mm
        c[i].area_mm_sq = ((float)_convertBytesTo32(contact_frame[++idx], contact_frame[++idx], contact_frame[++idx], contact_frame[++idx])) * sensor_area_to_mm_sq_factor;
        //Convert x_pos to x_pos_mm
        c[i].x_pos_mm = ((float)_convertBytesTo16(contact_frame[++idx], contact_frame[++idx])) * sensor_x_to_mm_factor;
        //Convert y_pos to y_pos_mm
        c[i].y_pos_mm = ((float)_convertBytesTo16(contact_frame[++idx], contact_frame[++idx])) * sensor_y_to_mm_factor;
        //Convert dx to dx_mm
        c[i].dx_mm =    ((float)_convertBytesTo16(contact_frame[++idx], contact_frame[++idx])) * sensor_x_to_mm_factor;
        //Convert dy to dy_mm
        c[i].dy_mm =    ((float)_convertBytesTo16(contact_frame[++idx], contact_frame[++idx])) * sensor_y_to_mm_factor;
        //Convert orientation to angle in degrees
        c[i].orientation_degrees = ((float)_convertBytesToS16(contact_frame[++idx], contact_frame[++idx])) * sensor_orientation_to_degrees_factor;
        //Convert major_axis to mm (assumes that x_to_mm and y_to_mm are the same)
        c[i].major_axis_mm = ((float)_convertBytesTo16(contact_frame[++idx], contact_frame[++idx])) * sensor_x_to_mm_factor;
        //Convert minor_axis to mm (assumes that x_to_mm and y_to_mm are the same)
        c[i].minor_axis_mm = ((float)_convertBytesTo16(contact_frame[++idx], contact_frame[++idx])) * sensor_x_to_mm_factor;
        ++idx; //peak_x
        ++idx; //peak_y
        c[i].id = (((int)contact_frame[++idx]) & 0xff);
        c[i].type = (((int)contact_frame[++idx]) & 0xff);
      }
      retval = c;
    }  
    //TODO: ACTUALLY USE CHECKSUM!!!
    //byte checksum;
    //while((checksum = (byte)serial_port.read()) == -1);
    //println("finish read");
  
    return retval;
  }
  
  
  // Returns (x,y,z) acceleration in G's using the following coordinate system:
  //
  //          ---------------------------
  //        /   Z /\  _                 /
  //       /       |  /| Y             /
  //      /        | /                /
  //     /         |/                /
  //    /           -----> X        /
  //   /                           /
  //   ----------------------------
  //
  // Assumes accelerometer is configured to the default +/- 2G range
  public float[] readAccelerometerData()
  {
    // Read accelerometer data bytes for X, Y and Z
    int[] acc_bytes = _readReg(SENSEL_REG_ACCEL_X,6);

    // Convert raw bytes to signed values
    int[] acc_values = new int[3];
    acc_values[0] = _convertBytesToS16((byte)acc_bytes[0], (byte)acc_bytes[1]);
    acc_values[1] = _convertBytesToS16((byte)acc_bytes[2], (byte)acc_bytes[3]);
    acc_values[2] = _convertBytesToS16((byte)acc_bytes[4], (byte)acc_bytes[5]);
    
    // Rescale to G's (at a range of +/- 2G, accelerometer returns 0x4000 for 1G acceleration)
    float[] acc_data = new float[3];
    acc_data[0] = ((float)acc_values[0] / 0x4000);
    acc_data[1] = ((float)acc_values[1] / 0x4000);    
    acc_data[2] = ((float)acc_values[2] / 0x4000);
    
    return acc_data;
  }
}
