Wrap programs with slack
===

slack.com is a shared chat room, sort of like a web-based IRC.
It has a fairly simple REST API that is easy to script with external
programs.

This is a set of tools that can be used to wrap stdin/stdout of
normal programs to make them interact with slack. You will need to
create a file `slack.token` that contains your access token,
which can be found at the bottom of the web API page: https://api.slack.com/web

Do not check this file in!  It is noted in `.gitignore` so that it
won't accidentally be included by a `git add .`, but you should still
be careful.


