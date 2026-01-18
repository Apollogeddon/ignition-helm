# Changelog

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
