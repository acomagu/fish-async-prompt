function __async_prompt_setup_on_startup --on-event fish_prompt
    functions -e (status current-function)

    __async_prompt_setup
end

function __async_prompt_setup
    set -q async_prompt_functions
    and set -g __async_prompt_functions_internal $async_prompt_functions

    for func in (__async_prompt_config_functions)
        functions -q '__async_prompt_'$func'_orig'
        or functions -c $func '__async_prompt_'$func'_orig'

        function $func -V func
            eval 'echo $__async_prompt_'$func'_text'
        end
    end
end

function __async_prompt_reset --on-variable async_prompt_functions
    # Revert functions
    for func in (__async_prompt_config_functions)
        functions -q '__async_prompt_'$func'_orig'
        and begin
            functions -e $func

            # If the function is defined redaundantly, cannot override it by
            # `functions -c` so done it by create wrapper function.
            function $func -V func
                eval '__async_prompt_'$func'_orig' $argv
            end
        end
    end

    __async_prompt_setup
end

function __async_prompt_sync_val --on-signal WINCH
    for func in (__async_prompt_config_functions)
        __async_prompt_var_move '__async_prompt_'$func'_text' '__async_prompt_'$func'_text_'(echo %self)
    end
end

function __async_prompt_var_move
    set dst $argv[1]
    set orig $argv[2]

    set -q $orig; and begin
        set -g $dst $$orig
        set -e $orig
    end
end

function __async_prompt_fire --on-event fish_prompt
    set st $status

    for func in (__async_prompt_config_functions)
        __async_prompt_config_inherit_variables |__async_prompt_spawn $st 'set -U __async_prompt_'$func'_text_'(echo %self)' ('$func')'
        function '__async_prompt_'$func'_handler' --on-process-exit (jobs -lp |tail -n1)
            kill -WINCH %self
        end
    end
end

function __async_prompt_spawn
    begin
        set st $argv[1]
        while read line
            contains $line FISH_VERSION PWD SHLVL _ history
            and continue

            test "$line" = status
            and echo status $st
            or echo $line (string escape -- $$line)
        end
    end |fish -c 'function __async_prompt_ses
        return $argv
    end
    while read -a line
        test -z "$line"
        and continue

        test "$line[1]" = status
        and set st $line[2]
        or eval set "$line"
    end

    not set -q st
    and true
    or __async_prompt_ses $st
    '$argv[2] &
end

function __async_prompt_config_inherit_variables
    set -q async_prompt_inherit_variables
    and begin
        test "$async_prompt_inherit_variables" = all
        and set -ng
        or for item in $async_prompt_inherit_variables
            echo $item
        end
    end
    or echo status
end

function __async_prompt_config_functions
    set -q __async_prompt_functions_internal
    and for func in $__async_prompt_functions_internal
        functions -q "$func"
        or continue

        echo $func
    end
    or begin
        echo fish_prompt
        echo fish_right_prompt
    end
end
