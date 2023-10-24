"""
function git_status(session::AbstractBashSession, path; git = "git")
    CommandLine.cd(session, path)
    lines = CommandLine.checkoutput(session, "$(git) status --short")
    CommandLine.cd(session, "-")
    return lines
end

function changes(session::AbstractBashSession, path; git = "git")::Vector{String}
    # See https://git-scm.com/docs/git-status#_short_format
    function is_change(line::String)
        X = line[1]
        Y = line[2]
        return (X in ['M', 'A']) || (Y in ['M', 'R', 'C'])
    end

    lines = CommandLine.git_status(session, path; git = git)
    return [line[4:end] for line in lines if is_change(line)]
end

function changes_from(session::AbstractBashSession, path; git = "git", branch = "master")::Vector{String}
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


#Get all tracked files in branch `branch` of git repository `path` is session `session`
function tracked_files(session::AbstractBashSession, path; git = "git", branch = "master")::Vector{String}
    CommandLine.cd(session, path)
    lines = CommandLine.checkoutput(session, "$(git) ls-tree --full-tree --name-only -r $(branch)")
    CommandLine.cd(session, "-")
    return lines
end
"""

module Docker
import CommandLine as CLI

"""
One must define the environment variable `CL_GIT` in a `Shell`
to be able to call the function of this module.
"""
# Git SubCommands
SUB_COMMANDS = [
    # Main porcelain commands
    :add, # Add file contents to the index
    :am, # Apply a series of patches from a mailbox
    :archive, # Create an archive of files from a named tree
    :bisect, # Use binary search to find the commit that introduced a bug
    :branch, # List, create, or delete branches
    :bundle, # Move objects and refs by archive
    :checkout, # Switch branches or restore working tree files
    :cherry_pick, # Apply the changes introduced by some existing commits
    :citool, # Graphical alternative to :commit
    :clean, # Remove untracked files from the working tree
    :clone, # Clone a repository into a new directory
    :commit, # Record changes to the repository
    :describe, # Give an object a human readable name based on an available ref
    :diff, # Show changes between commits, commit and working tree, etc
    :fetch, # Download objects and refs from another repository
    :format_patch, # Prepare patches for e-mail submission
    :gc, # Cleanup unnecessary files and optimize the local repository
    :grep, # Print lines matching a pattern
    :gui, # A portable graphical interface to Git
    :init, # Create an empty Git repository or reinitialize an existing one
    :log, # Show commit logs
    :maintenance, # Run tasks to optimize Git repository data
    :merge, # Join two or more development histories together
    :mv, # Move or rename a file, a directory, or a symlink
    :notes, # Add or inspect object notes
    :pull, # Fetch from and integrate with another repository or a local branch
    :push, # Update remote refs along with associated objects
    :range_diff, # Compare two commit ranges (e.g. two versions of a branch)
    :rebase, # Reapply commits on top of another base tip
    :reset, # Reset current HEAD to the specified state
    :restore, # Restore working tree files
    :revert, # Revert some existing commits
    :rm, # Remove files from the working tree and from the index
    :shortlog, # Summarize git log output
    :show, # Show various types of objects
    :sparse_checkout, # Reduce your working tree to a subset of tracked files
    :stash, # Stash the changes in a dirty working directory away
    :status, # Show the working tree status
    :submodule, # Initialize, update or inspect submodules
    :switch, # Switch branches
    :tag, # Create, list, delete or verify a tag object signed with GPG
    :worktree, # Manage multiple working trees
    # Manipulators:
    :config, # Get and set repository or global options
    :fast_export, # Git data exporter
    :fast_import, # Backend for fast Git data importers
    :filter_branch, # Rewrite branches
    :mergetool, # Run merge conflict resolution tools to resolve merge conflicts
    :pack_refs, # Pack heads and tags for efficient repository access
    :prune, # Prune all unreachable objects from the object database
    :reflog, # Manage reflog information
    :remote, # Manage set of tracked repositories
    :repack, # Pack unpacked objects in a repository
    :replace, # Create, list, delete refs to replace objects
    # Interrogators:
    :annotate, # Annotate file lines with commit information
    :blame, # Show what revision and author last modified each line of a file
    :bugreport, # Collect information for user to file a bug report
    :count_objects, # Count unpacked number of objects and their disk consumption
    :diagnose, # Generate a zip archive of diagnostic information
    :difftool, # Show changes using common diff tools
    :fsck, # Verifies the connectivity and validity of the objects in the database
    :help, # Display help information about Git
    :instaweb, # Instantly browse your working repository in gitweb
    :merge_tree, # Perform merge without touching index or working tree
    :rerere, # Reuse recorded resolution of conflicted merges
    :show_branch, # Show branches and their commits
    :verify_commit, # Check the GPG signature of commits
    :verify_tag, # Check the GPG signature of tags
    :version # Display version information about Git
]


# Define SubCommands calls as fonction of the module
for fct in SUB_COMMANDS
    @eval function $(Symbol(fct, :_str))(s::CLI.Shell, args...; kwargs...)
        strfct = string($fct)
        return "$(s[:CL_GIT]) $strfct $(make_cmd(args...; kwargs...))"
    end

    @eval function $fct(s::CLI.Shell, args...; kwargs...)
        return CLI.run(s, $(Symbol(fct, :_str))(s, args...; kwargs...))
    end

    # Also export the function
    @eval export $(fct), $(Symbol(fct, :_str))
end
end