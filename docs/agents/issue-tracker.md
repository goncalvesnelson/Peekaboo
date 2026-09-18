# Issue tracker: GitHub

Specs and work items live in GitHub Issues for `goncalvesnelson/Peekaboo`. Use the `gh` CLI from the repository and resolve its remote with `git remote -v`.

## Operations

- Read an issue with `gh issue view <number> --comments`.
- List open issues with `gh issue list --state open --json number,title,body,labels`.
- Create an issue with `gh issue create --title '<title>' --body-file <path>`.
- Edit labels with `gh issue edit <number> --add-label '<label>'` or `--remove-label '<label>'`.
- Close completed work with `gh issue close <number>`.

Use a body file for multiline issue text. Publish only work within the user's requested scope. Follow `triage-labels.md` for label meanings.

When a skill says to publish to the issue tracker, create a GitHub issue. When it says to fetch a ticket, read that issue and its comments.

## Pull requests as a triage surface

PRs as a request surface: no.
