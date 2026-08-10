module redub.extensions.helper.environment;

version(Posix)
{
    string redubRcHeaderStart = "\n# Begin Redub Managed #\n";
    string redubRcHeaderEnd = "\n# End Redub Managed #\n";
}

/** 
 * Saves in the HKLU on Windows
 * Params:
 *   key = The key of the variable
 *   value = The value
 */
version(Windows)
private void saveEnvVariable(string key, string value)
{
    import std.windows.registry;
    Key HKCU = Registry.currentUser;
    Key env = HKCU.getKey("Environment", REGSAM.KEY_WRITE);
    import std.stdio;
    writeln("Writing: ", env.name, " ", key, " -> ", value);
    env.setValue(key, value);

}

void saveEnvVariables(string[2][] keyValues)
{
    import std.algorithm;
    import redub.misc.path;
    import std.array:join;
    import std.path:pathSeparator;
    string newPathEntry = keyValues.filter!(kv => kv[0].endsWith("PATH")).map!(kv => kv[1]).join(pathSeparator);
    version(Windows)
    {
        import std.windows.registry;
        Key HKCU = Registry.currentUser;
        Key redubKey = HKCU.createKey("Software\\Redub");

        import std.stdio;
        redubKey.setValue("ManagedEnvironment", newPathEntry);
        foreach(kv; keyValues)
            saveEnvVariable(kv[0], kv[1]);

        string pathEnv = HKCU.getKey("Environment").getValue("Path").value_SZ();
        saveEnvVariable("Path", pathEnv~pathSeparator~newPathEntry);
        notifySystemEnvUpdate();
    }
    else version(Posix)
    {
        import redub.parsers.environment;
        import std.exception:enforce;
        import std.file;
        import redub.api;
        string entries = keyValues.map!(kv => "export "~ kv[0]~ "="~kv[1]).join("\n");
        entries~= "\nexport PATH=$PATH:"~newPathEntry~"\n";

        string shell = buildNormalizedPath(getDubWorkspacePath, "redub_env.sh");
        string rcFile = getRcFile();
        enforce(exists(rcFile), "No support to save env variables in this system. Checked either .bashrc or .zshrc");
        string dataToSave = redubRcHeaderStart~"source \""~shell~"\""~redubRcHeaderEnd;
        string oldContent = std.file.readText(rcFile);

        ptrdiff_t oldPlace = countUntil(oldContent, dataToSave);
        std.file.write(shell, entries);
        if(oldPlace == -1)
            std.file.write(rcFile, oldContent~dataToSave);
    }
    else assert(false, "No support to save env variables in this system.");
}

version(Windows)
void notifySystemEnvUpdate()
{
    import core.sys.windows.winuser;
    import core.sys.windows.windef;
    SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, cast(LPARAM)"Environment"w.ptr, SMTO_ABORTIFHUNG, 5000, null);
}

void deleteRedubEnvVariables()
{
    version(Windows)
    {
        import std.windows.registry;
        import std.path;
        import std.string;
        import std.algorithm;
        import redub.parsers.environment;
        Key HKCU = Registry.currentUser;
        Key redubKey = HKCU.getKey("Software\\Redub");
        try
        {
            Value appendedEnv = redubKey.getValue("ManagedEnvironment");
            string currPath = getEnvVariable("PATH");
            
            string[] existingPaths = appendedEnv.value_SZ.split(pathSeparator);
            string[] currPaths = currPath.split(pathSeparator);
            string[] result;
            outer: foreach(p; currPaths)
            {
                import std.uni;
                foreach(existing; existingPaths)
                    if(asLowerCase(p) == asLowerCase(existing))
                        continue outer;
                result~= p;
            }
            saveEnvVariable("Path", result.join(pathSeparator));
            notifySystemEnvUpdate();
        }
        catch(Exception e)
        {
            return;
        }
    }
    else version(Posix)
    {
        import std.file;
        import std.algorithm:countUntil;
        string rc = getRcFile();
        string content = std.file.readText(rc);
        
        ptrdiff_t start = countUntil(content, redubRcHeaderStart);
        ptrdiff_t end = countUntil(content, redubRcHeaderEnd);
        if(start != -1 && end != -1)
        {
            content = content[0..start] ~ content[end+redubRcHeaderEnd.length..$];
            std.file.write(rc, content);
        }
    }
}

version(Posix)
string getRcFile()
{
    import std.path;
    import redub.parsers.environment;
    version(linux)
        return buildNormalizedPath(getEnvVariable("HOME"), ".bashrc");
    else version(OSX)
        return buildNormalizedPath(getEnvVariable("HOME"), ".zshrc");
    else
        return null;
}
version(Windows)
private void deleteEnvVariable(string key)
{
    import std.windows.registry;
    Key HKCU = Registry.currentUser;
    Key env = HKCU.getKey("Environment", REGSAM.KEY_WRITE);
    env.deleteKey(key);
}