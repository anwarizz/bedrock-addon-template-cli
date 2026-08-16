This is a small Windows system I made to make setting up Minecraft Bedrock addon projects a little easier, especially if you do things manually like I do.

I'm leaving it here in case you find it useful too.

How to use it:
Clone this repository somewhere on your device, then run install.bat

You'll be asked for two things:
- Where you want to install this system.
- Where your com.mojang folder is located.

That's it

Once it's installed, open CMD / Command Prompt and run:

```cadon```
or
```cadon <project_name>```

It will automatically create the RP and BP folders inside your com.mojang folder, including the folders you usually need for each pack. The ```<project_name>``` you entered will be used as the RP and BP folder name.

The manifest.json files will also be copied into both folders, and the required UUIDs will be generated automatically.


If you ever lose access to your com.mojang folder or move it somewhere else, just go to the folder where this system is installed and find config.json.

You can change the com.mojang path there.