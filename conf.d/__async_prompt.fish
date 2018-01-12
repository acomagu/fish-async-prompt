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
    functions -q fish_prompt
    and begin
        fish -c 'set -U __async_prompt_text_'(echo %self)' (fish_prompt)' &
        function __async_prompt_handler --on-process-exit (jobs -lp |tail -n1)
            kill -WINCH %self
        end
    end

    functions -q fish_right_prompt
    and begin
        fish -c 'set -U __async_prompt_right_text_'(echo %self)' (fish_right_prompt)' &
        function __async_prompt_right_handler --on-process-exit (jobs -lp |tail -n1)
            kill -WINCH %self
        end
    end
end
