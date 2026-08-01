SPACEMAP(1)

# NAME

spacemap - visualize and navigate yabai spaces

# SYNOPSIS

*spacemap* [*OPTIONS*]

# DESCRIPTION

Spacemap is a native macOS HUD for yabai spaces. With no options, it launches
the menu bar application and waits for the configured hotkey.

# OPTIONS

*--version*
	Print the Spacemap version and exit.

*--trigger*
	Toggle the HUD in the running Spacemap application and exit.

*--space* _SELECTOR_
	Focus a yabai space, show the HUD, and exit. _SELECTOR_ may be an index from
	1 through 16, *prev*, *next*, *first*, *last*, *recent*, *mouse*, or a yabai
	space label.

*--show-menu*
	Show the menu bar menu. The application continues running.

*--settings*
	Open the settings window. The application continues running.

*--config*
	Open the configuration file in the default editor and exit.

*--help*
	Print command-line help and exit.

# FILES

_$HOME/.config/spacemap/config.toml_
	Spacemap configuration. Most changes are reloaded when the HUD opens; hotkey
	changes require the running application to restart.

_$HOME/.config/spacemap/themes/_
	Directory containing custom *.smthemes* theme files.

_/tmp/spacemap_USERNAME.socket_
	Unix domain socket used by the CLI and yabai signals to notify the running
	application.

# EXAMPLES

Toggle the running HUD:

	spacemap --trigger

Focus the next space from an skhd binding and show the HUD:

	ctrl - right : spacemap --space next

Focus a labeled space:

	spacemap --space web

# ENVIRONMENT

Spacemap discovers yabai at _/opt/homebrew/bin/yabai_ or
_/usr/local/bin/yabai_.

# SEE ALSO

*yabai*(1), *skhd*(1)

# AUTHORS

Spacemap contributors.
