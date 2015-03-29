Wrap programs with slack
===

slack.com is a shared chat room, sort of like a web-based IRC.
It has a fairly simple REST API that is easy to script with external
programs.

!(Slack Web API showing token)[https://farm9.staticflickr.com/8715/16761229497_910c9c1cfc.jpg]

This is a set of tools that can be used to wrap stdin/stdout of
normal programs to make them interact with slack. You will need to
create a file `slack.token` that contains your access token,
which can be found at the bottom of the web API page: https://api.slack.com/web

Do not check this file in!  It is noted in `.gitignore` so that it
won't accidentally be included by a `git add .`, but you should still
be careful.

Usage
===

    Usage: ./slack-wrap [options] -- cmd args...
    Options:
      -t | --token token     Authorization token (default is to read from file)
      -c | --channel id      Channel ID (required)
      -u | --user name       User name to use for the bot
      -i | --interval secs   Time between polls (default 0.5 seconds)
      -I | --ignore RE       Regular expression to ignore on commands
      -F | --filter RE       Regular expression to apply to output from command


slack-frotz
===
![Frotz playing trinty on slack](https://farm9.staticflickr.com/8715/16346258494_62564c392d.jpg)

[frotz](http://frotz.sourceforge.net/), the Interactive Fiction
Z-machine interpreter, is an easy thing to tie into slack.  It waits for
"commands" on the slack channel and feeds them into the text
adventure game using the dumb-terminal version, `dfrotz`, that is
suitable for paper terminals and doesn't do any ANSI command sequences.
You'll need to build it explicitly in the frotz code tree by running
`make dfrotz`.

It uses several ignore regular expressions so that it won't try to
interpret gify commands or images that have been pasted into the chat.
It also tries to avoid allowing the user to type commands like `quit`
to shutdown the program.

The output filter is also used to remove the classic `>` prompt from
the printed results.
