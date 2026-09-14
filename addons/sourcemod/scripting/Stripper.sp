#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
#include <Stripper>

public Plugin myinfo =
{
    name		= "Stripper:Source (SP edition)",
    version		= "1.3.7",
    description	= "Stripper:Source functionality in a Sourcemod plugin",
    author		= "Original Author: BAILOPAN. Ported to SM by: tilgep. Edited by: Lerrdy, .Rushaway",
    url			= "https://forums.alliedmods.net/showthread.php?t=339448"
}

enum Mode
{
    Mode_None,
    Mode_Filter,
    Mode_Add,
    Mode_Modify,
}

enum SubMode
{
    SubMode_None,
    SubMode_Match,
    SubMode_Replace,
    SubMode_Delete,
    SubMode_Insert,
}

enum struct Property
{
    char key[PLATFORM_MAX_PATH];
    char val[PLATFORM_MAX_PATH];
    bool regex;
    Regex compiled;	// Precompiled pattern, valid only when 'regex' is true
}

static void FreeCompiledRegexes(ArrayList list)
{
    Property kv;
    for(int i = 0; i < list.Length; i++)
    {
        list.GetArray(i, kv, sizeof(kv));
        if(kv.compiled != null)
        {
            delete kv.compiled;
            kv.compiled = null;
            list.SetArray(i, kv, sizeof(kv));
        }
    }
}

/* Stripper block struct */
enum struct Block
{
    Mode mode;
    SubMode submode;
    ArrayList match;	// Filter/Modify
    ArrayList replace;	// Modify
    ArrayList del;		// Modify
    ArrayList insert;	// Add/Modify
    bool hasClassname;	// Ensures that an add block has a classname set

    void Init()
    {
        this.mode = Mode_None;
        this.submode = SubMode_None;
        this.match = CreateArray(sizeof(Property));
        this.replace = CreateArray(sizeof(Property));
        this.del = CreateArray(sizeof(Property));
        this.insert = CreateArray(sizeof(Property));
    }

    void Clear()
    {
        this.hasClassname = false;
        this.mode = Mode_None;
        this.submode = SubMode_None;

        FreeCompiledRegexes(this.match);
        FreeCompiledRegexes(this.replace);
        FreeCompiledRegexes(this.del);
        FreeCompiledRegexes(this.insert);

        this.match.Clear();
        this.replace.Clear();
        this.del.Clear();
        this.insert.Clear();
    }
}

char g_sFile[PLATFORM_MAX_PATH];
char g_sLogPath[PLATFORM_MAX_PATH];
bool g_bConfigLoaded = false;
bool g_bConfigError = false;
Handle g_hFwd_OnErrorLogged = INVALID_HANDLE;
ConVar g_cvFileLowercase;
Block g_Block; // Global current stripper block
int g_iSection;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("Stripper_LogError", Native_Log);
    g_hFwd_OnErrorLogged = CreateGlobalForward("Stripper_OnErrorLogged", ET_Ignore, Param_String);

    RegPluginLibrary("Stripper");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_Block.Init();

    RegAdminCmd("stripper_dump", Command_Dump, ADMFLAG_ROOT, "Writes all of the map entity properties to a file in logs/stripper/dumps/");
    RegAdminCmd("sm_stripper", Command_Stripper, ADMFLAG_GENERIC, "Prints out if the current map has a loaded stripper file");

    g_cvFileLowercase = CreateConVar("stripper_file_lowercase", "0", "Whether to load map config filenames as lower case", _, true, 0.0, true, 1.0);
    AutoExecConfig(true, "stripper");
}

public void OnPluginEnd()
{
    g_Block.Clear();
}

public Action Command_Stripper(int client, int args)
{
    bool bAccess = CheckCommandAccess(client, "sm_stripper", ADMFLAG_ROOT);
    if (g_bConfigLoaded)
    {
        ReplyToCommand(client, "[Stripper] The current map has a loaded stripper config.");
        if(bAccess) ReplyToCommand(client, "[Stripper] Loaded config: %s", g_sFile);
    }
    else if (g_bConfigError)
    {
        ReplyToCommand(client, "[Stripper] The current map loaded a stripper config but it contains error(s).");
        if(bAccess) ReplyToCommand(client, "[Stripper] Check: %s", g_sFile);
    }
    else
    {
        ReplyToCommand(client, "[Stripper] The current map did not load a stripper config.");
        if(bAccess) ReplyToCommand(client, "[Stripper] No file found: %s", g_sFile);
    }

    return Plugin_Handled;
}

public Action Command_Dump(int client, int args)
{
    char buf1[PLATFORM_MAX_PATH], buf2[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
    int num = -1;

    GetCurrentMap(buf1, PLATFORM_MAX_PATH);

    CreateDirRecursive("logs/stripper");
    CreateDirRecursive("logs/stripper/dumps");

    BuildPath(Path_SM, buf2, PLATFORM_MAX_PATH, "logs/stripper/dumps");

    do
    {
        num++;
        // Use same format as original stripper
        Format(path, PLATFORM_MAX_PATH, "%s/%s.%04d.cfg", buf2, buf1, num);
    }
    while(FileExists(path));

    File fi = OpenFile(path, "w");
    if(fi == null)
    {
        Stripper_LogError("Failed to create dump file \"%s\"", path);
        return Plugin_Handled;
    }

    EntityLumpEntry ent;

    for(int i = 0; i < EntityLump.Length(); i++)
    {
        ent = EntityLump.Get(i);

        fi.WriteLine("{");

        for(int j = 0; j < ent.Length; j++)
        {
            ent.Get(j, buf1, PLATFORM_MAX_PATH, buf2, PLATFORM_MAX_PATH);
            fi.WriteLine("\"%s\" \"%s\"", buf1, buf2);
        }

        fi.WriteLine("}");

        delete ent;
    }

    delete fi;

    ReplyToCommand(client, "[Stripper] Dumped entities to '%s'", path);
    return Plugin_Handled;
}

static void CreateDirRecursive(const char[] relPath)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "%s", relPath);
    if (!DirExists(path))
        CreateDirectory(path, 0o755);

    SetFilePermissions(path, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC|FPERM_G_READ|FPERM_G_EXEC|FPERM_O_READ|FPERM_O_EXEC);
}

static void BuildLogPath(char[] buffer, int maxlen)
{
    char mapName[PLATFORM_MAX_PATH];
    GetCurrentMap(mapName, sizeof(mapName));

    CreateDirRecursive("logs");
    CreateDirRecursive("logs/stripper");
    CreateDirRecursive("logs/stripper/maps");

    BuildPath(Path_SM, buffer, maxlen, "logs/stripper/maps/%s.log", mapName);
}

public void OnMapInit(const char[] mapName)
{
    // Path used for logging.
    BuildLogPath(g_sLogPath, sizeof(g_sLogPath));

    g_bConfigLoaded = false;
    g_bConfigError = false;

    // Parse global filters
    BuildPath(Path_SM, g_sFile, sizeof(g_sFile), "configs/stripper/global_filters.cfg");
    ParseFile(false);

    // Now parse map config
    BuildPath(Path_SM, g_sFile, sizeof(g_sFile), "configs/stripper/maps/%s.cfg", mapName);

    if(!ParseFile(true) && g_cvFileLowercase.BoolValue)
    {
        strcopy(g_sFile, sizeof(g_sFile), mapName);
        for(int i = 0; g_sFile[i]; i++)
            g_sFile[i] = CharToLower(g_sFile[i]);

        BuildPath(Path_SM, g_sFile, sizeof(g_sFile), "configs/stripper/maps/%s.cfg", g_sFile);
        ParseFile(true);
    }
}

public bool ParseFile(bool mapconfig)
{
    int line, col;
    g_iSection = 0;

    g_Block.Clear();

    SMCParser parser = SMC_CreateParser();
    SMC_SetReaders(parser, Config_NewSection, Config_KeyValue, Config_EndSection);

    SMCError result = SMC_ParseFile(parser, g_sFile, line, col);
    delete parser;

    if (result == SMCError_Okay)
    {
        if (mapconfig)
            g_bConfigLoaded = true;

        return true;
    }

    if(result != SMCError_Okay && result != SMCError_StreamOpen)
    {
        if(result == SMCError_StreamOpen)
        {
            g_bConfigLoaded = false;
            LogMessage("Failed to open stripper config \"%s\"", g_sFile);
        }
        else
        {
            char error[128];
            g_bConfigError = true;
            SMC_GetErrorString(result, error, sizeof(error));
            Stripper_LogError("%s on line %d, col %d of %s", error, line, col, g_sFile);
        }
    }

    return false;
}

public SMCResult Config_NewSection(SMCParser smc, const char[] name, bool opt_quotes)
{
    g_iSection++;
    if(!strcmp(name, "filter:", false) || !strcmp(name, "remove:", false))
    {
        if(g_Block.mode != Mode_None)
        {
            g_bConfigError = true;
            Stripper_LogError("Found 'filter' block while inside another block at section %d in file '%s'", g_iSection, g_sFile);
        }

        g_Block.Clear();
        g_Block.mode = Mode_Filter;
    }
    else if(!strcmp(name, "add:", false))
    {
        if(g_Block.mode != Mode_None)
        {
            g_bConfigError = true;
            Stripper_LogError("Found 'add' block while inside another block at section %d in file '%s'", g_iSection, g_sFile);
        }

        g_Block.Clear();
        g_Block.mode = Mode_Add;
    }
    else if(!strcmp(name, "modify:", false))
    {
        if(g_Block.mode != Mode_None)
        {
            g_bConfigError = true;
            Stripper_LogError("Found 'modify' block while inside another block at section %d in file '%s'", g_iSection, g_sFile);
        }

        g_Block.Clear();
        g_Block.mode = Mode_Modify;
    }
    else if(g_Block.mode == Mode_Modify)
    {
        if(!strcmp(name, "match:", false))			g_Block.submode = SubMode_Match;
        else if(!strcmp(name, "replace:", false))	g_Block.submode = SubMode_Replace;
        else if(!strcmp(name, "delete:", false))	g_Block.submode = SubMode_Delete;
        else if(!strcmp(name, "insert:", false))	g_Block.submode = SubMode_Insert;
        else
        {
            g_bConfigError = true;
            Stripper_LogError("Found invalid section '%s' in modify block at section %d in file '%s'", name, g_iSection, g_sFile);
        }
    }
    else
    {
        g_bConfigError = true;
        Stripper_LogError("Found invalid section name '%s' at section %d in file '%s'", name, g_iSection, g_sFile);
    }

    return SMCParse_Continue;
}

public SMCResult Config_KeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
    // Resolve the destination list first so we never compile a regex we would throw away.
    ArrayList target = null;
    switch(g_Block.mode)
    {
        case Mode_Filter:	target = g_Block.match;
        case Mode_Add:		target = g_Block.insert;
        case Mode_Modify:
        {
            switch(g_Block.submode)
            {
                case SubMode_Match:		target = g_Block.match;
                case SubMode_Replace:	target = g_Block.replace;
                case SubMode_Delete:	target = g_Block.del;
                case SubMode_Insert:	target = g_Block.insert;
            }
        }
    }

    if(target == null)
        return SMCParse_Continue;

    Property kv;
    strcopy(kv.key, PLATFORM_MAX_PATH, key);
    strcopy(kv.val, PLATFORM_MAX_PATH, value);

    bool isMatchable = (target == g_Block.match || target == g_Block.del);
    if(isMatchable && FormatRegex(kv.val, strlen(kv.val)))
    {
        kv.regex = true;
        kv.compiled = CompileRegex(kv.val);
        if(kv.compiled == null)
        {
            g_bConfigError = true;
            Stripper_LogError("Invalid regex '/%s/' at section %d in file '%s'", kv.val, g_iSection, g_sFile);
        }
    }

    // Adding an entity without a classname will crash the server (shortest classname is "gib")
    if(g_Block.mode == Mode_Add && strcmp(key, "classname", false) == 0 && strlen(value) > 2)
        g_Block.hasClassname = true;

    target.PushArray(kv);
    return SMCParse_Continue;
}

public SMCResult Config_EndSection(SMCParser smc)
{
    switch(g_Block.mode)
    {
        case Mode_Filter:
        {
            if(g_Block.match.Length > 0) RunRemoveFilter();

            g_Block.mode = Mode_None;
        }
        case Mode_Add:
        {
            if(g_Block.insert.Length > 0)
            {
                if(g_Block.hasClassname)
                    RunAddFilter();
                else
                {
                    g_bConfigError = true;
                    Stripper_LogError("Add block with no classname found at section %d in file '%s'", g_iSection, g_sFile);
                }
            }

            g_Block.mode = Mode_None;
        }
        case Mode_Modify:
        {
            // Exiting a modify sub-block
            if(g_Block.submode != SubMode_None)
            {
                g_Block.submode = SubMode_None;
                return SMCParse_Continue;
            }

            // Must have something to match for modify blocks
            if(g_Block.match.Length > 0) RunModifyFilter();

            g_Block.mode = Mode_None;
        }
    }
    return SMCParse_Continue;
}

public void RunRemoveFilter()
{
    /* g_Block.match holds what we want
     * we know it has at least 1 entry here
     */

    char val2[PLATFORM_MAX_PATH];
    Property kv;
    EntityLumpEntry entry;
    for(int i, matches, j, index; i < EntityLump.Length(); i++)
    {
        matches = 0;
        entry = EntityLump.Get(i);

        for(j = 0; j < g_Block.match.Length; j++)
        {
            g_Block.match.GetArray(j, kv, sizeof(kv));

            index = entry.GetNextKey(kv.key, val2, sizeof(val2));
            while(index != -1)
            {
                if(EntPropsMatch(kv, val2))
                {
                    matches++;
                    break;
                }

                index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
            }
        }

        if(matches == g_Block.match.Length)
        {
            EntityLump.Erase(i);
            i--;
        }
        delete entry;
    }
}

public void RunAddFilter()
{
    /* g_Block.insert holds what we want
     * we know it has at least 1 entry here
     */

    int index = EntityLump.Append();
    EntityLumpEntry entry = EntityLump.Get(index);

    Property kv;
    for(int i; i < g_Block.insert.Length; i++)
    {
        g_Block.insert.GetArray(i, kv, sizeof(kv));
        entry.Append(kv.key, kv.val);
    }

    delete entry;
}

public void RunModifyFilter()
{
    /* g_Block.match holds at least 1 entry here
     * others may not have anything
     */

    // Nothing to do if these are all empty
    if(g_Block.replace.Length == 0 && g_Block.del.Length == 0 && g_Block.insert.Length == 0)
    {
        return;
    }

    char val2[PLATFORM_MAX_PATH];

    Property kv;
    EntityLumpEntry entry;
    for(int i, matches, j, index; i < EntityLump.Length(); i++)
    {
        matches = 0;
        entry = EntityLump.Get(i);

        /* Check matches */
        for(j = 0; j < g_Block.match.Length; j++)
        {
            g_Block.match.GetArray(j, kv, sizeof(kv));

            index = entry.GetNextKey(kv.key, val2, sizeof(val2));
            while(index != -1)
            {
                if(EntPropsMatch(kv, val2))
                {
                    matches++;
                    break;
                }

                index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
            }
        }

        if(matches < g_Block.match.Length)
        {
            delete entry;
            continue;
        }

        /* This entry matches, perform any changes */

        /* First do deletions */
        if(g_Block.del.Length > 0)
        {
            for(j = 0; j < g_Block.del.Length; j++)
            {
                g_Block.del.GetArray(j, kv, sizeof(kv));

                index = entry.GetNextKey(kv.key, val2, sizeof(val2));
                while(index != -1)
                {
                    if(EntPropsMatch(kv, val2))
                    {
                        entry.Erase(index);
                        index--;
                    }
                    index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
                }
            }
        }

        /* do replacements */
        if(g_Block.replace.Length > 0)
        {
            for(j = 0; j < g_Block.replace.Length; j++)
            {
                g_Block.replace.GetArray(j, kv, sizeof(kv));

                index = entry.GetNextKey(kv.key, val2, sizeof(val2));
                while(index != -1)
                {
                    entry.Update(index, NULL_STRING, kv.val);
                    index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
                }
            }
        }

        /* do insertions */
        if(g_Block.insert.Length > 0)
        {
            for(j = 0; j < g_Block.insert.Length; j++)
            {
                g_Block.insert.GetArray(j, kv, sizeof(kv));
                entry.Append(kv.key, kv.val);
            }
        }

        delete entry;
    }
}

/**
 * Checks whether an entity property value matches a config property.
 *
 * @param kv		Config property (its precompiled regex is used when kv.regex is set)
 * @param val2		Entity property value to test
 * @return			True if match, false otherwise
 */
stock bool EntPropsMatch(const Property kv, const char[] val2)
{
    if(kv.regex)
        return kv.compiled != null && MatchRegex(kv.compiled, val2) > 0;

    return strcmp(kv.val, val2) == 0;
}

stock bool FormatRegex(char[] pattern, int len)
{
    if(len >= 2 && pattern[0] == '/' && pattern[len-1] == '/')
    {
        strcopy(pattern, len-1, pattern[1]);
        return true;
    }

    return false;
}

// native Stripper_LogError(const char[] format, any...);
public int Native_Log(Handle plugin, int numParams)
{
    char sBuffer[2048];
    FormatNativeString(0, 1, 2, sizeof(sBuffer), _, sBuffer);

    // OnMapInit may not have run yet for a plugin loaded mid-map.
    if(g_sLogPath[0] == '\0')
        BuildLogPath(g_sLogPath, sizeof(g_sLogPath));

    LogToFileEx(g_sLogPath, "%s", sBuffer);

    // Start forward call
    Call_StartForward(g_hFwd_OnErrorLogged);
    Call_PushString(sBuffer);
    Call_Finish();

    return 1;
}
