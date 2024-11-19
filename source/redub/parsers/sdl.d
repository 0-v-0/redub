module redub.parsers.sdl;
public import redub.buildapi;
public import std.system;
import redub.tree_generators.dub;

/**
 * Converts SDL into a JSON file and parse it as a JSON
 * Uses filePath as fileData for parseWithData
 * Params:
 *   filePath = The path in which the SDL file is located
 *   workingDir = Working dir of the recipe
 *   cInfo = Compilation Info filters
 *   defaultPackageName = Default name, used for --single
 *   version_ = Version being used
 *   subConfiguration = The configuration to use
 *   subPackage = The sub package to use
 *   parentName = Used as metadata
 *   isDescribeOnly = Used for not running the preGenerate commands
 *   isRoot = metadata
 * Returns: The new build requirements
 */
BuildRequirements parse(
    string filePath, 
    string workingDir,  
    CompilationInfo cInfo,
    string defaultPackageName,
    string version_, 
    BuildRequirements.Configuration subConfiguration, 
    string subPackage,
    string parentName,
    bool isDescribeOnly = false,
    bool isRoot = false
)
{
    import std.file;
    return parseWithData(filePath,
        readText(filePath),
        workingDir,
        cInfo,
        defaultPackageName,
        version_,
        subConfiguration,
        subPackage,
        parentName,
        isDescribeOnly,
        isRoot,
    );
}

/**
 * Converts SDL into a JSON file and parse it as a JSON
 * Params:
 *   filePath = The path in which the SDL file is located
 *   fileData = Uses that data instead of file path for parsing
 *   workingDir = Working dir of the recipe
 *   cInfo = Compilation Info filters
 *   defaultPackageName = Default name, used for --single
 *   version_ = Version being used
 *   subConfiguration = The configuration to use
 *   subPackage = The sub package to use
 *   parentName = Metadata
 *   isDescribeOnly = Used for not running preGenerate commands
 *   isRoot = metadata
 * Returns: The new build requirements
 */
BuildRequirements parseWithData(
    string filePath,
    string fileData,
    string workingDir,
    CompilationInfo cInfo,
    string defaultPackageName,
    string version_,
    BuildRequirements.Configuration subConfiguration,
    string subPackage,
    string parentName,
    bool isDescribeOnly = false,
    bool isRoot = false
)
{
    static import redub.parsers.json;
    import redub.parsers.base;
    import dub_sdl_to_json;

    ParseConfig c = ParseConfig(workingDir, subConfiguration, subPackage, version_, cInfo, defaultPackageName, null, parentName, preGenerateRun: !isDescribeOnly);
    fileData = fixSDLParsingBugs(fileData);
    JSONValue json = sdlToJSON(parseSDL(filePath, fixSDLParsingBugs(fileData)));
    BuildRequirements ret = redub.parsers.json.parse(json, c, isRoot);
    return ret;
}


/**
*   Strips single and multi line comments (C style)
*/
string stripComments(string str)
{
    string ret;
    size_t i = 0;
    size_t length = str.length;
    ret.reserve(str.length);

    while(i < length)
    {
        //Don't parse comments inside strings
        if(str[i] == '"')
        {
            size_t left = i;
            i++;
            while(i < length && str[i] != '"')
            {
                if(str[i] == '\\')
                    i++;
                i++;
            }
            i++; //Skip '"'
            ret~= str[left..i];
        }
        //Parse single liner comments
        else if(str[i] == '/' && i+1 < length && str[i+1] == '/')
        {
            i+=2;
            while(i < length && str[i] != '\n')
                i++;
        }
        //Single line #
        else if(str[i] == '#')
        {
            i++;
            while(i < length && str[i] != '\n')
                i++;
        }
        //Parse multi line comments
        else if(str[i] == '/' && i+1 < length && str[i+1] == '*')
        {
            i+= 2;
            while(i < length)
            {
                if(str[i] == '*' && i+1 < length && str[i+1] == '/')
                    break;
                i++;
            }
            i+= 2;
        }
        //Safe check to see if it is in range
        if(i < length)
            ret~= str[i];
        i++;
    }
    return ret;
}


/**
 * Fixes SDL for being converted to JSON
 * Params:
 *   sdlData = Some SDL data may input extra \n. Those are currently in the process of being ignored by the JSON parsing as it may break.
 * Returns: SDL parse fixed.
 */
string fixSDLParsingBugs(string sdlData)
{
    import std.file;
    import std.string:replace;

    version(Windows)
        enum lb = "\r\n";
    else
        enum lb = "\n";
    return stripComments(sdlData).replace("\\"~lb, " ").replace("`"~lb, "`");
}