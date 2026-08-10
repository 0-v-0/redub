module redub.extensions.setup;

version(RedubCLI):
import redub.extensions.cli;
import redub.extensions.helper.environment;

int setupMain(string[] args)
{
    import redub.misc.find_executable;
    import redub.meta;
    import redub.misc.path;
    import redub.parsers.environment;
    import core.runtime;
    import std.file;
    import hip.data.json;
    import redub.cli.dub;

    struct SetupArgs
    {
        @("Uninstalls a setup made by redub. Removes variables such as REDUB_PATH, REDUB_LDC_PATH, REDUB_LDC, REDUB_DMD_PATH and REDUB_DMD")
        bool uninstall;
    }
    import std.getopt;

    SetupArgs setup;
    GetoptResult res = betterGetopt(args, setup);
    if(res.helpWanted)
    {
        defaultGetoptPrinter(RedubVersionShort~" setup information: \n", res.options);
        return 0;
    }
    if(setup.uninstall)
    {
        deleteRedubEnvVariables();
        return 0;
    }



    
    JSONValue meta = getRedubMeta();
    JSONValue* global = "globalPaths" in meta;
    string[2][] vars;
    vars~= ["REDUB_PATH", buildNormalizedPath(thisExePath, "..")];
    if(global)
    {
        JSONValue* ldc = "ldc2" in *global;
        JSONValue* dmd = "dmd" in *global;
        if(ldc)
        {
            vars~= ["REDUB_LDC_PATH", buildNormalizedPath(ldc.str, "..")];
            vars~= ["REDUB_LDC", buildNormalizedPath(ldc.str)];
        }
        if(dmd) 
        {
            vars~= ["REDUB_DMD_PATH", buildNormalizedPath(dmd.str, "..")];
            vars~= ["REDUB_DMD", buildNormalizedPath(dmd.str)];
        }
    }
    if(vars.length)
    {
        string pathEnv = getEnvVariable("PATH");
        import std.stdio;
        writeln("Saved Environment Variables: ", vars);
        saveEnvVariables(vars, pathEnv);
    }
    return 0;
}