#Sensel Processing API

This API allows users to communicate with a Sensel device through [Processing](https://processing.org) programming language and development environment. Processing is cross-platform, and this API should work across Windows, Mac, and Linux. If you find any incompatibilities, please submit a bug report through Github.

Note: Long-term, this API will most likely be moved to a Processing library, but for now it's easier to maintain in a simple .pde file.

##Setup
In order to use this API, please [download processing](https://processing.org/download), and install it on your machine. NOTE: Please use Processing version 2.2.1! Developers have experienced issues when trying to work with Processing 3.0, and we are still working to resolve these issues.

Clone this Github project, and drop sensel.pde into a new project directory.

##Usage
The Sensel Processing API provides an object-oriented approach to interacting with a Sensel device. Here's a high-level view of how to use this API:

First, we need to declare a couple global variables:

```java
//Declare these variables outside of any methods
SenselDevice sensel;
boolean sensel_sensor_opened = false;
```

Next, we need to properly setup the sensor. In the `setup()` method, we can instantiate a DisposeHandler (this will allow us to close the sensor when the program exits) and a SenselDevice. Then we call `openConnection()`, which returns true if we successfully connect to a Sensel device. If we connect to a sensor, we need to tell the sensor to send us contacts. We use the method `setFrameContentControl()`, and pass in the `SenselDevice.SENSEL_FRAME_CONTACTS_FLAG` constant. After this, we tell the sensor to start scanning by calling `startScanning()`:

```java
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
  ...
}
```

In the special Processing `draw()` method, we can call `readContacts()`. This returns an array of contacts.

```java
void draw()
{
  if(!sensel_sensor_opened)
    return;

  SenselContact[] contacts = sensel.readContacts();

  if(contacts != null) //Check for contacts
  {
    //USE CONTACT DATA HERE
  }
  ...
}
```

At the bottom of the file, we can declare our DisposeHandler class, which will allow us to execute the `dispose` method when the program exits. This allows us to properly close the Sensel device by calling `stopScanning()` and `closeConnection()`

```java
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
```

##Examples

There are two examples in this repository that you can use as a starting point for your project:

####examples/sensel_example_read_contacts
This project opens up a Sensel device, reads out contact data, and prints it to the screen.

####examples/sensel_example_visualize_contacts
This project opens up a Sensel device, and shows a visual representation of the pressure data. A circle is rendered for each contact, and the diameter of the circle corresponds to the contact's pressure. This example also shows how to effectively scale the contacts to a window on the screen.
