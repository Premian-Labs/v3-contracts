// Hardhat plugins
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@solidstate/hardhat-4byte-uploader';
import '@solidstate/hardhat-test-short-circuit';
import '@typechain/hardhat';
import Dotenv from 'dotenv';
import 'hardhat-abi-exporter';
import 'hardhat-artifactor';
import 'hardhat-contract-sizer';
import 'hardhat-dependency-compiler';
import 'hardhat-docgen';
import 'hardhat-gas-reporter';
import 'hardhat-spdx-license-identifier';
import 'solidity-coverage';
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
  PKEY_ETH_MAIN,
  PKEY_ETH_TEST,
  REPORT_GAS,
} = process.env;

// As the PKEYs are only used for deployment, we use default dummy PKEYs if none are set in .env file, so that project can compile
const pkeyMainnet =
  PKEY_ETH_MAIN == undefined || PKEY_ETH_MAIN.length == 0
    ? 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    : PKEY_ETH_MAIN;
const pkeyTestnet =
  PKEY_ETH_TEST == undefined || PKEY_ETH_TEST.length == 0
    ? 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    : PKEY_ETH_TEST;

export default {
  solidity: {
    compilers: [
      {
        version: '0.8.20',
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
      // Uncomment the following lines if we need to reduce UnderwriterVault bytecode size further
      // 'contracts/vault/strategies/underwriter/UnderwriterVault.sol': {
      //   version: '0.8.20',
      //   settings: {
      //     viaIR: false,
      //     optimizer: {
      //       enabled: true,
      //       runs: 20,
      //     },
      //   },
      // },
      'contracts/staking/VxPremia.sol': {
        version: '0.8.20',
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
      accounts: [pkeyTestnet],
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
      accounts: [pkeyMainnet],
      timeout: 300000,
    },
    goerli: {
      url: `https://eth-goerli.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [pkeyTestnet],
      timeout: 300000,
    },
    arbitrumGoerli: {
      url: `https://arb-goerli.g.alchemy.com/v2/${API_KEY_ALCHEMY}`,
      accounts: [pkeyTestnet],
      timeout: 300000,
    },
    arbitrumNova: {
      url: `https://nova.arbitrum.io/rpc`,
      accounts: [pkeyMainnet],
      timeout: 300000,
    },
  },

  abiExporter: {
    runOnCompile: true,
    path: './abi',
    clear: true,
    flat: true,
    except: ['@uniswap'],
  },

  docgen: {
    runOnCompile: false,
    clear: true,
  },

  etherscan: {
    apiKey: {
      arbitrumOne: API_KEY_ARBISCAN,
    },
  },

  gasReporter: {
    enabled: REPORT_GAS === 'true',
  },

  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },

  typechain: {
    alwaysGenerateOverloads: true,
    outDir: 'typechain',
  },

  mocha: {
    timeout: 6000000,
  },
};
