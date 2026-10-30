# lenyldes.zsh-theme

# Основной prompt
PROMPT="%F{red}%n@%m%f:%F{cyan}%~%f
%(?.%F{green}➜.%F{red}➜)%f "

# Git информация справа
RPROMPT='$(git_prompt_info)'

# Git prompt настройки
ZSH_THEME_GIT_PROMPT_PREFIX="%F{cyan}git:(%F{red}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%f"
ZSH_THEME_GIT_PROMPT_DIRTY="%F{cyan}) %F{yellow}✗%f"
ZSH_THEME_GIT_PROMPT_CLEAN="%F{cyan})%f"
