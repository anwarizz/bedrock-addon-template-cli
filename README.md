This is a small Windows system I made to make setting up Minecraft Bedrock addon projects a little easier, especially if you do things manually like I do.

I'm leaving it here in case you find it useful too.

How to use it:
Clone this repository somewhere on your device, then run install.bat

You'll be asked for two things:
- Where you want to install this system.
- Where your com.mojang folder is located.

That's it

Once it's installed, open CMD / Command Prompt and run:

`cadon help` - Display all the available commands listed below. But if you want to read more about how each command works, feel free to continue reading.

> Some of the available commands are not listed in this README.

**Creating a Project**

```cadon```
or
```cadon <project_name>```

It will automatically create the RP and BP folders inside your com.mojang folder, including the folders you usually need for each pack. The ```<project_name>``` you entered will be used as the RP and BP folder name.

The manifest.json files will also be copied into both folders, and the required UUIDs will be generated automatically.


If you ever lose access to your com.mojang folder or move it somewhere else, just go to the folder where this system is installed and find config.json.

You can change the com.mojang path there.


**Additional Commands**

- `cadon <project_name>` - minimal setup  
  Creates the basic RP and BP folders you need to get started.

- `cadon <project_name> *` - full setup  
  Creates the RP and BP folders with all the usual folders needed for an addon project.

- if you use Visual Studio Code, `cadon code code` or `cadon code <path_to_vscode>` - This configures the system to automatically open Visual Studio Code after you create a project, with the workspace for your new project already set up.

- `cadon entity` - This command must be run from the root folder of a valid addon project, inside an RP or BP folder that contains a valid `manifest.json`  
  The system will ask you to enter a display name (e.g. `baboon`) and an identifier (e.g. `myaddon:baboon`).  
  It will automatically add all the files needed to create an entity to both the RP and BP of your project.  
  This will create a basic entity that doesn't move.

- `cadon item` - Similar to `cadon entity`, this command will automatically add all the files needed to create an item to both the RP and BP of your project.  
  The system will ask you to enter a display name (e.g. `Cool Ore`) and an identifier (e.g. `myaddon:cool_ore`).  
  This will create a basic item with the required files and configuration.

## Clone Project from CurseForge

For me, one of the annoying things when updating an old project is getting everything ready again. I didn't know the fastest way to open an old project, so I usually had to create a new workspace and drag every folder I needed into it.

To make things a little easier, there's a command that can download a project We've already uploaded to CurseForge, automatically extract it into the RP and BP folders inside `com.mojang`, and automatically open the workspace in Visual Studio Code.

- `cadon apikey <apikey>` - Get a free API key from `console.curseforge.com` and enter it here.

- `cadon projectid <projectid> <fileid>` - Clone a project from CurseForge using its project ID and file ID.  
  You can find the **project ID** on your project page, and the **file ID** in the **Files** section.

## Package the current project's RP and BP into a versioned folder and a `.mcaddon` file.

I usually keep my finished projects in a folder called 'Publish' on my local storage. Inside it, each project has its own folder named after the project, containing the RP, BP, and the .mcaddon file ready to be played.

Manually copying the RP and BP, compressing them into a .mcaddon, and then moving everything into the Publish folder can get pretty annoying. It was also a little worrying because it's easy to accidentally miss something or put a file in the wrong place.

* `cadon publish` - Initially, this command will ask you for the path to your 'Publish' folder (you can use any folder where you keep your projects), then ask for the updated version of your addon (e.g. 1.0.1). It will automatically create a folder named after your project inside the Publish folder, copy the RP and BP into it, and compress them into a .mcaddon file at the same time.
