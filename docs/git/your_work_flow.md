# 📑 WORK FLOW WITH GIT 💡

## 1. Create your own branch
* Before making any changes, always create a new branch from `main`.
* Branch `main` will be the **product stable state**.
* Name it according to the feature or task (e.g., `feat/login-page`, `docs/update-readme`):
```bash
git switch -c <your-branch-name>
```

## 2. Commit your work
* Stage your changes:
```bash
git add .
```
* Commit your work **without** the `-m` flag.
* Your configured text editor (VS Code or Vim) will automatically pop up displaying the template:
```bash
git commit
```
* You only need to edit the message in that **template message**, then save and exit.
* ➡️ [How to write a good commit message.](./git_convention.md)
* How to edit in Vim (in case you skip optional config in **step 2**):
  - If you are in **normal mode** (the cursor will be **block**), press `i` to enter **insert mode**.
  - Edit your message, e.g: `docs: add README.md`.
  - Then, press `Esc` to be back in **normal mode** and type `:wq` and press `Enter` to save your commit.
* Check your commit message:
``` bash
git log
```
**Note:** If after you commit your work and want to change the message (only use just after your last commit):
```bash
git commit --amend
```

## 3. Push your work
* Push your local branch to your personal forked repository (`origin`) for the first time:
```bash
git push -u origin <your_own_branch>
```

## 4. Create Pull Request (PR)
* Go to your forked repository on GitHub website.
* You will see a yellow banner with a button: **Compare & pull request**.
* Click it, write a clear description of your changes, and submit the PR to the original group repo (`upstream/main`).

## 5. Pull & Update locally
* To keep your local machine up-to-date with new changes merged by other team members into the group repo, run these commands:
```bash
# Switch back to your local main branch
git switch main

# Fetch and merge changes from the group upstream
git pull upstream main

# Push the updated main to your personal GitHub fork
git push origin main
```

## 6. Stashing Local Work
* Use `stash` when you have uncommitted changes in your working directory, but need a clean state to pull updates, switch branches, or perform a merge.
```bash
# Temporarily save and hide your uncommitted changes
git stash

# Re-apply your saved changes back to your working directory and remove them from the stash list
git stash pop

# Or remove completely (use when you dont need your old changes anymore)
git stash drop
```

## NEXT STEP:
* [CLEAN UP BRANCH](clean_up_branch.md)