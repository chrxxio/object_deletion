I have only used this on QBOX.

FiveM ready, I haven't tested this on anything but my own personal server. I would recommend backing up your files before using this.

Installation Instructions:

	-create a folder called "object_deletion"
	-drag the contents into the the "object_deletion" folder
	-type /deleteobject to activate deletion mode.

(DISCLAIMER, this was a personal script I made to make it easier for myself in creating the server I am making now) I wanted to share this, for who it may help. 
 	

## Object Deletion System

This resource allows authorized players to permanently delete map objects with the ability to undo recent deletions.

### Features
- Permanently delete objects from the map
- Database storage for persistence across server restarts
- Undo last deletion with a simple command
- Debug command to identify nearby objects

### Commands
- `deletethisobjectmodel [modelName]` - Delete the closest object of specified model
- `undoDelete` - Restore the last object you deleted
- `nearbyobjects [radius]` - List nearby objects (for debugging)

### Permissions
- Requires ACE permission `command.deletethisobjectmodel`

### Installation
1. Ensure you have oxmysql installed
2. Add to server.cfg `ensure object_deletion`
3. Add permission `add_ace group.admin command.deletethisobjectmodel allow`
