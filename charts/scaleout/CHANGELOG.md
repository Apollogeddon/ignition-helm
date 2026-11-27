# Changelog

## [6.0.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v5.0.0...ignition-scaleout-v6.0.0) (2026-11-27)


### ⚠ BREAKING CHANGES

* **charts:** add a values.schema.json to both charts, so a misspelt key such as redundency fails install, template and lint; values with unknown keys no longer render
* **charts:** make accepting the ignition eula opt-in with a top-level acceptEula, so a user reads it before deploying; renders without acceptEula=true now fail
* **charts:** drop the default admin, gan and web keystore passwords and add existingSecret, so no gateway starts with a known password; installs that relied on admin/metro/ignition must now set them

### Features

* **charts:** Add a values.schema.json to both charts, so a misspelt key such as redundency fails install, template and lint; values with unknown keys no longer render ([8e4dd91](https://github.com/Apollogeddon/ignition-helm/commit/8e4dd9146bbb03ef7a2f4a0251c270e31de19f07))
* **charts:** Add config, secrets, logging and scripts checksums to the gateway pod templates, so a helm upgrade that changes them restarts the gateways ([a97d8dd](https://github.com/Apollogeddon/ignition-helm/commit/a97d8ddbde8921d153255d26318792179176bd44))
* **charts:** Drop the default admin, gan and web keystore passwords and add existingSecret, so no gateway starts with a known password; installs that relied on admin/metro/ignition must now set them ([4619934](https://github.com/Apollogeddon/ignition-helm/commit/4619934627d8c857098eed1d121930cfc17b2e8f))
* **charts:** Make accepting the ignition eula opt-in with a top-level acceptEula, so a user reads it before deploying; renders without acceptEula=true now fail ([d78783a](https://github.com/Apollogeddon/ignition-helm/commit/d78783a2541c5540a33170c01648dcf878d5d961))
* **charts:** Turn the startup probe on by default with about 10 minutes before a restart, so a first start or a large gwbk restore isn't killed by liveness ([1188c1c](https://github.com/Apollogeddon/ignition-helm/commit/1188c1cfac2a2a8d7452b2c42b14b4dcf7c0cc5c))


### Bug Fixes

* **charts:** Accept ignition-common 4 or 5, so the release that bumps common to 5.0.0 still builds both charts ([aa2be69](https://github.com/Apollogeddon/ignition-helm/commit/aa2be697564eda2eea3ca3f3184970fc60fdcc9b))
* **charts:** Accept ignition-common 4 or 5, so the release that bumps common to 5.0.0 still builds both charts ([2e55a56](https://github.com/Apollogeddon/ignition-helm/commit/2e55a562ab9b07f5b2b79d43b1dd5d4d43c52859))
* **charts:** Count a backup incompatible with its master as ready for 30 minutes, so a rolling update that changes the modules goes on to replace the master instead of hanging ([0f23cc0](https://github.com/Apollogeddon/ignition-helm/commit/0f23cc00ee7548e88ccaa9899d0e07f39a1bd945))
* **charts:** Issue the gan ca from the release's own self-signed issuer, so a redundant pair under a ca cluster issuer trusts each other ([9a91d8d](https://github.com/Apollogeddon/ignition-helm/commit/9a91d8d9776d68d4bbb66ce547e3bec0e3b6bff0))
* **charts:** Keep the container ports, probes, network policy, headless services and redundancy peer on the gateway's own 8088/8043/8060, so a custom service.ports only moves the service port ([f8382cd](https://github.com/Apollogeddon/ignition-helm/commit/f8382cd37a36405df90151177d476ebdab0fa2c3))
* **charts:** Mount extraVolumeMounts and localMounts read-only in the preconfigure init container, so restore.path can read a gwbk from a mounted volume ([c53dbb3](https://github.com/Apollogeddon/ignition-helm/commit/c53dbb3cc560a7767976c257b51b394c69718d74))
* **charts:** Pass the gan and web keystore passwords to the gateway jvm, so a redundant pair whose secrets aren't metro and ignition connects ([2f95ad7](https://github.com/Apollogeddon/ignition-helm/commit/2f95ad71a8e1005859184c0f305262f5916a0b61))
* **charts:** Require ignition-common as a minimum, not a caret range, so a release that takes common to a new major version still builds the charts ([efc4bcc](https://github.com/Apollogeddon/ignition-helm/commit/efc4bccd720d95d5896e681d005f6a997df5ccfb))
* **charts:** Require ignition-common as a minimum, not a caret range, so a release that takes common to a new major version still builds the charts ([92a49c0](https://github.com/Apollogeddon/ignition-helm/commit/92a49c056adc93155226519bebd5a84eb9978ddd))
* Require ignition-common ^4.0.0 in the charts that bundle it ([7bf66ca](https://github.com/Apollogeddon/ignition-helm/commit/7bf66ca0f8f9b0181710b607b6fb671ab40accbc))
* Require ignition-common ^4.0.0 in the charts that bundle it ([1f41ab0](https://github.com/Apollogeddon/ignition-helm/commit/1f41ab08ef9af99525a28d726950aa6656899338))
* **scaleout:** Default the frontend to ClientIP session affinity with more than one gateway, and create its pdb only with at least two, so sessions stick and a single frontend no longer blocks node drains ([4e0b6ba](https://github.com/Apollogeddon/ignition-helm/commit/4e0b6bac86d0836c87f84dae285e1e9bbac1037a))
* **scaleout:** Render the frontend's logback.xml from frontend.logging, so frontend log levels are no longer silently replaced by the backend's ([bbdf0c1](https://github.com/Apollogeddon/ignition-helm/commit/bbdf0c1d7234bb27799ab9de7ae75f023829c659))

## [5.0.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v4.3.4...ignition-scaleout-v5.0.0) (2026-10-16)


### ⚠ BREAKING CHANGES

* review 4 findings (frontend autoscaler selector, gateway network trust, dotfile seeding) ([#97](https://github.com/Apollogeddon/ignition-helm/issues/97))

### Bug Fixes

* Gan keystore password under sealedsecrets, and a sealedsecrets example that unseals ([#99](https://github.com/Apollogeddon/ignition-helm/issues/99)) ([96a1310](https://github.com/Apollogeddon/ignition-helm/commit/96a1310fb5722bee317ce64866db70234906c7cc))
* Review 3 findings (examples and NetworkPolicy, redundancy escaping, anti-affinity, SA token, timeouts) ([#94](https://github.com/Apollogeddon/ignition-helm/issues/94)) ([63351f3](https://github.com/Apollogeddon/ignition-helm/commit/63351f38b8abaa01bf8dd9de504b351be0e09139))
* Review 4 findings (frontend autoscaler selector, gateway network trust, dotfile seeding) ([#97](https://github.com/Apollogeddon/ignition-helm/issues/97)) ([baf1028](https://github.com/Apollogeddon/ignition-helm/commit/baf1028d2d6b298f9777922d08b613a9055ce4fb))

## [4.3.4](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v4.3.3...ignition-scaleout-v4.3.4) (2026-10-12)


### Bug Fixes

* Require ignition-common ^3.3.2 in the charts that bundle it ([#91](https://github.com/Apollogeddon/ignition-helm/issues/91)) ([5fe8a51](https://github.com/Apollogeddon/ignition-helm/commit/5fe8a519e99823e828681faa7898afc9e531dd95))

## [4.3.3](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v4.3.2...ignition-scaleout-v4.3.3) (2026-10-12)


### Bug Fixes

* **common:** Mount the gan ca and keystore passphrase in the certificate rotation cronjob ([6f2b77d](https://github.com/Apollogeddon/ignition-helm/commit/6f2b77dc97be8699ba11627c3251a5bc203a7db7))
* Default both charts to ignition 8.3.10 and test 8.1.55 and 8.3.10, as ignition-demo runs ([dd5994e](https://github.com/Apollogeddon/ignition-helm/commit/dd5994e812996e4ad7b6360e9ab0784b78c5f47c))
* Rotation cronjob mounts, keystore passphrase quoting, ignition version drift and kubectl docs ([dc35a00](https://github.com/Apollogeddon/ignition-helm/commit/dc35a00fda1d47db830a438c51394517470795a2))

## [4.3.2](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v4.3.1...ignition-scaleout-v4.3.2) (2026-10-12)


### Bug Fixes

* Release both charts with ignition-common 3.3.1, and with every common release after it ([bb3079d](https://github.com/Apollogeddon/ignition-helm/commit/bb3079d377a5017d920ed007653949c71b51c9cc))
* Require ignition-common ^3.3.1 in both charts, so they ship the data volume seed fix ([08b25c0](https://github.com/Apollogeddon/ignition-helm/commit/08b25c0f6ce856e867066512e1d6f71c0568d037))

## [4.3.1](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v4.3.0...ignition-scaleout-v4.3.1) (2026-10-11)


### Bug Fixes

* Redo an interrupted data volume seed, and describe the scaleout chart ([94d56a1](https://github.com/Apollogeddon/ignition-helm/commit/94d56a162e865b9df0a65dd0d46550827c93e1ec))
* **scaleout:** Describe the scaleout chart rather than the failover one ([c7680c3](https://github.com/Apollogeddon/ignition-helm/commit/c7680c340f15c439504f773e700a34a86d89896c))

## [4.3.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v4.2.2...ignition-scaleout-v4.3.0) (2026-10-11)


### Features

* **scaleout:** Leave the frontend's replicas to its HPA and refuse a backend HPA ([#76](https://github.com/Apollogeddon/ignition-helm/issues/76)) ([893c8f8](https://github.com/Apollogeddon/ignition-helm/commit/893c8f80000f51db59fa44ecf94a8fbee1a6276a))

## [4.2.2](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-4.2.1...ignition-scaleout-4.2.2) (2026-10-09)


### Bug Fixes

* **charts:** Mount the scripts Secret in the GAN certificate rotation CronJob ([17e369e](https://github.com/Apollogeddon/ignition-helm/commit/17e369e7c7ab5660e5ee4a9605044974933aea46))
* **charts:** Restore the gateway backup from restore.url or restore.path on the first start ([878c5ee](https://github.com/Apollogeddon/ignition-helm/commit/878c5eef83f099c20607fd7f7abc07ae7c5dde71))
* **deps:** Bump the dependencies group across 2 directories with 1 update ([66d3a9a](https://github.com/Apollogeddon/ignition-helm/commit/66d3a9a4c30f91c336abec4637664f50c00daf3f))
* **scaleout:** Point the frontend EAM Agent at the backend Controller's gateway name ([7997899](https://github.com/Apollogeddon/ignition-helm/commit/7997899e2b66837b694c158c5d13ba5de7c0a528))

## [4.2.1](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v4.2.0...ignition-scaleout-v4.2.1) (2026-10-07)


### Bug Fixes

* **charts:** End values.yaml with a newline for yamllint ([e23de78](https://github.com/Apollogeddon/ignition-helm/commit/e23de7870de0a7689de6d6636b3846efe9770206))

## [4.2.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-4.1.0...ignition-scaleout-v4.2.0) (2026-10-07)


### Features

* **charts:** Add fixDataOwnership for upgrades from charts that ran the gateway as root ([a3d178b](https://github.com/Apollogeddon/ignition-helm/commit/a3d178b65286e8ebcb1058be3ef3680ef15069cf))


### Bug Fixes

* **charts:** Meet the restricted Pod Security level (runAsNonRoot and a hardened GAN rotation CronJob) ([3b0a992](https://github.com/Apollogeddon/ignition-helm/commit/3b0a99260648ada42a61819dfc2ebd1c56c67b9b))

## [4.1.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v4.0.0...ignition-scaleout-v4.1.0) (2026-03-22)


### Features

* **charts:** Add production features, monitoring, and health checks ([90aeb15](https://github.com/Apollogeddon/ignition-helm/commit/90aeb15bf0876d5f8aae1560cd63cdd91b6f9515))

## [4.0.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v3.2.0...ignition-scaleout-v4.0.0) (2026-01-25)


### ⚠ BREAKING CHANGES

* **config:** Redundancy is now enabled by default in Ignition charts. Existing deployments not explicitly setting `redundancy.enabled` to `false` will now attempt to run in redundant mode, which may require additional configuration (e.g., shared storage).
* **helm:** Hardened security contexts are now enforced, overriding previous configurations. 'configmap-ignition-files' is now a Secret. Kubernetes label selectors have been updated to 'app.kubernetes.io/name'.
* **config:** Keystore passwords moved to a centralised 'secrets' map. Update your values files to use 'IGNITION_WEB_KEYSTORE_PASSWORD' and 'IGNITION_GAN_KEYSTORE_PASSWORD' within the 'secrets' section.
* **helm:** The METRO_KEYSTORE_PASSPHRASE environment variable must now be explicitly set. The previous implicit 'metro' default is no longer applied.

### Features

* **charts:** Add web server ssl/tls configuration ([05893f1](https://github.com/Apollogeddon/ignition-helm/commit/05893f1176b773adb89e3c7f70ffc663363b189e))
* **ci:** Add CI/CD for Helm charts ([702a54e](https://github.com/Apollogeddon/ignition-helm/commit/702a54e818e8f50528f34c70716af67d75424fca))
* **config:** Centralise keystore passwords into secrets map ([a84fe44](https://github.com/Apollogeddon/ignition-helm/commit/a84fe445168d6dd8679a224824ae46071b173aa8))
* **config:** Enable redundancy by default for Ignition charts ([61b4df7](https://github.com/Apollogeddon/ignition-helm/commit/61b4df704b5e3298438fa2dd2b0666d65cc28e3a))
* **helm:** Add automated dependency update workflow ([7d366e6](https://github.com/Apollogeddon/ignition-helm/commit/7d366e6333ad5300fa01ab2861b529563d1d6c4d))
* **helm:** Add security context config for containers ([9e36a2f](https://github.com/Apollogeddon/ignition-helm/commit/9e36a2f28d457265352f2878dab87d27fef2f9d1))
* **helm:** Configure runtime default seccomp profiles ([1a87cfe](https://github.com/Apollogeddon/ignition-helm/commit/1a87cfe828a1f5b725277e762369799a68b44f75))
* **helm:** Establish robust runtime controls for Ignition containers ([e9450f5](https://github.com/Apollogeddon/ignition-helm/commit/e9450f547625100f03482a955ab1c9ed924fc28d))
* **helm:** Improve chart configurability and security context defaults ([7960865](https://github.com/Apollogeddon/ignition-helm/commit/7960865e55efdd85526ea241f334c02129321eb5))
* **helm:** Introduce common GAN certificate templates ([17a261f](https://github.com/Apollogeddon/ignition-helm/commit/17a261fb9203f74d8c837182f0f8e0b46b51cb75))
* **helm:** Introduce security hardening and chart best practices ([000430a](https://github.com/Apollogeddon/ignition-helm/commit/000430a6cc992bb976e2bc3418ed7762a9c40c51))
* **helm:** Introduce static NodePort configuration for services ([9edf3a4](https://github.com/Apollogeddon/ignition-helm/commit/9edf3a4356ce43ede2cb3f266ded6d6dda432d7b))


### Bug Fixes

* **charts:** Consolidate common scripts into shared template ([9976c5d](https://github.com/Apollogeddon/ignition-helm/commit/9976c5d7971d3dc1c7ea84f6b48e9a4dba4f0d1d))
* **charts:** Remove explicit appVersion from Helm charts ([9bf8144](https://github.com/Apollogeddon/ignition-helm/commit/9bf8144e2b43e0a1cb3122f326a7eb3dea57cf3f))
* **helm:** Align trivy ignore comment ([2ed9bf6](https://github.com/Apollogeddon/ignition-helm/commit/2ed9bf6fbc199bc6025642072440f16ebf07c8e3))
* **helm:** Consolidate common templates and security contexts ([b084196](https://github.com/Apollogeddon/ignition-helm/commit/b084196069da25c1b3f9373c59108daf737cf504))
* **helm:** Introduce common resource templates ([c34286c](https://github.com/Apollogeddon/ignition-helm/commit/c34286c106ce75f7d2ea98dadfc71b48ddc0e0e1))
* **helm:** Streamline security contexts and chart values ([5189a72](https://github.com/Apollogeddon/ignition-helm/commit/5189a72f124b756508d9055ec132e6996fa885df))
* **helm:** Update common chart logic into helpers ([2aa221b](https://github.com/Apollogeddon/ignition-helm/commit/2aa221b40720033fa9a3e270a93c795200d688fe))

## [3.2.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v3.1.0...ignition-scaleout-v3.2.0) (2026-01-25)


### Features

* **charts:** Add web server ssl/tls configuration ([05893f1](https://github.com/Apollogeddon/ignition-helm/commit/05893f1176b773adb89e3c7f70ffc663363b189e))


### Bug Fixes

* **helm:** Consolidate common templates and security contexts ([b084196](https://github.com/Apollogeddon/ignition-helm/commit/b084196069da25c1b3f9373c59108daf737cf504))

## [3.1.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v3.0.0...ignition-scaleout-v3.1.0) (2026-01-18)


### Features

* **helm:** Improve chart configurability and security context defaults ([7960865](https://github.com/Apollogeddon/ignition-helm/commit/7960865e55efdd85526ea241f334c02129321eb5))


### Bug Fixes

* **helm:** Align trivy ignore comment ([2ed9bf6](https://github.com/Apollogeddon/ignition-helm/commit/2ed9bf6fbc199bc6025642072440f16ebf07c8e3))
* **helm:** Streamline security contexts and chart values ([5189a72](https://github.com/Apollogeddon/ignition-helm/commit/5189a72f124b756508d9055ec132e6996fa885df))

## [3.0.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v2.0.0...ignition-scaleout-v3.0.0) (2026-01-18)


### ⚠ BREAKING CHANGES

* **config:** Redundancy is now enabled by default in Ignition charts. Existing deployments not explicitly setting `redundancy.enabled` to `false` will now attempt to run in redundant mode, which may require additional configuration (e.g., shared storage).
* **helm:** Hardened security contexts are now enforced, overriding previous configurations. 'configmap-ignition-files' is now a Secret. Kubernetes label selectors have been updated to 'app.kubernetes.io/name'.
* **config:** Keystore passwords moved to a centralised 'secrets' map. Update your values files to use 'IGNITION_WEB_KEYSTORE_PASSWORD' and 'IGNITION_GAN_KEYSTORE_PASSWORD' within the 'secrets' section.

### Features

* **config:** Centralise keystore passwords into secrets map ([a84fe44](https://github.com/Apollogeddon/ignition-helm/commit/a84fe445168d6dd8679a224824ae46071b173aa8))
* **config:** Enable redundancy by default for Ignition charts ([61b4df7](https://github.com/Apollogeddon/ignition-helm/commit/61b4df704b5e3298438fa2dd2b0666d65cc28e3a))
* **helm:** Introduce security hardening and chart best practices ([000430a](https://github.com/Apollogeddon/ignition-helm/commit/000430a6cc992bb976e2bc3418ed7762a9c40c51))

## [2.0.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v1.3.0...ignition-scaleout-v2.0.0) (2026-01-17)


### ⚠ BREAKING CHANGES

* **helm:** The METRO_KEYSTORE_PASSPHRASE environment variable must now be explicitly set. The previous implicit 'metro' default is no longer applied.

### Features

* **helm:** Add security context config for containers ([9e36a2f](https://github.com/Apollogeddon/ignition-helm/commit/9e36a2f28d457265352f2878dab87d27fef2f9d1))
* **helm:** Configure runtime default seccomp profiles ([1a87cfe](https://github.com/Apollogeddon/ignition-helm/commit/1a87cfe828a1f5b725277e762369799a68b44f75))
* **helm:** Establish robust runtime controls for Ignition containers ([e9450f5](https://github.com/Apollogeddon/ignition-helm/commit/e9450f547625100f03482a955ab1c9ed924fc28d))

## [1.3.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v1.2.0...ignition-scaleout-v1.3.0) (2026-01-17)


### Features

* **helm:** Introduce static NodePort configuration for services ([9edf3a4](https://github.com/Apollogeddon/ignition-helm/commit/9edf3a4356ce43ede2cb3f266ded6d6dda432d7b))

## [1.2.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v1.1.3...ignition-scaleout-v1.2.0) (2026-01-08)


### Features

* **helm:** Introduce common GAN certificate templates ([17a261f](https://github.com/Apollogeddon/ignition-helm/commit/17a261fb9203f74d8c837182f0f8e0b46b51cb75))


### Bug Fixes

* **helm:** Introduce common resource templates ([c34286c](https://github.com/Apollogeddon/ignition-helm/commit/c34286c106ce75f7d2ea98dadfc71b48ddc0e0e1))

## [1.1.3](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v1.1.2...ignition-scaleout-v1.1.3) (2026-01-08)


### Bug Fixes

* **helm:** Update common chart logic into helpers ([2aa221b](https://github.com/Apollogeddon/ignition-helm/commit/2aa221b40720033fa9a3e270a93c795200d688fe))

## [1.1.2](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v1.1.1...ignition-scaleout-v1.1.2) (2026-01-06)


### Bug Fixes

* **charts:** Consolidate common scripts into shared template ([9976c5d](https://github.com/Apollogeddon/ignition-helm/commit/9976c5d7971d3dc1c7ea84f6b48e9a4dba4f0d1d))

## [1.1.1](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v1.1.0...ignition-scaleout-v1.1.1) (2026-01-06)


### Bug Fixes

* **charts:** Remove explicit appVersion from Helm charts ([9bf8144](https://github.com/Apollogeddon/ignition-helm/commit/9bf8144e2b43e0a1cb3122f326a7eb3dea57cf3f))

## [1.1.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-scaleout-v1.0.0...ignition-scaleout-v1.1.0) (2026-01-06)


### Features

* **ci:** Add CI/CD for Helm charts ([702a54e](https://github.com/Apollogeddon/ignition-helm/commit/702a54e818e8f50528f34c70716af67d75424fca))
