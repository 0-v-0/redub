module command_generators.linkers;
public import redub.compiler_identification;
public import redub.buildapi;
public import std.system;
import redub.command_generators.commons;


string[] parseLinkConfiguration(const ThreadBuildData data, CompilingSession s, string requirementCache)
{
    import redub.misc.path;
    import redub.building.cache;
    string[] commands;
    AcceptedLinker linker = s.compiler.linker;
    bool emitStartGroup = s.isa != ISA.webAssembly && linker != AcceptedLinker.ld64;


    const BuildConfiguration b = data.cfg;
    with(b)
    {
        {
            import redub.command_generators.d_compilers;

            if (targetType.isLinkedSeparately)
            {
                string cacheDir = getCacheOutputDir(requirementCache, b, s, data.extra.isRoot);
                string objExtension = getObjectExtension(s.os);
                if(s.compiler.isDCompiler)
                    commands~= "-of"~buildNormalizedPath(cacheDir, getOutputName(b, s.os)).escapePath;
                else
                {
                    commands~= "-o";
                    commands~= buildNormalizedPath(cacheDir, getOutputName(b, s.os)).escapePath;
                }
                if(b.outputsDeps)
                    putSourceFiles(commands, null, [getObjectDir(cacheDir)], null, null, objExtension);
                else
                    commands~= buildNormalizedPath(outputDirectory, targetName~objExtension).escapePath;
            }
            if(s.compiler.isDCompiler)
            {
                string arch = mapArch(s.compiler.compiler, b.arch);
                if(arch)
                    commands~= arch;
            }
            commands~= filterLinkFlags(b.dFlags);
        }
        if(targetType == TargetType.dynamicLibrary)
            commands~= getTargetTypeFlag(targetType, s.compiler);
        
        if (targetType.isLinkedSeparately)
        {
            //Only linux supports start/end group and no-as-needed. OSX does not
            if(emitStartGroup)
            {
                commands~= "-L--no-as-needed";
                commands~= "-L--start-group";
            }
            ///Use library full path for the base file
            commands = mapAppendReverse(commands, data.extra.librariesFullPath, (string l) => "-L"~getOutputName(TargetType.staticLibrary, l, s.os));
            if(emitStartGroup)
                commands~= "-L--end-group";
            commands = mapAppendPrefix(commands, linkFlags, "-L", false);
            commands = mapAppendPrefix(commands, libraryPaths, "-L-L", true);
            commands~= getLinkFiles(b.sourceFiles);
            commands = mapAppend(commands, libraries, (string l) => "-L-l"~stripLibraryExtension(l));
            
        }
    }

    return commands;
}

string[] parseLinkConfigurationMSVC(const ThreadBuildData data, CompilingSession s, string requirementCache)
{
    import std.algorithm.iteration;
    import redub.misc.path;
    import std.string;
    import redub.building.cache;


    if(!s.os.isWindows) return parseLinkConfiguration(data, s, requirementCache);
    string[] commands;
    const BuildConfiguration b = data.cfg;
    with(b)
    {
        string cacheDir = getCacheOutputDir(requirementCache, b, s, data.extra.isRoot);
        commands~= "-of"~buildNormalizedPath(cacheDir, getOutputName(b, s.os)).escapePath;
        string objExtension = getObjectExtension(s.os);
        if(b.outputsDeps)
            putSourceFiles(commands, null, [getObjectDir(cacheDir)], null, null, objExtension);
        else
            commands~= buildNormalizedPath(outputDirectory, targetName~objExtension).escapePath;

        if(s.compiler.isDCompiler)
        {
            import redub.command_generators.d_compilers;
            string arch = mapArch(s.compiler.compiler, b.arch);
            if(arch)
                commands~= arch;
            commands~= filterLinkFlags(b.dFlags);
        }
        if(!s.compiler.usesIncremental)
        {
            commands~= "-L/INCREMENTAL:NO";
        }
        
        if(targetType == TargetType.dynamicLibrary)
            commands~= getTargetTypeFlag(targetType, s.compiler);
        
        commands = mapAppendReverse(commands, data.extra.librariesFullPath, (string l) => (l~getLibraryExtension(s.os)).escapePath);

        commands = mapAppendPrefix(commands, linkFlags, "-L", false);

        commands = mapAppendPrefix(commands, libraryPaths, "-L/LIBPATH:", true);
        commands~= getLinkFiles(b.sourceFiles);
        commands = mapAppend(commands, libraries, (string l) => "-L"~stripLibraryExtension(l)~".lib");

    }
    return commands;
}


string getTargetTypeFlag(TargetType o, Compiler compiler)
{
    static import redub.command_generators.d_compilers;
    static import redub.command_generators.gnu_based;

    switch(compiler.compiler) with(AcceptedCompiler)
    {
        case dmd, ldc2: return redub.command_generators.d_compilers.getTargetTypeFlag(o, compiler.compiler);
        case gcc, gxx: return redub.command_generators.gnu_based.getTargetTypeFlag(o);
        default: throw new Exception("Unsupported compiler "~compiler.binOrPath);
    }
}


