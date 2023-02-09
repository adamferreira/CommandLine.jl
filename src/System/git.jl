function git_status(session::BashSession, path; git = "git")
    CommandLine.cd(session, path)
    lines = CommandLine.checkoutput(session, "$(git) status --short")
    CommandLine.cd(session, "-")
    return lines
end