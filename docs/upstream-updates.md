# Updating FrankGeary

FrankGeary tracks GNOME Geary closely, with Frank-specific changes kept small
and easy to review.

## Remotes

```sh
git remote add upstream https://gitlab.gnome.org/GNOME/geary.git
git remote set-url upstream https://gitlab.gnome.org/GNOME/geary.git
git fetch upstream main --tags
```

`origin` should point at the FrankGeary GitHub repository.

## Normal update flow

```sh
git checkout master
git fetch origin master
git fetch upstream main --tags
git rebase upstream/main
meson setup build -Dprofile=development --wipe
meson compile -C build
meson test -C build --print-errorlogs
git push --force-with-lease origin master
```

Use `--force-with-lease`, not plain `--force`. If the GitHub branch moved since
you fetched it, stop and inspect the new commits before pushing.

## Patch policy

Keep FrankGeary changes small and separated by feature:

1. autocomplete/no-reply policy;
2. Copy Image;
3. folder sidebar toggle;
4. docs/packaging/CI.
