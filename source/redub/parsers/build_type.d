module redub.parsers.build_type;
public import redub.buildapi;
public import redub.compiler_identification;
import redub.command_generators.d_compilers;

BuildConfiguration parse(BuildType buildType, AcceptedCompiler comp)
{
    auto m = getFlagMapper(comp);
    BuildConfiguration b;
    switch(buildType) with(ValidDFlags)
    {
        case BuildType.debug_:            b.dFlags = [m(debugMode), m(debugInfo)]; break;
        case BuildType.plain: break;
        case BuildType.release:           b.dFlags = [m(releaseMode), m(optimize), m(inline)]; break;
        case BuildType.release_debug:     b.dFlags = [m(releaseMode), m(optimize), m(inline), m(debugInfo)]; break;
        case BuildType.release_nobounds:  b.dFlags = [m(releaseMode), m(optimize), m(inline), m(noBoundsCheck)]; break;
        case BuildType.unittest_:         b.dFlags = [m(unittests), m(debugMode), m(debugInfo)]; break;
        case BuildType.profile:           b.dFlags = [m(profile), m(debugInfo)]; break;
        case BuildType.profile_gc:        b.dFlags = [m(profileGC), m(debugInfo)]; break;
        case BuildType.docs: break;
        case BuildType.ddox: break;
        case BuildType.cov:               b.dFlags = [m(coverage), m(debugInfo)]; break;
        case BuildType.cov_ctfe:          b.dFlags = [m(coverageCTFE), m(debugInfo)]; break;
        case BuildType.unittest_cov:      b.dFlags = [m(unittests), m(coverage), m(debugMode), m(debugInfo)]; break;
        case BuildType.unittest_cov_ctfe: b.dFlags = [m(unittests), m(coverageCTFE), m(debugMode), m(debugInfo)]; break;
        case BuildType.syntax:            b.dFlags = [m(syntaxOnly)]; break;
        default: throw new Exception("Unknown build type "~buildType);
    }
    return b;
}