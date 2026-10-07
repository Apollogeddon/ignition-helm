# Changelog

## [3.2.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-3.1.0...ignition-common-v3.2.0) (2026-10-07)


### Features

* **charts:** Add activeRouting so a redundant pair only serves traffic from the Active gateway ([fff3cc9](https://github.com/Apollogeddon/ignition-helm/commit/fff3cc96fd5f51a232948a657dfba22422782bdc))
* **charts:** Add an optional startupProbe ([6bf3eac](https://github.com/Apollogeddon/ignition-helm/commit/6bf3eac943c8275d1f54de76f413fdb56bc38b32))
* **charts:** Add cert rotation, update strategies, and module sideloading ([dafd473](https://github.com/Apollogeddon/ignition-helm/commit/dafd4732eb3b087abf3400ac48b25493d76e11fd))
* **charts:** Add fixDataOwnership for upgrades from charts that ran the gateway as root ([a3d178b](https://github.com/Apollogeddon/ignition-helm/commit/a3d178b65286e8ebcb1058be3ef3680ef15069cf))
* **charts:** Add ingress className for ingressClassName ([bd013a3](https://github.com/Apollogeddon/ignition-helm/commit/bd013a3438b88b885d1bfbc2c63edc3bedb3ffaf))
* **charts:** Add NetworkPolicy extraIngress rules ([fac7ac2](https://github.com/Apollogeddon/ignition-helm/commit/fac7ac219ec0c0b28edd8e0ae84dd022f178b299))
* **charts:** Add optional sizeLimit for the logs, temp and .ignition emptyDirs ([c854879](https://github.com/Apollogeddon/ignition-helm/commit/c854879f87f63986929584b41f6b0b3b045a15ac))
* **charts:** Add per-logger levels and SQLite log limits and stop forcing gateway.SslManager to DEBUG ([42e915e](https://github.com/Apollogeddon/ignition-helm/commit/42e915ef0825efe2b9b4f36e48683bdcef9dc9c4))
* **charts:** Add restartOnRenewal to roll gateways when their certificates are renewed ([1d56624](https://github.com/Apollogeddon/ignition-helm/commit/1d5662452c87db7e5d01c174f3de2a2bac1853fc))


### Bug Fixes

* **charts:** Apply the redundancy role and settings from values on every start ([f408c43](https://github.com/Apollogeddon/ignition-helm/commit/f408c431ff85fafd797b3551b8790b398737b18a))
* **charts:** Check /StatusPing for RUNNING, drop the password-resetting preStop hook and honour configured probe commands ([9de6439](https://github.com/Apollogeddon/ignition-helm/commit/9de6439aacc42ba7c1d59b87cba2f8b653436245))
* **charts:** Fail readiness while the gateway is still commissioning ([055ab88](https://github.com/Apollogeddon/ignition-helm/commit/055ab883bc2fe3f377c69bc262f88c8b345b3e7a))
* **charts:** Keep the redundancy peer address in step with the chart on every start ([dbf9eca](https://github.com/Apollogeddon/ignition-helm/commit/dbf9ecad80f97a78801b2c442a09507c31e944fc))
* **charts:** Meet the restricted Pod Security level (runAsNonRoot and a hardened GAN rotation CronJob) ([3b0a992](https://github.com/Apollogeddon/ignition-helm/commit/3b0a99260648ada42a61819dfc2ebd1c56c67b9b))
* **charts:** Mount the scripts Secret in the active routing and certify pods ([1b550f5](https://github.com/Apollogeddon/ignition-helm/commit/1b550f533d91c8f392ae836b29b8c3fc5cc4caca))
* **charts:** Send the wrapper log to stdout by default so logs/wrapper.log cannot fill the emptyDir ([6f85164](https://github.com/Apollogeddon/ignition-helm/commit/6f851644e7679902f5e25de5e31ecf37a29519de))
* **charts:** Set GAN certificate key rotationPolicy explicitly ([ea97718](https://github.com/Apollogeddon/ignition-helm/commit/ea9771871650c27442497c76cbdde4f0f41fda63))
* **charts:** Ship shutdown.sh as a no-op so pods from 4.1.0 cannot reset the gateway login when replaced ([3437d5c](https://github.com/Apollogeddon/ignition-helm/commit/3437d5cddfadbe51b3ff68fb62b2bdefc495b39e))
* **scaleout:** Scope frontend and backend Services, PDBs, NetworkPolicies and ServiceMonitors by component ([2e07bb3](https://github.com/Apollogeddon/ignition-helm/commit/2e07bb3c8e74b3203d7bd62de810b510436f7c5d))


### Reverts

* **charts:** Drop the 4.1.0 shutdown.sh no-op now that 4.1.0 is unpublished ([abfa6b3](https://github.com/Apollogeddon/ignition-helm/commit/abfa6b3244efc6450411fbd65b4d75bccdec748e))

## [3.1.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v3.0.0...ignition-common-v3.1.0) (2026-03-22)


### Features

* **charts:** Add production features, monitoring, and health checks ([90aeb15](https://github.com/Apollogeddon/ignition-helm/commit/90aeb15bf0876d5f8aae1560cd63cdd91b6f9515))

## [3.0.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v2.2.0...ignition-common-v3.0.0) (2026-01-25)


### ⚠ BREAKING CHANGES

* **helm:** Hardened security contexts are now enforced, overriding previous configurations. 'configmap-ignition-files' is now a Secret. Kubernetes label selectors have been updated to 'app.kubernetes.io/name'.
* **config:** Keystore passwords moved to a centralised 'secrets' map. Update your values files to use 'IGNITION_WEB_KEYSTORE_PASSWORD' and 'IGNITION_GAN_KEYSTORE_PASSWORD' within the 'secrets' section.
* **common:** The common chart now provisions scripts as Kubernetes Secrets instead of ConfigMaps. This improves security posture, especially for sensitive data.
* **helm:** The METRO_KEYSTORE_PASSPHRASE environment variable must now be explicitly set. The previous implicit 'metro' default is no longer applied.

### Features

* **charts:** Add web server ssl/tls configuration ([05893f1](https://github.com/Apollogeddon/ignition-helm/commit/05893f1176b773adb89e3c7f70ffc663363b189e))
* **ci:** Add CI/CD for Helm charts ([702a54e](https://github.com/Apollogeddon/ignition-helm/commit/702a54e818e8f50528f34c70716af67d75424fca))
* **config:** Centralise keystore passwords into secrets map ([a84fe44](https://github.com/Apollogeddon/ignition-helm/commit/a84fe445168d6dd8679a224824ae46071b173aa8))
* **helm:** Add automated dependency update workflow ([7d366e6](https://github.com/Apollogeddon/ignition-helm/commit/7d366e6333ad5300fa01ab2861b529563d1d6c4d))
* **helm:** Establish robust runtime controls for Ignition containers ([e9450f5](https://github.com/Apollogeddon/ignition-helm/commit/e9450f547625100f03482a955ab1c9ed924fc28d))
* **helm:** Improve chart configurability and security context defaults ([7960865](https://github.com/Apollogeddon/ignition-helm/commit/7960865e55efdd85526ea241f334c02129321eb5))
* **helm:** Introduce common GAN certificate templates ([17a261f](https://github.com/Apollogeddon/ignition-helm/commit/17a261fb9203f74d8c837182f0f8e0b46b51cb75))
* **helm:** Introduce security hardening and chart best practices ([000430a](https://github.com/Apollogeddon/ignition-helm/commit/000430a6cc992bb976e2bc3418ed7762a9c40c51))
* **helm:** Introduce static NodePort configuration for services ([9edf3a4](https://github.com/Apollogeddon/ignition-helm/commit/9edf3a4356ce43ede2cb3f266ded6d6dda432d7b))


### Bug Fixes

* **charts:** Consolidate common scripts into shared template ([9976c5d](https://github.com/Apollogeddon/ignition-helm/commit/9976c5d7971d3dc1c7ea84f6b48e9a4dba4f0d1d))
* **common:** Migrate common scripts to Kubernetes Secrets ([a19a92a](https://github.com/Apollogeddon/ignition-helm/commit/a19a92a0165fefbf30797605eb933fada787a769))
* **gan:** Correct certificate and secret naming ([d030190](https://github.com/Apollogeddon/ignition-helm/commit/d030190228fde44b0774a9dca6ee1ab682b33ccd))
* **helm:** Consolidate common templates and security contexts ([b084196](https://github.com/Apollogeddon/ignition-helm/commit/b084196069da25c1b3f9373c59108daf737cf504))
* **helm:** Introduce common resource templates ([c34286c](https://github.com/Apollogeddon/ignition-helm/commit/c34286c106ce75f7d2ea98dadfc71b48ddc0e0e1))
* **helm:** Streamline security contexts and chart values ([5189a72](https://github.com/Apollogeddon/ignition-helm/commit/5189a72f124b756508d9055ec132e6996fa885df))
* **helm:** Update common chart logic into helpers ([2aa221b](https://github.com/Apollogeddon/ignition-helm/commit/2aa221b40720033fa9a3e270a93c795200d688fe))
* **scripts:** Ensure keystore directory exists for population ([d0ebbf7](https://github.com/Apollogeddon/ignition-helm/commit/d0ebbf7e988c2358228c2124b03800173419e425))

## [2.2.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v2.1.0...ignition-common-v2.2.0) (2026-01-25)


### Features

* **charts:** Add web server ssl/tls configuration ([05893f1](https://github.com/Apollogeddon/ignition-helm/commit/05893f1176b773adb89e3c7f70ffc663363b189e))


### Bug Fixes

* **gan:** Correct certificate and secret naming ([d030190](https://github.com/Apollogeddon/ignition-helm/commit/d030190228fde44b0774a9dca6ee1ab682b33ccd))
* **helm:** Consolidate common templates and security contexts ([b084196](https://github.com/Apollogeddon/ignition-helm/commit/b084196069da25c1b3f9373c59108daf737cf504))

## [2.1.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v2.0.0...ignition-common-v2.1.0) (2026-01-18)


### Features

* **helm:** Improve chart configurability and security context defaults ([7960865](https://github.com/Apollogeddon/ignition-helm/commit/7960865e55efdd85526ea241f334c02129321eb5))


### Bug Fixes

* **helm:** Streamline security contexts and chart values ([5189a72](https://github.com/Apollogeddon/ignition-helm/commit/5189a72f124b756508d9055ec132e6996fa885df))

## [2.0.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v1.0.0...ignition-common-v2.0.0) (2026-01-18)


### ⚠ BREAKING CHANGES

* **helm:** Hardened security contexts are now enforced, overriding previous configurations. 'configmap-ignition-files' is now a Secret. Kubernetes label selectors have been updated to 'app.kubernetes.io/name'.
* **config:** Keystore passwords moved to a centralised 'secrets' map. Update your values files to use 'IGNITION_WEB_KEYSTORE_PASSWORD' and 'IGNITION_GAN_KEYSTORE_PASSWORD' within the 'secrets' section.

### Features

* **config:** Centralise keystore passwords into secrets map ([a84fe44](https://github.com/Apollogeddon/ignition-helm/commit/a84fe445168d6dd8679a224824ae46071b173aa8))
* **helm:** Introduce security hardening and chart best practices ([000430a](https://github.com/Apollogeddon/ignition-helm/commit/000430a6cc992bb976e2bc3418ed7762a9c40c51))

## [1.0.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v0.4.0...ignition-common-v1.0.0) (2026-01-17)


### ⚠ BREAKING CHANGES

* **common:** The common chart now provisions scripts as Kubernetes Secrets instead of ConfigMaps. This improves security posture, especially for sensitive data.
* **helm:** The METRO_KEYSTORE_PASSPHRASE environment variable must now be explicitly set. The previous implicit 'metro' default is no longer applied.

### Features

* **helm:** Establish robust runtime controls for Ignition containers ([e9450f5](https://github.com/Apollogeddon/ignition-helm/commit/e9450f547625100f03482a955ab1c9ed924fc28d))


### Bug Fixes

* **common:** Migrate common scripts to Kubernetes Secrets ([a19a92a](https://github.com/Apollogeddon/ignition-helm/commit/a19a92a0165fefbf30797605eb933fada787a769))

## [0.4.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v0.3.0...ignition-common-v0.4.0) (2026-01-17)


### Features

* **helm:** Introduce static NodePort configuration for services ([9edf3a4](https://github.com/Apollogeddon/ignition-helm/commit/9edf3a4356ce43ede2cb3f266ded6d6dda432d7b))

## [0.3.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v0.2.3...ignition-common-v0.3.0) (2026-01-08)


### Features

* **helm:** Introduce common GAN certificate templates ([17a261f](https://github.com/Apollogeddon/ignition-helm/commit/17a261fb9203f74d8c837182f0f8e0b46b51cb75))


### Bug Fixes

* **helm:** Introduce common resource templates ([c34286c](https://github.com/Apollogeddon/ignition-helm/commit/c34286c106ce75f7d2ea98dadfc71b48ddc0e0e1))

## [0.2.3](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-0.2.2...ignition-common-v0.2.3) (2026-01-08)


### Bug Fixes

* **helm:** Update common chart logic into helpers ([2aa221b](https://github.com/Apollogeddon/ignition-helm/commit/2aa221b40720033fa9a3e270a93c795200d688fe))

## [0.2.2](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v0.2.1...ignition-common-v0.2.2) (2026-01-06)


### Bug Fixes

* **scripts:** Ensure keystore directory exists for population ([d0ebbf7](https://github.com/Apollogeddon/ignition-helm/commit/d0ebbf7e988c2358228c2124b03800173419e425))

## [0.2.1](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v0.2.0...ignition-common-v0.2.1) (2026-01-06)


### Bug Fixes

* **charts:** Consolidate common scripts into shared template ([9976c5d](https://github.com/Apollogeddon/ignition-helm/commit/9976c5d7971d3dc1c7ea84f6b48e9a4dba4f0d1d))

## [0.2.0](https://github.com/Apollogeddon/ignition-helm/compare/ignition-common-v0.1.0...ignition-common-v0.2.0) (2026-01-06)


### Features

* **ci:** Add CI/CD for Helm charts ([702a54e](https://github.com/Apollogeddon/ignition-helm/commit/702a54e818e8f50528f34c70716af67d75424fca))
