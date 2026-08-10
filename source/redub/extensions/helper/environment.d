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
    Key env = HKCU.getKey("Environment");
    env.setValue(key, value);
}

void saveEnvVariables(string[2][] keyValues, string pathEnv)
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
        Key redub = HKCU.createKey("Software\\Redub");
        redub.setValue("ManagedEnvironment", newPathEntry);
        foreach(kv; 0..keys.length)
            saveEnvVariable(kv[0], kv[1]);
        saveEnvVariable("PATH", pathEnv~pathSeparator~newPathEntry);
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
        Key redub = HKCU.createKey("Software\\Redub");
        try
        {
            string appendedEnv = redub.getValue("ManagedEnvironment");
            string currPath = getEnvVariable("PATH");
            foreach(inputPath; splitter(appendedEnv, pathSeparator))
            {
                ptrdiff_t start = currPath.countUntil(inputPath);
                if(start != -1)
                {
                    currPath = currPath[0..start] ~ currPath[start+inputPath.length+1..$];
                }
            }
            saveEnvVariable("PATH", currPath);
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
    {
        import std.windows.registry;
        Key HKCU = Registry.currentUser;
        Key env = HKCU.getKey("Environment");
        env.deleteKey(key);
    }
}