module redub.misc.find_executable;

string findExecutable(string executableName)
{
    import redub.parsers.environment;
    import redub.misc.path;
    import std.path : isAbsolute, extension, buildPath;
    import std.file;
    import std.algorithm.iteration:splitter;

    if(executableName.length == 0)
        throw new Exception("Needs an executable name to find.");
    string pathEnv = getEnvVariable("PATH");

    version(Windows)
        static immutable string[] EXTENSIONS = [".exe", ".bat", ".cmd", ".com", ""];
    else
        static immutable string[] EXTENSIONS = [""];
    static immutable string[] emptyExt = [""];

    const(string)[] extensionsTest = EXTENSIONS;
    if(extension(executableName) != null)
        extensionsTest = emptyExt;

    static bool isExecutable(string tPath)
    {
        version(Posix)
        {
            import std.string:toStringz;
            import core.sys.posix.sys.stat;
            stat_t stats;
            if(stat(toStringz(tPath), &stats) != 0)
                return false;

            static immutable flags = S_IXUSR | S_IXGRP | S_IXOTH;
            return (stats.st_mode & flags) == flags;
        }
        else return std.file.exists(tPath);
    }

    if(isAbsolute(executableName) && isExecutable(executableName))
        return executableName;


    char[4096] buffer = void;
    char[] bufferSink = buffer;

    foreach(path; splitter(pathEnv, pathSeparator))
    {
        string str = redub.misc.path.normalizePath(bufferSink, path, executableName);
        foreach(ext; extensionsTest)
        {
            bufferSink[str.length..str.length+ext.length] = ext;
            string fullPath = cast(string)buffer[0..str.length+ext.length];
            if(std.file.exists(fullPath))
                return fullPath.dup;
        }

    }
    return null;
}