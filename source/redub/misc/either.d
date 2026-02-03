module redub.misc.either;

T either(T, Ts...)(T first, lazy Ts alternatives) if(alternatives.length >= 1)
{
    static if(is(T : char[]) || is(T : string))
    {
        if(first.length != 0) return first;
        foreach(string alt; alternatives)
            if(alt.length != 0)
                return alt;
        return alternatives[$-1];
    }
    else
    {
        if(first) return first;
        foreach(alt; alternatives)
            if(alt)
                return alt;
        return alternatives[$-1];
    }
}