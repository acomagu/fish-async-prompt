# Don't run if the shell is not interactive
status is-interactive
or exit 0


# Logs a message to the debug log file if `rpoc_debug_log_enable` is set to
# `1`.
function __async_prompt_log --argument-names func_name message
    if test "$async_prompt_debug_log_enable" = 1
        # Initialize debug log file in XDG cache dir or ~/.cache if not already done
        if not set -q async_prompt_debug_log_path
            set -l cache_dir
            if set -q XDG_CACHE_HOME
                set cache_dir "$XDG_CACHE_HOME/fish"
            else
                set cache_dir "$HOME/.cache/fish"
            end
            mkdir -p "$cache_dir"
            set -g async_prompt_debug_log_path "$cache_dir/async_prompt_debug.log"
        end

        echo (date "+%Y-%m-%d %H:%M:%S") "[$func_name]" "$message" >> $async_prompt_debug_log_path
    end
end


# Creates a temporary directory for storing the async prompt output.
set -g __async_prompt_tmpdir (command mktemp -d)


# Called when the prompt is about to be displayed for the first time.
#
# Replaces the prompt functions (fish_prompt, fish_right_prompt) with
# with functions that don't render the prompt and instead cat the output
# of the async prompt functions.
#
# Effectively, runs only once because the function is removed immediately
# after it runs.
function __async_prompt_setup_on_startup --on-event fish_prompt
    __async_prompt_log "__async_prompt_setup_on_startup" "Starting setup"

    # Remove this function after it runs once, since it only needs to run on startup
    functions -e (status current-function)

    if test "$async_prompt_enable" = 0
        __async_prompt_log "__async_prompt_setup_on_startup" "Async prompt disabled"
        return 0
    end

    for func in (__async_prompt_config_functions)
        __async_prompt_log "__async_prompt_setup_on_startup" "Setting up function: $func"

        # Backup the original fish prompt functions if they exist so that they
        # can be used by other fish plugins, such as `refresh-prompt-on-cmd`.
        functions -c $func '__async_prompt_orig_'$func

        # Replace the fish_prompt functions with replacements that cat the
        # sync and async prompts from the tmpdir
        function $func -V func
            test -e $__async_prompt_tmpdir'/'$fish_pid'_'$func
            # Using `string collect` as a faster cat.
            and string collect <$__async_prompt_tmpdir'/'$fish_pid'_'$func
        end
    end
end

set -g __async_prompt_last_pipestatus 0
function __async_prompt_keep_last_pipestatus --on-event fish_postexec
    __async_prompt_log "__async_prompt_setup_on_startup" "Setup complete"

    set -g __async_prompt_last_pipestatus $pipestatus
end


# Make sure __async_prompt_fire is called when the bind mode variable changes.
not set -q async_prompt_on_variable
and set async_prompt_on_variable fish_bind_mode PWD


# Called when the prompt is about to be displayed (`--on-event fish_prompt`) or
# when one of the variables in `$async_prompt_on_variable` changes.
#
# Executes the loading indicator functions synchronously and stores the result
# in the temporary files. Then the async prompt functions are executed
# asynchronously in the background.
#
# Once all `--on-event fish_prompt` events have been processed, the prompt is
# painted using the functions created in `__async_prompt_setup_on_startup`.
#
# They display the contents of temporary files as the left and right prompt. At
# that point the temporary files contain the result of the synchronous loading
# indicator functions.
#
# Once the async background process is done, it sends a signal to the parent
# shell, which causes the prompt to be repainted again. This time the temporary
# file contains the async prompt and the loading indicator is replaced with the
# result of the async prompt.
function __async_prompt_fire --on-event fish_prompt (for var in $async_prompt_on_variable; printf '%s\n' --on-variable $var; end)
    __async_prompt_log "__async_prompt_fire" "Starting..."

    set -l __async_prompt_last_pipestatus $pipestatus

    # Generate the sync and async prompts for each function (fish_prompt,
    # fish_right_prompt, etc.)
    for func in (__async_prompt_config_functions)
        __async_prompt_log "__async_prompt_fire" "Generating async prompt for function: $func"
        set -l tmpfile $__async_prompt_tmpdir'/'$fish_pid'_'$func

        # Check if a loading_indicator function is defined for the prompt
        # function (fish_prompt, fish_right_prompt, etc.)
        #
        # If it is, pass it the last prompt so that it can display the
        # previous prompt, a temporary prompt or a loading indicator while
        # the full async prompt is being generated.
        #
        # Store the result in the tmpfile.
        if functions -q $func'_loading_indicator' && test -e $tmpfile
            __async_prompt_log "__async_prompt_fire" "Generating loading indicator for function: $func"
            read -zl last_prompt <$tmpfile
            eval (string escape -- $func'_loading_indicator' "$last_prompt") >$tmpfile
        end

        # Call the __async_prompt_spawn function and pass it the command it
        # should execute as well as a list of variables that should be passed
        # to the background process.
        #
        # The result is stored in the $prompt variable and then written to the
        # temporary file (replacing the loading indicator)..
        __async_prompt_config_inherit_variables | __async_prompt_last_pipestatus=$__async_prompt_last_pipestatus __async_prompt_spawn \
            'if functions -q '$func'; '$func'; else; echo -n ""; end | read -z prompt; echo -n $prompt >'$tmpfile
    end
    __async_prompt_log "__async_prompt_fire" "Prompt fire complete"
end


# Spawns a command in the background.
#
# Takes an argument for the command to execute in the background process.
# And also accepts a pipe with a list of env variable names that should be
# forwarded to the background process.
#
# Can be called like...
# `__async_prompt_config_inherit_variables | __async_prompt_spawn 'echo $fish_bind_mode'`
function __async_prompt_spawn -a cmd
    __async_prompt_log "__async_prompt_spawn" "Spawning command: $cmd"

    # Determines values for piped variable names and stores them as a list
    # of strings like `fish_bind_mode default`
    set -l envs
    begin
        while read line
            switch "$line"
                case fish_bind_mode
                    echo fish_bind_mode $fish_bind_mode
                case FISH_VERSION PWD _ history 'fish_*' hostname version status_generation
                case status pipestatus
                    echo pipestatus $__async_prompt_last_pipestatus
                case SHLVL
                    set envs $envs SHLVL=$SHLVL
                case '*'
                    echo $line (string escape -- $$line)
            end
        end
    end | read -lz vars

    __async_prompt_log "__async_prompt_spawn" "Got vars: $vars"

    # This actually spawns the background process.
    #
    #   - Reads the variables from the pipe and sets them as env variables
    #   - Recreates the exact pipe status of each command in the original
    #     pipes (such as command 1 | command2 | command3)
    #   - Runs the command in the background process
    #   - Sends a `SIGUSR1` signal to the parent process when the command is
    #     done
    echo $vars | env $envs fish -c 'begin
    function __async_prompt_signal
        kill -s "'(__async_prompt_config_internal_signal)'" '$fish_pid' 2>/dev/null
    end
    while read -a line
        test -z "$line"
        and continue

        if test "$line[1]" = pipestatus
            set -f _pipestatus $line[2..]
        else
            eval set "$line"
        end
    end

    function __async_prompt_set_status
        return $argv
    end
    if set -q _pipestatus
        switch (count $_pipestatus)
            case 1
                __async_prompt_set_status $_pipestatus[1]
            case 2
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2]
            case 3
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3]
            case 4
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4]
            case 5
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5]
            case 6
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5] \
                | __async_prompt_set_status $_pipestatus[6]
            case 7
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5] \
                | __async_prompt_set_status $_pipestatus[6] \
                | __async_prompt_set_status $_pipestatus[7]
            case 8
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5] \
                | __async_prompt_set_status $_pipestatus[6] \
                | __async_prompt_set_status $_pipestatus[7] \
                | __async_prompt_set_status $_pipestatus[8]
            default
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5] \
                | __async_prompt_set_status $_pipestatus[6] \
                | __async_prompt_set_status $_pipestatus[7] \
                | __async_prompt_set_status $_pipestatus[8] \
                | __async_prompt_set_status $_pipestatus[-1]
        end
    else
        true
    end
    '$cmd'
    __async_prompt_signal
end 2>&3' 3>&2 2>/dev/null &

    # Disowning removes the background process from the shell's list of jobs.
    if test (__async_prompt_config_disown) = 1
        disown
    end

    __async_prompt_log "__async_prompt_spawn" "Command spawned and disowned: $__async_prompt_config_disown"
end


# Returns a list of variable names that should be forwarded to the background
# process.
#
# You can set `async_prompt_inherit_variables` to `all` to inherit all global
# variables or set it to a list of variable names to inherit only those.
function __async_prompt_config_inherit_variables
    __async_prompt_log "__async_prompt_config_inherit_variables" "Getting inherited variables"

    if set -q async_prompt_inherit_variables
        if test "$async_prompt_inherit_variables" = all
            # Print all global variables, but only the names.
            set -ng
        else
            for item in $async_prompt_inherit_variables
                echo $item
            end
        end
    else
        echo CMD_DURATION
        echo fish_bind_mode
        echo pipestatus
        echo SHLVL
        echo status
    end
    echo __async_prompt_last_pipestatus
end


# Returns a list of prompt functions that should be executed asynchronously.
#
# You can set `async_prompt_functions` to a list of function names or it will
# default to `fish_prompt` and `fish_right_prompt`.
function __async_prompt_config_functions
    __async_prompt_log "__async_prompt_config_functions" "Getting configured prompt functions"

    set -l funcs (
        if set -q async_prompt_functions
            string join \n $async_prompt_functions
        else
            echo fish_prompt
            echo fish_right_prompt
        end
    )

    # Only output functions that actually exist
    for func in $funcs
        functions -q "$func"
        or continue

        echo $func
    end
end


# Returns the signal number that should be used to notify the parent process
# that the background process is done.
#
# You can set `async_prompt_signal_number` to a custom signal number or it will
# default to `SIGUSR1`.
function __async_prompt_config_internal_signal
    if test -z "$async_prompt_signal_number"
        echo SIGUSR1
    else
        echo "$async_prompt_signal_number"
    end
end


# Returns whether the background process should be disowned.
#
# You can set `async_prompt_disown` to `1` to disown the background process or
# set it to `0` to disable disowning.
function __async_prompt_config_disown
    if test -z "$async_prompt_disown"
        echo 1
    else
        echo "$async_prompt_disown"
    end
end


# Called when the background process sends the signal indicating that it's
# done (by default SIGUSR1).
#
# This function asks fish to repaint the prompt, which causes the new functions
# that cat the tmp file in `__async_prompt_setup_on_startup` to be executed.
function __async_prompt_repaint_prompt --on-signal (__async_prompt_config_internal_signal)
    __async_prompt_log "__async_prompt_repaint_prompt" "Repainting prompt"

    commandline -f repaint >/dev/null 2>/dev/null
end


# Cleans up the temporary directory when the shell exits.
function __async_prompt_tmpdir_cleanup --on-event fish_exit
    __async_prompt_log "__async_prompt_tmpdir_cleanup" "Cleaning up temporary directory: $__async_prompt_tmpdir"

    command rm -rf "$__async_prompt_tmpdir"
end
