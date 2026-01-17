# Changelog

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
