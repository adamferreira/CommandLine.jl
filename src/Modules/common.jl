function make_cmd(args...; kwargs...)::String
    strargs = Base.join(vcat(args...), ' ')
    # Get last argument of the command
    # for example in  docker run [OPTIONS] IMAGE [COMMAND] [ARG...]
    # `argument` should be IMAGE
    last_arg = :argument in keys(kwargs) ? kwargs[:argument] : ""
    strkwargs = Base.join(
        vcat(
            map(p -> begin
                # Ignore :argument kwargs as it will be used as `last_arg`
                if (p.first == :argument) return "" end

                if isa(p.second, Bool)
                    if p.second return "--$(p.first)" end
                else
                    return "--$(p.first) $(p.second)"
                end
                return ""
            end,
            collect(kwargs)
            )
        ), ' '
    )

    return "$strargs $strkwargs $last_arg"
end