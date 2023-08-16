// Hardhat plugins
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@solidstate/hardhat-4byte-uploader';
import '@typechain/hardhat';
import Dotenv from 'dotenv';
import 'hardhat-abi-exporter';
import 'hardhat-artifactor';
import 'hardhat-contract-sizer';
import 'hardhat-dependency-compiler';
import 'hardhat-spdx-license-identifier';
import 'hardhat-preprocessor';
import fs from 'fs';

Dotenv.config();

function getRemappings() {
  return fs
    .readFileSync('remappings.txt', 'utf8')
    .split('\n')
    .filter(Boolean)
    .filter((el) => !el.includes('node_modules'))
    .map((line: string) => line.trim().split('='));
}

const {
  API_KEY_ALCHEMY,
  API_KEY_ARBISCAN,
  PKEY_DEPLOYER_MAIN,
  PKEY_DEPLOYER_TEST,
  PKEY_PROPOSER_MAIN,
  PKEY_PROPOSER_TEST,
} = process.env;

/**
 * As the PKEYs are only used for deployment, we use default dummy PKEYs if none are set in .env file, so that project can compile
 * @param pKey PKEY to return or replace, if necessary
 */
function tryFetchPKey(pKey: string | undefined) {
  return pKey == undefined || pKey.length == 0
    ? 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    : pKey;
}

const pkeyDeployerMainnet = tryFetchPKey(PKEY_DEPLOYER_MAIN);
const pkeyDeployerTestnet = tryFetchPKey(PKEY_DEPLOYER_TEST);
const pkeyProposerMainnet = tryFetchPKey(PKEY_PROPOSER_MAIN);
const pkeyProposerTestnet = tryFetchPKey(PKEY_PROPOSER_TEST);

export default {
  solidity: {
    compilers: [
      {
        version: '0.8.19',
        settings: {
          viaIR: false,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
    overrides: {
      // This override allows to save ~0.5kB contract size if necessary
      // 'contracts/vault/strategies/underwriter/UnderwriterVault.sol': {
      //   version: '0.8.19',
      //   settings: {
      //     viaIR: false,
      //     optimizer: {
      //       enabled: true,
      //       runs: 20,
      //     },
      //   },
      // },
      'contracts/staking/VxPremia.sol': {
        version: '0.8.19',
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  paths: {
    cache: './cache_hardhat',
  },
  // This fully resolves paths for imports in the ./lib directory for Hardhat
  preprocess: {
    eachLine: (hre: any) => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          getRemappings().forEach(([find, replace]) => {
            if (line.match(find)) {
              line = line.replace(find, replace);
            }
          });
        }
        return line;
      },
    }),
  },
  networks: {
    anvil: {
      url: `http://127.0.0.1:8545`,
      accounts: [pkeyDeployerTestnet, pkeyProposerTestnet],
    },
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
        blockNumber: 16597500,
      },
      allowUnlimitedContractSize: true,
      blockGasLimit: 180000000000,
    },
    arbitrum: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${API_KEY_ALCHEMY}`,
      accounts: [pkeyDeployerMainnet, pkeyProposerMainnet],
      timeout: 300000,
    },
    goerli: {
      url: `https://eth-goerli.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [pkeyDeployerTestnet, pkeyProposerTestnet],
      timeout: 300000,
    },
    arbitrumGoerli: {
      url: `https://arb-goerli.g.alchemy.com/v2/${API_KEY_ALCHEMY}`,
      accounts: [pkeyDeployerTestnet, pkeyProposerTestnet],
      timeout: 300000,
    },
    arbitrumNova: {
      url: `https://nova.arbitrum.io/rpc`,
      accounts: [pkeyDeployerMainnet, pkeyProposerMainnet],
      timeout: 300000,
    },
  },

  abiExporter: {
    runOnCompile: true,
    path: './abi',
    clear: true,
    flat: true,
  },

  etherscan: {
    apiKey: {
      arbitrumOne: API_KEY_ARBISCAN,
    },
  },

  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },

  typechain: {
    alwaysGenerateOverloads: true,
    outDir: 'typechain',
  },
};
