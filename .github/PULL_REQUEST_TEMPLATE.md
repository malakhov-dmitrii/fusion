<!-- Keep the diff small and the harness mechanical. -->

**What & why**

**Checks**
- [ ] `bash -n skills/fusion/fusion.sh install.sh` passes
- [ ] `shellcheck -S error skills/fusion/fusion.sh install.sh` passes
- [ ] `fusion.sh selftest <provider>` passes against a provider I have
- [ ] `README.md` / `SKILL.md` updated if behavior changed
- [ ] `CHANGELOG.md` entry added under *Unreleased*
