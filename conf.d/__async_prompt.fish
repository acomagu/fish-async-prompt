function __async_prompt_setup --on-event fish_prompt
    functions -e (status current-function)

    functions -q fish_prompt
    and function fish_prompt
        echo $__async_prompt_text
    end

    functions -q fish_right_prompt
    and function fish_right_prompt
        echo $__async_prompt_right_text
    end
end

function __async_prompt_sync_val --on-signal WINCH
    __async_prompt_var_move __async_prompt_text __async_prompt_text_(echo %self)
    __async_prompt_var_move __async_prompt_right_text __async_prompt_right_text_(echo %self)
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
    functions -q fish_prompt
    and begin
        __async_prompt_config_inherit_variables |__async_prompt_spawn $st 'set -U __async_prompt_text_'(echo %self)' (fish_prompt)'
        function __async_prompt_handler --on-process-exit (jobs -lp |tail -n1)
            kill -WINCH %self
        end
    end

    functions -q fish_right_prompt
    and begin
        __async_prompt_config_inherit_variables |__async_prompt_spawn $st 'set -U __async_prompt_right_text_'(echo %self)' (fish_right_prompt)'
        function __async_prompt_right_handler --on-process-exit (jobs -lp |tail -n1)
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
