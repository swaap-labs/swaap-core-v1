<img src="https://docs.swaap.finance/img/brand.png" alt="drawing" width="300"/>


# Core @ v1
[![npm version](https://img.shields.io/npm/v/@swaap-labs/swaap-core-v1/latest.svg)](https://www.npmjs.com/package/@swaap-labs/swaap-core-v1/v/latest)
[![License](https://img.shields.io/badge/License-GPLv3-green.svg)](https://www.gnu.org/licenses/gpl-3.0)

## Overview

Swaap Protocol is building the first market neutral AMM. This repository contains its core smart contracts. 

For an in-depth documentation of Swaap, see our [docs](https://docs.swaap.finance/).

## Get Started

### Build and Test
```bash
$ yarn # install all dependencies
$ yarn build # compile all contracts
$ yarn test # run all tests
```

### Deployment
To deploy the Factory contract to an EVM-compatible chain:

```bash
$ yarn deploy:$NETWORK
```

Where $NETWORK corresponds to a target network as defined in the [truffle-config.js](truffle-config.js) file.

## Ecosystem

### Using Swaap interfaces
The Swaap Core v1 interfaces are available for import into solidity smart contracts via the npm artifact `@swaap-labs/swaap-core-v1`, e.g.:

```solidity
import '@swaap-labs/swaap-core-v1/contracts/interfaces/IPool.sol';

contract MyContract {
  IPool pool;

  function doSomethingWithPool() {
    // pool.joinPool(...);
  }
}
```

### Error codes
Error messages are formated as `SWAAP#$ERROR_ID` strings.

Corresponding human readable messages can be found here: [contracts/Errors.sol](contracts/Errors.sol).

## Security
### Audits
Swaap Protocol Core module have been audited by Chainsecurity and Runtime Verification. The audit reports can be found in the [audits](./audits/) folder of this repository.

### Upgradability
All core smart contracts are immutable, and cannot be upgraded.

## Licensing
Solidity source code is licensed under the GNU General Public License Version 3 (GPL v3): see [`LICENSE`](./LICENSE).


