function __async_prompt_setup --on-event fish_prompt
    functions -e (status current-function)

    functions -q fish_prompt
    and function fish_prompt
        __async_prompt __async_prompt_text
    end

    functions -q fish_right_prompt
    and function fish_right_prompt
        __async_prompt __async_prompt_right_text
    end
end

function __async_prompt_sync_val --on-signal WINCH
    __async_prompt_sync_val_for __async_prompt_text
    __async_prompt_sync_val_for __async_prompt_right_text
end

function __async_prompt_sync_val_for
    set pref $argv[1]
    set univ_text_name $pref'_'(echo %self)
    set univ_text (eval 'echo $'$univ_text_name)
    set glbl_text_name $pref

    set -q $univ_text_name; and begin
        set -g $glbl_text_name $univ_text
        set -e $univ_text_name
    end
end

function __async_prompt
    set pref $argv[1]
    set glbl_text_name $pref
    set glbl_text (eval 'echo $'$glbl_text_name)

    echo $glbl_text
end

function __async_prompt_fire --on-event fish_prompt
    functions -q fish_prompt
    and __async_prompt_ask __async_prompt

    functions -q fish_right_prompt
    and __async_prompt_ask __async_prompt_right
end

function __async_prompt_ask
    set pref $argv[1]
    fish -c 'set -U '$pref'_text_'(echo %self)' ('(__async_prompt_main_func_name $pref)')' &
    function $pref'_handler' --on-process-exit (jobs -lp | tail -n1)
        kill -WINCH %self
    end
end

function __async_prompt_main_func_name
    test $argv[1] = __async_prompt
    and echo fish_prompt
    or test $argv[1] = __async_prompt_right
    and echo fish_right_prompt
end
