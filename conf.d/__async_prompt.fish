status is-interactive
or exit 0

set -g __async_prompt_tmpdir /tmp/fish-async-prompt
mkdir -p $__async_prompt_tmpdir

function __async_prompt_setup_on_startup --on-event fish_prompt
    functions -e (status current-function)

    __async_prompt_setup
end

function __async_prompt_setup
    set -q async_prompt_functions
    and set -g __async_prompt_functions_internal $async_prompt_functions

    for func in (__async_prompt_config_functions)
        function $func -V func
            test -e $__async_prompt_tmpdir'/'$fish_pid'_'$func
            and cat $__async_prompt_tmpdir'/'$fish_pid'_'$func
        end
    end
end

function __async_prompt_fire --on-event fish_prompt
    set st $status

    for func in (__async_prompt_config_functions)
        __async_prompt_config_inherit_variables | __async_prompt_spawn $st \
            $func' | read -z prompt
            echo -n $prompt >'$__async_prompt_tmpdir'/'$fish_pid'_'$func
    end
end

function __async_prompt_spawn
    set -l envs
    begin
        set st $argv[1]
        while read line
            switch "$line"
                case FISH_VERSION PWD _ history 'fish_*' hostname version
                case status
                    echo status $st
                case SHLVL
                    set envs $envs SHLVL=(math $SHLVL - 1)
                case '*'
                    echo $line (string escape -- $$line)
            end
        end
    end | read -lz vars
    echo $vars | env $envs fish -c '
    function __async_prompt_set_status
        return $argv
    end
    function __async_prompt_signal
        kill -s "'(__async_prompt_config_internal_signal)'" '$fish_pid'
    end
    while read -a line
        test -z "$line"
        and continue

        if test "$line[1]" = status
            set st $line[2]
        else
            eval set "$line"
        end
    end

    not set -q st
    and true
    or __async_prompt_set_status $st
    '$argv[2]'
    __async_prompt_signal
    sleep 0.3
    __async_prompt_signal
    sleep 0.3
    __async_prompt_signal' &
    disown
end

function __async_prompt_config_inherit_variables
    if set -q async_prompt_inherit_variables
        if test "$async_prompt_inherit_variables" = all
            set -ng
        else
            for item in $async_prompt_inherit_variables
                echo $item
            end
        end
    else
        echo status
        echo SHLVL
        echo CMD_DURATION
    end
end

function __async_prompt_config_functions
    set -l funcs (
        if set -q __async_prompt_functions_internal
            string join \n $__async_prompt_functions_internal
        else
            echo fish_prompt
            echo fish_right_prompt
        end
    )
    for func in $funcs
        functions -q "$func"
        or continue

        echo $func
    end
end

function __async_prompt_config_internal_signal
    if test -z "$async_prompt_signal_number"
        echo SIGUSR1
    else
        echo "$async_prompt_signal_number"
    end
end

function __async_prompt_repaint_prompt --on-signal (__async_prompt_config_internal_signal)
    commandline -f repaint >/dev/null 2>/dev/null
end
