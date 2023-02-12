function git_status(session::BashSession, path; git = "git")
    CommandLine.cd(session, path)
    lines = CommandLine.checkoutput(session, "$(git) status --short")
    CommandLine.cd(session, "-")
    return lines
end

function changes(session::BashSession, path; git = "git")::Vector{String}
    # See https://git-scm.com/docs/git-status#_short_format
    function is_change(line::String)
        X = line[1]
        Y = line[2]
        return (X in ['M', 'A']) || (Y in ['M', 'R', 'C'])
    end

    lines = CommandLine.git_status(session, path; git = git)
    return [line[4:end] for line in lines if is_change(line)]
end

function changes_from(session::BashSession, path; git = "git", branch = "master")::Vector{String}
    # See file:///C:/Program%20Files/Git/mingw64/share/doc/git-doc/git-diff.html
    # --diff-filter=[(A|C|D|M|R|T|U|X|B)…​[*]]
    function is_change(line::String)
        X = line[1]
        # Do not count deleted files as changes for now ('D')
        # TODO: do it
        return (X in ['M', 'A'])
    end
    CommandLine.cd(session, path)
    lines = CommandLine.checkoutput(session, "$(git) diff --name-status $(branch)")
    CommandLine.cd(session, "-")
    return [replace(line[2:end], '\t' => "") for line in lines if is_change(line)]
end