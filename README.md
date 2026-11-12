A rewrite of Stripper:Source into Sourcepawn  
It can read stripper configs with no changes necessary*  
  
*See [this issue report](https://github.com/tilgep/stripper/issues/2) for an edge case  

### **Requires at least Sourcemod 1.11.6919 for entity lump access**

Info on stripper: https://www.bailopan.net/stripper/  
Forum thread for this plugin: https://forums.alliedmods.net/showthread.php?t=339448

### Configuration
`sourcemod/configs/stripper/global_filters.cfg` for the global config  
`sourcemod/configs/stripper/maps/mapname.cfg` for map specific config

### Limits
- Keys: up to 255 characters.
- Values: up to 2047 characters, the engine limit for an entity lump value (`MAPKEY_MAXLENGTH`).
- Outputs (`target,input,param,delay,times`): the engine parses each comma-separated field into a 256-byte buffer, so each field must stay under 256 characters even when the whole line is longer.
- A config line (`"key" "value"`) must fit in the 4096-byte buffer of the SourceMod config parser.

Longer keys or values are truncated and reported in `logs/stripper/maps/<map>.log`.

### Cvars
`stripper_file_lowercase` - Whether to load map config filenames as lower case

### Commands
`stripper_dump` - dumps all current entity properties to a file in `logs/stripper/dumps/`
