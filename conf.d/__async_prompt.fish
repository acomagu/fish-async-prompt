if status is-interactive
    function __async_prompt_setup_on_startup --on-event fish_prompt
        functions -e (status current-function)

        __async_prompt_setup
    end

    function __async_prompt_setup
        set -l fish_pids (pgrep -f fish)
        set -U -n | sed -En 's/(__async_prompt_.*_([0-9]+))/\1 \2/p' | while read -l varname pid
            if not contains "$pid" fish_pids
                set -e $varname
            end
        end

        set -q async_prompt_functions
        and set -g __async_prompt_functions_internal $async_prompt_functions

        for func in (__async_prompt_config_functions)
            functions -q '__async_prompt_'$func'_orig'
            or functions -c $func '__async_prompt_'$func'_orig'

            function $func -V func
                eval 'echo -n $__async_prompt_'$func'_text'
            end
        end

        function __async_prompt_post_prompt --on-event fish_prompt
            sh -c "for i in \$(seq 3); do kill -WINCH $fish_pid; sleep 0.5; done" &
            disown
        end
        __async_prompt_post_prompt
    end

    function __async_prompt_reset --on-variable async_prompt_functions
        # Revert functions
        for func in (__async_prompt_config_functions)
            if functions -q '__async_prompt_'$func'_orig'
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
            __async_prompt_var_move '__async_prompt_'$func'_text' '__async_prompt_'$func'_text_'(__async_prompt_pid)
        end
    end

    function __async_prompt_var_move
        set -l dst $argv[1]
        set -l orig $argv[2]

        if set -q $orig
            set -g $dst "$$orig"
            set -e $orig
        end
    end

    function __async_prompt_fire --on-event fish_prompt
        set st $status

        for func in (__async_prompt_config_functions)
            __async_prompt_config_inherit_variables | __async_prompt_spawn $st $func' | read -z prompt; set -U __async_prompt_'$func'_text_'(__async_prompt_pid)' "$prompt"'
            function '__async_prompt_'$func'_handler' --on-job-exit (jobs -lp | tail -n1)
                kill -WINCH (__async_prompt_pid)
                sleep 0.1
                kill -WINCH (__async_prompt_pid)
            end
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
        echo $vars | env $envs fish -c 'function __async_prompt_set_status
            return $argv
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
        '$argv[2] &
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

    function __async_prompt_pid
        if test -n "$pid"
            echo $pid
        else
            if test -n "$fish_pid"
                # New fish pid format
                echo $fish_pid
            else
                # Old fish pid format
                echo %self
            end
        end
    end
end
