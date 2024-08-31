module redub.building.compile;
import redub.building.cache;
import redub.logging;
import redub.buildapi;
import std.system;
import std.concurrency;
import redub.compiler_identification;
import redub.command_generators.automatic;

struct CompilationResult
{
    string compilationCommand;
    string message;
    size_t msNeeded;
    int status;
    shared ProjectNode node;
    shared CompilationCache cache;
}

import std.typecons;
import core.sys.windows.stat;
import redub.api;
alias ExecutionResult = Tuple!(int, "status", string, "output");
/**
*   If any command has status, it will stop executing them and return
*/
private ExecutionResult executeCommands(const string[] commandsList, string listName, ref CompilationResult res, string workingDir, immutable string[string] env)
{
    import std.process;
    foreach(cmd; commandsList)
    {
        auto execRes  = executeShell(cmd, env, Config.none, size_t.max, workingDir);
        if(execRes.status)
        {
            res.status = execRes.status;
            res.message = "Result of "~listName~" command '"~cmd~"' "~execRes.output;
            return execRes;
        }
    }
    return ExecutionResult(0, "Success");
}

void execCompilationThread(immutable ThreadBuildData data, shared ProjectNode pack, OS os, Compiler compiler, shared CompilationCache cache, immutable string[string] env)
{
    CompilationResult res = execCompilation(data, pack, os, compiler, cache, env);
    scope(exit)
    {
        ownerTid.send(res);
    }
}

CompilationResult execCompilation(immutable ThreadBuildData data, shared ProjectNode pack, OS os, Compiler compiler, shared CompilationCache cache, immutable string[string] env)
{
    import std.file;
    import std.process;
    import std.datetime.stopwatch;
    import redub.command_generators.commons;

    CompilationResult res;
    res.node = pack;
    StopWatch sw = StopWatch(AutoStart.yes);
    scope(exit)
    {
        res.msNeeded = sw.peek.total!"msecs";
        res.cache.requirementCache = cache.requirementCache;
    }
    try
    {
        if(pack.isUpToDate && !pack.isCopyEnough)
        {
            res.cache = cache;
            return res;
        }

        immutable BuildConfiguration cfg = data.cfg;
        //Remove existing binary, since it won't be replaced by simply executing commands
        string outDir = getConfigurationOutputPath(cfg, os);
        if(exists(outDir))
            remove(outDir);

        if(executeCommands(cfg.preBuildCommands, "preBuildCommand", res, cfg.workingDir, env).status)
            return res;


        if(pack.requirements.cfg.targetType != TargetType.none)
        {
            import std.path;
            string inDir = getCacheOutputDir(cache.rootHash, cast()pack.requirements, compiler, os);
            if(!exists(inDir))
                mkdirRecurse(inDir);

            ///Creates a folder to C output since it doesn't do automatically.
            if(!isDCompiler(compiler))
                createOutputDirFolder(cfg);

            ExecutionResult ret;
            if(std.system.os.isWindows)
            {
                if(!pack.isCopyEnough)
                {
                    string[] flags = getCompilationFlags(cfg, os, compiler, cache.rootHash);
                    string commandFile = createCommandFile(cfg, os, compiler, flags, res.compilationCommand);
                    res.compilationCommand = compiler.binOrPath ~ " "~res.compilationCommand;
                    ret = executeShell(compiler.binOrPath ~ " @"~commandFile);
                    std.file.remove(commandFile);
                }
            }
            else
            {
                res.compilationCommand = getCompileCommands(cfg, os, compiler, cache.rootHash);
                ret = executeShell(res.compilationCommand, null, Config.none, size_t.max, cfg.workingDir);
            }

            if(!isDCompiler(compiler) && !ret.status) //Always requires link.
            {
                CompilationResult linkRes = link(cast()pack, cache.requirementCache, data, os, compiler, env);
                ret.status = linkRes.status;
                ret.output~= linkRes.message;
                res.compilationCommand~= linkRes.compilationCommand;
            }

            copyDir(inDir, dirName(outDir));


            ///Shared Library(mostly?)
            if(isDCompiler(compiler) && isLinkedSeparately(data.cfg.targetType) && !pack.isRoot)
            {
                CompilationResult linkRes = link(cast()pack, cache.requirementCache, data, os, compiler, env);
                ret.status = linkRes.status;
                ret.output~= linkRes.message;
                res.compilationCommand~= "\n\nLinking: \n\t"~ linkRes.compilationCommand;
            }


            res.status = ret.status;
            res.message = ret.output;

        }


        if(res.status == 0)
        {
            if(executeCommands(cfg.postBuildCommands, "postBuildCommand", res, cfg.workingDir, env).status)
                return res;
            if(!cfg.targetType.isLinkedSeparately && executeCommands(cfg.postGenerateCommands, "postGenerateCommand", res, cfg.workingDir, env).status)
                return res;
        }
    }
    catch(Throwable e)
    {
        res.status = 1;
        res.message = e.toString;
    }
    return res;
}

CompilationResult link(ProjectNode root, string rootHash, const ThreadBuildData data, OS os, Compiler compiler, immutable string[string] env)
{
    import std.process;
    CompilationResult ret;

    if(!root.isCopyEnough)
    {
        ret.compilationCommand = getLinkCommands(data, os, compiler, rootHash);
        auto exec = executeShell(ret.compilationCommand);
        ret.status = exec.status;
        ret.message = exec.output;
        if(exec.status != 0)
            return ret;
    }
    import redub.command_generators.commons;
    import std.path;

    string inDir = getCacheOutputDir(rootHash, cast()root.requirements, compiler, os);
    string outDir = getConfigurationOutputPath(data.cfg, os);
    copyDir(inDir, dirName(outDir));



    if(data.cfg.targetType.isLinkedSeparately)
        executeCommands(data.cfg.postGenerateCommands, "postGenerateCommand", ret, data.cfg.workingDir, env);

    return ret;
}


bool buildProjectParallelSimple(ProjectNode root, Compiler compiler, OS os)
{
    import std.concurrency;
    ProjectNode[] dependencyFreePackages = root.findLeavesNodes();
    string mainPackHash = hashFrom(root.requirements, compiler);
    bool[ProjectNode] spawned;

    AdvCacheFormula formulaCache;

    printCachedBuildInfo(root);
    while(true)
    {
        foreach(dep; dependencyFreePackages)
        {
            if(!(dep in spawned))
            {
                if(dep.shouldEnterCompilationThread)
                {
                    spawned[dep] = true;
                    spawn(&execCompilationThread,
                        dep.requirements.buildData, cast(shared)dep, os,
                        compiler, cast(shared)CompilationCache.get(mainPackHash, dep.requirements, compiler),
                        getEnvForProject(dep)
                    );
                }
                else
                    dep.becomeIndependent();
            }
        }
        CompilationResult res = receiveOnly!CompilationResult;
        ProjectNode finishedPackage = cast()res.node;
        if(res.status)
        {
            buildFailed(finishedPackage, res, compiler);
            return false;
        }
        else
        {
            if(!finishedPackage.isUpToDate)
                buildSucceeded(finishedPackage, res);
            finishedPackage.becomeIndependent();
            dependencyFreePackages = root.findLeavesNodes();

            if(!finishedPackage.requirements.cfg.targetType.isLinkedSeparately)
            {
                CompilationCache existingCache = CompilationCache.get(mainPackHash, finishedPackage.requirements, compiler);
                const AdvCacheFormula existingFormula = existingCache.getFormula();
                CompilationCache.make(existingCache.requirementCache, mainPackHash, finishedPackage.requirements, os, compiler, &existingFormula, &formulaCache);
                updateCache(mainPackHash, CompilationCache.make(existingCache.requirementCache, mainPackHash, finishedPackage.requirements, os, compiler, &existingFormula, &formulaCache));
            }
            if(finishedPackage is root)
                break;
        }
    }
    return doLink(root, os, compiler, mainPackHash, &formulaCache) && copyFiles(root);
}


bool buildProjectFullyParallelized(ProjectNode root, Compiler compiler, OS os)
{
    import std.concurrency;
    string mainPackHash = hashFrom(root.requirements, compiler);
    CompilationCache[] cache = cacheStatusForProject(root, compiler);

    size_t i = 0;
    size_t sentPackages = 0;
    foreach(ProjectNode pack; root.collapse)
    {
        if(pack.shouldEnterCompilationThread)
        {
            sentPackages++;
            spawn(&execCompilationThread,
                pack.requirements.buildData,
                cast(shared)pack, os, compiler,
                cast(shared)cache[i],
                getEnvForProject(pack)
            );

        }
        i++;
    }

    printCachedBuildInfo(root);

    AdvCacheFormula formulaCache;
    foreach(_; 0..sentPackages)
    {
        CompilationResult res = receiveOnly!CompilationResult;
        ProjectNode finishedPackage = cast()res.node;

        if(res.status)
        {
            import core.thread;
            buildFailed(finishedPackage, res, compiler);
            thread_joinAll();
            return false;
        }
        else
        {
            buildSucceeded(finishedPackage, res);

            if(!finishedPackage.requirements.cfg.targetType.isLinkedSeparately)
            {
                CompilationCache existingCache = CompilationCache.get(mainPackHash, finishedPackage.requirements, compiler);
                const AdvCacheFormula existingFormula = existingCache.getFormula();
                updateCache(mainPackHash, CompilationCache.make(existingCache.requirementCache, mainPackHash, finishedPackage.requirements, os, compiler, &existingFormula, &formulaCache));
            }
        }
    }
    return doLink(root, os, compiler, mainPackHash, &formulaCache) && copyFiles(root);
}

/**
 * When wanting to do a single thread build, this function must be called.
 * This function is also used when the project has no dependency.
 * Params:
 *   root = What is the project to build
 *   compiler = Which compiler
 *   os = Which OS
 * Returns: Has succeeded
 */
bool buildProjectSingleThread(ProjectNode root, Compiler compiler, OS os)
{
    ProjectNode[] dependencyFreePackages = root.findLeavesNodes();
    string mainPackHash = hashFrom(root.requirements, compiler);

    printCachedBuildInfo(root);
    while(true)
    {
        ProjectNode finishedPackage;
        foreach(dep; dependencyFreePackages)
        {
            if(dep.shouldEnterCompilationThread)
            {
                CompilationResult res = execCompilation(dep.requirements.buildData, cast(shared)dep, os, compiler,
                    cast(shared)CompilationCache.get(mainPackHash, dep.requirements, compiler), getEnvForProject(dep)
                );
                if(res.status)
                {
                    buildFailed(dep, res, compiler);
                    return false;
                }
                else
                    buildSucceeded(dep, res);
            }
            finishedPackage = dep;
            finishedPackage.becomeIndependent();
            dependencyFreePackages = root.findLeavesNodes();
        }
        if(finishedPackage is root)
            break;
    }
    return doLink(root, os, compiler, mainPackHash) && copyFiles(root);
}

private void printCachedBuildInfo(ProjectNode root)
{
    string upToDate;
    string copyEnough;
    foreach(ProjectNode node; root.collapse)
    {
        string cfg = node.requirements.targetConfiguration ? (" ["~node.requirements.targetConfiguration~"]") : null;
        cfg = node.name~ cfg~"; ";

        if(node.isCopyEnough)
            copyEnough~= cfg;
        else if(node.isUpToDate)
            upToDate~= cfg;
    }
    if(copyEnough.length)
        infos("Copy Enough: ", copyEnough);
    if(upToDate.length)
        infos("Up-to-Date: ", upToDate);
}


private void buildSucceeded(ProjectNode node, CompilationResult res)
{
    if(!node.isCopyEnough)
    {
        string cfg = node.requirements.targetConfiguration ? (" ["~node.requirements.targetConfiguration~"]") : null;
        string ver = node.requirements.version_.length ? (" "~node.requirements.version_) : null;

        infos("Built: ", node.name, ver, cfg, ". Took ", res.msNeeded, "ms");
        vlog("\n\t", res.compilationCommand, " \n");
    }

}
private void buildFailed(const ProjectNode node, CompilationResult res, const Compiler compiler)
{
    import redub.misc.github_tag_check;
    errorTitle("Build Failure: '", node.name, " ",node.requirements.version_," [", node.requirements.targetConfiguration,"]' \n\t",
        RedubVersionShort, "\n\t", compiler.getCompilerWithVersion, "\n\tFailed with flags: \n\n\t",
        res.compilationCommand,
        "\nFailed after ", res.msNeeded,"ms with message\n\t", res.message
    );
    showNewerVersionMessage();
}


private bool copyFiles(ProjectNode root)
{
    static import std.file;
    import redub.misc.hard_link;
    import std.path;
    string outputDir = root.requirements.cfg.outputDirectory;
    foreach(ProjectNode proj; root.collapse)
    {
        string[] files = proj.requirements.cfg.filesToCopy;
        if(files.length)
        {
            info("\tCopying files for project ", proj.name);
            foreach(f; files)
            {
                string inputPath;
                string outputPath;
                if(isAbsolute(f))
                {
                    inputPath = buildNormalizedPath(f);
                    outputPath = buildNormalizedPath(outputDir, f.baseName);
                }
                else
                {
                    inputPath = buildNormalizedPath(proj.requirements.cfg.workingDir, f);
                    outputPath = buildNormalizedPath(outputDir, f);
                }
                vlog("\t\tCopying ", inputPath, " to ", outputPath);
                if(!hardLinkFile(inputPath, outputPath, true))
                {
                    error("Could not copy file ", inputPath);
                    return false;
                }
            }
        }
    }
    return true;
}

immutable(string[string]) getEnvForProject(const ProjectNode node)
{
    import redub.parsers.environment;
    import std.process:environment;
    PackageDubVariables vars = getEnvironmentVariablesForPackage(node.requirements.cfg);
    string[string] env = environment.toAA;
    static foreach(mem; __traits(allMembers, PackageDubVariables))
        env[mem] = __traits(getMember, vars, mem);
    return cast(immutable)env;

}

private bool doLink(ProjectNode root, OS os, Compiler compiler, string mainPackHash, AdvCacheFormula* formulaCache = null)
{
    bool isUpToDate = root.isUpToDate;
    bool shouldSkipLinking = isUpToDate || (compiler.isDCompiler && !root.requirements.cfg.targetType.isLinkedSeparately);

    if(!shouldSkipLinking)
    {
        CompilationResult linkRes;
        auto result = timed(() {
             linkRes = link(root, mainPackHash, root.requirements.buildData, os, compiler, getEnvForProject(root));
             return true;
        });
        if(linkRes.status)
        {
            import redub.misc.github_tag_check;
            errorTitle("Linking Error at \"", root.name, "\". \n\t"~ RedubVersionShort~ "\n\t" ~ compiler.getCompilerWithVersion ~ "\n\tFailed with flags: \n\n\t",
                linkRes.compilationCommand,"\n\t\t  :\n\t",
                linkRes.message,
            );
            showNewerVersionMessage();
            return false;
        }
        else
        {
            infos("Linked: ", root.name, " finished in ", result.msecs, "ms!");
            vlog("\n\t", linkRes.compilationCommand, " \n");
        }
    }
    ///Try copying if it already exists, this operation is fast anyway for up to date builds.
    else if(root.isCopyEnough)
    {
        import redub.command_generators.commons;
        import std.path;
        string inDir = getCacheOutputDir(mainPackHash, cast()root.requirements, compiler, os);
        string outDir = getConfigurationOutputPath(root.requirements.cfg, os);
        copyDir(inDir, dirName(outDir));
    }

    if(isUpToDate)
        infos("Up-to-Date: ", root.name, ", skipping linking");
    else if(root.requirements.cfg.targetType != TargetType.none)
    {
        AdvCacheFormula cache;
        if(formulaCache != null)
            cache = *formulaCache;
        auto result = timed(()
        {
            foreach(ProjectNode node; root.collapse)
            {
                bool hasAlreadyWrittenInCache = formulaCache != null && !node.requirements.cfg.targetType.isLinkedSeparately;
                // bool hasAlreadyWrittenInCache = false;

                if(!node.isUpToDate && !hasAlreadyWrittenInCache)
                {
                    CompilationCache existingCache = CompilationCache.get(mainPackHash, node.requirements, compiler);
                    const AdvCacheFormula existingFormula = existingCache.getFormula();
                    updateCache(mainPackHash, CompilationCache.make(existingCache.requirementCache, mainPackHash, node.requirements, os, compiler, &existingFormula, &cache));
                }
            }
            updateCacheOnDisk(mainPackHash);
            return true;
        });
        info("Wrote cache in ", result.msecs, "ms");
    }

    return true;
}