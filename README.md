# Premia - Next-Generation Options AMM

https://premia.finance

## Deployments

TBD

<!---
| Network          |                                      |
| ---------------- | ------------------------------------ |
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

| Key                | Description                                                             | Required for           |
| ------------------ | ----------------------------------------------------------------------- | ---------------------- |
| `API_KEY_ALCHEMY`  | [Alchemy](https://www.alchemy.com/) API key for node connectivity       | Tests + deployments    |
| `API_KEY_ARBISCAN` | [Arbiscan](https://arbiscan.io//) API key for source code verification  | Contracts verification |
| `PKEY_ETH_MAIN`    | private key for production use on mainnets                              | Mainnet deployment     |
| `PKEY_ETH_TEST`    | private key for test/development use on testnets                        | Testnet deployment     |
| `REPORT_GAS`       | if `true`, a gas report will be generated after running tests (hardhat) | Optional               |

### Testing

Test contracts via Hardhat:

```bash
yarn run hardhat test
```

Test contracts via Forge:

```bash
forge test -vvv
```

Activate gas usage reporting by setting the `REPORT_GAS` environment variable to `"true"`:

```bash
REPORT_GAS=true yarn run hardhat test
```

Generate a code coverage report using `solidity-coverage`:

```bash
yarn run hardhat coverage
```

Generate a code coverage report using Forge:

```bash
forge coverage
```

## Licensing

TBD
