# Premia - Next-Generation Options AMM

https://premia.finance

## Deployments

| Network         | Deployment                |                                                            |
| --------------- | ------------------------- | ---------------------------------------------------------- |
| Arbitrum Goerli | Core Contracts            | [📜](utils/deployment/arbitrumGoerli/coreTable.md)         |
| Arbitrum Goerli | Option Physically Settled | [📜](utils/deployment/arbitrumGoerli/optionPSTable.md)     |
| Arbitrum Goerli | Option Rewards            | [📜](utils/deployment/arbitrumGoerli/optionRewardTable.md) |
| Arbitrum Goerli | Vaults                    | [📜](utils/deployment/arbitrumGoerli/vaultsTable.md)       |

<!---
 | Arbitrum Mainnet | [📜](./docs/deployments/ARBITRUM.md) |
-->

## Development

Install dependencies via Yarn:

```bash
yarn install
```

Setup Husky to format code on commit:

```bash
yarn postinstall
```

Create a `.env` file with the following values defined:

| Key                  | Description                                                                          | Required for           |
| -------------------- | ------------------------------------------------------------------------------------ | ---------------------- |
| `API_KEY_ALCHEMY`    | [Alchemy](https://www.alchemy.com/) API key for node connectivity                    | Tests + deployments    |
| `API_KEY_ARBISCAN`   | [Arbiscan](https://arbiscan.io//) API key for source code verification               | Contracts verification |
| `PKEY_DEPLOYER_MAIN` | contract deployer private key for production use on mainnets                         | Mainnet deployment     |
| `PKEY_DEPLOYER_TEST` | contract deployer private key for test/development use on testnets                   | Testnet deployment     |
| `PKEY_PROPOSER_MAIN` | Safe multi-sig transaction proposer private key for production use on mainnets       | Mainnet deployment     |
| `PKEY_PROPOSER_TEST` | Safe multi-sig transaction proposer private key for test/development use on testnets | Testnet deployment     |

### Testing

Test contracts via Forge:

```bash
forge test -vv
```

Generate a code coverage report using Forge:

```bash
forge coverage
```

Generate a HTML code coverage report using Forge :

```bash
forge coverage --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage
```

### Deployment

Contracts deployment is done through Hardhat.
Available networks : `arbitrum`, `arbitrumNova`, `goerli`, `arbitrumGoerli`

```bash
hardhat run ./scripts/deploy/0000-baseLayer.ts --network goerli
```

### Contracts upgrade

Example to upgrade pools implementation on goerli network :

```bash
hardhat run ./scripts/upgrade/0000-pools.ts --network goerli
```

Other upgrades scripts are available in `./scripts/upgrade` to upgrade different components of the protocol.

## Docker

To run the code in developer mode using docker, start by building the docker image:

```bash
docker build -t premia-v3 .
```

Then run the docker container by using the command:

**MacOS/Linux**

```bash
docker run -it -u=$(id -u $USER):$(id -g $USER) \
           -v $PWD:/src \
           premia-v3
```

**Windows**

```bash
docker run -it -v %CD%:/src premia-v3
```

Upon executing, you will have access to the command line inside the container and will be able to run the commands for forge and hardhat.

## Licensing

TBD
