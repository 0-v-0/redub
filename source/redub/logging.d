module redub.logging;
import redub.libs.colorize;

enum LogLevel
{
    none,
    error,
    warn,
    info,
    verbose,
    vverbose
}
private LogLevel level;

LogLevel getLogLevel(){ return level; }

void inLogLevel(T)(LogLevel lvl, scope lazy T action)
{
    if(hasLogLevel(lvl))
        action;
}

bool hasLogLevel(LogLevel lvl)
{
    return level >= lvl;
}
void setLogLevel(LogLevel lvl){ level = lvl; }
void info(T...)(T args){if(level >= LogLevel.info) cwriteln(args);}
///Short for info success
void infos(T...)(string greenMsg, T args){if(level >= LogLevel.info) cwriteln(greenMsg.color(fg.green) ,args);}
void vlog(T...)(T args){if(level >= LogLevel.verbose) cwriteln(args);}
void vvlog(T...)(T args){if(level >= LogLevel.vverbose) cwriteln(args);}
void flush()
{
    if(level != LogLevel.none)
    {
        import std.stdio;
        stdout.flush;
    }
}
void warn(T...)(T args){if(level >= LogLevel.warn)cwriteln("Warning: ".color(fg.yellow), args);}
void warnTitle(T...)(string yellowMsg, T args){if(level >= LogLevel.warn)cwriteln(yellowMsg.color(fg.yellow), args);}
void error(T...)(T args){if(level >= LogLevel.error)cwriteln("ERROR! ".color(fg.red), args);}
void errorTitle(T...)(string redMsg, T args){if(level >= LogLevel.error)cwriteln(redMsg.color(fg.red), args);}